---
name: pre-launch
description: >-
  THE launch gate. Runs the Tier-B launch gates plus the full test and perf sweeps in order, each
  as a pass/fail section, and writes a GO / NO-GO readiness report. Trigger before any production
  launch, public release, or client handover. A skipped section is a NO-GO, never a silent pass.
allowed-tools: Read, Grep, Glob, Bash, Write, Task
model: sonnet
source: this library (original)
always_on: false
activation: "before any production launch / public release"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /pre-launch — GO / NO-GO gate

Orchestrates; does not do the work itself. Each section runs as a `Task` subagent (isolated
context — only the verdict + findings summary come back). Run the sections **in order**:

| # | Section | Module | Pass means |
|---|---------|--------|------------|
| 1 | Secret scan | [`../guardrails/secret-scanner.md`](../guardrails/secret-scanner.md) | full working tree clean (on-demand mode); git history clean via section 6's runbook §2 (gitleaks/trufflehog) |
| 2 | Dependency vulns | [`../guardrails/dependency-vuln-audit.md`](../guardrails/dependency-vuln-audit.md) | all ecosystems audited; no unfixed HIGH/CRITICAL |
| 3 | Security audit | [`../guardrails/security-auditor.md`](../guardrails/security-auditor.md) | deep pass; no unmitigated critical/high finding |
| 4 | Hardening proof | [`../guardrails/app-security-hardener.md`](../guardrails/app-security-hardener.md) | full self-test suite green (headers, authz probe, limits…) |
| 5 | Legal | [`../guardrails/legal-shield.md`](../guardrails/legal-shield.md) | AUDIT mode for the target markets; no blocking gap |
| 6 | Credential rotation | [`../guardrails/launch-rotation-runbook.md`](../guardrails/launch-rotation-runbook.md) | every credential rotated + old verified dead, or explicitly classified dev-only with no prod access |
| 7 | Test sweep | [`test-sweep.md`](test-sweep.md) (`/test-sweep full` → [`../agents/test-automator.md`](../agents/test-automator.md)) | full suite green |
| 8 | Performance | [`perf-audit.md`](perf-audit.md) (`/perf-audit`) | within budgets |
| 9 | Compliance controls | [`../guardrails/compliance-auditor.md`](../guardrails/compliance-auditor.md) | no HIGH control gap for the active frameworks (always runs; mandatory where specialized-domains arms it) |

## Rules
- **Never skip silently.** A section that can't run (tool missing, env down, no target market
  given) is recorded **NO-GO with the reason** — not omitted, not assumed green.
- **Never auto-CONFIRM.** Sections 6 (prod-breaking revocations) and anything touching prod state
  surface their `CONFIRM` prompts to the human; this command never answers them itself.
- Security/audit/compliance tooling is never disabled to get to GO — FORBIDDEN per
  GLOBAL_PREFERENCES.
- Sections are independent: a NO-GO in one does not stop the rest — run all 9, report everything,
  fix in one sprint.
- `penetration-tester` is not an automatic gate (it requires explicit written authorization and
  external tools) — offer it as an optional deep extension when its prerequisites exist.

## Output — `docs/launch/readiness-YYYY-MM-DD.md`
- One line per section: **GO / NO-GO** + one-sentence evidence (counts, suite result, report path).
- Each NO-GO links the module that fixes it (e.g. authz probe fail → `app-security-hardener` §4).
- **Overall verdict:** GO only if all 9 sections are GO. Anything else: NO-GO + ranked fix list.
- Headline-first in chat: overall verdict, then the per-section table, then the report path.
