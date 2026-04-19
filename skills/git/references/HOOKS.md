# Git Hooks

## Why Hooks

Hooks catch problems in seconds on your machine instead of minutes in CI. They prevent bad commits from entering history, reduce CI costs, and give developers instant feedback before code leaves their laptop.

## Lefthook vs Husky

| Feature | Lefthook | Husky |
|---|---|---|
| Language | Go binary | Node.js |
| Requires npm | No | Yes |
| Speed | Fast (native binary) | Slower (Node startup) |
| Config format | YAML | Shell scripts |
| Parallel execution | Built-in | Manual |
| Monorepo support | Built-in | Requires workarounds |
| Install | `brew install lefthook` | `npm install husky` |
| Zero-config lint-staged | Yes (`npx lint-staged`) | Yes |

**Use lefthook.** It is faster, works without Node.js, runs hooks in parallel, and uses a single YAML config. Husky is fine for small JS-only projects, but lefthook scales better.

## Lefthook Setup

```bash
# Install
brew install lefthook    # macOS
# or: go install github.com/evilmartians/lefthook@latest
# or: npm install -D lefthook

# Initialize in your repo (creates lefthook.yml, updates .git/hooks/)
lefthook install
```

## Complete lefthook.yml

Copy this into your project root. It covers formatting, linting, secret scanning, type checking, commit message validation, testing, and branch protection.

```yaml
# lefthook.yml
assert_lefthook_installed: true
no_tty: false

pre-commit:
  parallel: true
  commands:
    lint-staged:
      glob: "*.{js,ts,tsx,jsx,vue,svelte}"
      run: npx lint-staged
    secret-scan:
      run: |
        git diff --cached -U0 | \
        grep -qE '(AKIA[A-Z0-9]{16}|-----BEGIN .* PRIVATE KEY-----|xox[bpors]-|[sr]k_(live|test)_|ghp_[A-Za-z0-9]{36}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]+\.eyJ)' \
        && echo "SECRET DETECTED in staged changes. Remove it before committing." && exit 1 \
        || true
    typecheck:
      glob: "*.{ts,tsx}"
      run: npx tsc --noEmit --pretty
      skip:
        - merge
        - rebase

commit-msg:
  commands:
    commitlint:
      run: npx commitlint --edit {1}

pre-push:
  parallel: true
  commands:
    test:
      run: npm test -- --bail --forceExit
    build-check:
      run: npm run build --if-present
    branch-protection:
      run: |
        branch=$(git rev-parse --abbrev-ref HEAD)
        if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
          echo "Direct push to $branch is blocked. Use a pull request."
          exit 1
        fi
```

## Pre-Commit Hooks

### lint-staged config (package.json)

Runs formatters and linters only on staged files for speed.

```json
{
  "lint-staged": {
    "*.{js,ts,tsx,jsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{json,md,yml,yaml,css}": [
      "prettier --write"
    ],
    "*.css": [
      "stylelint --fix"
    ],
    "*.py": [
      "ruff check --fix",
      "ruff format"
    ]
  }
}
```

### Secret scanning

The inline grep in `lefthook.yml` handles common patterns. For a more thorough standalone script, see `SECURITY.md` -- the `scan-secrets` shell function covers 10 pattern categories and can be called from lefthook via `run: bash scripts/scan-secrets.sh`.

### Type checking

```yaml
typecheck:
  glob: "*.{ts,tsx}"
  run: npx tsc --noEmit --pretty
  skip:
    - merge
    - rebase    # skip during merge/rebase where intermediate states may have type errors
```

## Commit-Msg Hook

### commitlint.config.js (copy-paste ready)

```javascript
// commitlint.config.js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'perf', 'test', 'build', 'ci', 'chore', 'revert',
    ]],
    'subject-empty': [2, 'never'],
    'subject-case': [2, 'always', 'lower-case'],
    'subject-max-length': [2, 'always', 72],
    'body-max-line-length': [1, 'always', 100],
    'header-max-length': [2, 'always', 100],
  },
};
```

```bash
# Install commitlint
npm install --save-dev @commitlint/cli @commitlint/config-conventional
```

### Valid messages

```
feat(auth): add oauth2 login flow
fix(api): handle null response from payment gateway
docs: update contributing guide
refactor(db): extract connection pooling to shared module
chore(deps): bump express from 4.18.2 to 4.19.0
```

### Invalid messages (rejected by commitlint)

```
Added new feature          # no type prefix
feat: Add Login Page       # uppercase subject
feat(auth)                 # empty subject
fix: this is a very long commit message that exceeds the seventy-two character limit for the subject line   # too long
update stuff               # no type, vague
```

## Pre-Push Hook

### Run tests

```yaml
test:
  run: npm test -- --bail --forceExit
```

`--bail` stops on first failure for fast feedback. `--forceExit` prevents Jest from hanging on open handles.

### Build check

```yaml
build-check:
  run: npm run build --if-present
```

Catches build errors before they reach CI. `--if-present` skips gracefully if no build script exists.

### Protected branch guard

Prevents accidental direct pushes to protected branches. Already included in the `lefthook.yml` above for `main`/`master`. To add more branches, extend the check:

```yaml
branch-protection:
  run: |
    branch=$(git rev-parse --abbrev-ref HEAD)
    for b in main master production staging; do
      [ "$branch" = "$b" ] && echo "Direct push to $b blocked. Use a PR." && exit 1
    done
```

## CI Integration

Hooks and CI serve different purposes. Use both.

| Aspect | Git Hooks (local) | CI Pipeline (remote) |
|---|---|---|
| Speed | Seconds | Minutes |
| Runs on | Developer machine | CI server |
| Bypassable | Yes (`--no-verify`) | No |
| Coverage | Staged files only | Full repo |
| Cost | Free | Compute minutes |
| Purpose | Fast feedback, catch obvious errors | Source of truth, full validation |
| Examples | Lint, format, type check, secret scan | Full test suite, build, deploy, security audit |

Hooks are the first line of defense. CI is the authoritative gate. Never skip CI because hooks passed.

## Local Overrides

Create `lefthook-local.yml` for per-developer customization. This file should be in `.gitignore` so it does not affect other developers.

```yaml
# lefthook-local.yml (gitignored, per-developer)

pre-commit:
  commands:
    typecheck:
      skip: true    # skip typecheck locally if your IDE handles it

pre-push:
  commands:
    test:
      run: npm test -- --bail --testPathPattern="src/my-module"   # only run your tests
```

Add to `.gitignore`:

```gitignore
lefthook-local.yml
```

This lets developers customize hook behavior without modifying the shared `lefthook.yml`.

## Bypass

`--no-verify` skips all hooks. Use only in genuine emergencies.

```bash
git commit --no-verify -m "hotfix: emergency production patch"
git push --no-verify
```

### Acceptable reasons to bypass

- Emergency production hotfix that cannot wait for lint fixes
- Committing auto-generated files that fail lint rules
- CI-authored commits in automation scripts

### Unacceptable reasons

- "The linter is annoying" -- fix your code
- "Type checking is slow" -- use `lefthook-local.yml` to skip it locally
- "Commitlint rejected my message" -- write a proper conventional commit

If you bypass, add a comment to the PR explaining why. Never make `--no-verify` a habit.

## Troubleshooting

| Problem | Fix |
|---|---|
| Hook not running | `lefthook install` to reinstall; `ls -la .git/hooks/` to verify; `lefthook run pre-commit` to test manually |
| Permission denied | `chmod +x .git/hooks/*` and `chmod +x scripts/*.sh` |
| Command not found (`node`, `npx`) | Verify `which node`; if using nvm, add `rc: "~/.nvm/nvm.sh"` to lefthook.yml |
| Slow hooks | Set `parallel: true`; use `lint-staged` (not `eslint .`); add `skip: [merge, rebase]` for expensive checks |
| Hooks not running in CI | Expected -- hooks are local only. CI runs its own checks via workflow config |
