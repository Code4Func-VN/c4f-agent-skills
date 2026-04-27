---
name: go-engineer
description: Go backend engineering. Use when writing, reviewing, testing, or scaffolding Go code. Covers style, errors, concurrency, testing, project architecture (Echo + GORM + Docker).
license: Apache-2.0
metadata:
  stack: "Echo v4, GORM, PostgreSQL, Redis, Docker"
allowed-tools: Bash(bash:*)
---

# Go Engineer

## When to Activate

This skill applies to **all Go code work** — writing, reviewing, testing, scaffolding, refactoring.

## What to Do

| Task | Action | Reference |
|------|--------|-----------|
| Writing any Go code | Apply core rules below, then consult relevant reference | — |
| Creating new project | Run `scripts/init-project.sh` | `references/BLUEPRINT-STRUCTURE.md` + `references/BLUEPRINT-CONFIG.md` |
| Adding a feature module | Follow feature module pattern in `internal/modules/` | `references/CRAFT-FEATURE-DOMAIN.md` + `references/CRAFT-FEATURE-ADAPTER.md` |
| Writing database code | Transactions, scopes, N+1, migrations | `references/DATABASE.md` |
| Designing API endpoints | Pagination, filtering, error format, validation | `references/API-DESIGN.md` |
| Writing tests | Table-driven by default, test per layer | `references/TESTING.md` + `references/TESTING-LAYERS-UNIT.md` + `references/TESTING-LAYERS-INTEGRATION.md` |
| Reviewing code | Follow checklist systematically | `references/REVIEW.md` |
| Optimizing performance | Measure first, optimize hot paths only | `references/PERFORMANCE.md` |
| Working with goroutines | Every goroutine needs a stop mechanism | `references/CONCURRENCY.md` |

## Core Rules — Always Apply

### Style
- Priority: **Clarity -> Simplicity -> Concision -> Maintainability**
- `gofmt` is non-negotiable. Reduce nesting via early returns (guard clauses)
- MixedCaps only — no underscores. Initialisms: `HTTPClient`, `userID`
- Package names: lowercase, singular, descriptive (`auth`, `payment` — never `util`, `helper`)

### Errors
- Return `error` interface, never concrete types
- Error strings: lowercase, no punctuation
- Wrap with context: `fmt.Errorf("save user: %w", err)`
- Handle once: return OR log, never both

### Functions & Interfaces
- Accept interfaces, return concrete types
- Define interfaces at consumer site (small, 1-3 methods)
- Compile-time check: `var _ Repository = (*GormRepo)(nil)`

### Project Structure — Clean Architecture
- **3 top-level packages inside `internal/`:**
  - `internal/modules/` — business modules only (`user/`, `order/`, `task/`)
  - `internal/infrastructure/` — frameworks & drivers (`config/`, `database/`, `server/`)
  - `internal/shared/` — cross-cutting utilities (`response/`, `apperror/`, `validator/`, `middleware/`)
- Each business module has sub-folders by layer: `domain/`, `service/`, `handler/`, `repository/`
- File names = business actions: `register.go`, `find.go` — not `handler_register.go`
- `main.go` = one line: `server.Run()`
- `internal/` only — everything private. Never place infra code at business module level

### Security
- Config `validate()` fails fast if secrets missing
- `.env.example` committed, `.env` gitignored
- DB SSL required in production
- `crypto/rand` for keys, never `math/rand`

### Testing
- **Write test WITH code** — not after. `feat`/`fix` without test = blocked commit
- Domain: unit test, no mocks needed
- Service: unit test, mock repository interface
- Handler: integration test with httptest (required before PR)
- Repository: integration test with testcontainers (required before PR)
- `fix` commit: test MUST reproduce the bug first, then fix
- Refactor: existing tests MUST pass WITHOUT modification. Modified test = behavior change, not refactor

## Anti-Patterns — Quick Check

| Don't | Do |
|-------|----|
| `util/`, `helper/`, `models/` packages | Business domain packages (`modules/user/`, `modules/order/`) |
| `handler_register.go` | `handler/register.go` (folder = layer, file = action) |
| GORM tags on domain entity | Unexported model in `repository/`, mapping funcs |
| `log.Fatalf` everywhere | `slog.Error` + return error; let caller decide |
| Bare `return err` in repo | `fmt.Errorf("insert user: %w", err)` |
| `errors.New` comparison by string | `errors.Is` / `errors.As` |
| Business logic in handler | Handler maps HTTP <-> service, nothing more |
| `this`/`self` receiver | 1-2 letter abbreviation (`u`, `s`, `h`) |
| Config/DB in `internal/` root or business module | `infrastructure/config/`, `infrastructure/database/` |
| `.env` in git | `.env.example` committed, `.env` gitignored |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/init-project.sh` | Scaffold new project (Echo + GORM + Docker) |
| `scripts/check-naming.sh` | Detect naming violations |
| `scripts/check-errors.sh` | Detect error handling anti-patterns |
| `scripts/check-interface-compliance.sh` | Find missing compile-time checks |
| `scripts/check-docs.sh` | Report missing doc comments |
| `scripts/setup-lint.sh` | Generate .golangci.yml + run lint |
| `scripts/gen-table-test.sh` | Generate table-driven test scaffold |
| `scripts/bench-compare.sh` | Run benchmarks with comparison |
| `scripts/pre-review.sh` | Automated pre-review checks |

## References

### Quick References (~200-350 tokens each)
| Topic | File |
|-------|------|
| Error patterns | `references/ERROR-QUICK.md` |
| Naming conventions | `references/NAMING-QUICK.md` |
| Feature module scaffold | `references/FEATURE-QUICK.md` |

### Foundations
| Topic | File |
|-------|------|
| Style | `references/IDIOMS-STYLE.md` |
| Naming | `references/IDIOMS-NAMING.md` |
| Declarations | `references/IDIOMS-DECLARATIONS.md` |
| Error handling | `references/ERROR-HANDLING.md` |
| Functions & options | `references/FUNCTIONS.md` |
| Interfaces | `references/INTERFACES.md` |
| Data structures | `references/DATA-STRUCTURES.md` |

### Patterns
| Topic | File |
|-------|------|
| Concurrency & context | `references/CONCURRENCY.md` |
| Generics | `references/GENERICS.md` |
| Defensive coding | `references/DEFENSIVE.md` |

### Quality
| Topic | File |
|-------|------|
| Testing basics | `references/TESTING.md` |
| Testing per layer (unit) | `references/TESTING-LAYERS-UNIT.md` |
| Testing per layer (integration) | `references/TESTING-LAYERS-INTEGRATION.md` |
| Logging | `references/LOGGING.md` |
| Linting | `references/LINTING.md` |
| Performance | `references/PERFORMANCE.md` |
| Documentation | `references/DOCUMENTATION.md` |
| Code review | `references/REVIEW.md` |

### Architecture
| Topic | File |
|-------|------|
| Feature module (domain) | `references/CRAFT-FEATURE-DOMAIN.md` |
| Feature module (adapter) | `references/CRAFT-FEATURE-ADAPTER.md` |
| Project scaffold (structure) | `references/BLUEPRINT-STRUCTURE.md` |
| Project scaffold (config) | `references/BLUEPRINT-CONFIG.md` |
| Database patterns | `references/DATABASE.md` |
| API design | `references/API-DESIGN.md` |
