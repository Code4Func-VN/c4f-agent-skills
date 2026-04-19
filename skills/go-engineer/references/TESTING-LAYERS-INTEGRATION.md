# Testing Layers — Integration Tests, Helpers & Mocking

## Handler Tests

**When to use:** Testing that HTTP handlers return correct status codes,
response bodies, and error shapes. Mock the service interface — never test
business logic through the handler.

```go
package task_test

import (
    "context"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"

    "github.com/labstack/echo/v4"
    "myapp/internal/task/domain"
    "myapp/internal/task/handler"
)

type mockTaskService struct {
    createFn  func(ctx context.Context, title string) (*domain.Task, error)
    getByIDFn func(ctx context.Context, id string) (*domain.Task, error)
}

func (m *mockTaskService) Create(ctx context.Context, title string) (*domain.Task, error) {
    return m.createFn(ctx, title)
}

func (m *mockTaskService) GetByID(ctx context.Context, id string) (*domain.Task, error) {
    return m.getByIDFn(ctx, id)
}

func TestHandleCreateTask(t *testing.T) {
    tests := []struct {
        name       string
        body       string
        svcResult  *domain.Task
        svcErr     error
        wantStatus int
        wantBody   string
    }{
        {
            name:       "success",
            body:       `{"title":"New task"}`,
            svcResult:  &domain.Task{ID: "1", Title: "New task"},
            svcErr:     nil,
            wantStatus: http.StatusCreated,
            wantBody:   `"id":"1"`,
        },
        {
            name:       "invalid json",
            body:       `{bad`,
            wantStatus: http.StatusBadRequest,
            wantBody:   `"error"`,
        },
        {
            name:       "service error",
            body:       `{"title":"x"}`,
            svcResult:  nil,
            svcErr:     domain.ErrInvalidTitle,
            wantStatus: http.StatusUnprocessableEntity,
            wantBody:   `"error"`,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            e := echo.New()
            req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(tt.body))
            req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
            rec := httptest.NewRecorder()
            c := e.NewContext(req, rec)

            svc := &mockTaskService{
                createFn: func(_ context.Context, _ string) (*domain.Task, error) {
                    return tt.svcResult, tt.svcErr
                },
            }
            h := handler.NewTaskHandler(svc)

            _ = h.Create(c)

            if rec.Code != tt.wantStatus {
                t.Errorf("Create() status = %d, want %d", rec.Code, tt.wantStatus)
            }
            if !strings.Contains(rec.Body.String(), tt.wantBody) {
                t.Errorf("Create() body = %q, want substring %q", rec.Body.String(), tt.wantBody)
            }
        })
    }
}
```

**Common mistake:** Testing business logic in handler tests. If a handler test
needs complex mock setups to verify a business rule, that rule should be tested
in the service layer instead.

---

## Repository Tests

**When to use:** Integration tests that verify SQL queries, constraint
enforcement, and CRUD operations against a real database. Use testcontainers-go
to spin up a disposable Postgres instance.

```go
//go:build integration

package task_test

import (
    "context"
    "testing"

    "github.com/google/go-cmp/cmp"
    "github.com/testcontainers/testcontainers-go"
    "github.com/testcontainers/testcontainers-go/modules/postgres"
    "myapp/internal/task/domain"
    "myapp/internal/task/repository"
)

func startPostgres(t *testing.T) string {
    t.Helper()
    ctx := context.Background()

    ctr, err := postgres.Run(ctx, "postgres:16-alpine",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"),
        postgres.WithPassword("test"),
    )
    if err != nil {
        t.Fatalf("startPostgres: %v", err)
    }
    t.Cleanup(func() { testcontainers.CleanupContainer(t, ctr) })

    connStr, err := ctr.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        t.Fatalf("ConnectionString: %v", err)
    }
    return connStr
}

func TestTaskRepo_CreateAndGet(t *testing.T) {
    connStr := startPostgres(t)
    repo := repository.NewTaskRepo(connStr)

    ctx := context.Background()
    task, _ := domain.NewTask("Integration test task")

    if err := repo.Create(ctx, task); err != nil {
        t.Fatalf("Create(%q) error: %v", task.Title, err)
    }

    got, err := repo.GetByID(ctx, task.ID)
    if err != nil {
        t.Fatalf("GetByID(%q) error: %v", task.ID, err)
    }
    if diff := cmp.Diff(task, got); diff != "" {
        t.Errorf("GetByID() mismatch (-want +got):\n%s", diff)
    }
}

func TestTaskRepo_GetByID_NotFound(t *testing.T) {
    connStr := startPostgres(t)
    repo := repository.NewTaskRepo(connStr)

    _, err := repo.GetByID(context.Background(), "nonexistent")
    if err == nil {
        t.Error("GetByID(nonexistent) expected error, got nil")
    }
}
```

**Common mistake:** Using SQLite in-memory as a Postgres substitute. SQL
dialects differ — constraints, ON CONFLICT, and type behavior will not match.
Always test against the same database engine you deploy.

---

## Test Helpers

**When to use:** Extracting repeated setup into shared functions. Always call
`t.Helper()` first so failures report the caller's line, and use `t.Cleanup()`
so teardown runs even if the test panics.

```go
package testutil

import (
    "context"
    "database/sql"
    "testing"

    "myapp/internal/task/domain"
)

// MustCreateTask creates a task and fails the test if construction errors.
func MustCreateTask(t *testing.T, title string) *domain.Task {
    t.Helper()
    task, err := domain.NewTask(title)
    if err != nil {
        t.Fatalf("MustCreateTask(%q): %v", title, err)
    }
    return task
}

// OpenTestDB returns a connected DB and registers cleanup.
func OpenTestDB(t *testing.T, connStr string) *sql.DB {
    t.Helper()
    db, err := sql.Open("pgx", connStr)
    if err != nil {
        t.Fatalf("OpenTestDB: %v", err)
    }
    if err := db.PingContext(context.Background()); err != nil {
        t.Fatalf("OpenTestDB ping: %v", err)
    }
    t.Cleanup(func() { db.Close() })
    return db
}
```

**Common mistake:** Forgetting `t.Helper()` in utility functions. Without it,
test failure output points to the helper's line instead of the caller's line,
making failures hard to diagnose.

---

## Mocking Pattern

**When to use:** Any time a layer depends on an interface from the layer below.
Define a struct with function fields that implement the interface. No mock
framework needed.

```go
// Step 1: The interface lives in the consumer package.
package service

type TaskRepository interface {
    Create(ctx context.Context, t *domain.Task) error
    GetByID(ctx context.Context, id string) (*domain.Task, error)
    List(ctx context.Context, limit int) ([]*domain.Task, error)
}

// Step 2: The mock lives in the test file (not exported).
type mockTaskRepo struct {
    createFn  func(ctx context.Context, t *domain.Task) error
    getByIDFn func(ctx context.Context, id string) (*domain.Task, error)
    listFn    func(ctx context.Context, limit int) ([]*domain.Task, error)

    createCalls int // record calls when you need to assert invocation count
}

func (m *mockTaskRepo) Create(ctx context.Context, t *domain.Task) error {
    m.createCalls++
    return m.createFn(ctx, t)
}

func (m *mockTaskRepo) GetByID(ctx context.Context, id string) (*domain.Task, error) {
    return m.getByIDFn(ctx, id)
}

func (m *mockTaskRepo) List(ctx context.Context, limit int) ([]*domain.Task, error) {
    return m.listFn(ctx, limit)
}

// Step 3: Use in test — only set the functions you need.
func TestService_CreateCallsRepo(t *testing.T) {
    repo := &mockTaskRepo{
        createFn: func(_ context.Context, _ *domain.Task) error {
            return nil
        },
    }
    svc := NewTaskService(repo)

    _, _ = svc.Create(context.Background(), "Test")

    if repo.createCalls != 1 {
        t.Errorf("Create was called %d times, want 1", repo.createCalls)
    }
}
```

**Common mistake:** Using a mock framework like gomock or mockery. Manual mocks
are simpler, have no codegen step, and make the test fully readable without
jumping to generated files. Only consider a framework if the interface has more
than ~10 methods.
