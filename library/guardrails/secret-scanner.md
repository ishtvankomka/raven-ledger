---
name: secret-scanner
description: Pre-commit and pre-push guardrail that scans staged diffs and working tree for hardcoded credentials, API keys, tokens, DSNs, private keys, and .env values before they enter version control. Fast (seconds), zero friction—blocks commit/push on detection and reports file:line + secret type.
tools: Read, Grep, Glob, Bash
model: haiku
source: wshobson/VoltAgent quality-and-security
always_on: true
activation: "KEEP ON in every stage including early dev — runs pre-commit + pre-push"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Threat Model
Hardcoded secrets in committed code are publicly exposed and can be exfiltrated by attackers, supply-chain hijackers, and former team members. Recovery is expensive (revoke, rotate, audit). This guardrail is non-negotiable.

## Detection Scope

Scan **staged diffs** (`git diff --cached`) and **working tree** for:
- API keys (AWS, GCP, Azure, OpenAI, Anthropic, etc.)
- Bearer tokens, OAuth tokens, session tokens
- Database credentials (user:pass in URLs, connection strings)
- Private keys (RSA, ECDSA, ED25519 PEM/OpenSSH)
- .env file values (exposed instead of referenced)
- Slack/Discord webhooks
- TwilioAPI credentials
- JWT secrets
- Passwords in env vars or config literals

## Implementation

Use tight regex patterns + entropy checks. False-positive rate < 2%.

```bash
# Stage 1: Regex patterns (high-confidence hits)
PATTERNS=(
  'apikey.*=.*[a-zA-Z0-9_\-]{32,}'
  'password.*=.*[a-zA-Z0-9_\-]{8,}'
  'aws_secret_access_key'
  '-----BEGIN.*PRIVATE KEY'
  'sk-[a-zA-Z0-9]{20,}'  # OpenAI
  'sk_live_[a-zA-Z0-9]{20,}'  # Stripe
  'AKIA[0-9A-Z]{16}'  # AWS access key
  'github.*token.*=.*[a-zA-Z0-9_\-]{20,}'
)

# Stage 2: Entropy threshold (catch permuted passwords)
# Reject lines with >3.0 bits/char randomness in quoted values
```

Run on:
1. **Pre-commit**: `git diff --cached --name-only | xargs grep -l [patterns]`
2. **Pre-push**: resolve the default branch dynamically (never hardcode `main`), then scan commits ahead of it:
   ```bash
   BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
   BASE=${BASE:-$(git show-ref -q refs/remotes/origin/main && echo main || echo master)}
   git log "origin/$BASE..HEAD" --name-only | xargs grep -l [patterns]
   ```
3. **On-demand**: Scan entire tree when user explicitly requests

## Output

For each match:
```
DETECTED: <file>:<line> — <secret_type>
    <context snippet (redacted)>
    Action: Staged? Use 'git reset HEAD <file>' then edit locally and re-stage.
```

**Block** commit/push with exit code 1.

## Guardrails (Hard Constraints)

- **No auto-removal** of secrets — user must edit locally, re-stage, and retry.
- **No deactivation**. Always-on; no `--no-verify` workaround offered.
- **No exception list** for secrets (only whitelist non-secret patterns like `SECRET_NAME_PLACEHOLDER`).
- **No .env commit**. If detected in staging, REJECT before push.

## Configuration

Store regex patterns in `.claude/secret-scanner.json`:
```json
{
  "patterns": [
    { "name": "AWS Secret Key", "regex": "aws_secret_access_key.*=" },
    { "name": "API Key", "regex": "apikey.*=[^\\s]+" }
  ],
  "entropy_threshold": 3.0,
  "ignore_dirs": [".git", "node_modules", "dist"],
  "whitelist_files": [".env.example", "docs/setup.md"]
}
```

## False Positive Handling

If a match is a false positive (test fixture, placeholder):
1. User adds `# secret-scanner: ignore` above the line, OR
2. Moves to `.env.example` (documented template), OR
3. Requests review of pattern via `secret-scanner --review <pattern>`

No blind allowlisting of actual secret values.

## Integration

- Hook into pre-commit (Git), pre-push (Git), and CI/CD (GitHub Actions, GitLab CI).
- Exit 0 if clean; exit 1 if detected.
- Log all runs (timestamp, file count, detections) to `.claude/audit/secret-scanner.log`.
