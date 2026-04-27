#!/usr/bin/env bash
set -euo pipefail

VERSION="4.0.0"
SCRIPT_NAME="$(basename "$0")"

WITH_MIGRATIONS=false
FORCE=false
JSON_OUTPUT=false

usage() {
    cat <<EOF
$SCRIPT_NAME v$VERSION — Scaffold a Go project (Echo + GORM + Postgres + Redis, clean architecture)

USAGE
    bash $SCRIPT_NAME [options] <project-name> <module-path>

OPTIONS
    -h, --help           Show this help message
    -v, --version        Show version
    --with-migrations    Include migrations directory with initial SQL
    --force              Overwrite existing project directory
    --json               Output structured JSON metadata

STRUCTURE
    internal/
      infrastructure/    config, database, cache (redis), server
      modules/           business modules (user/, order/, …)
      shared/            response helpers, apperrors, middleware

EXAMPLES
    bash $SCRIPT_NAME myapp github.com/user/myapp
    bash $SCRIPT_NAME --with-migrations myapp github.com/user/myapp
EOF
}

die() { echo "error: $*" >&2; exit 2; }

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -v|--version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
        --with-migrations) WITH_MIGRATIONS=true; shift ;;
        --force) FORCE=true; shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        -*) die "unknown option: $1" ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

[[ ${#POSITIONAL[@]} -ge 2 ]] || die "requires <project-name> and <module-path>"
PROJECT_NAME="${POSITIONAL[0]}"
MODULE_PATH="${POSITIONAL[1]}"

if [[ -d "$PROJECT_NAME" && "$FORCE" == false ]]; then
    die "directory '$PROJECT_NAME' already exists (use --force to overwrite)"
fi
[[ -d "$PROJECT_NAME" && "$FORCE" == true ]] && rm -rf "$PROJECT_NAME"

CREATED_FILES=()

create_file() {
    local filepath="$1" content="$2"
    mkdir -p "$PROJECT_NAME/$(dirname "$filepath")"
    printf '%s\n' "$content" > "$PROJECT_NAME/$filepath"
    CREATED_FILES+=("$filepath")
}

# ── go.mod ────────────────────────────────────────────────────────────────────
create_file "go.mod" "module $MODULE_PATH

go 1.23

require (
	github.com/joho/godotenv v1.5.1
	github.com/labstack/echo/v4 v4.13.3
	github.com/redis/go-redis/v9 v9.7.0
	golang.org/x/crypto v0.31.0
	gorm.io/driver/postgres v1.5.11
	gorm.io/gorm v1.25.12
)"

# ── cmd/api/main.go ───────────────────────────────────────────────────────────
create_file "cmd/api/main.go" '// Package main is the entry point for the API server.
package main

import "'"$MODULE_PATH"'/internal/infrastructure/server"

func main() { server.Run() }'

# ── internal/infrastructure/config/config.go ─────────────────────────────────
create_file "internal/infrastructure/config/config.go" '// Package config loads and validates application configuration from environment variables.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds all application configuration.
type Config struct {
	Env      string
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct{ Port string }

// DatabaseConfig holds Postgres connection settings.
type DatabaseConfig struct{ Host, Port, User, Password, Name, SSLMode string }

// DSN returns a PostgreSQL connection string.
func (c DatabaseConfig) DSN() string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode)
}

// RedisConfig holds Redis connection settings.
type RedisConfig struct {
	Host     string
	Port     string
	Password string
	DB       int
}

// Addr returns the Redis address in host:port form.
func (c RedisConfig) Addr() string { return c.Host + ":" + c.Port }

// Load reads configuration from environment variables and validates it.
func Load() (*Config, error) {
	cfg := &Config{
		Env: env("APP_ENV", "local"),
		Server: ServerConfig{
			Port: env("SERVER_PORT", "8080"),
		},
		Database: DatabaseConfig{
			Host:     env("DB_HOST", "localhost"),
			Port:     env("DB_PORT", "5432"),
			User:     env("DB_USER", ""),
			Password: env("DB_PASSWORD", ""),
			Name:     env("DB_NAME", ""),
			SSLMode:  env("DB_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Host:     env("REDIS_HOST", "localhost"),
			Port:     env("REDIS_PORT", "6379"),
			Password: env("REDIS_PASSWORD", ""),
			DB:       envInt("REDIS_DB", 0),
		},
	}
	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("config: %w", err)
	}
	return cfg, nil
}

// IsProduction returns true when running in production environment.
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

func envInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}'

# ── internal/infrastructure/database/database.go ─────────────────────────────
create_file "internal/infrastructure/database/database.go" '// Package database provides GORM database connection management.
package database

import (
	"fmt"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"'"$MODULE_PATH"'/internal/infrastructure/config"
)

// Connect opens a GORM database connection and verifies connectivity.
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
}'

# ── internal/infrastructure/cache/cache.go ────────────────────────────────────
create_file "internal/infrastructure/cache/cache.go" '// Package cache provides Redis client management.
package cache

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"

	"'"$MODULE_PATH"'/internal/infrastructure/config"
)

// Connect creates a Redis client and verifies connectivity.
func Connect(cfg *config.Config) (*redis.Client, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     cfg.Redis.Addr(),
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	if err := client.Ping(context.Background()).Err(); err != nil {
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return client, nil
}'

# ── internal/infrastructure/server/server.go ─────────────────────────────────
create_file "internal/infrastructure/server/server.go" '// Package server wires all dependencies and manages the application lifecycle.
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

	"'"$MODULE_PATH"'/internal/infrastructure/cache"
	"'"$MODULE_PATH"'/internal/infrastructure/config"
	"'"$MODULE_PATH"'/internal/infrastructure/database"
	userHandler "'"$MODULE_PATH"'/internal/modules/user/handler"
	userRepo "'"$MODULE_PATH"'/internal/modules/user/repository"
	userService "'"$MODULE_PATH"'/internal/modules/user/service"
)

// Run bootstraps and starts the application with graceful shutdown.
func Run() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

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

	rdb, err := cache.Connect(cfg)
	if err != nil {
		slog.Error("failed to connect redis", "err", err)
		os.Exit(1)
	}
	_ = rdb // wire into services/repositories that need caching

	// Wire feature modules
	uRepo := userRepo.New(db)
	uSvc := userService.New(uRepo)
	uHandler := userHandler.New(uSvc)

	// Echo
	e := echo.New()
	e.HideBanner = true
	e.Use(middleware.Recover())
	e.Use(middleware.RequestID())
	if !cfg.IsProduction() {
		e.Use(middleware.Logger())
	}

	// Routes — each module registers its own
	api := e.Group("/api")
	uHandler.Register(api.Group("/users"))

	go func() {
		slog.Info("server starting", "port", cfg.Server.Port, "env", cfg.Env)
		if err := e.Start(":" + cfg.Server.Port); err != nil {
			slog.Info("server stopped", "reason", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	e.Shutdown(ctx)
}'

# ── internal/shared/response/response.go ─────────────────────────────────────
create_file "internal/shared/response/response.go" '// Package response provides shared HTTP response helpers for Echo handlers.
package response

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// ErrorResponse is the standard JSON error envelope.
type ErrorResponse struct {
	Error string `json:"error"`
}

// Error writes a JSON error response with the given status code.
func Error(c echo.Context, status int, msg string) error {
	return c.JSON(status, ErrorResponse{Error: msg})
}

// OK writes a 200 JSON response.
func OK(c echo.Context, data any) error {
	return c.JSON(http.StatusOK, data)
}

// Created writes a 201 JSON response.
func Created(c echo.Context, data any) error {
	return c.JSON(http.StatusCreated, data)
}'

# ── internal/modules/user/domain/ ─────────────────────────────────────────────
create_file "internal/modules/user/domain/user.go" '// Package domain defines the user entity, business rules, and repository interface.
package domain

import (
	"fmt"
	"net/mail"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// User is the core user entity.
type User struct {
	ID        string
	Email     string
	Name      string
	Password  string // bcrypt hash
	Active    bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// NewUser creates a User with validation and password hashing.
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

	return &User{
		Email:    email,
		Name:     name,
		Password: string(hashed),
		Active:   true,
	}, nil
}

// CheckPassword verifies a plaintext password against the hash.
func (u *User) CheckPassword(password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(u.Password), []byte(password)) == nil
}

// Deactivate marks the user as inactive.
func (u *User) Deactivate() { u.Active = false }'

create_file "internal/modules/user/domain/errors.go" 'package domain

import "errors"

// Sentinel errors for the user domain.
var (
	ErrNotFound         = errors.New("user not found")
	ErrEmailTaken       = errors.New("email already taken")
	ErrInvalidEmail     = errors.New("invalid email format")
	ErrPasswordTooShort = errors.New("password must be at least 8 characters")
)'

create_file "internal/modules/user/domain/repository.go" 'package domain

import "context"

// Repository defines the persistence contract for users.
type Repository interface {
	Create(ctx context.Context, user *User) error
	FindByID(ctx context.Context, id string) (*User, error)
	FindByEmail(ctx context.Context, email string) (*User, error)
}'

# ── internal/modules/user/service/ ────────────────────────────────────────────
create_file "internal/modules/user/service/service.go" '// Package service implements the business logic for users.
package service

import (
	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

// Service orchestrates user business rules.
type Service struct {
	repo domain.Repository
}

// New creates a new Service.
func New(repo domain.Repository) *Service {
	return &Service{repo: repo}
}'

create_file "internal/modules/user/service/register.go" 'package service

import (
	"context"
	"errors"
	"fmt"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

// Register creates a new user after checking for duplicates.
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
}'

create_file "internal/modules/user/service/find.go" 'package service

import (
	"context"
	"fmt"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

// GetByID returns an active user by ID.
func (s *Service) GetByID(ctx context.Context, id string) (*domain.User, error) {
	user, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	if !user.Active {
		return nil, domain.ErrNotFound
	}
	return user, nil
}'

# ── internal/modules/user/handler/ ────────────────────────────────────────────
create_file "internal/modules/user/handler/handler.go" '// Package handler provides HTTP endpoints for the user module.
package handler

import (
	"context"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

type service interface {
	Register(ctx context.Context, email, name, password string) (*domain.User, error)
	GetByID(ctx context.Context, id string) (*domain.User, error)
}

// Handler serves HTTP requests for the user module.
type Handler struct {
	svc service
}

// New creates a new Handler.
func New(svc service) *Handler {
	return &Handler{svc: svc}
}

// Register mounts all user routes on the given group.
func (h *Handler) Register(g *echo.Group) {
	g.POST("/register", h.register)
	g.GET("/:id", h.getByID)
}

type userResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
}'

create_file "internal/modules/user/handler/register.go" 'package handler

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
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

	return c.JSON(http.StatusCreated, userResponse{
		ID:    user.ID,
		Email: user.Email,
		Name:  user.Name,
	})
}'

create_file "internal/modules/user/handler/find.go" 'package handler

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

func (h *Handler) getByID(c echo.Context) error {
	user, err := h.svc.GetByID(c.Request().Context(), c.Param("id"))
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return echo.NewHTTPError(http.StatusNotFound, err.Error())
		}
		return echo.NewHTTPError(http.StatusInternalServerError, "internal error")
	}

	return c.JSON(http.StatusOK, userResponse{
		ID:    user.ID,
		Email: user.Email,
		Name:  user.Name,
	})
}'

# ── internal/modules/user/repository/ ────────────────────────────────────────
create_file "internal/modules/user/repository/repository.go" '// Package repository implements user persistence using GORM.
package repository

import (
	"time"

	"gorm.io/gorm"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
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

// GormRepository implements domain.Repository using GORM.
type GormRepository struct{ db *gorm.DB }

// New creates a new GormRepository.
func New(db *gorm.DB) *GormRepository { return &GormRepository{db: db} }'

create_file "internal/modules/user/repository/create.go" 'package repository

import (
	"context"
	"fmt"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

// Create inserts a new user and populates the generated ID and timestamps.
func (r *GormRepository) Create(ctx context.Context, u *domain.User) error {
	model := toModel(u)
	if err := r.db.WithContext(ctx).Create(model).Error; err != nil {
		return fmt.Errorf("insert user: %w", err)
	}
	u.ID = model.ID
	u.CreatedAt = model.CreatedAt
	return nil
}'

create_file "internal/modules/user/repository/find.go" 'package repository

import (
	"context"
	"errors"
	"fmt"

	"gorm.io/gorm"

	"'"$MODULE_PATH"'/internal/modules/user/domain"
)

// FindByID returns a user by primary key.
func (r *GormRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
	var m userModel
	if err := r.db.WithContext(ctx).Where("id = ?", id).First(&m).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, domain.ErrNotFound
		}
		return nil, fmt.Errorf("find user by id: %w", err)
	}
	return m.toDomain(), nil
}

// FindByEmail returns a user by email address.
func (r *GormRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	var m userModel
	if err := r.db.WithContext(ctx).Where("email = ?", email).First(&m).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, domain.ErrNotFound
		}
		return nil, fmt.Errorf("find user by email: %w", err)
	}
	return m.toDomain(), nil
}'

# ── .env.example ──────────────────────────────────────────────────────────────
create_file ".env.example" "APP_ENV=local
SERVER_PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=changeme
DB_NAME=$PROJECT_NAME
DB_SSLMODE=disable

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0"

# ── .env (local defaults, git-ignored) ───────────────────────────────────────
create_file ".env" "APP_ENV=local
SERVER_PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=changeme
DB_NAME=$PROJECT_NAME
DB_SSLMODE=disable

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0"

# ── Dockerfile ────────────────────────────────────────────────────────────────
create_file "Dockerfile" 'FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/app ./cmd/api

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /bin/app /bin/app
ENTRYPOINT ["/bin/app"]'

# ── docker-compose.yml ────────────────────────────────────────────────────────
create_file "docker-compose.yml" "services:
  app:
    build: .
    ports:
      - \"\${SERVER_PORT:-8080}:8080\"
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: \${DB_USER:-postgres}
      POSTGRES_PASSWORD: \${DB_PASSWORD:-changeme}
      POSTGRES_DB: \${DB_NAME:-$PROJECT_NAME}
    ports:
      - \"\${DB_PORT:-5432}:5432\"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U \${DB_USER:-postgres}\"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - \"\${REDIS_PORT:-6379}:6379\"
    volumes:
      - redisdata:/data
    healthcheck:
      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  redisdata:"

# ── Makefile ──────────────────────────────────────────────────────────────────
create_file "Makefile" ".PHONY: build run test lint clean dev

APP_NAME := $PROJECT_NAME

build:
	go build -o bin/\$(APP_NAME) ./cmd/api

run:
	go run ./cmd/api

dev:
	docker-compose up -d postgres redis
	go run ./cmd/api

test:
	go test ./... -race -count=1

lint:
	golangci-lint run ./...

clean:
	rm -rf bin/"

# ── .gitignore ────────────────────────────────────────────────────────────────
create_file ".gitignore" 'bin/
*.exe
*.test
*.out
vendor/
.idea/
.vscode/
*.swp
.env
!.env.example
.DS_Store'

# ── .golangci.yml ─────────────────────────────────────────────────────────────
create_file ".golangci.yml" 'run:
  timeout: 5m

linters:
  enable:
    - errcheck
    - govet
    - staticcheck
    - unused
    - gosimple
    - ineffassign

linters-settings:
  errcheck:
    check-type-assertions: true'

# ── Migrations (optional) ─────────────────────────────────────────────────────
if [[ "$WITH_MIGRATIONS" == true ]]; then
    create_file "migrations/001_create_users.sql" '-- +migrate Up
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email      TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    password   TEXT NOT NULL,
    active     BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);

-- +migrate Down
DROP TABLE IF EXISTS users;'
fi

# ── Memory Bank ───────────────────────────────────────────────────────────────
create_file "CLAUDE.md" "# CLAUDE.md

Project này dùng **Memory Bank** — hệ thống bộ nhớ ngoài giúp Claude nhớ context giữa các session.

---

## Đọc trước khi làm bất cứ thứ gì

Đọc các file sau theo thứ tự khi bắt đầu session mới:

1. [memory/active.md](memory/active.md) — đang làm gì, next step là gì ← **đọc đây trước**
2. [memory/project.md](memory/project.md) — app này làm gì, business rules
3. [memory/tech.md](memory/tech.md) — stack, conventions, cách setup local
4. [memory/decisions.md](memory/decisions.md) — quyết định kiến trúc đã chốt
5. [memory/gotchas.md](memory/gotchas.md) — bẫy đã từng gây bug

Đọc [memory/progress.md](memory/progress.md) khi cần biết toàn cảnh tiến độ.

---

## Kiến trúc bắt buộc

Clean Architecture 3 layer — không được thay đổi mà không có lý do rõ ràng:

- \`internal/infrastructure/\` — config, database (GORM/Postgres), cache (Redis), server (Echo)
- \`internal/modules/<feature>/\` — domain / service / handler / repository
- \`internal/shared/\` — response helpers, middleware dùng chung

Khi thêm feature mới: tạo \`internal/modules/<feature>/\`, không đặt code vào infrastructure hay shared.

---

## Quy tắc làm việc

### Trước khi code
- Tóm tắt ngắn: sẽ làm gì, file nào thay đổi, tại sao
- Nếu task đụng đến quyết định trong \`memory/decisions.md\`, xác nhận trước khi đi khác đi
- Nếu chưa rõ requirement, hỏi lại — đừng đoán rồi làm sai

### Trong khi code
- Không sửa file ngoài phạm vi task
- Error wrapping bắt buộc: \`fmt.Errorf(\"context: %w\", err)\`
- Domain entity không được import framework (Echo, GORM...)
- Handler chỉ map HTTP ↔ service, không chứa business logic

### Khi memory mâu thuẫn với code
Tin vào code — code là source of truth. Sau đó cập nhật memory cho đúng.

### Cuối mỗi session
Chạy \`/memory\` để cập nhật memory bank. Hoặc tự nhắc:
1. Cập nhật \`memory/active.md\` — trạng thái hiện tại, next step
2. Nếu xong feature → cập nhật \`memory/progress.md\`
3. Nếu phát hiện bug pattern mới → thêm vào \`memory/gotchas.md\`
4. Nếu chốt quyết định kiến trúc → thêm vào \`memory/decisions.md\`

---

## Cập nhật memory khi có thay đổi lớn

| Chuyện gì xảy ra | Cập nhật file nào |
|---|---|
| Thêm dependency mới | \`memory/tech.md\` |
| Chốt quyết định kiến trúc | \`memory/decisions.md\` |
| Phát hiện bug pattern | \`memory/gotchas.md\` |
| Xong một tính năng | \`memory/progress.md\` |
| Đổi hướng làm | \`memory/active.md\` + \`memory/progress.md\` |
| App thay đổi scope | \`memory/project.md\` |
| Memory file > 80 dòng | Prune: xóa entries cũ, completed, có thể suy ra từ code |"

create_file "memory/active.md" "# Session Hiện Tại

> File này thay đổi thường xuyên nhất — cập nhật cuối mỗi session làm việc.
> Mục đích: Claude đọc vào là biết ngay hôm nay tiếp tục từ đâu.

---

## Đang làm gì

**Tính năng:** Init project

**Trạng thái:** Vừa scaffold xong, chưa có feature nào

---

## Đã làm trong session gần nhất

1. Chạy \`init-project.sh\` — tạo cấu trúc project với Echo + GORM + Postgres + Redis
2. \`go mod tidy\` để download dependencies
3. Kiểm tra \`make dev\` chạy được (Postgres + Redis + app)

## Còn phải làm (bắt đầu từ đây)

- [ ] Điền \`memory/project.md\` — mô tả app làm gì, business rules
- [ ] Điền \`memory/tech.md\` — conventions riêng của project này
- [ ] Bắt đầu feature đầu tiên

---

## Template cho session tiếp theo

\`\`\`
## Đang làm gì
[Tên tính năng và trạng thái ngắn gọn]

## Đã làm trong session gần nhất ([ngày])
1. [Điều đã làm xong]

## Còn phải làm
- [ ] [Bước tiếp theo cụ thể]

## Quyết định đã chốt trong session này
[Nếu có — quyết định kiến trúc, cách tiếp cận và lý do]

## Cần lưu ý khi tiếp tục
[Gotchas, side effects, việc dở dang cần giải thích context]
\`\`\`"

create_file "memory/project.md" "# Project: $PROJECT_NAME

> Mô tả app là gì. Ít khi thay đổi — chỉ cập nhật khi scope thay đổi lớn.

---

## App làm gì

[Điền vào: app này giải quyết vấn đề gì, cho ai]

## Target users

[Điền vào: ai dùng app này, họ cần gì]

## Business rules quan trọng

[Điền vào: các rules nghiệp vụ bắt buộc phải nhớ khi code]

## Những thứ app KHÔNG làm

[Điền vào: scope rõ ràng giúp tránh feature creep]"

create_file "memory/tech.md" "# Tech Stack & Conventions

> Cập nhật khi thêm/bỏ dependency hoặc đổi convention.

---

## Stack

| Layer | Công nghệ | Ghi chú |
|---|---|---|
| Framework | Echo v4 | |
| ORM | GORM | Driver: pgx/v5 |
| Database | PostgreSQL 16 | |
| Cache | Redis 7 | go-redis/v9 |
| Language | Go 1.23 | |
| Deploy | Docker | docker-compose cho local |

## Cấu trúc thư mục

\`\`\`
cmd/api/main.go                     ← entry point, 1 dòng: server.Run()
internal/
  infrastructure/
    config/config.go                ← env vars, validation
    database/database.go            ← GORM connection
    cache/cache.go                  ← Redis connection
    server/server.go                ← wiring + Echo + graceful shutdown
  modules/
    <feature>/
      domain/                       ← entity, errors, repository interface
      service/                      ← business logic
      handler/                      ← HTTP mapping
      repository/                   ← GORM implementation
  shared/
    response/response.go            ← JSON helpers dùng chung
\`\`\`

## Conventions bắt buộc

**Error wrapping:** \`fmt.Errorf(\"context: %w\", err)\` — không bare return err trong repo.

**Compile-time check:** \`var _ domain.Repository = (*GormRepository)(nil)\` trong mỗi repository.

**Interface tại consumer:** định nghĩa interface trong package dùng nó (handler, service), không trong package implement.

**File name = business action:** \`register.go\`, \`find.go\` — không phải \`handler_register.go\`.

## Setup local

\`\`\`bash
cp .env.example .env   # điền DB_USER, DB_PASSWORD, DB_NAME
go mod tidy
make dev               # khởi động postgres + redis + app
\`\`\`

## Env vars cần có

\`\`\`
DB_USER, DB_PASSWORD, DB_NAME   ← bắt buộc, validate() sẽ fail nếu thiếu
REDIS_HOST, REDIS_PORT          ← mặc định localhost:6379
SERVER_PORT                     ← mặc định 8080
\`\`\`"

create_file "memory/decisions.md" "# Quyết định kiến trúc

> Những ràng buộc thiết kế đã chốt — giữ nguyên cho đến khi có quyết định mới ghi đè.
> Thêm vào đây khi chốt một cách tiếp cận và không muốn Claude đề xuất hướng khác.

---

## Clean Architecture 3 layer — không flatten

Domain entity không được import Echo hoặc GORM. Repository là nơi duy nhất biết đến GORM. Handler là nơi duy nhất biết đến Echo. Service không biết HTTP hay DB tồn tại.

Lý do: mỗi layer có thể test độc lập. Domain test không cần mock gì. Service chỉ mock Repository interface.

## Repository interface định nghĩa tại domain, implement tại repository package

\`domain/repository.go\` chứa interface. \`repository/repository.go\` implement và có compile-time check \`var _ domain.Repository = (*GormRepository)(nil)\`.

## Mỗi file = một business action

\`handler/register.go\`, \`service/find.go\`, \`repository/create.go\` — không gộp nhiều actions vào một file. File ngắn, dễ tìm, dễ review.

---

*Thêm quyết định mới ở đây khi có:*"

create_file "memory/gotchas.md" "# Gotchas — Bẫy Đã Từng Gây Bug

> Bug patterns đã gặp thực tế — đọc trước khi đụng vào các vùng code liên quan.
> Khi gotcha đã fix hoàn toàn: đánh dấu \`[ĐÃ FIX - ngày]\` hoặc xóa.

---

## GORM không populate ID sau Create nếu không dùng pointer

**Vấn đề:** \`db.Create(&model)\` chỉ populate generated fields (ID, CreatedAt) trên pointer receiver. Nếu truyền value thì ID vẫn rỗng sau khi gọi xong.

**Fix:** Luôn truyền pointer: \`r.db.WithContext(ctx).Create(model)\`, sau đó copy ngược về domain: \`u.ID = model.ID\`.

---

## Redis Ping không phát hiện config sai nếu server không chạy

**Vấn đề:** \`cache.Connect()\` gọi Ping khi khởi động. Nếu Redis chưa chạy, app exit ngay lập tức với lỗi không rõ.

**Fix:** Chạy \`make dev\` thay vì \`make run\` để đảm bảo Postgres và Redis đã up trước khi app start.

---

*Thêm gotcha mới ở đây khi phát hiện bug pattern:*"

create_file "memory/progress.md" "# Tiến Độ

> Cập nhật cuối mỗi tính năng hoàn thành. Không cần cập nhật theo ngày — cập nhật theo milestone.

---

## Đã xong

### Hạ tầng cơ bản
- [x] Scaffold project với Echo + GORM + Postgres + Redis
- [x] Config với validation (fail fast nếu thiếu secrets)
- [x] Graceful shutdown
- [x] Module user mẫu (domain / service / handler / repository)

---

## Đang làm

*(chưa có)*

---

## Backlog

*(điền vào các feature cần làm)*

---

## Đã bỏ / Không làm nữa

| Tính năng | Lý do bỏ |
|---|---|
| | |"

create_file ".claude/commands/memory.md" 'Cập nhật memory bank cho project này dựa trên những gì đã làm trong session vừa rồi:

1. **memory/active.md** — luôn cập nhật: trạng thái hiện tại, đã làm gì, next step cụ thể
2. **memory/progress.md** — cập nhật nếu session này bắt đầu hoặc hoàn thành tính năng nào
3. **memory/decisions.md** — thêm vào nếu session này chốt quyết định kiến trúc mới
4. **memory/gotchas.md** — thêm vào nếu session này phát hiện bug pattern mới

Với mỗi file cần cập nhật: đọc nội dung hiện tại trước, sau đó chỉnh sửa tại chỗ — không viết lại toàn bộ file.'

# ── Output ────────────────────────────────────────────────────────────────────
FILE_COUNT=${#CREATED_FILES[@]}

if [[ "$JSON_OUTPUT" == true ]]; then
    FILES_JSON="["
    for i in "${!CREATED_FILES[@]}"; do
        [[ $i -gt 0 ]] && FILES_JSON+=","
        FILES_JSON+="\"${CREATED_FILES[$i]}\""
    done
    FILES_JSON+="]"

    cat <<EOF
{
  "project": "$PROJECT_NAME",
  "module": "$MODULE_PATH",
  "files_created": $FILE_COUNT,
  "files": $FILES_JSON,
  "with_migrations": $WITH_MIGRATIONS
}
EOF
else
    echo ""
    echo "Created $PROJECT_NAME — $FILE_COUNT files"
    echo ""
    echo "Project structure:"
    if command -v tree &>/dev/null; then
        tree "$PROJECT_NAME" --noreport -I '.env'
    else
        find "$PROJECT_NAME" -type f ! -name '.env' | sort | sed "s|^$PROJECT_NAME/|  |"
    fi
    echo ""
    echo "Next steps:"
    echo "  cd $PROJECT_NAME"
    echo "  cp .env.example .env  # edit secrets"
    echo "  go mod tidy"
    echo "  make dev              # starts postgres + redis + app"
fi
