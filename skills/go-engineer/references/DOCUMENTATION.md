# Go Documentation

## Doc Comments

> **Normative**: All top-level exported names must have doc comments.

### Basic Rules

1. Begin with the name of the object being described
2. An article ("a", "an", "the") may precede the name
3. Use full sentences (capitalized, punctuated)

```go
// A Request represents a request to run a command.
type Request struct { ...

// Encode writes the JSON encoding of req to w.
func Encode(w io.Writer, req *Request) { ...
```

Unexported types/functions with unobvious behavior should also have doc comments.

---

## Comment Sentences

> **Normative**: Documentation comments must be complete sentences.

- Capitalize the first word, end with punctuation
- Exception: may begin with uncapitalized identifier if clear
- End-of-line comments for struct fields can be phrases

---

## Comment Line Length

> **Advisory**: Aim for ~80 columns, but no hard limit.

Break based on punctuation. Don't split long URLs.

---

## Struct Documentation

Group fields with section comments. Mark optional fields with defaults:

```go
type Options struct {
    // General setup:
    Name  string
    Group *FooGroup

    // Customization:
    LargeGroupThreshold int // optional; default: 10
}
```

---

## Package Comments

> **Normative**: Every package must have exactly one package comment.

```go
// Package math provides basic constants and mathematical functions.
package math
```

- For `main` packages, use the binary name: `// The seed_generator command ...`
- For long package comments, use a `doc.go` file

---

## What to Document

> **Advisory**: Document non-obvious behavior, not obvious behavior.

| Topic | Document when... | Skip when... |
|-------|-----------------|--------------|
| Parameters | Non-obvious behavior, edge cases | Restates the type signature |
| Contexts | Behavior differs from standard cancellation | Standard `ctx.Err()` return |
| Concurrency | Ambiguous thread safety (e.g., read that mutates) | Read-only is safe, mutation is unsafe |
| Cleanup | Always document resource release | -- |
| Errors | Sentinel values, error types (use `*PathError`) | -- |
| Named results | Multiple params of same type, action-oriented names | Type alone is clear enough |

Key principles:

- Context cancellation returning `ctx.Err()` is implied -- don't restate it
- Read-only ops are assumed thread-safe; mutations assumed unsafe -- don't restate
- Always document cleanup requirements (e.g., `Call Stop to release resources`)
- Use pointer in error type docs (`*PathError`) for correct `errors.Is`/`errors.As`
- Don't name results just to enable naked returns -- clarity > brevity

---

## Runnable Examples

> **Advisory**: Provide runnable examples in test files (`*_test.go`).

```go
func ExampleConfig_WriteTo() {
    cfg := &Config{Name: "example"}
    cfg.WriteTo(os.Stdout)
    // Output:
    // {"name": "example"}
}
```

Examples appear in Godoc attached to the documented element.

---

## Quick Reference

| Topic | Key Rule |
|-------|----------|
| Doc comments | Start with name, use full sentences |
| Line length | ~80 chars, prioritize readability |
| Package comments | One per package, above `package` clause |
| Parameters | Document non-obvious behavior only |
| Contexts | Document exceptions to implied behavior |
| Concurrency | Document ambiguous thread safety |
| Cleanup | Always document resource release |
| Errors | Document sentinels and types (note pointer) |
| Examples | Use runnable examples in test files |
| Formatting | Blank lines for paragraphs, indent for code |
