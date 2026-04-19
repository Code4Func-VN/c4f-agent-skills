# Go Project Blueprint — Structure

Clean Architecture (3-layer) with Echo v4, GORM, and PostgreSQL.

---

## 1. Directory Layout

```
project/
├── cmd/api/main.go                              # server.Run()
├── internal/
│   ├── modules/                                  # ── Business modules ──
│   │   └── user/
│   │       ├── domain/
│   │       │   ├── user.go                       # Entity, NewUser(), CheckPassword()
│   │       │   ├── errors.go                     # Sentinel errors
│   │       │   └── repository.go                 # Repository interface
│   │       ├── service/
│   │       │   ├── service.go                    # Struct, constructor
│   │       │   ├── register.go                   # Register business logic
│   │       │   └── find.go                       # GetByID business logic
│   │       ├── handler/
│   │       │   ├── handler.go                    # Struct, routes, service interface, response types
│   │       │   ├── register.go                   # POST /api/users/register
│   │       │   └── find.go                       # GET /api/users/:id
│   │       └── repository/
│   │           ├── repository.go                 # GormRepository struct, model, mapping
│   │           ├── create.go                     # Create
│   │           └── find.go                       # FindByID, FindByEmail
│   ├── infrastructure/                           # ── Frameworks & Drivers ──
│   │   ├── config/config.go                      # Env-based config with validation
│   │   ├── database/database.go                  # GORM connection
│   │   ├── server/server.go                      # Wiring, bootstrap, graceful shutdown
│   └── shared/                                   # ── Cross-cutting utilities ──
│       ├── response/response.go                  # Shared HTTP response helpers
│       ├── apperror/apperror.go                  # AppError, HTTPErrorHandler
│       ├── validator/validator.go                # Request validator
│       └── middleware/middleware.go               # CORS, auth, rate limiting
├── .env.example
├── .gitignore
├── docker-compose.yml
├── Dockerfile
└── Makefile
```

---

## 2. Naming Rules

| What | Convention | Example | Bad Example |
|------|-----------|---------|-------------|
| Module folder | Business domain noun | `modules/user/`, `modules/order/`, `modules/payment/` | `handlers/`, `models/` |
| Infrastructure folder | Framework/driver concern | `infrastructure/config/`, `infrastructure/database/` | `config/` at root of `internal/` |
| Shared folder | Cross-cutting utility | `shared/response/`, `shared/apperror/` | `util/`, `helper/` |
| Sub-folder | Layer name | `domain/`, `service/`, `handler/`, `repository/` | -- |
| File name | Business action verb | `register.go`, `find.go`, `activate.go` | `handler_register.go`, `user_get.go` |
| Base file | Layer name | `handler.go`, `service.go`, `repository.go` | `base.go`, `init.go` |

---

## 3. File Rules

These rules apply to each business module inside `internal/modules/<feature>/`:

| Folder | Base file MUST contain | Action files MUST contain | MUST NOT contain |
|--------|----------------------|--------------------------|-----------------|
| `domain/` | Entity struct, `New<Entity>()` with validation, business methods | -- | Framework imports, GORM tags |
| `domain/errors.go` | Sentinel errors (`ErrNotFound`, etc.) | -- | Error handling logic |
| `domain/repository.go` | `Repository` interface | -- | Implementations |
| `service/` | `Service` struct, constructor | One business method per file | HTTP types, GORM types |
| `handler/` | Unexported `service` interface, `Handler` struct, `Register(g)`, response types | One endpoint method per file | Business logic, repo calls |
| `repository/` | Unexported GORM model, mapping funcs, `var _ domain.Repository`, struct | One repo method per file, `fmt.Errorf` wrapping | Business logic, HTTP types |

---

## 4. Adding a New Feature

1. `internal/modules/<feature>/domain/` -- entity, errors, repository interface
2. `internal/modules/<feature>/service/` -- `service.go` + one file per business action
3. `internal/modules/<feature>/handler/` -- `handler.go` + one file per endpoint
4. `internal/modules/<feature>/repository/` -- `repository.go` + one file per DB operation
5. Wire in `internal/infrastructure/server/server.go`

### Anti-Patterns

| Don't | Do | Why |
|-------|----|-----|
| `handler/`, `models/` at top level | `user/`, `order/` (business-first) | Feature changes stay in one module |
| `handler_register.go` | `handler/register.go` | Folder = layer, file = action |
| GORM tags on domain entity | Unexported model in `repository/` | Domain stays framework-free |
| Validation only in handler | `New<Entity>()` validates in domain | Rules enforced at every entry point |
| Default passwords in config | `validate()` fails fast if missing | Prevents silent misconfiguration |
| `.env` in git | `.env.example` committed, `.env` gitignored | Secrets never in VCS |
| Business logic in handler | Handler maps HTTP <-> service only | Logic testable without HTTP |
| Config/database in business module | `infrastructure/config/`, `infrastructure/database/` | Infra concerns separated from domain |
| Bare error returns in repo | `fmt.Errorf("context: %w", err)` | Errors traceable across layers |

---

## 5. Automation

Scaffold a new project using the init script (note: init script may need updating for the new clean architecture structure):

```bash
bash skills/go-engineer/scripts/init-project.sh myapp github.com/user/myapp
bash skills/go-engineer/scripts/init-project.sh --with-migrations myapp github.com/user/myapp
```
