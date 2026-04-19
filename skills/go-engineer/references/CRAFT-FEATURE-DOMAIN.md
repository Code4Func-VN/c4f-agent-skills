# Feature Module Pattern — Domain & Service

Each business module has 4 sub-packages: `domain/`, `service/`, `handler/`, `repository/`.
File names are **business actions** — the folder tells you the layer.

---

## domain/ — Entity + Business Rules

Pure Go. No framework imports. Business logic lives on the entity.

```go
// internal/modules/user/domain/user.go
package domain

import (
    "fmt"
    "net/mail"
    "time"

    "golang.org/x/crypto/bcrypt"
)

type User struct {
    ID        string
    Email     string
    Name      string
    Password  string // bcrypt hash
    Active    bool
    CreatedAt time.Time
    UpdatedAt time.Time
}

func NewUser(email, name, password string) (*User, error) {
    if _, err := mail.ParseAddress(email); err != nil {
        return nil, ErrInvalidEmail
    }
    if len(password) < 8 {
        return nil, ErrPasswordTooShort
    }
    hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    if err != nil {
        return nil, fmt.Errorf("hash password: %w", err)
    }
    return &User{Email: email, Name: name, Password: string(hashed), Active: true}, nil
}

func (u *User) CheckPassword(pw string) bool {
    return bcrypt.CompareHashAndPassword([]byte(u.Password), []byte(pw)) == nil
}

func (u *User) Deactivate() { u.Active = false }
```

```go
// internal/modules/user/domain/errors.go
package domain

import "errors"

var (
    ErrNotFound         = errors.New("user not found")
    ErrEmailTaken       = errors.New("email already taken")
    ErrInvalidEmail     = errors.New("invalid email format")
    ErrPasswordTooShort = errors.New("password must be at least 8 characters")
)
```

```go
// internal/modules/user/domain/repository.go
package domain

import "context"

type Repository interface {
    Create(ctx context.Context, user *User) error
    FindByID(ctx context.Context, id string) (*User, error)
    FindByEmail(ctx context.Context, email string) (*User, error)
}
```

---

## service/ — Business Rule Orchestration

One file per business action. Imports only `domain`.

```go
// internal/modules/user/service/service.go
package service

import "yourmodule/internal/modules/user/domain"

type Service struct{ repo domain.Repository }

func New(repo domain.Repository) *Service {
    return &Service{repo: repo}
}
```

```go
// internal/modules/user/service/register.go
package service

import (
    "context"
    "errors"
    "fmt"

    "yourmodule/internal/modules/user/domain"
)

func (s *Service) Register(ctx context.Context, email, name, password string) (*domain.User, error) {
    existing, err := s.repo.FindByEmail(ctx, email)
    if err != nil && !errors.Is(err, domain.ErrNotFound) {
        return nil, fmt.Errorf("check existing: %w", err)
    }
    if existing != nil {
        return nil, domain.ErrEmailTaken
    }
    user, err := domain.NewUser(email, name, password)
    if err != nil {
        return nil, err
    }
    if err := s.repo.Create(ctx, user); err != nil {
        return nil, fmt.Errorf("save user: %w", err)
    }
    return user, nil
}
```

```go
// internal/modules/user/service/find.go
package service

import (
    "context"
    "fmt"

    "yourmodule/internal/modules/user/domain"
)

func (s *Service) GetByID(ctx context.Context, id string) (*domain.User, error) {
    user, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("get user: %w", err)
    }
    if !user.Active {
        return nil, domain.ErrNotFound // business rule: inactive = not found
    }
    return user, nil
}
```
