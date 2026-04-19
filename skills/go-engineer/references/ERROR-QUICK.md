# Quick Error Patterns

Choose strategy by caller need:

| Caller needs to match? | Message | Use |
|------------------------|---------|-----|
| No, static | `errors.New("message")` | Simple failure |
| No, dynamic | `fmt.Errorf("msg: %v", val)` | Context for debugging |
| Yes, static | `var ErrFoo = errors.New("...")` | Sentinel for `errors.Is` |
| Yes, dynamic | Custom `error` type | Structured data for `errors.As` |

**Sentinel errors** — caller checks with `errors.Is`:

```go
var (
    ErrNotFound     = errors.New("user not found")
    ErrEmailTaken   = errors.New("email already taken")
)

if errors.Is(err, domain.ErrNotFound) { /* handle */ }
```

**Typed errors** — caller extracts data with `errors.As`:

```go
type ValidationError struct {
    Field   string
    Message string
}
func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: %s %s", e.Field, e.Message)
}

var ve *ValidationError
if errors.As(err, &ve) { /* use ve.Field */ }
```

**Wrapping** — add context, preserve chain:

```go
// %w preserves chain for errors.Is / errors.As
return fmt.Errorf("save user: %w", err)

// %v at system boundaries to hide internals
return fmt.Errorf("storage error: %v", err)
```

Handle once: return OR log, never both. Place `%w` at end of format string.
