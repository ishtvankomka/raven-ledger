---
name: test-sweep
description: >-
  Run the autonomous test suite — /test-sweep [smoke|full] [web|mobile|api|all]. Thin dispatcher
  that delegates each surface to the test-automator agent, aggregates a per-surface pass/fail
  table plus bugs filed, and exits 1 on any real failure. Defaults: smoke tier, all surfaces.
  Section 7 of /pre-launch runs this as "/test-sweep full".
allowed-tools: Task, Read, Bash
model: haiku
source: this library (original)
always_on: false
activation: "on-demand any repo; invoked by /pre-launch"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /test-sweep [smoke|full] [web|mobile|api|all]

Dispatcher only — the work lives in [`../agents/test-automator.md`](../agents/test-automator.md).

## Arguments

| Arg | Values | Default |
|---|---|---|
| tier | `smoke` \| `full` | `smoke` |
| surface | `web` \| `mobile` \| `api` \| `all` | `all` |

## Procedure

1. **Detect present surfaces** from the repo (web app router/React app, API controllers/OpenAPI,
   Expo/RN project). A requested surface that doesn't exist is reported as `absent` — never
   counted as a pass, never a silent skip.
2. **Per requested + present surface:** spawn a `Task` subagent running test-automator with the
   tier — isolated context; only its Output block comes back.
3. **Aggregate** into the table below. Do not run tests directly in this command's context.

## Output

Headline first: overall `PASS` / `FAIL`, then the per-surface table:

```
Surface | Tier  | Pass | Fail | Quarantined | Bugs filed
web     | smoke |  41  |  1   | 2           | 1 → context/bugs/OPEN.md
api     | smoke |  18  |  0   | 0           | 0
mobile  | —     | absent (no Expo/RN project detected)
```

- Every "bugs filed" count links the `context/bugs/OPEN.md` entries (UC-IDs included).
- Quarantined flakes are listed but do not fail the sweep.

## Exit code

- **Exit 1 on any real failure** — an app bug filed or an unclassified test failure on any
  surface. Honest codes; never mask a failure to look green.
- Exit 0 only when every requested + present surface is green (quarantined-only is green,
  but always reported).
