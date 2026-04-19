# Branch Strategy

Practical rules for branching, naming, protection, releases, and cleanup.

---

## Default: Trunk-Based Development

Use trunk-based development unless the project explicitly requires Git Flow.

**Rules:**
1. `main` is always deployable -- never push broken code directly.
2. Keep feature branches under 2 days. Merge to `main` at least daily.
3. Hide incomplete work behind feature flags, not long-lived branches.
4. Every merge to `main` should pass all tests and be production-ready.
5. Prefer small, frequent merges over large, infrequent ones.

**To start a new feature:**
```bash
git checkout main && git pull origin main
git checkout -b feat/add-search-bar
# work in small commits, push daily
git push -u origin feat/add-search-bar
```

**To keep your branch current with main:**
```bash
git fetch origin main
git rebase origin/main
# resolve any conflicts, then force-push your branch
git push --force-with-lease
```

---

## When to Use Git Flow

Switch to Git Flow only when these conditions apply:
- Multiple release versions are maintained simultaneously (e.g., v2.x and v3.x)
- Releases require a stabilization period with dedicated QA
- Hotfixes must ship independently from ongoing feature work
- The team has more than 10 active contributors on the same repo

**Git Flow branch roles:**

| Branch      | Purpose                              | Lifetime     |
|-------------|--------------------------------------|--------------|
| `main`      | Production-ready releases only       | Permanent    |
| `develop`   | Integration branch for next release  | Permanent    |
| `feature/*` | New features, branched from develop  | Days to weeks|
| `release/*` | Stabilize a release candidate        | Days         |
| `hotfix/*`  | Urgent fix for production            | Hours to days|

**To create a hotfix in Git Flow:**
```bash
git checkout main && git pull origin main
git checkout -b hotfix/fix-payment-crash
# fix, commit, then merge to both main and develop
git checkout main && git merge hotfix/fix-payment-crash
git checkout develop && git merge hotfix/fix-payment-crash
```

---

## Branch Naming

Format: `type/description` -- lowercase, hyphenated, under 50 characters.
Include ticket number when available: `feat/TM-142-user-search`.

| Type        | Example                        | Use Case                      |
|-------------|--------------------------------|-------------------------------|
| `feat/`     | `feat/user-auth`               | New feature                   |
| `fix/`      | `fix/login-redirect`           | Bug fix                       |
| `refactor/` | `refactor/db-connection-pool`  | Code restructuring            |
| `chore/`    | `chore/upgrade-deps`           | Maintenance task              |
| `hotfix/`   | `hotfix/null-pointer-crash`    | Urgent production fix         |
| `docs/`     | `docs/api-authentication`      | Documentation update          |
| `test/`     | `test/payment-integration`     | Test additions                |
| `ci/`       | `ci/add-deploy-stage`          | Pipeline configuration        |

**Bad:** `myFeature` (no type, camelCase), `fix/Fix-The-Bug` (capitalized),
`feature/add-user-authentication-with-oauth2-and-social-login-support` (too long).

**Good:** `feat/oauth2-login`, `fix/session-timeout`, `chore/TM-88-upgrade-node`.

---

## Protection Rules

Configure these rules on `main` (and `develop` if using Git Flow).

**Required protections:**
- Require at least 1 pull request review before merge
- Require status checks to pass (tests, lint, build)
- No force push -- prevent history rewriting
- No direct branch deletion
- Require linear history (squash or rebase merges only)

**Optional:** require 2+ reviewers, signed commits, restrict push access.

**To set up branch protection with GitHub CLI:**
```bash
gh api repos/{owner}/{repo}/branches/main/protection --method PUT \
  --field required_pull_request_reviews='{"required_approving_review_count":1}' \
  --field required_status_checks='{"strict":true,"contexts":["ci/tests","ci/lint"]}' \
  --field enforce_admins=true --field restrictions=null
```

**CODEOWNERS file example:**
Place at `.github/CODEOWNERS` to auto-assign reviewers.

```
*                       @team-lead
src/components/**       @frontend-team
src/api/**              @backend-team
src/db/**               @backend-team
.github/workflows/**    @platform-team
docs/**                 @tech-writers
```

---

## Branch Lifecycle

Follow this flow for every branch: create, develop, PR, merge, delete.

**Step 1 -- Create from latest main:**
```bash
git checkout main && git pull origin main
git checkout -b feat/user-search
```

**Step 2 -- Develop with small, focused commits:**
```bash
git add src/search.ts src/search.test.ts
git commit -m "feat(search): add user search endpoint"
git add src/search-index.ts
git commit -m "feat(search): build search index on startup"
```

**Step 3 -- Push and open a pull request:**
```bash
git push -u origin feat/user-search
gh pr create --title "feat(search): add user search" \
  --body "Adds full-text search on user name and email fields."
```

**Step 4 -- Address review feedback:**
```bash
# Make changes based on review
git add src/search.ts
git commit -m "fix(search): add input sanitization per review"
git push
```

**Step 5 -- Merge via PR (squash for clean history):**
```bash
gh pr merge --squash --delete-branch
```

**Step 6 -- Clean up local branches:**
```bash
git checkout main && git pull origin main
git branch -d feat/user-search
```

---

## Stale Branch Cleanup

Remove merged and abandoned branches to keep the repository clean.

**List local branches already merged into main:**
```bash
git branch --merged main | grep -v "main"
```

**Delete all merged local branches at once:**
```bash
git branch --merged main | grep -v "main" | xargs git branch -d
```

**Prune remote tracking references for deleted remote branches:**
```bash
git fetch --prune
```

**Find remote branches older than 90 days using GitHub CLI:**
```bash
gh api repos/{owner}/{repo}/branches --paginate \
  --jq '.[] | select(.commit.commit.author.date < "2026-01-12") | .name'
```

**Delete a stale remote branch:**
```bash
git push origin --delete feat/old-abandoned-branch
```

**Automate cleanup in GitHub:**
Enable "Automatically delete head branches" in repo settings
(Settings > General > Pull Requests). This deletes branches after PR merge
so you never accumulate stale remote branches.

---

## Release Tagging

Use SemVer format: `vMAJOR.MINOR.PATCH`. Pre-release: `v2.0.0-beta.1`.

**When to create a tag:**
- After `main` is stable and all CI checks pass
- On the exact commit intended for production release
- Never tag a commit that has not been tested

**To create an annotated tag:**
```bash
git checkout main && git pull origin main
git tag -a v1.3.0 -m "Release v1.3.0: user search and performance improvements"
git push origin v1.3.0
```

**To create a GitHub release (generates release notes from PRs):**
```bash
gh release create v1.3.0 --generate-notes
```

**To create a pre-release tag:**
```bash
git tag -a v2.0.0-rc.1 -m "Release candidate 1 for v2.0.0"
git push origin v2.0.0-rc.1
gh release create v2.0.0-rc.1 --prerelease --generate-notes
```

**To list existing tags:**
```bash
git tag --list 'v*' --sort=-version:refname | head -10
```

**SemVer rules:**
- **MAJOR** (v1 -> v2): breaking changes, incompatible API changes
- **MINOR** (v1.1 -> v1.2): new features, backward compatible
- **PATCH** (v1.1.1 -> v1.1.2): bug fixes, backward compatible

---

## Changelog Generation

Generate changelogs automatically from conventional commit messages.

**Using git log to generate a simple changelog:**
```bash
# List all changes since last tag
git log v1.2.0..HEAD --oneline --no-merges

# Group by type
git log v1.2.0..HEAD --pretty=format:"%s" --no-merges | sort
```

**Recommended tools:**

| Tool                    | Command                                  |
|-------------------------|------------------------------------------|
| `conventional-changelog`| `npx conventional-changelog -p angular`  |
| `standard-version`      | `npx standard-version`                   |
| `release-please`        | GitHub Action, fully automated           |
| `git-cliff`             | `git-cliff --latest`                     |

**To set up release-please (recommended for GitHub projects):**

Create `.github/workflows/release.yml`:
```yaml
name: Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          release-type: node
```

Release-please reads conventional commits, opens a release PR with changelog
updates, and creates GitHub releases with tags when the PR merges.

**To generate a changelog with git-cliff:**
```bash
# Generate full changelog
git-cliff --output CHANGELOG.md

# Generate only unreleased changes
git-cliff --unreleased --output CHANGELOG.md
```

**Type-to-section mapping:** `feat` becomes Features, `fix` becomes Bug Fixes,
`BREAKING CHANGE` gets a dedicated section. Other types (`chore`, `ci`, `docs`,
`style`, `refactor`, `perf`, `test`, `build`) are excluded by default.
