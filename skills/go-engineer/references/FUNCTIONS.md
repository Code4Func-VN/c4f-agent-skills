# Go Function Design

## Function Grouping and Ordering

Organize functions in a file by these rules:

1. Functions sorted in **rough call order**
2. Functions **grouped by receiver**
3. **Exported** functions appear first, after `struct`/`const`/`var` definitions
4. `NewXxx`/`newXxx` constructors appear right after the type definition
5. Plain utility functions appear toward the end of the file

```go
type something struct{ ... }

func newSomething() *something { return &something{} }

func (s *something) Cost() int { return calcCost(s.weights) }

func (s *something) Stop() { ... }

func calcCost(n []int) int { ... }
```

---

## Function Signatures

Keep the signature on a single line when possible. When it must wrap, put **all
arguments on their own lines** with a trailing comma:

```go
func (r *SomeType) SomeLongFunctionName(
    foo1, foo2, foo3 string,
    foo4, foo5, foo6 int,
) {
    foo7 := bar(foo1)
}
```

Add `/* name */` comments for ambiguous arguments, or better yet, replace naked
`bool` parameters with custom types.

---

## Pointers to Interfaces

You almost never need a pointer to an interface. Pass interfaces as values — the
underlying data can still be a pointer.

```go
// Bad: pointer to interface
func process(r *io.Reader) { ... }

// Good: pass the interface value
func process(r io.Reader) { ... }
```

---

## Printf and Stringer

### Printf-style Function Names

Functions that accept a format string should end in `f` for `go vet` support.
Declare format strings as `const` when used outside `Printf` calls.

Prefer `%q` over `%s` with manual quoting when formatting strings for logging
or error messages — it safely escapes special characters and wraps in quotes:

```go
return fmt.Errorf("unknown key %q", key) // produces: unknown key "foo\nbar"
```

---

## Quick Reference

| Topic | Rule |
|-------|------|
| File ordering | Type -> constructor -> exported -> unexported -> utils |
| Signature wrapping | All args on own lines with trailing comma |
| Naked parameters | Add `/* name */` comments or use custom types |
| Pointers to interfaces | Almost never needed; pass interfaces by value |
| Printf function names | End with `f` for `go vet` support |

---

# Functional Options Pattern

Functional options is a pattern where you declare an opaque `Option` type that records information in an internal struct. The constructor accepts a variadic number of these options and applies them to configure the result.

## When to Use

Use functional options when:

- **3+ optional arguments** on constructors or public APIs
- **Extensible APIs** that may gain new options over time
- **Clean caller experience** is important (no need to pass defaults)

## The Pattern

### Core Components

1. **Unexported `options` struct** - holds all configuration
2. **Exported `Option` interface** - with unexported `apply` method
3. **Option types** - implement the interface
4. **`With*` constructors** - create options

### Option Interface

```go
type Option interface {
    apply(*options)
}
```

The unexported `apply` method ensures only options from this package can be used.

## Complete Implementation

```go
package db

import "log/slog"

// options holds all configuration for opening a connection.
type options struct {
    cache  bool
    logger *slog.Logger
}

// Option configures how we open the connection.
type Option interface {
    apply(*options)
}

// cacheOption implements Option for cache setting (simple type alias).
type cacheOption bool

func (c cacheOption) apply(opts *options) {
    opts.cache = bool(c)
}

// WithCache enables or disables caching.
func WithCache(c bool) Option {
    return cacheOption(c)
}

// loggerOption implements Option for logger setting (struct for pointers).
type loggerOption struct {
    log *slog.Logger
}

func (l loggerOption) apply(opts *options) {
    opts.logger = l.log
}

// WithLogger sets the logger for the connection.
func WithLogger(log *slog.Logger) Option {
    return loggerOption{log: log}
}

// Open creates a connection.
func Open(addr string, opts ...Option) (*Connection, error) {
    // Start with defaults
    options := options{
        cache:  defaultCache,
        logger: slog.Default(),
    }

    // Apply all provided options
    for _, o := range opts {
        o.apply(&options)
    }

    // Use options.cache and options.logger...
    return &Connection{}, nil
}
```

## Usage Examples

### Without Functional Options (Bad)

```go
// Caller must always provide all parameters, even defaults
db.Open(addr, db.DefaultCache, slog.Default())
db.Open(addr, db.DefaultCache, log)
db.Open(addr, false /* cache */, slog.Default())
db.Open(addr, false /* cache */, log)
```

### With Functional Options (Good)

```go
// Only provide options when needed
db.Open(addr)
db.Open(addr, db.WithLogger(log))
db.Open(addr, db.WithCache(false))
db.Open(
    addr,
    db.WithCache(false),
    db.WithLogger(log),
)
```

## Comparison: Functional Options vs Config Struct

| Aspect | Functional Options | Config Struct |
|--------|-------------------|---------------|
| **Extensibility** | Add new `With*` functions | Add new fields (may break) |
| **Defaults** | Built into constructor | Zero values or separate defaults |
| **Caller experience** | Only specify what differs | Must construct entire struct |
| **Testability** | Options are comparable | Struct comparison |
| **Complexity** | More boilerplate | Simpler setup |

**Prefer Config Struct when**: Fewer than 3 options, options rarely change, all options usually specified together, or internal APIs only.

## Why Not Closures?

An alternative implementation uses closures:

```go
// Closure approach (not recommended)
type Option func(*options)

func WithCache(c bool) Option {
    return func(o *options) { o.cache = c }
}
```

The interface approach is preferred because:

1. **Testability** - Options can be compared in tests and mocks
2. **Debuggability** - Options can implement `fmt.Stringer`
3. **Flexibility** - Options can implement additional interfaces
4. **Visibility** - Option types are visible in documentation

## Quick Reference

```go
// 1. Unexported options struct with defaults
type options struct {
    field1 Type1
    field2 Type2
}

// 2. Exported Option interface, unexported method
type Option interface {
    apply(*options)
}

// 3. Option type + apply + With* constructor
type field1Option Type1

func (o field1Option) apply(opts *options) { opts.field1 = Type1(o) }
func WithField1(v Type1) Option            { return field1Option(v) }

// 4. Constructor applies options over defaults
func New(required string, opts ...Option) (*Thing, error) {
    o := options{field1: defaultField1, field2: defaultField2}
    for _, opt := range opts {
        opt.apply(&o)
    }
    // ...
}
```

### Checklist

- [ ] `options` struct is unexported
- [ ] `Option` interface has unexported `apply` method
- [ ] Each option has a `With*` constructor
- [ ] Defaults are set before applying options
- [ ] Required parameters are separate from `...Option`

### External Resources

- [Self-referential functions and the design of options](https://commandcenter.blogspot.com/2014/01/self-referential-functions-and-design.html) - Rob Pike
- [Functional options for friendly APIs](https://dave.cheney.net/2014/10/17/functional-options-for-friendly-apis) - Dave Cheney
