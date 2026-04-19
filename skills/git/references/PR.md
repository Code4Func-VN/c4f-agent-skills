# Quick PR

## Create

```bash
gh pr create --title "feat(auth): add OAuth2 PKCE flow" --body "$(cat <<'EOF'
## Summary
Add OAuth2 PKCE authorization flow for mobile clients.
Closes #214

## Changes
- Add PKCE challenge generation
- Add token exchange endpoint
- Update login page
- Add integration tests

## Test Plan
- [ ] `npm test` passes
- [ ] Manual: complete OAuth flow on staging

## Breaking Changes
None.
EOF
)"
```

## Options

```bash
--reviewer alice,bob      # Request reviewers
--draft                   # Draft PR
--base develop            # Target branch (default: main)
--label "bug,urgent"      # Labels
```

## Title Format

Good: `feat(user): add profile settings`
Bad: `Update user stuff`

## Pre-PR Checklist

- [ ] Tests pass
- [ ] Lint clean
- [ ] Build succeeds
- [ ] Rebased on latest main
- [ ] No debug code, no TODOs
- [ ] Secrets scanned

## Merge

```bash
gh pr merge --squash --delete-branch    # Features
gh pr merge --rebase --delete-branch    # Small fixes
gh pr merge --merge                     # Releases
```
