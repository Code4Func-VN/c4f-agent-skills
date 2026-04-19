# REST API Design Patterns -- Echo + GORM

## 1. Error Response Format

**Rule:** Handlers return `echo.NewHTTPError` — the central error handler translates to a consistent JSON envelope. Central handler never imports `domain` or `gorm`.

```go
// internal/httputil/error.go
package httputil

type ErrorResponse struct {
    Error ErrorBody `json:"error"`
}

type ErrorBody struct {
    Code    string            `json:"code"`
    Message string            `json:"message"`
    Fields  map[string]string `json:"fields,omitempty"`
}

// HTTPErrorHandler registers on Echo — only knows about echo.HTTPError.
func HTTPErrorHandler(err error, c echo.Context) {
    if c.Response().Committed {
        return
    }

    code := http.StatusInternalServerError
    body := ErrorBody{Code: "INTERNAL_ERROR", Message: "unexpected error"}

    var he *echo.HTTPError
    if errors.As(err, &he) {
        code = he.Code
        body.Code = http.StatusText(he.Code)
        body.Message = fmt.Sprintf("%v", he.Message)
    }

    _ = c.JSON(code, ErrorResponse{Error: body})
}
```

Handlers do the domain-to-HTTP mapping — central handler stays clean:

```go
// internal/user/handler/register.go — handler maps domain errors
func (h *Handler) register(c echo.Context) error {
    user, err := h.svc.Register(c.Request().Context(), req.Email, req.Name, req.Password)
    if err != nil {
        switch {
        case errors.Is(err, domain.ErrEmailTaken):
            return echo.NewHTTPError(http.StatusConflict, "email already taken")
        case errors.Is(err, domain.ErrInvalidEmail):
            return echo.NewHTTPError(http.StatusBadRequest, "invalid email")
        default:
            return echo.NewHTTPError(http.StatusInternalServerError, "internal error")
        }
    }
    return c.JSON(http.StatusCreated, map[string]any{"data": toResponse(user)})
}
```

**Common mistake:** Central error handler that imports `domain` or `gorm` — couples shared infrastructure to feature modules. Keep mapping in handlers.

## 2. Pagination

**Rule:** Offset-based for most APIs. Cursor-based only for infinite scroll/real-time feeds.

### Offset-based (default)

```go
// internal/httputil/pagination.go
package httputil

type PageParams struct {
    Page    int `query:"page"`
    PerPage int `query:"per_page"`
}

func (p *PageParams) Normalize() {
    if p.Page < 1 {
        p.Page = 1
    }
    if p.PerPage < 1 || p.PerPage > 100 {
        p.PerPage = 20
    }
}

func (p PageParams) Offset() int {
    return (p.Page - 1) * p.PerPage
}

type PageMeta struct {
    Page       int   `json:"page"`
    PerPage    int   `json:"per_page"`
    Total      int64 `json:"total"`
    TotalPages int64 `json:"total_pages"`
}

func NewPageMeta(p PageParams, total int64) PageMeta {
    pages := total / int64(p.PerPage)
    if total%int64(p.PerPage) > 0 {
        pages++
    }
    return PageMeta{Page: p.Page, PerPage: p.PerPage, Total: total, TotalPages: pages}
}

// GORM scope
func Paginate(p PageParams) func(db *gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        return db.Offset(p.Offset()).Limit(p.PerPage)
    }
}
```

### Cursor-based (for feeds)

```go
// internal/httputil/cursor.go
type CursorParams struct {
    Cursor string `query:"cursor"` // base64-encoded last ID
    Limit  int    `query:"limit"`
}

func (p *CursorParams) Normalize() {
    if p.Limit < 1 || p.Limit > 100 {
        p.Limit = 20
    }
}

type CursorMeta struct {
    NextCursor string `json:"next_cursor,omitempty"`
    HasMore    bool   `json:"has_more"`
}
```

**Common mistake:** Running `COUNT(*)` in the same query as `LIMIT/OFFSET`. Always count first, then paginate — two separate queries.

## 3. Filtering & Sorting

**Rule:** Flat query params for filters. `-` prefix for descending sort. **Allow-list** sort fields to prevent SQL injection.
```go
// internal/order/handler/list.go
type listFilter struct {
    Status   string `query:"status"`
    Priority string `query:"priority"`
    Sort     string `query:"sort"` // "-created_at,title"
}

var allowedSorts = map[string]bool{
    "created_at": true, "updated_at": true, "title": true, "priority": true,
}

func applyFilter(f listFilter) func(db *gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        if f.Status != "" {
            db = db.Where("status = ?", f.Status)
        }
        if f.Priority != "" {
            db = db.Where("priority = ?", f.Priority)
        }
        for _, field := range strings.Split(f.Sort, ",") {
            field = strings.TrimSpace(field)
            dir := "ASC"
            if strings.HasPrefix(field, "-") {
                dir = "DESC"
                field = field[1:]
            }
            if allowedSorts[field] {
                db = db.Order(field + " " + dir)
            }
        }
        return db
    }
}
```

**Common mistake:** Passing user input directly into `ORDER BY`. Even with GORM, raw field names in `Order()` are SQL injection vectors without an allow-list.

## 4. Request Validation

**Rule:** Bind first, validate second. `400` for malformed body. `422` for well-formed body that fails validation.
```go
// internal/httputil/validator.go
package httputil

import "github.com/go-playground/validator/v10"

type Validator struct {
    v *validator.Validate
}

func NewValidator() *Validator {
    return &Validator{v: validator.New()}
}

func (cv *Validator) Validate(i any) error {
    return cv.v.Struct(i)
}

// Registration: e.Validator = httputil.NewValidator()
```

```go
// Handler usage
type createRequest struct {
    Title    string `json:"title" validate:"required,min=1,max=255"`
    Priority string `json:"priority" validate:"required,oneof=low medium high"`
}

func (h *Handler) create(c echo.Context) error {
    var req createRequest
    if err := c.Bind(&req); err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "malformed request body")
    }
    if err := c.Validate(&req); err != nil {
        var ve validator.ValidationErrors
        if errors.As(err, &ve) {
            fields := make(map[string]string, len(ve))
            for _, fe := range ve {
                fields[fe.Field()] = fe.Tag()
            }
            return c.JSON(http.StatusUnprocessableEntity, httputil.ErrorResponse{
                Error: httputil.ErrorBody{
                    Code:    "VALIDATION_FAILED",
                    Message: "request validation failed",
                    Fields:  fields,
                },
            })
        }
        return err
    }
    // ... proceed
}
```

**Common mistake:** Using `400` for all input errors. `400` = can't parse the body at all. `422` = parsed fine but values are invalid.

## 5. API Versioning

**Rule:** Version via URL prefix `/api/v1/`. Each version is an isolated Echo route group.
```go
// internal/app/app.go — route registration
api := e.Group("/api")

v1 := api.Group("/v1")
v1.Use(authMiddleware)

userHandler.Register(v1.Group("/users"))
orderHandler.Register(v1.Group("/orders"))

// When v2 is needed — never break v1 contracts
// v2 := api.Group("/v2")
```

**Common mistake:** Versioning via headers. Simpler to test, cache, and debug with URL prefix for most projects.

## 6. Response Conventions

**Rule:** Consistent shapes. Wrap in `{"data": ...}` for single, `{"data": [...], "meta": {...}}` for lists.

```go
// Single resource
return c.JSON(http.StatusOK, map[string]any{"data": toResponse(user)})

// List with pagination
return c.JSON(http.StatusOK, map[string]any{
    "data": toResponseList(users),
    "meta": httputil.NewPageMeta(params, total),
})

// Created — 201 + Location header
c.Response().Header().Set("Location", fmt.Sprintf("/api/v1/users/%s", user.ID))
return c.JSON(http.StatusCreated, map[string]any{"data": toResponse(user)})

// Deleted — 204 no body
return c.NoContent(http.StatusNoContent)

// Empty list — still 200, not 404
return c.JSON(http.StatusOK, map[string]any{"data": []any{}, "meta": meta})
```

**Common mistake:** Returning `404` for empty lists. An empty list is `200` with `[]`. `404` means the specific resource doesn't exist.

## 7. Status Code Guide

| Code | When to use |
|------|-------------|
| `200` | Successful GET, PUT, PATCH |
| `201` | POST created a resource (include `Location` header) |
| `204` | Successful DELETE or PUT with no response body |
| `400` | Malformed JSON, wrong content-type, unparseable params |
| `401` | Missing or invalid authentication token |
| `403` | Authenticated but no permission for this resource |
| `404` | Specific resource not found (not empty list) |
| `409` | Duplicate creation, optimistic lock failure |
| `422` | Valid JSON but fails validation rules |
| `429` | Rate limit exceeded (include `Retry-After` header) |
| `500` | Unhandled panic, DB down, unexpected bug |
| `503` | Planned maintenance, dependency unavailable |

**Rule:** Never return `200` with an error inside the body. Use correct status codes — clients, proxies, and monitoring depend on them.
