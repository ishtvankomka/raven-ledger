---
name: launch-rotation-runbook
description: >-
  Pre-launch credential rotation runbook. Dev-time direct token use is the accepted velocity
  convention; this runbook is the exit ramp that upgrades it to enterprise-grade before launch —
  inventory every credential, scan git history, rotate/re-issue in safe order, verify old
  credentials are dead, record the rotation. Also runs on any suspected leak.
tools: Read, Grep, Glob, Bash, Write, Edit
model: sonnet
source: this library (original)
always_on: false
activation: "MANDATORY step of /pre-launch; also on any suspected leak"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

Speed profile per GLOBAL_PREFERENCES. The deal encoded there: dev runs on direct tokens in
git-ignored `env/<env>.env` files for velocity — and **all of them get rotated before launch**.
This file is that second half, operationalized. Names and metadata only; **never print a secret
value** — not in output, not in logs, not in the record.

## 1 · INVENTORY — enumerate every credential
Walk all sources; a credential you didn't list is a credential you didn't rotate:
- `env/<env>.env` files — var names only (`grep -E '^[A-Z0-9_]+=' env/*.env | cut -d= -f1`).
- `.mcp.json` and any tool/agent config carrying tokens.
- CI secrets (GitHub Actions / GitLab CI variables).
- Cloud IAM keys and service accounts (AWS/GCP/Azure).
- Database URLs and DB user passwords.
- JWT / session / cookie signing secrets.
- OAuth client secrets; webhook signing secrets.
- EAS / app-store credentials (mobile).
- Third-party API keys: payment, email, analytics, LLM providers.

Output a table: **name → service → used by (app/CI/agent) → blast radius if leaked**.

## 2 · HISTORY SCAN — git remembers everything
Run `gitleaks detect --source . --log-opts="--all"` (or `trufflehog git file://.`) over the FULL
history, all branches. **Any historical hit = unconditional rotation** for that credential —
deleting the commit does not un-leak it; history is permanent and bot-indexed.

## 3 · CLASSIFY — three buckets per credential
1. **Rotate-in-place** — same scope, new value (most third-party API keys).
2. **Re-issue least-privilege** — dev keys are often over-scoped (admin tokens, `*` IAM policies);
   launch is the moment to issue a prod key scoped to what prod actually calls.
3. **Move to secret manager / CI-injected** — prod secrets that should never live in a file on a
   machine (cloud secret manager, CI secret store).

## 4 · ORDER — rotate without breaking prod
1. **Leaf/external services first** — analytics, email, LLM keys: low coupling, easy verify.
2. **JWT/session secrets** — dual-key overlap window: verify with old+new, sign with new, retire
   old after max session lifetime. Never a hard cut that logs out or 401s everyone.
3. **DB credentials last** — new user/password, staged rollout, connection-drain plan so pooled
   connections on the old credential drain before it drops.

## 5 · EXECUTE — per credential, in order
1. Issue new credential (least-privilege per §3).
2. Deploy/update consumers (env files, CI secrets, secret manager).
3. Verify new works — a real call through the app path, not just a smoke ping.
4. Revoke old.
5. **VERIFY OLD IS DEAD** — a real API call with the old credential MUST fail. Not revoked-in-the-
   dashboard: proven-dead. A rotation without this step is not done.

Revocations that can break prod (shared keys, DB users, anything with unknown consumers) are
**CONFIRM-gated** per GLOBAL_PREFERENCES: state the credential name + blast radius, wait for
`CONFIRM`. Everything else proceeds.

## 6 · CLOSE — record + set the post-launch convention
- Write `docs/launch/rotation-YYYY-MM-DD.md`: credential names, service, rotation date, verify
  status — **never values**.
- Post-launch convention: prod secrets are CI/secret-manager-injected; `env/<env>.env` files
  remain the dev convention (git-ignored, `env/.env.example` committed) per GLOBAL_PREFERENCES.
- Report to `/pre-launch`: PASS only when every inventoried credential is rotated + verified-dead
  or explicitly classified as dev-only with no prod access. Anything else is FAIL with the list.

## Hard constraints
- Never print, log, or write a secret value anywhere — names and metadata only.
- Never skip the verify-old-is-dead step; a dashboard "revoked" state is a claim, not a proof.
- Any historical git leak rotates unconditionally — no "it was only a dev key" exceptions.
- Suspected leak at any time → run this runbook immediately for the affected credential(s).
