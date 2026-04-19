# GitHub CLI (gh)

## 1. PR Operations

```bash
gh pr create --title "Add rate limiting" --body "Description here"
gh pr create --title "Add rate limiting" --draft --reviewer "alice,bob" --label "enhancement"
gh pr create --title "Hotfix auth" --base release/v2.1
gh pr list
gh pr list --state merged --author "@me" --limit 10
gh pr view 42
gh pr view 42 --web
gh pr checkout 42
gh pr review 42 --approve
gh pr review 42 --request-changes --body "Need tests for edge cases"
gh pr review 42 --comment --body "Minor suggestions inline"
gh pr ready 42
gh pr diff 42
gh pr merge 42 --squash --delete-branch
gh pr merge 42 --rebase --delete-branch
gh pr close 42 --comment "Superseded by #45"
```

---

## 2. PR Body with HEREDOC

```bash
gh pr create --title "Add rate limiting middleware" --body "$(cat <<'EOF'
## Summary
- Implement token bucket rate limiter for API endpoints
- Return 429 with Retry-After header when limit exceeded

## Changes
- `src/middleware/rate-limiter.ts` — core logic
- `src/config/limits.ts` — configurable thresholds
- `tests/rate-limiter.test.ts` — unit and integration tests

## Test plan
- [ ] Unit tests for token bucket algorithm
- [ ] Integration tests for 429 responses
- [ ] Load test with 1000 concurrent requests

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Draft PR

```bash
gh pr create --draft --title "WIP: Payments v2" --body "$(cat <<'EOF'
## Summary
- Refactor payment processing pipeline
- **Not ready for review** — sharing for early feedback

## TODO
- [ ] Stripe webhook handler
- [ ] Idempotency keys
EOF
)"
```

---

## 3. Issue Operations

```bash
gh issue create --title "Login fails on Safari" --body "Steps to reproduce..." --label "bug"
gh issue create --title "Add dark mode" --label "enhancement,design" --assignee "@me"
gh issue list
gh issue list --label "bug" --assignee "@me" --state open
gh issue list --milestone "v2.0" --limit 20
gh issue view 99
gh issue view 99 --web
gh issue comment 99 --body "Reproduced on Safari 18.2. Working on a fix."
gh issue close 99
gh issue close 99 --comment "Fixed in #102"
gh issue reopen 99
gh issue edit 99 --add-assignee "alice" --add-label "priority:high"
gh issue edit 99 --remove-label "needs-triage"
gh issue transfer 99 owner/other-repo
```

---

## 4. Releases

```bash
# Auto-generate notes from merged PRs
gh release create v1.0.0 --title "v1.0.0" --generate-notes

# Custom notes with HEREDOC
gh release create v1.0.0 --title "v1.0.0" --notes "$(cat <<'EOF'
## What's New
- User authentication with OAuth2
- Rate limiting middleware

## Bug Fixes
- Fix session timeout on mobile (#123)

## Breaking Changes
- API v1 endpoints removed. Migrate to v2.
EOF
)"

# Draft pre-release
gh release create v2.0.0-rc.1 --title "v2.0.0 RC1" --draft --prerelease --generate-notes

# Upload assets
gh release create v1.0.0 ./dist/app-linux ./dist/app-darwin --title "v1.0.0" --generate-notes

# Manage
gh release edit v1.0.0 --draft=false
gh release list
gh release delete v0.9.0 --yes
```

---

## 5. Actions / CI

```bash
gh run list --workflow "CI" --branch main --limit 5
gh run watch                                          # stream live logs
gh run view 123456
gh run view 123456 --log-failed
gh pr checks 42 --watch --interval 30                 # wait for checks
gh run rerun 123456 --failed                          # re-run failed only
gh run rerun 123456                                   # re-run all
gh workflow run deploy.yml --field environment=staging # manual trigger
gh workflow list
```

---

## 6. Repository

```bash
gh repo clone owner/repo
gh repo fork owner/repo --clone
gh repo view --web
gh repo create my-app --private --clone --add-readme
```

---

## 7. JSON Scripting

Use `--json` to select fields and `--jq` to filter/transform.

```bash
# Get current PR URL
gh pr view --json url --jq '.url'

# List open PRs with author
gh pr list --json number,title,author \
  --jq '.[] | "\(.number)\t\(.author.login)\t\(.title)"'

# PRs needing review
gh pr list --json number,title,reviewDecision \
  --jq '.[] | select(.reviewDecision != "APPROVED") | "#\(.number): \(.title)"'

# Count open bugs
gh issue list --label "bug" --json number --jq 'length'

# Failed checks for a PR
gh pr checks 42 --json name,state \
  --jq '.[] | select(.state == "FAILURE") | .name'

# Export issues for scripting
gh issue list --state open --json number,title,labels --limit 500 > issues.json

# Stale PRs (no updates in 30 days)
gh pr list --json number,title,updatedAt \
  --jq '[.[] | select(.updatedAt < "2026-03-13")] | .[] | "#\(.number): \(.title)"'

# PR reviewer decisions
gh pr view 42 --json reviews --jq '.reviews[] | "\(.author.login): \(.state)"'
```

---

## 8. API Escape Hatch

Use `gh api` for anything not covered by built-in commands.

```bash
# Get PR comments
gh api repos/owner/repo/pulls/42/comments --jq '.[].body'

# Branch protection rules
gh api repos/owner/repo/branches/main/protection

# Add label via API
gh api repos/owner/repo/issues/42/labels \
  --method POST --field 'labels[]=needs-review'

# List org members
gh api orgs/my-org/members --jq '.[].login'

# Paginate all issues
gh api repos/owner/repo/issues --paginate --jq '.[].title'
```

### GraphQL

```bash
gh api graphql -f query='
  query {
    repository(owner: "owner", name: "repo") {
      pullRequest(number: 42) {
        mergeable
        mergeStateStatus
        reviewDecision
      }
    }
  }
' --jq '.data.repository.pullRequest'
```

---

## 9. Auto-Merge

```bash
# Enable auto-merge (merges when checks + reviews pass)
gh pr merge 42 --auto --squash --delete-branch
gh pr merge 42 --auto --merge --delete-branch

# Disable auto-merge
gh pr merge 42 --disable-auto
```

**Prerequisites**: branch protection rules enabled, required status checks configured, required reviews configured, "Allow auto-merge" enabled in repo settings.

### Create PR + Enable Auto-Merge

```bash
gh pr create --title "Dependency update" --body "Automated update" --label "dependencies"
gh pr merge --auto --squash --delete-branch
```

---

## 10. Aliases

```bash
# Set aliases
gh alias set prc 'pr create --draft'
gh alias set prm 'pr merge --squash --delete-branch'
gh alias set mypr 'pr list --author "@me" --state open'

# Use them
gh prc --title "WIP: new feature"
gh prm 42
gh mypr

# More useful aliases
gh alias set review-queue 'pr list --search "review-requested:@me"'
gh alias set open 'repo view --web'

# Manage
gh alias list
gh alias delete prc
```

### Shell Aliases (complement gh aliases)

```bash
# Add to ~/.zshrc or ~/.bashrc
alias ghpr='gh pr create --draft'
alias ghm='gh pr merge --squash --delete-branch'
alias ghw='gh run watch'
alias ghc='gh pr checks --watch'
```
