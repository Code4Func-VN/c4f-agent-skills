# Go Interfaces and Composition

## Accept Interfaces, Return Concrete Types

Interfaces belong in the package that **consumes** values, not the package that
**implements** them. Return concrete (usually pointer or struct) types from
constructors so new methods can be added without refactoring.

```go
// Good: consumer defines the interface it needs
package consumer

type Thinger interface { Thing() bool }

func Foo(t Thinger) string { ... }
```

```go
// Good: producer returns concrete type
package producer

type Thinger struct{ ... }
func (t Thinger) Thing() bool { ... }
func NewThinger() Thinger { return Thinger{ ... } }
```

```go
// Bad: producer defines and returns its own interface
package producer

type Thinger interface { Thing() bool }
type defaultThinger struct{ ... }
func NewThinger() Thinger { return defaultThinger{ ... } }
```

**Do not define interfaces before they are used.** Without a realistic example
of usage, it is too difficult to see whether an interface is even necessary.

---

## When to Return an Interface

Return an interface from a constructor **only** when the type exists solely to
satisfy that interface and has no useful exported methods beyond it:

```go
func NewHash() hash.Hash32 {
    return &myHash{}  // unexported type, only useful as hash.Hash32
}
```

**Do not default to returning interfaces.** In most cases, return the concrete
type — this lets callers access all methods, add new methods in the future, and
decide for themselves whether to depend on the interface or the concrete type.
Go favors explicit, concrete types over premature abstraction.

---

## Type Assertions: Comma-Ok Idiom

Without checking, a failed assertion causes a runtime panic. Always use the
comma-ok idiom to test safely:

```go
str, ok := value.(string)
if ok {
    fmt.Printf("string value is: %q\n", str)
}
```

To check if a value implements an interface:

```go
if _, ok := val.(json.Marshaler); ok {
    fmt.Printf("value %v implements json.Marshaler\n", val)
}
```

---

## Type Switch

It's idiomatic to reuse the variable name (`t := t.(type)`) — the variable has
the correct type in each case branch. When a case lists multiple types
(`case int, int64:`), the variable has the interface type.

---

## Embedding

Avoid embedding types in public structs — the inner type's full method set
becomes part of your public API. Use unexported fields instead.

---

## Interface Satisfaction Checks

Use a blank identifier assignment to verify a type implements an interface at
compile time:

```go
var _ json.Marshaler = (*RawMessage)(nil)
```

This causes a compile error if `*RawMessage` doesn't implement `json.Marshaler`.

Use this pattern when:
- There are no static conversions that would verify the interface automatically
- The type must satisfy an interface for correct behavior (e.g., custom JSON
  marshaling)
- Interface changes should break compilation, not silently degrade

**Don't** add these checks for every interface — only when no other static
conversion would catch the error.

> **Validation**: After defining interfaces or implementations, run `bash scripts/check-interface-compliance.sh` to verify all concrete types have compile-time `var _ I = (*T)(nil)` checks.

---

## Receiver Type

If in doubt, use a pointer receiver. Don't mix receiver types on a single
type — if any method needs a pointer, use pointers for all methods. Use value
receivers only for small, immutable types (`Point`, `time.Time`) or basic types.

---

## Quick Reference

| Concept | Pattern | Notes |
|---------|---------|-------|
| Consumer owns interface | Define interfaces where used | Not in the implementing package |
| Safe type assertion | `v, ok := x.(Type)` | Returns zero value + false |
| Type switch | `switch v := x.(type)` | Variable has correct type per case |
| Interface embedding | `type RW interface { Reader; Writer }` | Union of methods |
| Struct embedding | `type S struct { *T }` | Promotes T's methods |
| Interface check | `var _ I = (*T)(nil)` | Compile-time verification |
| Return interface | Only when type exists solely for the interface | Prefer concrete types |
