# Go Defensive Programming Patterns

## Defensive Checklist Priority

When hardening code at API boundaries, check in this order:

```
Reviewing an API boundary?
├─ 1. Error handling     → Return errors; don't panic
├─ 2. Input validation   → Copy slices/maps received from callers
├─ 3. Output safety      → Copy slices/maps before returning to callers
├─ 4. Resource cleanup   → Use defer for Close/Unlock/Cancel
├─ 5. Interface checks   → var _ Interface = (*Type)(nil) for compile-time verification
├─ 6. Time correctness   → Use time.Time and time.Duration, not int/float
├─ 7. Enum safety        → Start iota at 1 so zero-value is invalid
└─ 8. Crypto safety      → crypto/rand for keys, never math/rand
```

---

## Quick Reference

| Pattern | Rule |
|---------|------|
| Boundary copies | Copy slices/maps on receive and return |
| Defer cleanup | `defer f.Close()` right after `os.Open` |
| Interface check | `var _ I = (*T)(nil)` |
| Time types | `time.Time` / `time.Duration`, never raw int |
| Enum start | `iota + 1` so zero = invalid |
| Crypto rand | `crypto/rand` for keys, never `math/rand` |
| Must functions | Only at init; panic on failure |
| Panic/recover | Never expose panics across packages |
| Mutable globals | Replace with dependency injection |

---

## Verify Interface Compliance

Use compile-time checks to verify interface implementation.

```go
var _ http.Handler = (*Handler)(nil)
```

## Copy Slices and Maps at Boundaries

Slices and maps contain pointers to underlying data. Copy at API boundaries to prevent unintended modifications.

```go
// Receiving: copy incoming slice
d.trips = make([]Trip, len(trips))
copy(d.trips, trips)

// Returning: copy map before returning
result := make(map[string]int, len(s.counters))
for k, v := range s.counters { result[k] = v }
```

## Defer to Clean Up

Use `defer` to clean up resources (files, locks). Avoids missed cleanup on multiple return paths.

```go
p.Lock()
defer p.Unlock()

if p.count < 10 {
  return p.count
}
p.count++
return p.count
```

Defer overhead is negligible. Place `defer f.Close()` immediately after
`os.Open` for clarity. Arguments to deferred functions are evaluated when
`defer` executes, not when the function runs. Multiple defers execute in
LIFO order.

## Struct Field Tags

> **Advisory**: Always add explicit field tags to structs that are marshaled or unmarshaled.

```go
type User struct {
    Name  string `json:"name"  yaml:"name"`
    Email string `json:"email" yaml:"email"`
}
```

Field tags are a **serialization contract** -- renaming a struct field without
updating the tag silently breaks wire compatibility. Treat tags as part of
the public API for any type that crosses a serialization boundary.

## Start Enums at One

Start enums at non-zero to distinguish uninitialized from valid values.

```go
const (
  Add Operation = iota + 1  // Add=1, zero value = uninitialized
  Subtract
  Multiply
)
```

**Exception**: When zero is the sensible default (e.g., `LogToStdout = iota`).

## Time, Struct Tags, and Embedding

Use `time.Time` and `time.Duration` instead of raw ints for time values. Add field tags to marshaled structs. Be deliberate about embedding types in public structs.

## Avoid Mutable Globals

Inject dependencies instead of mutating package-level variables. This makes
code testable without global save/restore.

```go
type signer struct {
  now func() time.Time  // injected; tests replace with fixed time
}

func newSigner() *signer {
  return &signer{now: time.Now}
}
```

## Crypto Rand

Do not use `math/rand` or `math/rand/v2` to generate keys -- this is a
**security concern**. Time-seeded generators have predictable output.

```go
import "crypto/rand"

// Go 1.24+: use rand.Text() directly
func Key() string { return rand.Text() }
```

For Go < 1.24, encode random bytes with `encoding/hex` or `encoding/base64`:

```go
import (
    "crypto/rand"
    "encoding/hex"
)

// Go 1.21+: compatible with all modern Go versions
func Key() string {
    b := make([]byte, 16)
    if _, err := rand.Read(b); err != nil {
        panic(err) // crypto/rand should never fail
    }
    return hex.EncodeToString(b)
}
```

---

## Panic and Recover

Use `panic` only for truly unrecoverable situations. Library functions
should avoid panic.

```go
func safelyDo(work *Work) {
    defer func() {
        if err := recover(); err != nil {
            log.Println("work failed:", err)
        }
    }()
    do(work)
}
```

**Key rules:**
- Never expose panics across package boundaries -- always convert to errors
- Acceptable to panic in `init()` if a library truly cannot set itself up
- Use recover to isolate panics in server goroutine handlers

## Must Functions

`Must` functions panic on error -- use them **only** during program
initialization where failure means the program cannot run.

```go
var validID = regexp.MustCompile(`^[a-z][a-z0-9-]{0,62}$`)
var tmpl = template.Must(template.ParseFiles("index.html"))
```
