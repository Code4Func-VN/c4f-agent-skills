# Go Project Blueprint — Config, Wiring & Docker

## 1. Config & Environment

### config.go

```go
package config

import (
    "fmt"
    "os"
    "strings"
)

type Config struct {
    Env      string // "local" or "production"
    Server   ServerConfig
    Database DatabaseConfig
}

type ServerConfig struct{ Port string }

type DatabaseConfig struct{ Host, Port, User, Password, Name, SSLMode string }

func (c DatabaseConfig) DSN() string {
    return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
        c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode)
}

func Load() (*Config, error) {
    cfg := &Config{
        Env: env("APP_ENV", "local"),
        Server: ServerConfig{Port: env("SERVER_PORT", "8080")},
        Database: DatabaseConfig{
            Host:     env("DB_HOST", "localhost"),
            Port:     env("DB_PORT", "5432"),
            User:     env("DB_USER", ""),
            Password: env("DB_PASSWORD", ""),
            Name:     env("DB_NAME", ""),
            SSLMode:  env("DB_SSLMODE", "disable"),
        },
    }
    if err := cfg.validate(); err != nil {
        return nil, fmt.Errorf("config: %w", err)
    }
    return cfg, nil
}

func (c *Config) IsProduction() bool { return c.Env == "production" }

func (c *Config) validate() error {
    var missing []string
    if c.Database.User == "" {
        missing = append(missing, "DB_USER")
    }
    if c.Database.Password == "" {
        missing = append(missing, "DB_PASSWORD")
    }
    if c.Database.Name == "" {
        missing = append(missing, "DB_NAME")
    }
    if len(missing) > 0 {
        return fmt.Errorf("required env vars not set: %s", strings.Join(missing, ", "))
    }
    if c.IsProduction() && c.Database.SSLMode == "disable" {
        return fmt.Errorf("DB_SSLMODE=disable is not allowed in production")
    }
    return nil
}

func env(key, fallback string) string {
    if v := os.Getenv(key); v != "" {
        return v
    }
    return fallback
}
```

### .env.example -- committed to git

```
APP_ENV=local
SERVER_PORT=8080
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=changeme
DB_NAME=myapp
DB_SSLMODE=disable
```

### Security Rules

| Rule | Enforcement |
|------|-------------|
| No default passwords | `validate()` requires `DB_USER`, `DB_PASSWORD`, `DB_NAME` |
| SSL in production | `validate()` blocks `DB_SSLMODE=disable` in production |
| Secrets not in git | `.gitignore` excludes `.env`, includes `.env.example` |
| `.env` loading | `godotenv.Load()` -- silently ignored if file missing (production) |
| GORM logging | `Silent` in production to prevent leaking SQL with secrets |

### Environment Differences

| Concern | Local | Production |
|---------|-------|------------|
| Secrets source | `.env` file | Platform env vars (K8s, ECS) |
| `.env` loaded? | Yes | No (file doesn't exist) |
| DB SSL | `disable` | `require` or `verify-full` |
| GORM log | `Info` | `Silent` |
| Echo logger | Enabled | Disabled |

## 2. Wiring & Bootstrap

`server.go` is the composition root -- wires all dependencies and manages lifecycle.

### server.go

```go
package server

import (
    "context"
    "log/slog"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/joho/godotenv"
    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"

    "yourmodule/internal/infrastructure/config"
    "yourmodule/internal/infrastructure/database"
    userHandler "yourmodule/internal/modules/user/handler"
    userRepo "yourmodule/internal/modules/user/repository"
    userService "yourmodule/internal/modules/user/service"
)

func Run() {
    slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

    // Load .env in local only — production uses real env vars
    _ = godotenv.Load()

    cfg, err := config.Load()
    if err != nil {
        slog.Error("invalid config", "err", err)
        os.Exit(1)
    }

    db, err := database.Connect(cfg)
    if err != nil {
        slog.Error("failed to connect database", "err", err)
        os.Exit(1)
    }

    // Wire feature modules
    uRepo := userRepo.New(db)
    uService := userService.New(uRepo)
    uHandler := userHandler.New(uService)

    // Echo
    e := echo.New()
    e.HideBanner = true
    e.Use(middleware.Recover())
    e.Use(middleware.RequestID())
    if !cfg.IsProduction() {
        e.Use(middleware.Logger())
    }

    // Routes — each feature registers its own
    api := e.Group("/api")
    uHandler.Register(api.Group("/users"))

    // Start
    go func() {
        slog.Info("server starting", "port", cfg.Server.Port, "env", cfg.Env)
        if err := e.Start(":" + cfg.Server.Port); err != nil {
            slog.Info("server stopped", "reason", err)
        }
    }()

    // Graceful shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    e.Shutdown(ctx)
}
```

### database.go

```go
package database

import (
    "fmt"

    "gorm.io/driver/postgres"
    "gorm.io/gorm"
    "gorm.io/gorm/logger"

    "yourmodule/internal/infrastructure/config"
)

func Connect(cfg *config.Config) (*gorm.DB, error) {
    logLevel := logger.Info
    if cfg.IsProduction() {
        logLevel = logger.Silent
    }

    db, err := gorm.Open(postgres.Open(cfg.Database.DSN()), &gorm.Config{
        Logger: logger.Default.LogMode(logLevel),
    })
    if err != nil {
        return nil, fmt.Errorf("open database: %w", err)
    }

    sqlDB, err := db.DB()
    if err != nil {
        return nil, fmt.Errorf("get sql.DB: %w", err)
    }
    if err := sqlDB.Ping(); err != nil {
        return nil, fmt.Errorf("ping database: %w", err)
    }
    return db, nil
}
```

### Adding a New Feature to server.go

Add 3 lines for wiring plus 1 line for routes:

```go
// Wire
oRepo := orderRepo.New(db)
oService := orderService.New(oRepo)
oHandler := orderHandler.New(oService)

// Routes
oHandler.Register(api.Group("/orders"))
```

---

## 3. Docker

### Dockerfile -- multi-stage production

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/app ./cmd/api

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /bin/app /bin/app
ENTRYPOINT ["/bin/app"]
```

### docker-compose.yml -- local development

```yaml
services:
  app:
    build: .
    ports:
      - "${SERVER_PORT:-8080}:8080"
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${DB_USER:-postgres}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-changeme}
      POSTGRES_DB: ${DB_NAME:-myapp}
    ports:
      - "${DB_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-postgres}"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```
