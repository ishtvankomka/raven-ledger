---
name: sentry-observability
type: stack-module
description: 'Read-only integration with Sentry to pull production error and performance insights across whatever services this repo actually instruments — scope comes from the Sentry projects the repo configures (SENTRY_ORG / SENTRY_PROJECT), never from an assumed service list. Ranks problem areas by severity and frequency, surfaces actionable issues into the context/ scaffold for triage. DSN presence signals instrumentation only; API pulls need SENTRY_AUTH_TOKEN + org/project slugs. Verifies connectivity before trusting "no errors" results.'
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo has Sentry instrumented"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Environment

- **Instrumentation signal**: `SENTRY_DSN` present = repo is instrumented. A DSN only authenticates event ingest — it cannot pull data.
- **Pull prerequisites**: `SENTRY_AUTH_TOKEN` + `SENTRY_ORG` + `SENTRY_PROJECT` — the read API requires an auth token plus org/project slugs.
- **Scope = the repo's own instrumented surfaces**, one Sentry project per surface. Enumerate them from what the repo actually configures (its `SENTRY_PROJECT` values / per-service Sentry init), not from an assumed set of services. If the repo declares its project list somewhere (`CLAUDE.md`, deploy config, env files), that list wins.
- Multiple projects: pull each one and label every finding with the surface it came from, so triage never merges two services into one issue.
- Verify the pull credentials work before claiming "no errors detected"
- If missing, report as "Sentry reads not configured" rather than "no issues"

## Core Workflow

### Pull Issues
1. Fetch recent errors and performance regressions from Sentry API (read-only)
2. Filter by environment (`production` default unless overridden)
3. Rank by:
   - Error frequency (highest count first)
   - User impact (crash vs. warning)
   - Time since first occurrence (recent spikes prioritized)

### Triage into the context/ scaffold (created by INSTALL_PROMPT.md)
- **High severity** (crashes, auth failures): → top of `context/bugs/OPEN.md`, marked URGENT
- **Medium** (performance regression, 4xx errors): → `context/bugs/OPEN.md`
- **Low** (deprecation warnings, repeat patterns): → `context/recurring-issues/`
- Include stack trace snippets, affected endpoints, and user count

### Issue Details
For each surfaced issue, extract:
- Event count + unique users impacted
- First & last occurrence timestamps
- Top 3 stack frames (brevity over full trace)
- Affected tags (service, environment, release)

## Mutations: CONFIRM Gate

**READ-ONLY by default.** If asked to resolve, assign, or mutate an issue in Sentry:

```
CONFIRM: Mutate Sentry issue [ID]?
  - Action: [resolve/assign/bulk-update]
  - Scope: [issue count]
  - Reversible: [yes/no]

Proceed? (type CONFIRM)
```

Never auto-resolve or auto-assign without explicit CONFIRM token.

## Integration Points

- **Diff context**: Note if recent PR correlates with error spike
- **Release tracking**: Link errors to deployment time windows
- **Runbook**: Surface known fixes from team if issue is recurring

## Caveats

- Sentry quota limits may truncate old events; note query window
- Sampling can undercount low-frequency issues in high-traffic services
- Performance insights require release tracking; validate SDK configuration
