# DATABASE.md — GORM Database Patterns Reference

Stack: GORM v2 (`gorm.io/gorm`), PostgreSQL, feature-first architecture.
Rule: Domain entities are separate from GORM models. Models live in `infra/`, entities in `domain/`.

---

## 1. Transactions

**Rule:** Prefer `db.Transaction()` for automatic rollback on error. Use manual `Begin/Commit` only when the transaction spans multiple function calls.

```go
// --- Closure-based (preferred) ---
err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
    if err := tx.Create(&order).Error; err != nil {
        return err // auto rollback
    }
    if err := tx.Create(&payment).Error; err != nil {
        return err // auto rollback
    }
    return nil // auto commit
})

// --- Manual (when you must pass tx across layers) ---
tx := db.WithContext(ctx).Begin()
if tx.Error != nil {
    return tx.Error
}
defer func() {
    if r := recover(); r != nil {
        tx.Rollback()
        panic(r)
    }
}()

if err := tx.Create(&order).Error; err != nil {
    tx.Rollback()
    return err
}
return tx.Commit().Error

// --- Nested transaction (SavePoint) ---
err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
    tx.Create(&order)

    return tx.Transaction(func(nested *gorm.DB) error {
        // creates SAVEPOINT internally
        return nested.Create(&orderItem).Error
    })
})
```

**Mistake:** Forgetting `defer tx.Rollback()` or the panic recovery in manual transactions. If a panic fires mid-transaction, the connection leaks back to the pool in a dirty state.

---

## 2. Migrations

**Rule:** Use `AutoMigrate` only in development and tests. Use versioned SQL migrations (golang-migrate, goose, atlas) in staging/production.

```go
// --- AutoMigrate (dev/test only) ---
err := db.AutoMigrate(&UserModel{}, &TaskModel{})

// --- SQL migration file naming (golang-migrate) ---
// 000001_create_users.up.sql
// 000001_create_users.down.sql
// 000002_add_tasks_table.up.sql
// 000002_add_tasks_table.down.sql

// --- When to use each ---
// AutoMigrate:  adds columns, creates tables — NEVER drops columns or tables
// SQL migration: full control — renames, drops, data backfills, index changes
```

**Mistake:** Relying on `AutoMigrate` in production. It silently skips destructive changes (column drops, type changes), leaving your schema out of sync with your models.

---

## 3. N+1 Problem

**Rule:** Never load associations inside a loop. Use `Preload` for separate queries or `Joins` for a single query with filtering.

```go
// --- BAD: N+1 — fires 1 + N queries ---
var users []UserModel
db.WithContext(ctx).Find(&users)
for _, u := range users {
    var tasks []TaskModel
    db.WithContext(ctx).Where("user_id = ?", u.ID).Find(&tasks) // query per user
}

// --- GOOD: Preload — fires exactly 2 queries ---
var users []UserModel
db.WithContext(ctx).Preload("Tasks").Find(&users)

// --- GOOD: Preload with conditions ---
db.WithContext(ctx).Preload("Tasks", "status = ?", "active").Find(&users)

// --- GOOD: Joins — single query, useful for filtering on association ---
db.WithContext(ctx).
    Joins("JOIN tasks ON tasks.user_id = users.id").
    Where("tasks.due_date < ?", time.Now()).
    Find(&users)
```

**Mistake:** Using `Preload` when you need to filter the parent by association data. `Preload` loads associations *after* the parent query — it cannot filter parents. Use `Joins` for that.

---

## 4. Connection Pool

**Rule:** Always configure the underlying `sql.DB` pool. GORM defaults are unbounded, which will exhaust PostgreSQL connections under load.

```go
sqlDB, err := db.DB()
if err != nil {
    return err
}

// --- Production defaults for a typical service ---
sqlDB.SetMaxOpenConns(25)          // match or stay below PG max_connections / num_instances
sqlDB.SetMaxIdleConns(10)          // keep warm connections ready, avoid reconnect overhead
sqlDB.SetConnMaxLifetime(5 * time.Minute)  // recycle conns to rebalance after PG failover
sqlDB.SetConnMaxIdleTime(1 * time.Minute)  // close idle conns faster under low traffic
```

**Mistake:** Leaving `MaxOpenConns` at 0 (unlimited). Under a traffic spike, each goroutine opens a new connection, exhausting PostgreSQL's `max_connections` and causing `too many clients` errors across all services.

---

## 5. Soft Delete

**Rule:** Embed `gorm.DeletedAt` in the model. GORM automatically adds `WHERE deleted_at IS NULL` to all queries.

```go
type TaskModel struct {
    ID        uuid.UUID      `gorm:"type:uuid;primaryKey"`
    Title     string
    DeletedAt gorm.DeletedAt `gorm:"index"` // soft delete field
    CreatedAt time.Time
    UpdatedAt time.Time
}

// --- Delete (sets deleted_at, does NOT remove row) ---
db.WithContext(ctx).Delete(&TaskModel{}, taskID)

// --- Query (automatically excludes soft-deleted) ---
db.WithContext(ctx).Find(&tasks) // WHERE deleted_at IS NULL

// --- Include soft-deleted records ---
db.WithContext(ctx).Unscoped().Find(&tasks)

// --- Permanently delete ---
db.WithContext(ctx).Unscoped().Delete(&TaskModel{}, taskID)
```

**Mistake:** Forgetting to add a database index on `deleted_at`. Every query appends `deleted_at IS NULL`, so without the index, full table scans happen on every read.

---

## 6. Query Patterns — Scopes

**Rule:** Extract reusable WHERE clauses into scopes. Compose them freely — GORM chains scopes with AND.

```go
// --- Pagination scope ---
func Paginate(page, pageSize int) func(db *gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        if page <= 0 {
            page = 1
        }
        if pageSize <= 0 || pageSize > 100 {
            pageSize = 20
        }
        offset := (page - 1) * pageSize
        return db.Offset(offset).Limit(pageSize)
    }
}

// --- Filter scope ---
func ByStatus(status string) func(db *gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        if status == "" {
            return db
        }
        return db.Where("status = ?", status)
    }
}

// --- Date range scope ---
func CreatedBetween(from, to time.Time) func(db *gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        return db.Where("created_at BETWEEN ? AND ?", from, to)
    }
}

// --- Compose scopes ---
var tasks []TaskModel
db.WithContext(ctx).
    Scopes(Paginate(req.Page, req.PageSize), ByStatus(req.Status)).
    Order("created_at DESC").
    Find(&tasks)
```

**Mistake:** Putting pagination/filtering logic inline in every handler. Duplicated, untested, and inconsistent across endpoints.

---

## 7. Error Handling

**Rule:** Map GORM/driver errors to domain errors at the repository boundary. Never let `gorm.ErrRecordNotFound` leak into service or handler layers.

```go
import (
    "errors"
    "gorm.io/gorm"
    "github.com/jackc/pgx/v5/pgconn"
)

// --- Domain errors (defined in domain/) ---
var (
    ErrNotFound      = errors.New("entity not found")
    ErrAlreadyExists = errors.New("entity already exists")
)

// --- Repository helper ---
func mapError(err error) error {
    if err == nil {
        return nil
    }
    if errors.Is(err, gorm.ErrRecordNotFound) {
        return ErrNotFound
    }
    var pgErr *pgconn.PgError
    if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
        return ErrAlreadyExists
    }
    return err // unknown — bubble up for 500
}

// --- Usage in repository ---
func (r *TaskRepo) GetByID(ctx context.Context, id uuid.UUID) (*TaskModel, error) {
    var task TaskModel
    err := r.db.WithContext(ctx).First(&task, "id = ?", id).Error
    return &task, mapError(err)
}
```

**Mistake:** Checking `err.Error()` string contents instead of using `errors.Is` / `errors.As`. String matching is brittle and breaks across driver versions.

---

## 8. Context

**Rule:** Every database call must use `db.WithContext(ctx)`. This propagates request deadlines, cancellation, and tracing spans to the database driver.

```go
// --- GOOD ---
func (r *TaskRepo) List(ctx context.Context) ([]TaskModel, error) {
    var tasks []TaskModel
    err := r.db.WithContext(ctx).Find(&tasks).Error
    return tasks, mapError(err)
}

// --- Set query timeout via context ---
ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
defer cancel()
err := r.db.WithContext(ctx).Find(&tasks).Error

// --- In middleware: store db with context already applied ---
func DBMiddleware(db *gorm.DB) gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Set("db", db.WithContext(c.Request.Context()))
        c.Next()
    }
}
```

**Mistake:** Using bare `db.Find()` without context. A runaway query has no deadline, holds a connection indefinitely, and is invisible to distributed tracing.

---

## Quick Reference Table

| Pattern            | When                                  | Key API                            |
|--------------------|---------------------------------------|------------------------------------|
| Transaction        | Multi-table writes                    | `db.Transaction(func(tx) error)`   |
| Preload            | Load associations (no parent filter)  | `db.Preload("Assoc").Find()`       |
| Joins              | Filter parent by association          | `db.Joins("JOIN ...").Find()`      |
| Scopes             | Reusable query fragments              | `db.Scopes(Paginate(1, 20))`      |
| Unscoped           | Include soft-deleted rows             | `db.Unscoped().Find()`            |
| WithContext        | Every single query                    | `db.WithContext(ctx)`              |
| First vs Find      | One record vs many                   | `First` returns ErrRecordNotFound  |
