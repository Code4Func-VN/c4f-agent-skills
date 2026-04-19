# Quick Naming Reference

## Receiver Names

| Type | Receiver | Example |
|------|----------|---------|
| `Client` | `c` | `func (c *Client) Send()` |
| `Server` | `s` | `func (s *Server) Start()` |
| `Handler` | `h` | `func (h *Handler) Create()` |
| `Service` | `s` | `func (s *Service) Register()` |
| `Repository` | `r` | `func (r *Repository) Find()` |
| `User` | `u` | `func (u *User) Deactivate()` |

Never `this` or `self`. Stay consistent across all methods of the same type.

## Interface Naming

One-method interfaces: method name + `-er` suffix.

| Method | Interface |
|--------|-----------|
| `Read` | `Reader` |
| `Write` | `Writer` |
| `Close` | `Closer` |
| `Format` | `Formatter` |
| `Handle` | `Handler` |

Multi-method: use a descriptive noun (`Repository`, `Store`, `Transport`).

## Initialisms Table

| Correct | Wrong |
|---------|-------|
| `HTTPClient` | `HttpClient` |
| `userID` | `userId` |
| `ParseURL` | `ParseUrl` |
| `XMLAPI` | `XmlApi` |
| `htmlParser` | `HTMLParser` (unexported = all lower) |

Rule: initialisms are all-caps when exported, all-lower when unexported.

## Variable Length by Scope

| Scope | Length | Example |
|-------|--------|---------|
| 1-7 lines | single letter | `i`, `n`, `r`, `w` |
| medium | short word | `count`, `buf`, `conn` |
| package-level | descriptive | `userAccountCount` |
