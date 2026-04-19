#!/usr/bin/env bash
set -euo pipefail

VERSION="3.0.0"
SCRIPT_NAME="$(basename "$0")"

WITH_MIGRATIONS=false
FORCE=false
JSON_OUTPUT=false

usage() {
    cat <<EOF
$SCRIPT_NAME v$VERSION — Scaffold a Go project (Echo + GORM + Docker, feature-first)

USAGE
    bash $SCRIPT_NAME [options] <project-name> <module-path>

OPTIONS
    -h, --help           Show this help message
    -v, --version        Show version
    --with-migrations    Include migrations directory
    --force              Overwrite existing project directory
    --json               Output structured JSON metadata

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

# ── go.mod ──
create_file "go.mod" "module $MODULE_PATH

go 1.23

require (
	github.com/joho/godotenv v1.5.1
	github.com/labstack/echo/v4 v4.13.3
	golang.org/x/crypto v0.31.0
	gorm.io/driver/postgres v1.5.11
	gorm.io/gorm v1.25.12
)"

# ── main.go ──
create_file "cmd/api/main.go" '// Package main is the entry point for the API server.
package main

import "'"$MODULE_PATH"'/internal/app"

func main() { app.Run() }'

# ── Config ──
create_file "internal/config/config.go" '// Package config loads and validates application configuration from environment variables.
package config

import (
	"fmt"
	"os"
	"strings"
)

// Config holds all application configuration.
type Config struct {
	Env      string
	Server   ServerConfig
	Database DatabaseConfig
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct{ Port string }

// DatabaseConfig holds database connection settings.
type DatabaseConfig struct{ Host, Port, User, Password, Name, SSLMode string }

// DSN returns a PostgreSQL connection string.
func (c DatabaseConfig) DSN() string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode)
}

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
}'

# ── Database ──
create_file "internal/database/database.go" '// Package database provides GORM database connection management.
package database

import (
	"fmt"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"'"$MODULE_PATH"'/internal/config"
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

# ── HTTP Utilities ──
create_file "internal/httputil/response.go" '// Package httputil provides shared HTTP response helpers for Echo handlers.
package httputil

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

# ── User Feature Module (sub-folder structure) ──

# ── user/domain ──
create_file "internal/user/domain/user.go" '// Package domain defines the user entity, business rules, and repository interface.
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
func (u *User) Deactivate() {
	u.Active = false
}'

create_file "internal/user/domain/errors.go" 'package domain

import "errors"

// Domain errors for the user feature.
var (
	ErrNotFound         = errors.New("user not found")
	ErrEmailTaken       = errors.New("email already taken")
	ErrInvalidEmail     = errors.New("invalid email format")
	ErrPasswordTooShort = errors.New("password must be at least 8 characters")
)'

create_file "internal/user/domain/repository.go" 'package domain

import "context"

// Repository defines the persistence contract for users.
type Repository interface {
	Create(ctx context.Context, user *User) error
	FindByID(ctx context.Context, id string) (*User, error)
	FindByEmail(ctx context.Context, email string) (*User, error)
}'

# ── user/service ──
create_file "internal/user/service/service.go" '// Package service implements the business logic for users.
package service

import (
	"'"$MODULE_PATH"'/internal/user/domain"
)

// Service orchestrates user business rules.
type Service struct {
	repo domain.Repository
}

// New creates a new Service.
func New(repo domain.Repository) *Service {
	return &Service{repo: repo}
}'

create_file "internal/user/service/register.go" 'package service

import (
	"context"
	"errors"
	"fmt"

	"'"$MODULE_PATH"'/internal/user/domain"
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

create_file "internal/user/service/find.go" 'package service

import (
	"context"
	"fmt"

	"'"$MODULE_PATH"'/internal/user/domain"
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

# ── user/handler ──
create_file "internal/user/handler/handler.go" '// Package handler provides HTTP endpoints for the user feature.
package handler

import (
	"context"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/user/domain"
)

type service interface {
	Register(ctx context.Context, email, name, password string) (*domain.User, error)
	GetByID(ctx context.Context, id string) (*domain.User, error)
}

// Handler serves HTTP requests for the user feature.
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

create_file "internal/user/handler/register.go" 'package handler

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/user/domain"
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

create_file "internal/user/handler/find.go" 'package handler

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"'"$MODULE_PATH"'/internal/user/domain"
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

# ── user/repository ──
create_file "internal/user/repository/repository.go" '// Package repository implements user persistence using GORM.
package repository

import (
	"time"

	"gorm.io/gorm"

	"'"$MODULE_PATH"'/internal/user/domain"
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

// TableName overrides the default GORM table name.
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
func New(db *gorm.DB) *GormRepository {
	return &GormRepository{db: db}
}'

create_file "internal/user/repository/create.go" 'package repository

import (
	"context"
	"fmt"

	"'"$MODULE_PATH"'/internal/user/domain"
)

// Create inserts a new user and populates the generated ID and timestamp.
func (r *GormRepository) Create(ctx context.Context, u *domain.User) error {
	model := toModel(u)
	if err := r.db.WithContext(ctx).Create(model).Error; err != nil {
		return fmt.Errorf("insert user: %w", err)
	}
	u.ID = model.ID
	u.CreatedAt = model.CreatedAt
	return nil
}'

create_file "internal/user/repository/find.go" 'package repository

import (
	"context"
	"errors"
	"fmt"

	"gorm.io/gorm"

	"'"$MODULE_PATH"'/internal/user/domain"
)

// FindByID returns a user by primary key.
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

// FindByEmail returns a user by email address.
func (r *GormRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	var model userModel
	if err := r.db.WithContext(ctx).Where("email = ?", email).First(&model).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, domain.ErrNotFound
		}
		return nil, fmt.Errorf("find user by email: %w", err)
	}
	return model.toDomain(), nil
}'

# ── App ──
create_file "internal/app/app.go" '// Package app wires all dependencies and manages the application lifecycle.
package app

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

	"'"$MODULE_PATH"'/internal/config"
	"'"$MODULE_PATH"'/internal/database"
	userHandler "'"$MODULE_PATH"'/internal/user/handler"
	userRepo "'"$MODULE_PATH"'/internal/user/repository"
	userService "'"$MODULE_PATH"'/internal/user/service"
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

	// Wire
	repo := userRepo.New(db)
	svc := userService.New(repo)
	handler := userHandler.New(svc)

	// Echo
	e := echo.New()
	e.HideBanner = true
	e.Use(middleware.Recover())
	e.Use(middleware.RequestID())
	if !cfg.IsProduction() {
		e.Use(middleware.Logger())
	}

	// Routes
	api := e.Group("/api")
	handler.Register(api.Group("/users"))

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

# ── .env.example ──
create_file ".env.example" 'APP_ENV=local
SERVER_PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=changeme
DB_NAME='"$PROJECT_NAME"'
DB_SSLMODE=disable'

# ── .env (local defaults) ──
create_file ".env" 'APP_ENV=local
SERVER_PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=changeme
DB_NAME='"$PROJECT_NAME"'
DB_SSLMODE=disable'

# ── Docker ──
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

create_file "docker-compose.yml" 'services:
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
      POSTGRES_DB: ${DB_NAME:-'"$PROJECT_NAME"'}
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
  pgdata:'

# ── Makefile ──
create_file "Makefile" '.PHONY: build run test lint clean dev

APP_NAME := '"$PROJECT_NAME"'

build:
	go build -o bin/$(APP_NAME) ./cmd/api

run:
	go run ./cmd/api

dev:
	docker-compose up -d postgres
	go run ./cmd/api

test:
	go test ./... -race -count=1

lint:
	golangci-lint run ./...

clean:
	rm -rf bin/'

# ── .gitignore ──
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

# ── .golangci.yml ──
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

# ── Migrations (optional) ──
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

# ── Output ──
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
    echo "  make dev              # starts postgres + app"
fi
