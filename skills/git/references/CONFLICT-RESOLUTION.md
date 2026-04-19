# Conflict Resolution

## 1. Decision Table

| Situation | Strategy | Reason |
|-----------|----------|--------|
| Feature branch behind main | `git rebase origin/main` | Linear history, clean diff for review |
| Shared branch (2+ developers) | `git merge --no-ff` | Never rewrite shared history |
| Noisy commits before PR | `git rebase -i HEAD~N` | Squash/fixup for clean story |
| Merging finished PR to main | `--squash` merge | Single atomic commit on main |
| Long-lived release branch | `git merge --no-ff` | Preserve branch context in history |

Rule of thumb: rebase your own work, merge shared work.

---

## 2. Rebase Workflow

```bash
git fetch origin
git rebase origin/main

# If conflicts -- git pauses at the conflicting commit
git status
# Open each file, resolve <<<<<<< / ======= / >>>>>>> markers
git add src/api/handler.ts
git rebase --continue
# Repeat for each conflicting commit

# Force-push rebased branch (your branch only)
git push --force-with-lease origin feature/my-branch
```

Always use `--force-with-lease` instead of `--force` -- it refuses to push if someone else pushed since your last fetch.

---

## 3. Interactive Rebase

```bash
git rebase -i HEAD~5           # last 5 commits
git rebase -i origin/main      # everything since branching
```

| Action | Effect | When to Use |
|--------|--------|-------------|
| `pick` | Keep commit as-is | Default |
| `squash` | Merge into previous, combine messages | Related commits to unify |
| `fixup` | Merge into previous, discard message | Typo fixes, forgotten files |
| `reword` | Keep commit, edit message | Fix a bad commit message |
| `drop` | Delete commit | Debug leftovers, accidental commits |
| `edit` | Pause at this commit | Split a commit or amend content |

### Example: Clean Up Before PR

```
pick a1b2c3d Add user auth endpoint
fixup e4f5g6h Fix typo in auth
pick i7j8k9l Add auth tests
drop m0n1o2p Debug console.log -- remove
squash q3r4s5t Update auth error messages
```

Result: 2 clean commits instead of 5 noisy ones.

---

## 4. Merge Workflow

Use merge over rebase when: branch is shared, you need audit trail, or policy requires merge commits.

```bash
# Merge with explicit merge commit
git merge --no-ff origin/main

# If conflicts, resolve then commit
git status
git add src/conflicted-file.ts
git commit

# --ff-only: fail if fast-forward not possible (verify clean state)
git merge --ff-only origin/main
```

---

## 5. Conflict Resolution Strategy

### Understand Both Sides

```bash
git log --merge --oneline                        # commits causing conflict
git diff --name-only --diff-filter=U             # conflicted files
git log --merge -p -- src/api/handler.ts         # what each side changed
```

### Resolve by Intent

Ask "What was each change trying to accomplish?" -- write code achieving both goals.

```bash
# Theirs is correct (lockfile, generated code)
git checkout --theirs package-lock.json && git add package-lock.json

# Yours is correct
git checkout --ours src/config.ts && git add src/config.ts

# Both matter -- manually merge the logic
```

### Verify

```bash
npm test                # run tests
git diff --check        # find remaining conflict markers
git diff --staged       # review resolved changes
```

---

## 6. Common Conflict Patterns

| Conflict Type | Resolution | Command |
|---------------|------------|---------|
| Lock files (package-lock, yarn.lock) | Accept theirs, regenerate | `git checkout --theirs package-lock.json && npm install` |
| DB migrations (same sequence) | Renumber your migration | Rename file, test full chain |
| Formatting (whitespace, prettier) | Accept either, re-run formatter | `git checkout --theirs <file> && npx prettier --write <file>` |
| Deleted vs modified | Check if deletion intentional | `git log --diff-filter=D -- <file>` |
| Adjacent lines | Manual merge required | Read both changes, combine logically |
| Import ordering | Accept either, let tooling sort | Re-run import sorter after checkout |
| Generated files (GraphQL, Prisma) | Accept either, regenerate | `git checkout --theirs <file> && npm run generate` |

### Deleted vs Modified

```bash
# Who deleted and why?
git log --diff-filter=D --summary -- src/old-component.tsx

# Deletion intentional (refactor) -- accept it
git rm src/old-component.tsx

# Deletion accidental -- keep modified version
git checkout --ours src/old-component.tsx && git add src/old-component.tsx
```

---

## 7. Tools

```bash
# Launch configured merge tool
git mergetool

# Set VS Code as merge tool
git config --global merge.tool vscode
git config --global mergetool.vscode.cmd 'code --wait --merge $REMOTE $LOCAL $BASE $MERGED'

# Clean up .orig backup files after mergetool
git clean -f -- '*.orig'

# Find leftover conflict markers
git diff --check
grep -rn '<<<<<<< ' src/
```

VS Code merge editor options: Accept Current (yours), Accept Incoming (theirs), Accept Both, Compare Changes. For complex conflicts: Command Palette > "Merge Editor: Open".

---

## 8. Abort and Recovery

```bash
# Abort in-progress operations
git rebase --abort
git merge --abort
git cherry-pick --abort
```

### Reflog Recovery

```bash
git reflog                                    # see recent HEAD positions
git reset --hard HEAD@{3}                     # recover pre-rebase state
git reflog | grep "keyword"                   # find lost commit
git cherry-pick <found-hash>                  # rescue it
```

### When to Abandon Approach

- 10+ conflicting files on one rebase step -- switch to merge
- Generated file conflicts across many commits -- squash first, then rebase
- Same lines conflict repeatedly -- squash related commits first

---

## 9. Prevention

- **Small PRs**: under 400 lines, 1-3 day lifespan
- **Frequent rebase**: daily onto main for long-running branches
- **Clear ownership**: avoid concurrent edits to same files
- **Communication**: announce large refactors before starting
- **Feature flags**: merge incomplete work behind flags

```bash
# Starting fresh
git checkout main && git pull origin main && git checkout -b feature/new-work

# Updating existing branch
git fetch origin && git rebase origin/main
```

---

## 10. Cherry-Pick

```bash
git cherry-pick abc1234                # single commit
git cherry-pick abc1234 def5678        # multiple commits
git cherry-pick abc1234..ghi9012       # range (exclusive start)
```

**When to use**: hotfix to release branch, backport to older version, rescue from deleted branch.

### Handling Conflicts

```bash
git status                             # see conflicts
git add <resolved-files>
git cherry-pick --continue

git cherry-pick --abort                # abandon
git cherry-pick --no-commit abc1234    # stage only, don't commit
```

**Avoid cherry-pick when**: you need the entire branch (merge instead), commit depends on prior commits, or you plan to merge the source branch later (creates duplicates).
