---
name: git
description: Git workflow. Auto-commits after code changes with conventional commits and security scanning. Also invocable as /git pr|scan. Use when ANY code is written, modified, or deleted.
argument-hint: "pr | scan | branch"
metadata:
  tools: "git, gh (GitHub CLI), commitlint, lefthook"
allowed-tools: Bash(git:*), Bash(gh:*)
---

# Git Engineer

## Behavior

### Auto (after code changes)

When code work is complete (feature done, bug fixed, refactor finished):
1. **Test gate**: if commit type is `feat`, `fix`, or `refactor` → run unit tests first. No test = no commit.
2. Read `references/COMMIT.md`
3. Stage → scan → split → commit automatically
4. Return structured result only

Do NOT ask user for permission to commit. Just do it — like auto-save.

### Commands (user invokes explicitly)

```
/commit                    # Manual commit (standalone command)
/git pr           # Push + create PR with template
/git scan         # Security scan all tracked files
/git branch       # Branch status + cleanup stale
```

PR is a deliberate decision — never auto-create.

## Test Enforcement

| Commit type | Unit test | Integration test |
|-------------|-----------|-----------------|
| `feat` | **Required** — write test WITH code | Not required per commit |
| `fix` | **Required** — test must reproduce bug | Not required per commit |
| `refactor` | **Required** — existing tests must pass, do NOT modify tests | Not required per commit |
| `docs`, `chore`, `ci`, `style` | Not required | Not required |
| `/git pr` | All pass | **Required** — write before PR |

**Anti-rationalizations:**
- "I'll add tests later" → No. `feat` without test = blocked commit.
- "It's a small change" → Small changes break things. Test it.
- "Refactor needs test updates" → If you modify tests, it's not refactor — it's behavior change.

## Core Rules

- **Conventional Commits**: `type(scope): description` — imperative, present tense, lowercase
- Types: `feat` > `fix` > `refactor` > `perf` > `test` > `docs` > `chore` > `ci`
- One logical change per commit. Split if mixed types or scopes
- Max 72 chars subject. Body explains **why**, not what
- **Never** AI attribution in commits
- **Scan before every commit** — if secrets: STOP, warn user, do NOT commit
- **Never** commit `.env`, `*.pem`, `id_rsa`, `credentials.json`
- `main` is always deployable. **Never** force push to `main`
- Branch naming: `type/description` — `feat/user-auth`, `fix/login-redirect`
- Delete branch after merge
- **Squash merge** features, **rebase** to update, **merge commit** for releases

## Auto-Commit Output

After every auto-commit, show only:

```
✓ type(scope): description
  N files (+X/-Y lines)
  tests: 5 passed
```

If secrets found:
```
✗ BLOCKED: secret detected in path/to/file.go
  Unstaged. Add to .gitignore and rotate the secret.
```

## References

| Task | File | Tokens |
|------|------|--------|
| Commit workflow | `references/COMMIT.md` | ~350 |
| Create PR | `references/PR.md` | ~400 |
| Security scan | `references/SCAN.md` | ~300 |
| Branch ops | `references/BRANCH.md` | ~300 |
| Conflicts | `references/CONFLICT-RESOLUTION.md` | ~1,700 |
| Hooks setup | `references/HOOKS.md` | ~2,000 |
| Signing | `references/SECURITY.md` | ~2,200 |
| Commit spec | `references/CONVENTIONAL-COMMITS.md` | ~2,300 |
| PR review | `references/WORKFLOW-PR.md` | ~2,200 |
| Branch strategy | `references/BRANCH-STRATEGY.md` | ~2,300 |
| GH CLI | `references/GH-CLI.md` | ~1,700 |

## Anti-Patterns

| Don't | Do |
|-------|----|
| Ask user to commit | Auto-commit after code changes |
| `git add .` blindly | `git add -p` or specific files |
| `"fix stuff"` | `fix(auth): resolve token expiry redirect` |
| Force push to main | Force push only to own feature branches |
| Giant commit (30+ files) | Split by type/scope |
| Commit secrets | Scan, STOP, `.gitignore`, rotate |
| `--no-verify` | Fix the hook issue |
| Auto-create PR | PR is deliberate — user invokes `/git pr` |
