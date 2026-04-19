# Git Security

## Scan Command

Run before every commit. Catches the most common secret patterns in staged changes.

**One-liner:**

```bash
git diff --cached -U0 | grep -nE 'AKIA[A-Z0-9]{16}|-----BEGIN .* PRIVATE KEY-----|xox[bpors]-|[sr]k_(live|test)_|ghp_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+|AIza[0-9A-Za-z_-]{35}|mongodb\+srv://[^[:space:]]+|postgres://[^[:space:]]+@' && echo "SECRETS DETECTED — do not commit" && exit 1
```

**Reusable shell function** (add to `~/.zshrc` or `~/.bashrc`):

```bash
scan-secrets() {
  local input
  if [ -t 0 ]; then
    input=$(git diff --cached -U0)
  else
    input=$(cat)
  fi

  local patterns=(
    'AKIA[A-Z0-9]{16}'
    '-----BEGIN .* PRIVATE KEY-----'
    'xox[bpors]-[0-9]{10,}'
    '[sr]k_(live|test)_[A-Za-z0-9]{20,}'
    'ghp_[A-Za-z0-9]{36}'
    'gho_[A-Za-z0-9]{36}'
    'github_pat_[A-Za-z0-9_]{60,}'
    'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+'
    'AIza[0-9A-Za-z_-]{35}'
    '(mongodb\+srv|postgres|mysql|redis)://[^[:space:]]+@'
    'password\s*[:=]\s*["\x27][^"\x27]{8,}'
  )
  local joined=$(IFS='|'; echo "${patterns[*]}")

  echo "$input" | grep -nE "$joined"
  if [ $? -eq 0 ]; then
    echo ""
    echo "SECRETS DETECTED. Do not commit."
    return 1
  fi
  return 0
}
```

Usage: `scan-secrets` (checks staged diff) or `cat file.js | scan-secrets` (checks any input).

## Secret Patterns

| Category | Pattern | Regex | Example |
|---|---|---|---|
| AWS Access Key | `AKIA` + 16 chars | `AKIA[A-Z0-9]{16}` | `AKIAIOSFODNN7EXAMPLE` |
| AWS Secret Key | 40-char base64 string | `[A-Za-z0-9/+=]{40}` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| GitHub Token | `ghp_`, `gho_`, `github_pat_` prefix | `gh[pousr]_[A-Za-z0-9_]{36,}` | `ghp_abc123def456ghi789jkl012mno345pqr6` |
| Slack Token | `xoxb-`, `xoxp-` prefix | `xox[bpors]-[0-9]{10,}` | `xoxb-1234567890-abcdefgh` |
| Stripe Key | `sk_live_` or `sk_test_` prefix | `[sr]k_(live\|test)_[A-Za-z0-9]{20,}` | `sk_live_abc123def456ghi789jk` |
| Google API Key | `AIza` prefix + 35 chars | `AIza[0-9A-Za-z_-]{35}` | `AIzaSyA1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q` |
| JWT | Three base64 segments with dots | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+` | `eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0...` |
| Database URL | Protocol with credentials in URL | `(postgres\|mysql\|mongodb\+srv\|redis)://[^:]+:[^@]+@` | `postgres://admin:s3cret@db.example.com/mydb` |
| OAuth Client Secret | Long alphanumeric with `secret` in context | `client_secret\s*[:=]\s*["'][^"']{20,}` | `client_secret: "GOCSPX-abc123..."` |
| Private Key File | PEM header marker | `-----BEGIN .* PRIVATE KEY-----` | `-----BEGIN RSA PRIVATE KEY-----` |

## Files to Always Ignore

Complete `.gitignore` template for secrets and sensitive files:

```gitignore
# ── Secrets and environment ──
.env
.env.*
!.env.example
.envrc

# ── Keys and certificates ──
*.pem
*.key
*.p12
*.pfx
*.crt
*.cer
*.der
*.jks
*.keystore
id_rsa
id_rsa.pub
id_ed25519
id_ed25519.pub

# ── Credential files ──
credentials.json
credentials.yaml
*credentials*.json
service-account*.json
*secret*.json
*secret*.yaml
gcloud-service-key.json
firebase-adminsdk*.json
.npmrc
.pypirc
.docker/config.json

# ── SSH ──
known_hosts
authorized_keys
*.ppk

# ── OS files ──
.DS_Store
Thumbs.db

# ── Dependencies ──
node_modules/
vendor/
.venv/
__pycache__/

# ── IDE (keep shared configs, ignore personal) ──
.idea/
.vscode/settings.json
.vscode/launch.json
*.swp
*.swo

# ── Build output ──
dist/
build/
*.log
```

## If Secrets Found Before Push

You have time. The secret has not left your machine yet.

```bash
# 1. STOP — do not commit or push

# 2. Unstage the file containing the secret
git reset HEAD <file-with-secret>

# 3. Remove the secret from the file
#    Replace with env var reference: process.env.API_KEY or os.environ["API_KEY"]

# 4. Add the file to .gitignore if it should never be tracked
echo "<file>" >> .gitignore

# 5. If the secret was in a tracked file, ensure the cleaned version is staged
git add <cleaned-file>
git add .gitignore

# 6. Rotate the secret — treat it as compromised
#    Even if never pushed, it existed in a diff on disk
```

## If Secrets Found After Push

The secret is compromised. Rotate first, clean history second.

```bash
# 1. ROTATE THE SECRET IMMEDIATELY
#    Go to AWS/GitHub/Stripe/etc console and generate new credentials
#    Update all services that use the old secret

# 2. Remove from history with BFG Repo-Cleaner (preferred — fast, simple)
brew install bfg                           # install
git clone --mirror git@github.com:org/repo.git  # fresh mirror clone
bfg --replace-text passwords.txt repo.git  # passwords.txt has one secret per line
cd repo.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force                           # WARNING: rewrites history for all collaborators

# 3. Alternative: git-filter-repo (no Java dependency)
pip install git-filter-repo
git filter-repo --invert-paths --path <file-with-secret>
# Or replace content:
git filter-repo --blob-callback '
  return blob.data.replace(b"sk_live_abc123", b"REDACTED")
'
git push --force origin --all
```

**Force push warning:** This rewrites history. All collaborators must re-clone or `git fetch --all && git reset --hard origin/main`. Coordinate with your team before force pushing.

## Commit Signing

### GPG signing

```bash
# 1. Generate a GPG key
gpg --full-generate-key                    # choose RSA 4096, no expiry or 1y

# 2. Get the key ID
gpg --list-secret-keys --keyid-format=long # copy the ID after "sec rsa4096/"

# 3. Export and add to GitHub (Settings > SSH and GPG keys > New GPG key)
gpg --armor --export <KEY_ID>              # paste the output into GitHub

# 4. Configure git to use the key
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true

# 5. Verify a signed commit
git log --show-signature -1
```

### SSH signing (simpler, recommended)

```bash
# 1. Configure git to use SSH key for signing
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Add the same SSH public key to GitHub under **Settings > SSH and GPG keys** with key type "Signing Key".

### Verify on GitHub

Signed commits show a green "Verified" badge. To enable for your org, go to **Settings > Branch protection > Require signed commits**.

## CODEOWNERS

Protect sensitive paths by requiring review from specific teams.

```
# .github/CODEOWNERS

# Security team must review secrets-related changes
/.env.example                @org/security
/config/secrets/             @org/security
/.github/workflows/          @org/devops
/infrastructure/             @org/devops @org/security

# Sensitive application paths
/src/auth/                   @org/security @org/backend
/src/payments/               @org/billing @org/security
/migrations/                 @org/backend-leads
```

GitHub enforces CODEOWNERS when branch protection rule "Require review from Code Owners" is enabled. PRs touching matched paths cannot merge without approval from the designated team.

## GitHub Secret Scanning

GitHub automatically scans for known secret patterns in public repos. For private repos, enable it manually.

```
Repository Settings > Code security and analysis > Secret scanning > Enable
```

Push protection blocks pushes containing detected secrets before they reach the remote.

```
Repository Settings > Code security and analysis > Push protection > Enable
```

If a pattern triggers a false positive, create `.github/secret_scanning.yml`:

```yaml
paths-ignore:
  - "docs/**"
  - "tests/fixtures/**"
```

Or allowlist specific strings in the GitHub UI under **Security > Secret scanning alerts > Close as > False positive**.

## Common Mistakes

| Mistake | Why it happens | Fix |
|---|---|---|
| Committing `.env` | Forgot `.gitignore` or file was tracked before ignore rule | `git rm --cached .env && echo .env >> .gitignore` |
| Hardcoded passwords in source | Quick prototyping, forgot to clean up | Use `process.env.X` or vault references, scan before commit |
| Debug tokens left in tests | Used real token during debugging | Use mock/fixture tokens in tests, never real ones |
| API key in frontend code | Didn't realize client code is public | Move to server-side, use proxy endpoint |
| Secret in commit message | Pasted credentials into message body | `git rebase -i` to reword, then force push |
| `.env.production` committed | Thought only `.env` was ignored | Use `.env.*` pattern in `.gitignore` with `!.env.example` |
| Key file with wrong extension | Named it `cert.txt` instead of `cert.pem` | Scan by content pattern, not just filename |
