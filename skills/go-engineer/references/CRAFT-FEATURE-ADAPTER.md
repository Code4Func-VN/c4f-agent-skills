# Feature Module Pattern — Handler & Repository

---

## handler/ — HTTP Layer

Handler defines its **own** `service` interface. One endpoint per file.

```go
// internal/modules/user/handler/handler.go
package handler

import (
    "context"

    "github.com/labstack/echo/v4"

    "yourmodule/internal/modules/user/domain"
)

type service interface {
    Register(ctx context.Context, email, name, password string) (*domain.User, error)
    GetByID(ctx context.Context, id string) (*domain.User, error)
}

type Handler struct{ svc service }

func New(svc service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(g *echo.Group) {
    g.POST("/register", h.register)
    g.GET("/:id", h.find)
}

type userResponse struct {
    ID    string `json:"id"`
    Email string `json:"email"`
    Name  string `json:"name"`
}
```

```go
// internal/modules/user/handler/register.go — business action name, not "handler_register"
package handler

import (
    "errors"
    "net/http"

    "github.com/labstack/echo/v4"

    "yourmodule/internal/modules/user/domain"
)

type registerRequest struct {
    Email    string `json:"email"`
    Name     string `json:"name"`
    Password string `json:"password"`
}

func (h *Handler) register(c echo.Context) error {
    var req registerRequest
    if err := c.Bind(&req); err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid request body")
    }
    user, err := h.svc.Register(c.Request().Context(), req.Email, req.Name, req.Password)
    if err != nil {
        switch {
        case errors.Is(err, domain.ErrEmailTaken):
            return echo.NewHTTPError(http.StatusConflict, err.Error())
        case errors.Is(err, domain.ErrInvalidEmail), errors.Is(err, domain.ErrPasswordTooShort):
            return echo.NewHTTPError(http.StatusBadRequest, err.Error())
        default:
            return echo.NewHTTPError(http.StatusInternalServerError, "internal error")
        }
    }
    return c.JSON(http.StatusCreated, userResponse{ID: user.ID, Email: user.Email, Name: user.Name})
}
```

```go
// internal/modules/user/handler/find.go
package handler

import (
    "errors"
    "net/http"

    "github.com/labstack/echo/v4"

    "yourmodule/internal/modules/user/domain"
)

func (h *Handler) find(c echo.Context) error {
    user, err := h.svc.GetByID(c.Request().Context(), c.Param("id"))
    if err != nil {
        if errors.Is(err, domain.ErrNotFound) {
            return echo.NewHTTPError(http.StatusNotFound, err.Error())
        }
        return echo.NewHTTPError(http.StatusInternalServerError, "internal error")
    }
    return c.JSON(http.StatusOK, userResponse{ID: user.ID, Email: user.Email, Name: user.Name})
}
```

---

## repository/ — GORM Implementation

Unexported model keeps domain entity clean. One operation per file.

```go
// internal/modules/user/repository/repository.go
package repository

import (
    "time"

    "gorm.io/gorm"

    "yourmodule/internal/modules/user/domain"
)

type userModel struct {
    ID        string `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
    Email     string `gorm:"uniqueIndex;not null"`
    Name      string `gorm:"not null"`
    Password  string `gorm:"not null"`
    Active    bool   `gorm:"default:true"`
    CreatedAt time.Time
    UpdatedAt time.Time
}

func (userModel) TableName() string { return "users" }

func toModel(u *domain.User) *userModel {
    return &userModel{
        ID: u.ID, Email: u.Email, Name: u.Name,
        Password: u.Password, Active: u.Active,
        CreatedAt: u.CreatedAt, UpdatedAt: u.UpdatedAt,
    }
}

func (m *userModel) toDomain() *domain.User {
    return &domain.User{
        ID: m.ID, Email: m.Email, Name: m.Name,
        Password: m.Password, Active: m.Active,
        CreatedAt: m.CreatedAt, UpdatedAt: m.UpdatedAt,
    }
}

var _ domain.Repository = (*GormRepository)(nil)

type GormRepository struct{ db *gorm.DB }

func New(db *gorm.DB) *GormRepository {
    return &GormRepository{db: db}
}
```

```go
// internal/modules/user/repository/create.go
package repository

import (
    "context"
    "fmt"

    "yourmodule/internal/modules/user/domain"
)

func (r *GormRepository) Create(ctx context.Context, u *domain.User) error {
    model := toModel(u)
    if err := r.db.WithContext(ctx).Create(model).Error; err != nil {
        return fmt.Errorf("insert user: %w", err)
    }
    u.ID = model.ID
    u.CreatedAt = model.CreatedAt
    return nil
}
```

```go
// internal/modules/user/repository/find.go
package repository

import (
    "context"
    "errors"
    "fmt"

    "gorm.io/gorm"

    "yourmodule/internal/modules/user/domain"
)

func (r *GormRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
    var model userModel
    if err := r.db.WithContext(ctx).Where("id = ?", id).First(&model).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, domain.ErrNotFound
        }
        return nil, fmt.Errorf("find user by id: %w", err)
    }
    return model.toDomain(), nil
}

func (r *GormRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    var model userModel
    if err := r.db.WithContext(ctx).Where("email = ?", email).First(&model).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, domain.ErrNotFound
        }
        return nil, fmt.Errorf("find user by email: %w", err)
    }
    return model.toDomain(), nil
}
```
