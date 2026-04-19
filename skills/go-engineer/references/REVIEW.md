# Go Code Review Checklist

## Review Procedure

1. Run `gofmt -d .` and `go vet ./...` to catch mechanical issues first
2. Read the diff file-by-file; for each file, check the categories below in order
3. Flag issues with specific line references and the rule name
4. After reviewing all files, re-read flagged items to verify they're genuine issues
5. Summarize findings grouped by severity (must-fix, should-fix, nit)

> **Validation**: After completing the review, re-read the diff once more to verify every flagged issue is real. Remove any finding you cannot justify with a specific line reference.

---

## Formatting

- [ ] **gofmt**: Code is formatted with `gofmt` or `goimports`

---

## Documentation

- [ ] **Comment sentences**: Comments are full sentences starting with the name being described, ending with a period
- [ ] **Doc comments**: All exported names have doc comments; non-trivial unexported declarations too
- [ ] **Package comments**: Package comment appears adjacent to package clause with no blank line
- [ ] **Named result parameters**: Only used when they clarify meaning (e.g., multiple same-type returns), not just to enable naked returns

---

## Error Handling

- [ ] **Handle errors**: No discarded errors with `_`; handle, return, or (exceptionally) panic
- [ ] **Error strings**: Lowercase, no punctuation (unless starting with proper noun/acronym)
- [ ] **In-band errors**: No magic values (-1, "", nil); use multiple returns with error or ok bool
- [ ] **Indent error flow**: Handle errors first and return; keep normal path at minimal indentation

---

## Naming

- [ ] **MixedCaps**: Use `MixedCaps` or `mixedCaps`, never underscores; unexported is `maxLength` not `MAX_LENGTH`
- [ ] **Initialisms**: Keep consistent case: `URL`/`url`, `ID`/`id`, `HTTP`/`http` (e.g., `ServeHTTP`, `xmlHTTPRequest`)
- [ ] **Variable names**: Short names for limited scope (`i`, `r`, `c`); longer names for wider scope
- [ ] **Receiver names**: One or two letter abbreviation of type (`c` for `Client`); no `this`, `self`, `me`; consistent across methods
- [ ] **Package names**: No stuttering (use `chubby.File` not `chubby.ChubbyFile`); avoid `util`, `common`, `misc`
- [ ] **Avoid built-in names**: Don't shadow `error`, `string`, `len`, `cap`, `append`, `copy`, `new`, `make`

---

## Concurrency

- [ ] **Goroutine lifetimes**: Clear when/whether goroutines exit; document if not obvious
- [ ] **Synchronous functions**: Prefer sync over async; let callers add concurrency if needed
- [ ] **Contexts**: First parameter; not in structs; no custom Context types; pass even if you think you don't need to

---

## Interfaces

- [ ] **Interface location**: Define in consumer package, not implementor; return concrete types from producers
- [ ] **No premature interfaces**: Don't define before used; don't define "for mocking" on implementor side
- [ ] **Receiver type**: Use pointer if mutating, has sync fields, or is large; value for small immutable types; don't mix

---

## Data Structures

- [ ] **Empty slices**: Prefer `var t []string` (nil) over `t := []string{}` (non-nil zero-length)
- [ ] **Copying**: Be careful copying structs with pointer/slice fields; don't copy `*T` methods' receivers by value

---

## Security

- [ ] **Crypto rand**: Use `crypto/rand` for keys, not `math/rand`
- [ ] **Don't panic**: Use error returns for normal error handling; panic only for truly exceptional cases

---

## Declarations and Initialization

- [ ] **Group similar**: Related `var`/`const`/`type` in parenthesized blocks; separate unrelated
- [ ] **var vs :=**: Use `var` for intentional zero values; `:=` for explicit assignments
- [ ] **Reduce scope**: Move declarations close to usage; use if-init to limit variable scope
- [ ] **Struct init**: Always use field names; omit zero fields; `var` for zero structs
- [ ] **Use `any`**: Prefer `any` over `interface{}` in new code

---

## Functions

- [ ] **File ordering**: Types -> constructors -> exported methods -> unexported -> utilities
- [ ] **Signature formatting**: All args on own lines with trailing comma when wrapping
- [ ] **Naked parameters**: Add `/* name */` comments for ambiguous bool/int args, or use custom types
- [ ] **Printf naming**: Functions accepting format strings end in `f` for `go vet`

---

## Style

- [ ] **Line length**: No rigid limit, but avoid uncomfortably long lines; break by semantics, not arbitrary length
- [ ] **Naked returns**: Only in short functions; explicit returns in medium/large functions
- [ ] **Pass values**: Don't use pointers just to save bytes; pass `string` not `*string` for small fixed-size types
- [ ] **String concatenation**: `+` for simple; `fmt.Sprintf` for formatting; `strings.Builder` for loops

---

## Logging

- [ ] **Use slog**: New code uses `log/slog`, not `log` or `fmt.Println` for operational logging
- [ ] **Structured fields**: Log messages use static strings with key-value attributes, not fmt.Sprintf
- [ ] **Appropriate levels**: Debug for developer tracing, Info for notable events, Warn for recoverable issues, Error for failures
- [ ] **No secrets in logs**: PII, credentials, and tokens are never logged

---

## Imports

- [ ] **Import groups**: Standard library first, then blank line, then external packages
- [ ] **Import renaming**: Avoid unless collision; rename local/project-specific import on collision
- [ ] **Import blank**: `import _ "pkg"` only in main package or tests
- [ ] **Import dot**: Only for circular dependency workarounds in tests

---

## Generics

- [ ] **When to use**: Only when multiple types share identical logic and interfaces don't suffice
- [ ] **Type aliases**: Use definitions for new types; aliases only for package migration

---

## Testing

- [ ] **Examples**: Include runnable `Example` functions or tests demonstrating usage
- [ ] **Useful test failures**: Messages include what was wrong, inputs, got, and want; order is `got != want`
- [ ] **TestMain**: Use only when all tests need common setup with teardown; prefer scoped helpers first
- [ ] **Real transports**: Prefer `httptest.NewServer` + real client over mocking HTTP

---

## Automated Checks

Run automated pre-review checks:

```bash
bash scripts/pre-review.sh ./...         # text output
bash scripts/pre-review.sh --json ./...  # structured JSON output
```

Or manually: `gofmt -l <path> && go vet ./... && golangci-lint run ./...`

Fix any issues before proceeding to the checklist above.

---

## Integrative Example

When building a production HTTP server, verify your code applies concurrency, error handling, context, documentation, and naming conventions together.
