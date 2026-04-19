# Quick Branch

## Naming

| Type | Example |
|------|---------|
| `feat/` | `feat/user-auth` |
| `fix/` | `fix/login-redirect` |
| `refactor/` | `refactor/db-pool` |
| `chore/` | `chore/upgrade-deps` |
| `hotfix/` | `hotfix/null-crash` |

With ticket: `feat/TM-142-user-search`

## Lifecycle

```bash
# Create
git checkout main && git pull origin main
git checkout -b feat/user-search

# Push
git push -u origin feat/user-search

# Update from main
git fetch origin main && git rebase origin/main
git push --force-with-lease

# Merge (via PR)
gh pr merge --squash --delete-branch

# Cleanup
git checkout main && git pull origin main
git branch -d feat/user-search

# Delete stale remote
git push origin --delete feat/old-branch
```
