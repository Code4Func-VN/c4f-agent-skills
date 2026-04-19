# Commit Workflow

Step-by-step instructions for staging, analyzing, splitting, and committing changes.

---

## Step 1: Stage Intentionally

Never blindly stage everything. Review what you are adding.

```bash
git add src/auth/login.ts src/auth/login.test.ts   # stage specific files
git add -p src/api/handler.ts                       # stage individual hunks
```

Interactive hunk prompts: `y` = stage, `n` = skip, `s` = split smaller, `q` = quit.

```bash
git diff --cached                   # full diff of staged changes
git diff --cached --stat            # summary: files, insertions, deletions
git diff --cached --name-only       # just file paths
git restore --staged <file>         # unstage one file
git restore --staged .              # unstage everything
```

```bash
# BAD — blind staging
git add .
git add -A
git add src/ && git commit -m "changes"

# GOOD — intentional staging
git add src/auth/login.ts src/auth/login.test.ts
git diff --cached --stat
git commit -m "feat(auth): add session refresh logic"
```

---

## Step 2: Security Scan

Run BEFORE every commit. No exceptions.

```bash
git diff --cached -U0 | grep -nE \
  'AKIA[A-Z0-9]{16}|-----BEGIN .* PRIVATE KEY-----|xox[bpors]-|[sr]k_(live|test)_|ghp_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+|API_KEY\s*=\s*["\x27][^"\x27]{8,}|PASSWORD\s*=\s*["\x27][^"\x27]{8,}|mongodb\+srv://[^\s]+|postgres://[^\s]+@|mysql://[^\s]+@|redis://[^\s]+@' \
  && echo "SECRETS DETECTED -- DO NOT COMMIT" || echo "Clean"
```

| Category          | Pattern                           | Example match                     |
|-------------------|-----------------------------------|-----------------------------------|
| AWS Access Key    | `AKIA[A-Z0-9]{16}`               | `AKIAIOSFODNN7EXAMPLE`            |
| Private Key       | `-----BEGIN .* PRIVATE KEY-----`  | `-----BEGIN RSA PRIVATE KEY-----` |
| GitHub Token      | `ghp_[A-Za-z0-9]{36}`            | `ghp_abc123def456...`             |
| Slack Token       | `xox[bpors]-...`                 | `xoxb-1234567890-abc`             |
| Stripe Key        | `[sr]k_(live\|test)_...`         | `sk_live_abc123...`               |
| JWT               | `eyJ...\.eyJ...`                 | `eyJhbGciOiJIUzI1NiJ9.eyJ...`    |
| DB Connection URL | `protocol://user:pass@host`      | `postgres://admin:s3cret@db.io`   |

### STOP protocol (if secrets detected)

```bash
# 1. STOP — do NOT commit or push
# 2. Unstage the file
git restore --staged <file-with-secret>
# 3. Remove secret from source, use env var instead
# 4. Add to .gitignore if file should never be tracked
echo ".env.local" >> .gitignore
# 5. Rotate the secret immediately — compromised the moment it touched a diff
```

---

## Step 3: Analyze Changes

```bash
git diff --cached --stat            # files changed, lines added/removed
git diff --cached --name-only       # just the file list
git diff --cached --shortstat       # one-line summary: 3 files, +42, -17
```

### Classify by type and scope

| Type       | Examples                                       |
|------------|------------------------------------------------|
| `feat`     | new endpoint, new component, new CLI command   |
| `fix`      | bug correction, error handling fix              |
| `refactor` | rename, extract function, restructure          |
| `test`     | new test, update test fixture                  |
| `docs`     | README, JSDoc, inline comments                 |
| `chore`    | deps update, CI config, linter config          |

Determine scope from file paths: all files under `src/auth/` = scope `auth`. Mixed paths = might need to split.

---

## Step 4: Split Decision

| Single commit when                        | Split into multiple when                    |
|-------------------------------------------|---------------------------------------------|
| All changes share same type AND scope     | Mixed types (feat + fix)                    |
| 3 files or fewer                          | Mixed scopes (auth + billing)               |
| 50 lines or fewer total diff              | 10+ files across unrelated areas            |
| Splitting would break intermediate state  | Deps update mixed with code changes         |
|                                           | Formatting mixed with logic changes         |
|                                           | Migration mixed with application code       |

### Grouping strategy example

```
Staged diff:
  M src/auth/login.ts         (feat — new OAuth flow)
  M src/auth/login.test.ts    (test — tests for OAuth)
  M src/billing/invoice.ts    (fix — tax calculation)
  M package.json              (chore — add oauth library)
  M package-lock.json         (chore — lockfile)

Split into 3 commits:
  Group 1: package.json + package-lock.json     → chore(deps): add oauth2 client library
  Group 2: src/auth/login.ts + login.test.ts    → feat(auth): add OAuth2 PKCE flow
  Group 3: src/billing/invoice.ts               → fix(billing): correct tax rate calculation
```

---

## Step 5: Multi-Commit Workflow

Unstage everything and re-stage per group.

```bash
git restore --staged .

# --- Commit 1: deps ---
git add package.json package-lock.json
git diff --cached --stat
git commit -m "chore(deps): add oauth2-client library"

# --- Commit 2: feature ---
git add src/auth/login.ts src/auth/login.test.ts
git diff --cached --stat
git commit -m "$(cat <<'EOF'
feat(auth): add OAuth2 PKCE flow

Implements authorization code flow with PKCE for mobile clients.
Uses oauth2-client library for token exchange.

Closes #214
EOF
)"

# --- Commit 3: bugfix ---
git add src/billing/invoice.ts
git commit -m "fix(billing): correct tax rate for EU customers"
```

### Partial file staging

When one file contains changes for different commits:

```bash
git add -p src/api/handler.ts       # stage only relevant hunks (y/n/s)
git commit -m "fix(api): validate request body before processing"

git add -p src/api/handler.ts       # stage remaining hunks
git commit -m "feat(api): add rate limiting headers to response"
```

---

## Step 6: Write Commit Message

### Single-line

```bash
git commit -m "type(scope): imperative description"
```

### Multi-line with HEREDOC

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add session timeout configuration

Allow admins to configure session timeout per role.
Default remains 30 minutes. Enterprise supports 24 hours.

- Add timeout_minutes column to roles table
- Update session middleware to read role config

Closes #187
EOF
)"
```

### Imperative mood

```bash
# BAD (past tense)
git commit -m "fix(api): fixed the broken endpoint"
git commit -m "feat(ui): added new button component"

# GOOD (imperative — "this commit will...")
git commit -m "fix(api): handle null response from upstream"
git commit -m "feat(ui): add export button to dashboard"
```

---

## Step 7: Verify

```bash
git log --oneline -5                # confirm commit(s) in history
git show --stat HEAD                # files and line counts in last commit
git status                          # working tree should be clean
```

### Amend rules

```bash
# Only amend if NOT yet pushed
git commit --amend -m "fix(api): correct the error message format"

# If already pushed — create a NEW commit instead
git commit -m "fix(api): update error message wording"
```

```bash
# BAD — amend after push rewrites shared history
git push origin feat/auth
git commit --amend -m "better message"
git push --force origin feat/auth           # DANGEROUS

# GOOD — amend only before first push
git commit -m "feat(auth): add login"
git commit --amend -m "feat(auth): add login endpoint"
git push origin feat/auth                   # first push, safe
```

---

## Common Mistakes

### 1. Blind staging

```bash
# BAD                                    # GOOD
git add .                                git add src/auth/session.ts
git commit -m "updates"                  git diff --cached --stat
                                         git commit -m "fix(auth): expire session after password change"
```

### 2. Giant mixed commits

```bash
# BAD                                    # GOOD
git commit -m "feat: various updates"    git commit -m "feat(search): add fuzzy matching"
                                         git commit -m "fix(auth): handle expired refresh tokens"
                                         git commit -m "chore(deps): update eslint to v9"
```

### 3. Committing secrets

```bash
# BAD                                    # GOOD
const key = "sk_live_abc123"             const key = process.env.STRIPE_SECRET_KEY
```

### 4. Vague messages

```bash
# BAD                                    # GOOD
git commit -m "fix bug"                  git commit -m "fix(cart): prevent negative quantity"
git commit -m "WIP"                      git commit -m "refactor(api): extract middleware module"
```

### 5. Amending after push

```bash
# BAD                                    # GOOD
git push origin feat/checkout            git push origin feat/checkout
git commit --amend -m "better msg"       git commit -m "fix(checkout): correct shipping label"
git push --force origin feat/checkout    git push origin feat/checkout
```
