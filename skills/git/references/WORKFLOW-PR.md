# PR Workflow

Step-by-step instructions for creating, reviewing, and merging pull requests.

---

## Step 1: Pre-PR Checklist

Run every check BEFORE creating the PR. Fix failures first.

```bash
npm test                            # tests pass (or: cargo test, go test ./...)
npm run lint                        # zero warnings
npm run build                       # build succeeds
git fetch origin && git rebase origin/main   # rebased on latest main
git diff origin/main...HEAD | grep -nE 'console\.log|debugger|TODO|FIXME' || echo "Clean"
```

```bash
# BAD — create PR without checking
git push && gh pr create --title "feat: new thing"

# GOOD — verify everything first
npm test && npm run lint && npm run build
git fetch origin && git rebase origin/main
git push -u origin feat/my-feature
gh pr create --title "feat(auth): add OAuth2 flow"
```

---

## Step 2: Push Branch

```bash
git push -u origin feat/my-feature          # first push with upstream tracking
git branch -vv                              # verify tracking info
git log --oneline origin/main..HEAD         # commits that will be in the PR
```

```bash
# BAD branch names               # GOOD branch names
git push -u origin my-branch     git push -u origin feat/add-oauth-flow
git push -u origin fix           git push -u origin fix/null-pointer-on-empty-cart
git push -u origin john/stuff    git push -u origin chore/upgrade-react-19
```

---

## Step 3: PR Title

Conventional commit format, under 70 characters.

```bash
# GOOD
feat(auth): add OAuth2 PKCE flow for mobile clients
fix(api): prevent duplicate webhook deliveries
refactor(db): migrate from raw SQL to query builder
chore(deps): upgrade React from 18.2 to 19.0
perf(search): add index on users.email column

# BAD
Update code                          # vague, no type
fix                                  # no scope, no description
Fixed the login bug                  # past tense, no type prefix
WIP: working on stuff                # not ready, don't create PR
feat(auth): add OAuth2 PKCE flow for mobile clients and also fix billing bug
                                     # multiple changes, too long
```

---

## Steps 4-5: PR Body + `gh pr create`

Full command with HEREDOC body. This template covers all required sections.

```bash
gh pr create --title "feat(auth): add OAuth2 PKCE flow" --body "$(cat <<'EOF'
## Summary

Add OAuth2 PKCE authorization flow for mobile clients.
Replaces the implicit grant flow deprecated by OAuth 2.1.

Closes #214

## Changes

- Add PKCE challenge generation in `src/auth/pkce.ts`
- Add token exchange endpoint `POST /api/auth/token`
- Update login page with OAuth redirect button
- Add integration tests for full OAuth flow

## Test Plan

- [ ] `npm test` passes
- [ ] Manual: complete OAuth flow on staging
- [ ] Edge case: expired auth code returns proper error

## Breaking Changes

None. (or list: `POST /api/auth/login` now requires `grant_type` field)

## Screenshots

(if UI changes — paste before/after)

## Related Issues

- Depends on #180 (OAuth provider config)
- Blocks #220 (SSO integration)
EOF
)"
```

### Common options

```bash
gh pr create --title "..." --body "..." --reviewer alice,bob    # assign reviewers
gh pr create --title "..." --body "..." --label "feature"       # add labels
gh pr create --title "..." --body "..." --draft                 # draft PR
gh pr create --title "..." --body "..." --base develop          # target branch
```

```bash
# BAD                                           # GOOD
gh pr create --title "feat: auth" --body ""     gh pr create --title "feat(auth): add OAuth2" --body "$(cat <<'EOF'
gh pr create --title "feat: auth" --body "Done" ## Summary
                                                ...
                                                EOF
                                                )"
```

---

## Step 6: Self-Review Checklist

Walk the diff on GitHub BEFORE requesting review.

1. **No debug code** — `console.log`, `debugger`, `print()`, temp scaffolding removed
2. **No orphaned TODOs** — every `TODO`/`FIXME` references a ticket or is resolved
3. **Types correct** — no `any` without justification, no missing return types on public functions
4. **Errors handled** — no swallowed exceptions, no bare `catch {}`
5. **Tests added** — new behavior has tests, bug fixes have regression tests
6. **Secrets scanned** — no API keys, credentials, `.env` values in the diff
7. **Docs updated** — if public API or config changed, docs reflect it
8. **Migrations reversible** — `down()` works, no data loss on rollback
9. **No unrelated changes** — diff contains ONLY what the PR title describes
10. **Commits clean** — each commit is atomic, messages follow conventional format

```bash
# BAD — request review immediately
git push && gh pr ready

# GOOD — review your own diff first
gh pr view --web                    # open PR in browser, walk every file
gh pr ready                         # mark ready after self-review passes
```

---

## Step 7: Reviewer Guide

### Focus areas (priority order)

1. **Correctness** — Does the code do what the PR claims? Edge cases handled?
2. **Security** — SQL injection, XSS, auth bypass, secret exposure, input validation
3. **Performance** — N+1 queries, unbounded loops, missing indexes, large payloads
4. **Naming** — Variables, functions, types clearly named? Consistent with codebase?
5. **Tests** — Sufficient coverage? Testing behavior, not implementation?

### Feedback format

```markdown
# BAD feedback
"This is wrong"
"Why did you do it this way?"

# GOOD feedback
"Bug: this will throw if `user` is null — add a guard here"
"Suggestion (non-blocking): consider extracting this into a helper"
"Question: is the retry intentional? Add a comment explaining why"
"Nit: `fetchUserData` → `getUserProfile` to match existing naming"
```

Labels: **Bug/Blocker** (must fix), **Suggestion** (non-blocking), **Question** (clarification), **Nit** (style).

---

## Step 8: Merge Strategy

| Strategy         | Command                        | When to use                                |
|------------------|--------------------------------|--------------------------------------------|
| **Squash**       | `gh pr merge <n> --squash`     | Features, bug fixes — default for most PRs |
| **Merge commit** | `gh pr merge <n> --merge`      | Release branches, epics with valuable history |
| **Rebase**       | `gh pr merge <n> --rebase`     | Single-commit fixes, docs, trivial changes |

**Squash** (most common): feature branch with WIP/fixup commits, individual commits not meaningful, want clean main history.

**Merge commit**: release branches where commits matter for changelog, epic branches with separately reviewed sub-features, need merge point for `git bisect`.

**Rebase**: branch has exactly 1 clean commit, docs-only or config-only change.

```bash
# BAD — merge with 15 "WIP" commits polluting main
gh pr merge 42 --merge

# GOOD — squash messy history
gh pr merge 42 --squash

# BAD — squash an epic with meaningful sub-commits
gh pr merge 42 --squash

# GOOD — merge commit preserves epic history
gh pr merge 42 --merge
```

---

## Step 9: Post-Merge

```bash
# Merge with auto-cleanup
gh pr merge 42 --squash --delete-branch

# Update local
git checkout main && git pull origin main
git branch -d feat/my-feature
git fetch --prune

# Verify deployment
gh run list --limit 5               # check CI/CD pipeline
gh run watch                        # watch specific run
# Smoke-test the feature, check error tracking (Sentry/Datadog)

# Close issues not auto-closed by "Closes #123"
gh issue close 123 --comment "Resolved in #42"
```

```bash
# BAD — merge and walk away, stale branches accumulate
gh pr merge 42 --squash

# GOOD — merge, clean up, verify
gh pr merge 42 --squash --delete-branch
git checkout main && git pull && git fetch --prune
gh run watch
```

---

## Common Mistakes

### 1. PR with unrelated changes

```bash
# BAD: feature + fix + formatting in one PR
# GOOD: separate PRs per concern
# PR #1: feat(auth): add OAuth2 flow
# PR #2: fix(billing): correct tax calculation
```

### 2. No test plan

```markdown
# BAD                                    # GOOD
## Test Plan                             ## Test Plan
"It works on my machine"                 - [ ] `npm test` passes (14 new tests)
                                         - [ ] Manual: OAuth login on staging
                                         - [ ] Edge case: expired code returns 401
```

### 3. Force-pushing after review

```bash
# BAD — destroys review comments context
git rebase -i HEAD~5 && git push --force

# GOOD — fixup commits, let squash-merge clean up
git commit -m "fixup: address review feedback"
git push
```
