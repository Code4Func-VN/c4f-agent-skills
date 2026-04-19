# Go Idioms — Style & Control Flow

---

## 1. Style Principles

### Priority Order

When writing readable Go code, apply these principles in order of importance:

1. **Clarity** -- Can a reader understand the code without extra context?
2. **Simplicity** -- Is this the simplest way to accomplish the goal?
3. **Concision** -- Does every line earn its place?
4. **Maintainability** -- Will this be easy to modify later?
5. **Consistency** -- Does it match surrounding code and project conventions?

### Formatting

Run `gofmt` -- no exceptions. There is **no rigid line length limit**, but a soft limit of 99 characters is recommended. Break by semantics, not length -- refactor rather than just wrap.

### Reduce Nesting

Handle error cases and special conditions first. Return early or continue the loop to keep the "happy path" unindented.

```go
// Bad: Deeply nested
for _, v := range data {
    if v.F1 == 1 {
        v = process(v)
        if err := v.Call(); err == nil {
            v.Send()
        } else {
            return err
        }
    } else {
        log.Printf("Invalid v: %v", v)
    }
}

// Good: Flat structure with early returns
for _, v := range data {
    if v.F1 != 1 {
        log.Printf("Invalid v: %v", v)
        continue
    }

    v = process(v)
    if err := v.Call(); err != nil {
        return err
    }
    v.Send()
}
```

### Unnecessary Else

If a variable is set in both branches of an if, use default + override pattern.

```go
// Bad: Setting in both branches
var a int
if b {
    a = 100
} else {
    a = 10
}

// Good: Default + override
a := 10
if b {
    a = 100
}
```

### Naked Returns

A `return` statement without arguments returns the named return values.

```go
func split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return // returns x, y
}
```

Guidelines:

- **OK in small functions**: Naked returns are fine in functions that are just a handful of lines.
- **Be explicit in medium+ functions**: Once a function grows to medium size, be explicit with return values for clarity.
- **Don't name results just for naked returns**: Clarity of documentation is always more important than saving a line or two.

```go
// Good: Small function, naked return is clear
func minMax(a, b int) (min, max int) {
    if a < b {
        min, max = a, b
    } else {
        min, max = b, a
    }
    return
}

// Good: Larger function, explicit return
func processData(data []byte) (result []byte, err error) {
    result = make([]byte, 0, len(data))

    for _, b := range data {
        if b == 0 {
            return nil, errors.New("null byte in data")
        }
        result = append(result, transform(b))
    }

    return result, nil // explicit: clearer in longer functions
}
```

### Semicolons

Go's lexer automatically inserts semicolons after any line whose last token is an identifier, literal, or one of: `break continue fallthrough return ++ -- ) }`.

This means **opening braces must be on the same line** as the control structure:

```go
// Good: brace on same line
if i < f() {
    g()
}

// Bad: brace on next line -- lexer inserts semicolon after f()
if i < f()  // wrong!
{           // wrong!
    g()
}
```

Idiomatic Go only has explicit semicolons in `for` loop clauses and to separate multiple statements on a single line.

---

## 2. Control Flow

### If with Initialization

`if` and `switch` accept an optional initialization statement. Use it to scope variables to the conditional block:

```go
if err := file.Chmod(0664); err != nil {
    log.Print(err)
    return err
}
```

If you need the variable beyond a few lines after the `if`, declare it separately and use a standard `if` instead:

```go
x, err := f()
if err != nil {
    return err
}
// lots of code that uses x
```

### Indent Error Flow (Guard Clauses)

When an `if` body ends with `break`, `continue`, `goto`, or `return`, omit the unnecessary `else`. Keep the success path unindented:

```go
f, err := os.Open(name)
if err != nil {
    return err
}
d, err := f.Stat()
if err != nil {
    f.Close()
    return err
}
codeUsing(f, d)
```

Never bury normal flow inside an `else` when the `if` already returns.

### Redeclaration and Reassignment

The `:=` short declaration allows redeclaring variables in the same scope:

```go
f, err := os.Open(name)  // declares f and err
d, err := f.Stat()       // declares d, reassigns err
```

A variable `v` may appear in a `:=` declaration even if already declared, provided:

1. The declaration is in the **same scope** as the existing `v`
2. The value is **assignable** to `v`
3. At least **one other variable** is newly created by the declaration

### Variable Shadowing

**Warning**: If `v` is declared in an outer scope, `:=` creates a **new** variable that shadows it -- a common source of bugs:

```go
// Bug: ctx inside the if block shadows the outer ctx
if *shortenDeadlines {
    ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
    defer cancel()
}
// ctx here is still the original -- the shadowed ctx didn't escape

// Fix: use = instead of :=
var cancel func()
ctx, cancel = context.WithTimeout(ctx, 3*time.Second)
```

### For Loops

Go's `for` is its only looping construct, unifying `while`, `do-while`, and C-style `for`:

```go
// Condition-only (Go's "while")
for x > 0 {
    x = process(x)
}

// Infinite loop
for {
    if done() { break }
}

// C-style three-component
for i := 0; i < n; i++ { ... }
```

### Range

`range` iterates over slices, maps, strings, and channels:

```go
for i, v := range slice { ... }   // index + value
for k, v := range myMap { ... }   // key + value (non-deterministic order)
for i, r := range "hello" { ... } // byte index + rune (not byte)
for v := range ch { ... }         // receives until channel closed
```

**Key rules:**
- Range over strings yields **runes**, not bytes -- `i` is the byte offset.
- Range over maps has **non-deterministic order** -- don't rely on it.
- Use `_` to discard the index or value: `for _, v := range slice`.

### Parallel Assignment

Go has no comma operator. Use parallel assignment for multiple loop variables:

```go
for i, j := 0, len(a)-1; i < j; i, j = i+1, j-1 {
    a[i], a[j] = a[j], a[i]
}
```

`++` and `--` are statements, not expressions -- they cannot appear in parallel assignment.

### Switch: Labeled Break

`break` inside a `switch` within a `for` loop only breaks the switch. Use a labeled `break` to exit the enclosing loop:

```go
Loop:
    for _, v := range items {
        switch v.Type {
        case "done":
            break Loop  // breaks the for loop
        }
    }
```

### The Blank Identifier

**Never discard errors carelessly** -- a nil dereference panic may follow.

Verify interface compliance at compile time: `var _ io.Writer = (*MyType)(nil)`.

### Control Flow Quick Reference

| Pattern | Go Idiom |
|---------|----------|
| If initialization | `if err := f(); err != nil { }` |
| Early return | Omit `else` when if body returns |
| Redeclaration | `:=` reassigns if same scope + new var |
| Shadowing trap | `:=` in inner scope creates new variable |
| Parallel assignment | `i, j = i+1, j-1` |
| Expression-less switch | `switch { case cond: }` |
| Comma cases | `case 'a', 'b', 'c':` |
| No fallthrough | Default behavior (explicit `fallthrough` if needed) |
| Break from loop in switch | `break Label` |
| Discard value | `_, err := f()` |
| Side-effect import | `import _ "pkg"` |
| Interface check | `var _ Interface = (*Type)(nil)` |
