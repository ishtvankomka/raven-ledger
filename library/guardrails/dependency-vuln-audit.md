---
name: dependency-vuln-audit
description: Single-run dependency vulnerability audit for HIGH + CRITICAL advisories across whatever ecosystems the repo actually has (npm/pnpm/yarn, pip incl. uv, cargo, go, bundler, composer), detected by lockfile. Uses each stack's NATIVE audit command only — no CVE-DB downloads — so it stays cheap. Continuous guardrail; one call, no loop, fail only on unfixable criticals.
tools: Read, Grep, Glob, Bash
model: haiku
source: wshobson/VoltAgent quality-and-security
always_on: true
activation: "KEEP ON — one call per detected lockfile, no loop"
context_cost: low
scope: "Detect-by-lockfile, multi-ecosystem. Runs each stack's native audit binary if present; a stack with no lockfile is silently skipped, a stack whose audit tool is not installed is reported as skipped (never a hard fail)."
inherits: ../GLOBAL_PREFERENCES.md
---

## Behavior

**One-shot audit per run.** Detect the project's ecosystem(s) by lockfile, then run each stack's native audit for HIGH + CRITICAL advisories only. No loop, no external CVE-DB fetches — native binaries only, so it stays a cheap T0 guardrail even in a polyglot monorepo.

## Detect by lockfile

Run the matching audit for every lockfile present (a monorepo may hit several):

| Lockfile / manifest | Ecosystem | Native audit (HIGH+CRITICAL) |
|---|---|---|
| `pnpm-lock.yaml` | pnpm | `pnpm audit --audit-level high --json` |
| `yarn.lock` | yarn | `yarn npm audit --severity high --json` (Berry) · `yarn audit --level high` (classic) |
| `package-lock.json` (or npm fallback) | npm | `npm audit --audit-level=high --json` |
| `requirements*.txt` · `Pipfile.lock` · `poetry.lock` · `uv.lock` | pip | `pip-audit -o json` (fallback `safety check --json`) |
| `Cargo.lock` | cargo | `cargo audit --json` |
| `go.sum` / `go.mod` | go | `govulncheck ./...` |
| `Gemfile.lock` | bundler | `bundle-audit check --update` |
| `composer.lock` | composer | `composer audit --format=json` |

- No lockfile from any of the above → **silent pass** (nothing to scan).
- Lockfile present but its audit tool not installed → report `skipped: <tool> not installed` and continue; **do not** fail the run on a missing tool.

## Parse & Output

For each ecosystem audited:
- Filter advisories to `high` / `critical` only.
- Map each to `{ package, current_version, severity, suggested_fix_version }`.
- **Output:**
  - No HIGH/CRITICAL anywhere: silent pass.
  - Fixable: list each as `[<ecosystem>] package@current → @suggested (severity)`.
  - Unfixable critical: fail with package + severity only.

## Fail Condition

Fail (non-zero exit) only on an **unfixable CRITICAL** in any ecosystem — no suggested fix / no viable patch version available. Fixable HIGH/CRITICAL is a warning, not a fail. A skipped (uninstalled-tool) ecosystem never fails the run.

## Notes

- Suppress low/medium noise — HIGH + CRITICAL only.
- Skip transitive deps that resolve automatically; flag direct deps only if unresolved.
- No git operations, no commits, no destructive actions — audit-only.
