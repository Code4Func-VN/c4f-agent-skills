# Go Context Usage

## Context as First Parameter

Functions that use a Context should accept it as their **first parameter**:

```go
func F(ctx context.Context, /* other arguments */) error
func ProcessRequest(ctx context.Context, req *Request) (*Response, error)
```

This is a strong convention in Go that makes context flow visible and consistent
across codebases.

---

## Don't Store Context in Structs

Do not add a Context member to a struct type. Instead, pass `ctx` as a parameter
to each method that needs it:

```go
// Bad: Context stored in struct
type Worker struct {
    ctx context.Context  // Don't do this
}

// Good: Context passed to methods
type Worker struct{ /* ... */ }

func (w *Worker) Process(ctx context.Context) error {
    // Context explicitly passed — lifetime clear
}
```

**Exception**: Methods whose signature must match an interface in the standard
library or a third-party library may need to work around this.

---

## Don't Create Custom Context Types

Do not create custom Context types or use interfaces other than `context.Context`
in function signatures:

```go
// Bad: Custom context type
type MyContext interface {
    context.Context
    GetUserID() string
}

// Good: Use standard context.Context with value extraction
func Process(ctx context.Context) error {
    userID := GetUserID(ctx)
}
```

---

## Where to Put Application Data

Consider these options in order of preference:

1. **Function parameters** — most explicit and type-safe
2. **Receiver** — for data that belongs to the type
3. **Globals** — for truly global configuration (use sparingly)
4. **Context value** — only for request-scoped data

Context values are appropriate for:
- Request IDs and trace IDs
- Authentication/authorization info that flows with requests
- Deadlines and cancellation signals

Context values are **not** appropriate for:
- Optional function parameters
- Data that could be passed explicitly
- Configuration that doesn't vary per-request

---

## Common Context Patterns

### Deriving Contexts

Always `defer cancel()` immediately after creating a derived context:

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```

### Checking Cancellation

```go
select {
case <-ctx.Done():
    return ctx.Err()
default:
    // Do work
}
```

### Context Immutability

Contexts are immutable — it's safe to pass the same `ctx` to multiple
concurrent calls that share the same deadline and cancellation signal.

---

# Go Concurrency

## Goroutine Lifetimes

> **Normative**: When you spawn goroutines, make it clear when or whether they
> exit.

Goroutines can leak by blocking on channel sends/receives. The GC **will not
terminate** a blocked goroutine even if no other goroutine holds a reference to
the channel. Even non-leaking in-flight goroutines cause panics (send on closed
channel), data races, memory issues, and resource leaks.

### Core Rules

1. **Every goroutine needs a stop mechanism** — a predictable end time, a
   cancellation signal, or both
2. **Code must be able to wait** for the goroutine to finish
3. **No goroutines in `init()`** — expose lifecycle methods (`Close`, `Stop`,
   `Shutdown`) instead
4. **Keep synchronization scoped** — constrain to function scope, factor logic
   into synchronous functions

```go
// Good: Clear lifetime with WaitGroup
var wg sync.WaitGroup
for item := range queue {
    wg.Add(1)
    go func() { defer wg.Done(); process(ctx, item) }()
}
wg.Wait()
// Note: In Go 1.22+, each loop iteration captures its own `item`.
// For Go < 1.22, add `item := item` before the goroutine to avoid a race.
```

```go
// Bad: No way to stop or wait
go func() { for { flush(); time.Sleep(delay) } }()
```

### Nil Channel Gotcha

Sending to or receiving from a `nil` channel **blocks forever**. This is by
design and useful in select statements to disable a case, but is a common
source of deadlocks when a channel variable is accidentally left uninitialized:

```go
var ch chan int  // nil — any send or receive blocks forever
ch <- 1         // deadlock!
```

**Test for leaks** with [go.uber.org/goleak](https://pkg.go.dev/go.uber.org/goleak).

> **Principle**: Never start a goroutine without knowing how it will stop.

---

## Share by Communicating

> "Do not communicate by sharing memory; instead, share memory by communicating."

This is Go's foundational concurrency design principle. Use **channels** for
ownership transfer and orchestration — when one goroutine produces a value and
another consumes it. Use **mutexes** when multiple goroutines access shared
state and channels would add unnecessary complexity.

**Default to channels.** Fall back to `sync.Mutex` / `sync.RWMutex` when the
problem is naturally about protecting a shared data structure (e.g., a cache or
counter) rather than passing data between goroutines.

---

## Synchronous Functions

> **Normative**: Prefer synchronous functions over asynchronous ones.

| Benefit | Why |
|---|---|
| Localized goroutines | Lifetimes easier to reason about |
| Avoids leaks and races | Easier to prevent resource leaks and data races |
| Easier to test | Check input/output without polling |
| Caller flexibility | Caller adds concurrency when needed |

> **Advisory**: It is quite difficult (sometimes impossible) to remove
> unnecessary concurrency at the caller side. Let the caller add concurrency
> when needed.

---

## Zero-value Mutexes

The zero-value of `sync.Mutex` and `sync.RWMutex` is valid — almost never need
a pointer to a mutex.

```go
// Good: Zero-value is valid    // Bad: Unnecessary pointer
var mu sync.Mutex                mu := new(sync.Mutex)
```

**Don't embed mutexes** — use a named `mu` field to keep `Lock`/`Unlock` as
implementation details, not exported API.

---

## Channel Direction

> **Normative**: Specify channel direction where possible.

Direction prevents errors (compiler catches closing a receive-only channel),
conveys ownership, and is self-documenting.

```go
func produce(out chan<- int) { /* send-only */ }
func consume(in <-chan int)  { /* receive-only */ }
func transform(in <-chan int, out chan<- int) { /* both */ }
```

### Channel Size: One or None

Channels should have size **zero** (unbuffered) or **one**. Any other size
requires justification for:

- How the size was determined
- What prevents the channel from filling under load
- What happens when writers block

```go
c := make(chan int)    // unbuffered — Good
c := make(chan int, 1) // size one — Good
c := make(chan int, 64) // arbitrary — needs justification
```

---

## Atomic Operations

Use `atomic.Bool`, `atomic.Int64`, etc. from stdlib `sync/atomic` (Go 1.19+)
for type-safe atomic operations. Raw `int32`/`int64` fields make it easy to
forget atomic access on some code paths.

> **Note**: The third-party `go.uber.org/atomic` package predates Go 1.19's
> stdlib additions. For new code, **prefer stdlib `sync/atomic`** — it provides
> the same type-safe wrappers without an external dependency.

```go
// Good: Type-safe              // Bad: Easy to forget
var running atomic.Bool          var running int32 // atomic
running.Store(true)              atomic.StoreInt32(&running, 1)
running.Load()                   running == 1 // race!
```

---

## Documenting Concurrency

> **Advisory**: Document thread-safety when it's not obvious from the operation
> type.

Go users assume read-only operations are safe for concurrent use, and mutating
operations are not. Document concurrency when:

1. **Read vs mutating is unclear** — e.g., a `Lookup` that mutates LRU state
2. **API provides synchronization** — e.g., thread-safe clients
3. **Interface has concurrency requirements** — document in type definition

---

## Buffer Pooling with Channels

Use a buffered channel as a free list to reuse allocated buffers. This "leaky
buffer" pattern uses `select` with `default` for non-blocking operations.

---

### External Resources

- [Never start a goroutine without knowing how it will
  stop](https://dave.cheney.net/2016/12/22/never-start-a-goroutine-without-knowing-how-it-will-stop)
  — Dave Cheney
- [Rethinking Classical Concurrency
  Patterns](https://www.youtube.com/watch?v=5zXAHh5tJqQ) — Bryan Mills
  (GopherCon 2018)
- [When Go programs end](https://changelog.com/gotime/165) — Go Time podcast
- [go.uber.org/goleak](https://pkg.go.dev/go.uber.org/goleak) — Goroutine leak
  detector for testing
- [sync/atomic](https://pkg.go.dev/sync/atomic) — Type-safe atomic operations
  (Go 1.19+ stdlib)
