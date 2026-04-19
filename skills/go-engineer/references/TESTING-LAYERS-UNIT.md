# Testing Layers — Unit Tests (Domain & Service)

## Testing Strategy

| Layer | What to Test | How | Dependencies |
|------------|--------------------------------------|--------------------------------------|--------------------------|
| Domain | Constructors, validation, methods | Pure unit tests | None |
| Service | Business rule orchestration | Unit tests with mock repositories | Mock repo interface |
| Handler | HTTP status codes, response body | `httptest` + Echo test context | Mock service interface |
| Repository | CRUD operations, constraint errors | Integration tests with real DB | Testcontainers / dockertest |

> **Normative**: Each layer tests only its own logic. Never reach through a
> layer boundary — mock the dependency below.

---

## Domain Tests

**When to use:** Testing entity constructors, validation rules, and pure
business methods. Domain has zero external dependencies so no mocks are needed.

```go
package task_test

import (
    "testing"

    "github.com/google/go-cmp/cmp"
    "myapp/internal/task/domain"
)

func TestNewTask(t *testing.T) {
    tests := []struct {
        name    string
        title   string
        wantErr bool
    }{
        {name: "valid title", title: "Buy groceries", wantErr: false},
        {name: "empty title", title: "", wantErr: true},
        {name: "whitespace only", title: "   ", wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            task, err := domain.NewTask(tt.title)
            if gotErr := err != nil; gotErr != tt.wantErr {
                t.Errorf("NewTask(%q) error = %v, want error = %t", tt.title, err, tt.wantErr)
            }
            if err == nil && task.Title != tt.title {
                t.Errorf("NewTask(%q).Title = %q, want %q", tt.title, task.Title, tt.title)
            }
        })
    }
}

func TestTask_Complete(t *testing.T) {
    task, _ := domain.NewTask("Do laundry")

    task.Complete()

    want := domain.StatusDone
    if task.Status != want {
        t.Errorf("Task.Complete() status = %v, want %v", task.Status, want)
    }
}
```

**Common mistake:** Testing domain objects with a live database. Domain tests
must run with zero infrastructure — if you need a DB, you are testing the
repository layer.

---

## Service Tests

**When to use:** Testing business rule orchestration that coordinates between
domain entities and repository calls. Mock the repository interface to isolate
service logic.

```go
package task_test

import (
    "context"
    "errors"
    "testing"

    "github.com/google/go-cmp/cmp"
    "myapp/internal/task/domain"
    "myapp/internal/task/service"
)

// mockTaskRepo implements repository.TaskRepository with manual mocks.
type mockTaskRepo struct {
    createFn func(ctx context.Context, t *domain.Task) error
    getByIDFn func(ctx context.Context, id string) (*domain.Task, error)
}

func (m *mockTaskRepo) Create(ctx context.Context, t *domain.Task) error {
    return m.createFn(ctx, t)
}

func (m *mockTaskRepo) GetByID(ctx context.Context, id string) (*domain.Task, error) {
    return m.getByIDFn(ctx, id)
}

func TestTaskService_Create(t *testing.T) {
    tests := []struct {
        name    string
        title   string
        repoErr error
        wantErr bool
    }{
        {name: "success", title: "New task", repoErr: nil, wantErr: false},
        {name: "repo failure", title: "New task", repoErr: errors.New("db down"), wantErr: true},
        {name: "invalid title", title: "", repoErr: nil, wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            repo := &mockTaskRepo{
                createFn: func(_ context.Context, _ *domain.Task) error {
                    return tt.repoErr
                },
            }
            svc := service.NewTaskService(repo)

            _, err := svc.Create(context.Background(), tt.title)
            if gotErr := err != nil; gotErr != tt.wantErr {
                t.Errorf("Create(%q) error = %v, want error = %t", tt.title, err, tt.wantErr)
            }
        })
    }
}

func TestTaskService_GetByID(t *testing.T) {
    want := &domain.Task{ID: "abc-123", Title: "Found task"}

    repo := &mockTaskRepo{
        getByIDFn: func(_ context.Context, id string) (*domain.Task, error) {
            if id == "abc-123" {
                return want, nil
            }
            return nil, domain.ErrTaskNotFound
        },
    }
    svc := service.NewTaskService(repo)

    got, err := svc.GetByID(context.Background(), "abc-123")
    if err != nil {
        t.Fatalf("GetByID(%q) unexpected error: %v", "abc-123", err)
    }
    if diff := cmp.Diff(want, got); diff != "" {
        t.Errorf("GetByID() mismatch (-want +got):\n%s", diff)
    }
}
```

**Common mistake:** Putting conditional logic inside mock functions. If the mock
needs branching, the test is doing too much — split into separate test cases.
