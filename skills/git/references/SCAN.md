# Quick Security Scan

## Command

```bash
git diff --cached -U0 | grep -nE \
  'AKIA[A-Z0-9]{16}|-----BEGIN .* PRIVATE KEY|xox[bpors]-|[sr]k_(live|test)_|ghp_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]+\.eyJ|AIza[0-9A-Za-z_-]{35}|mongodb\+srv://[^[:space:]]+|postgres://[^[:space:]]+@'
```

## Patterns

| Category | Pattern | Example |
|----------|---------|---------|
| AWS Key | `AKIA` + 16 | `AKIAIOSFODNN7EXAMPLE` |
| GitHub | `ghp_` | `ghp_abc123def456...` |
| Slack | `xoxb-` | `xoxb-1234-abc` |
| Stripe | `sk_live_` | `sk_live_abc123...` |
| Private Key | `-----BEGIN` | PEM files |
| DB URL | `postgres://` | `postgres://user:pass@host/db` |

## If Found: STOP

1. `git reset HEAD <file>`
2. Replace with env var
3. Add to `.gitignore`
4. **Rotate the secret** — it's compromised
