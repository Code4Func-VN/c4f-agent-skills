# Conventional Commits

Practical rules for writing commit messages that drive automated changelogs,
semantic versioning, and readable project history.

---

## Format

Structure every commit message as:

```
type(scope): subject

[optional body]

[optional footer(s)]
```

- The first line (header) is mandatory and must be under 72 characters total.
- Separate the body from the header with one blank line.
- Separate footers from the body with one blank line.

---

## Types (Priority Order)

Use the highest-priority type that matches the change. When a commit includes
both a feature and a refactor, pick `feat` because it carries more semantic
weight.

| #  | Type       | Description                              | Example                                         |
|----|------------|------------------------------------------|-------------------------------------------------|
| 1  | `feat`     | New user-facing feature                  | `feat(cart): add quantity selector`              |
| 2  | `fix`      | Bug fix                                  | `fix(auth): prevent session timeout on refresh`  |
| 3  | `refactor` | Restructure without behavior change      | `refactor: extract validation into shared utils` |
| 4  | `perf`     | Performance improvement                  | `perf(db): add index on users.email`             |
| 5  | `test`     | Add or update tests only                 | `test(api): add integration tests for /orders`   |
| 6  | `docs`     | Documentation only                       | `docs: update API authentication guide`          |
| 7  | `chore`    | Maintenance, deps, tooling               | `chore: upgrade eslint to v9`                    |
| 8  | `ci`       | CI/CD pipeline configuration             | `ci: add deploy stage to GitHub Actions`         |
| 9  | `style`    | Formatting, whitespace, semicolons       | `style: fix indentation in config files`         |
| 10 | `build`    | Build system or external dependencies    | `build: switch bundler from webpack to vite`     |

---

## Scopes

To add a scope, put the module or area name in parentheses after the type.

**Naming convention:**
- Lowercase, single word or hyphenated: `auth`, `user-profile`, `api`
- Match your project's directory or module names when possible
- Keep scopes consistent across the project (don't use `auth` and `authentication`)

**Common scopes:**
`api`, `auth`, `db`, `ui`, `cli`, `config`, `deps`, `docs`, `core`, `build`

**When to omit scope:**
- The change touches many modules equally: `refactor: rename userId to id`
- The scope adds no useful information: `chore: update lockfile`

---

## Subject Rules

Write the subject (text after the colon) following these rules:

1. **Imperative present tense** -- "add", "fix", "remove" (not "added", "fixes", "removing")
2. **Lowercase first letter** -- `fix: correct null check` not `fix: Correct null check`
3. **72 characters max** for the full header (type + scope + colon + subject)
4. **No period** at the end
5. **Describe the what** from a user/system perspective, not the how

To check imperative mood, your subject should complete the sentence:
"If applied, this commit will ___."

```
# Good -- "this commit will add export button"
feat(reports): add export button

# Bad -- "this commit will added export button" (makes no sense)
feat(reports): added export button
```

---

## Body

Write a body when the subject alone does not explain **why** the change exists.

**When to include a body:**
- The fix addresses a non-obvious bug (explain the root cause)
- The change has trade-offs or alternatives considered
- The change is a workaround with known limitations
- The migration or refactor has context others need

**Format rules:**
- Separate from subject with one blank line
- Wrap lines at 80 characters
- Explain **why**, not **what** (the diff shows what)
- Use bullet points for multiple reasons

```
fix(payments): retry failed charges with exponential backoff

Stripe webhook delivery was unreliable during high traffic. Charges
marked as failed were not retried, causing lost revenue.

Added exponential backoff (1s, 2s, 4s, 8s, max 5 retries) to handle
transient Stripe API errors without overwhelming their rate limits.
```

---

## Breaking Changes

A breaking change alters the public API in a way that requires consumers to
change their code.

**Two ways to mark a breaking change:**

1. Add `!` after the type/scope:
```
feat(api)!: require authentication for all endpoints
```

2. Add a `BREAKING CHANGE:` footer:
```
feat(api): require authentication for all endpoints

BREAKING CHANGE: all endpoints now require a Bearer token. Unauthenticated
requests return 401 instead of the previous default guest access.
```

3. Use both together for maximum visibility:
```
feat(api)!: require authentication for all endpoints

BREAKING CHANGE: all endpoints now require a Bearer token.
```

**SemVer impact:**
- `BREAKING CHANGE` on any type triggers a **major** version bump (1.x.x -> 2.0.0)
- `feat` without breaking change triggers a **minor** bump (1.1.x -> 1.2.0)
- `fix` without breaking change triggers a **patch** bump (1.1.1 -> 1.1.2)

---

## Good Examples

**Simple feature:**
```
feat(search): add autocomplete suggestions dropdown
```

**Fix with body explaining root cause:**
```
fix(api): prevent duplicate webhook deliveries

The dispatcher retried on HTTP 202 responses, treating them as failures.
This caused duplicate events for every successful delivery. Now only
4xx/5xx responses trigger retries.

Closes: #342
```

**Breaking change with full context:**
```
feat(auth)!: switch from cookie auth to Bearer tokens

Session cookies caused CSRF issues on mobile clients and complicated
the microservice architecture. Bearer tokens simplify auth across all
client types and enable stateless service-to-service communication.

BREAKING CHANGE: clients must send Authorization: Bearer <token> header.
Cookie-based sessions are no longer accepted. See migration guide at
docs/auth-migration.md.

Closes: #891
```

**Refactor with no scope:**
```
refactor: extract validation logic into shared utility module

Five controllers duplicated the same email and phone validation.
Centralized into src/utils/validators.ts to reduce maintenance burden.
```

**Dependency update:**
```
chore(deps): upgrade react from 18.2 to 19.0

Includes automatic batching improvements and the new use() hook.
Tested against all existing component tests with zero failures.
```

**Fix referencing an issue:**
```
fix(ui): correct z-index stacking on modal overlay

The overlay rendered behind the navigation bar on Safari 17 due to
a stacking context created by the parent's transform property.

Fixes: #567
Tested-on: Safari 17.2, Chrome 121, Firefox 122
```

---

## Bad Examples

```
feat: Changes
```
Why bad: vague subject, capitalized first letter, does not describe what changed.

```
fixed the login bug.
```
Why bad: no type prefix, past tense ("fixed"), ends with a period, no scope.

```
feat(auth): add OAuth2 PKCE flow for mobile clients and also fix the billing calculation bug and update dependencies
```
Why bad: three unrelated changes crammed into one commit. Exceeds 72-character
limit. Split into three separate commits.

```
feat(auth): Add new feature

Generated by AI assistant
Co-Authored-By: Claude <noreply@anthropic.com>
```
Why bad: capitalized subject, vague description ("new feature"), includes AI
attribution in the message body. Never add AI attribution to commits.

---

## Special Rules

**No AI attribution:**
Never include "Generated by", "Co-Authored-By: AI", or any AI tool credit
in the commit message. The commit author field already tracks who committed.

**.claude directory rules:**
- Commits that only modify files inside `.claude/` use the `chore` type
- Scope to `claude` when touching only `.claude/` files: `chore(claude): update settings`
- When `.claude/` changes accompany code changes, use the code change's type
  and scope -- do not split into separate commits for `.claude/` alone

**Issue references:**
- Place issue references in the footer, not the subject
- Use `Closes:`, `Fixes:`, or `Refs:` prefixes
- Multiple issues: one per line in the footer

```
fix(auth): handle expired refresh tokens gracefully

Fixes: #201
Fixes: #203
Refs: #180
```

---

## Multi-Commit Strategy

**When to split commits:**
- Two or more unrelated changes (a feature + a bug fix)
- A refactor that enables a feature (refactor first, then feature)
- Test additions separate from the code they test (when tests are substantial)
- Dependency updates separate from the code that uses them

**When to keep as one commit:**
- A feature and its unit tests (they are one logical change)
- A bug fix and the regression test that covers it
- A rename/move and the import updates it requires

**Grouping strategy for a PR with multiple commits:**

```
# Commit 1: preparatory refactor
refactor(auth): extract token validation into middleware

# Commit 2: the actual feature
feat(auth): add refresh token rotation

# Commit 3: documentation
docs(auth): add token rotation flow diagram
```

Each commit must compile and pass tests independently. Never leave the
codebase in a broken state between commits.
