---
name: perf-audit
description: >-
  Measurement-only performance gate. /perf-audit [web|api|mobile|all] runs the measurement side
  of performance-engineer's playbooks, compares results against the budgets, and writes a dated
  report with the top-5 fixes ranked by user-impact-per-effort. Exits 1 if any budget is
  exceeded. Report-only — fixes route to performance-engineer.
allowed-tools: Read, Bash, Grep, Glob, Write
model: haiku
source: this library (original)
always_on: false
activation: "on-demand in any repo"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
keywords: "bundle size, slow, performance budget, lighthouse"

---

# /perf-audit [web|api|mobile|all]

Runs the **measurement side** of [`../agents/performance-engineer.md`](../agents/performance-engineer.md)'s
playbooks. Default scope: `all`. A scope that doesn't apply to the repo (no web app, no RN app)
is reported `n/a` — never silently skipped.

## Budgets (fail = exceeded)

| Scope | Budget |
|---|---|
| web | LCP < 2.5s · CLS < 0.1 · TBT < 200ms (lab proxy for INP) per key route |
| web | first-load JS ≤ 200 KB gzipped per route |
| api | p95 latency < 500 ms per key endpoint (dev/staging target) |
| api | no hot-path query with an N+1 or unexplained seq-scan signature |
| mobile | cold start < 2 s on a mid-range physical device |

If the repo defines its own budgets (CI config, README, context/ scaffold notes), those win —
but never loosen a budget silently; state which set was used.

## Measure (change nothing)

- **web** — `npx lighthouse <url> --output=json` per key route, desktop + mobile emulation.
  INP is a field metric Lighthouse cannot report: use TBT < 200ms as the lab proxy, or pull p75
  INP from the CrUX API when the site has field data — state which was used.
  Bundle: `next build` per-route first-load output (or the bundler's stats) and
  `npx source-map-explorer` on the worst route.
- **api** — time key endpoints (`curl -w`, or a brief low-concurrency run against dev/staging);
  `EXPLAIN ANALYZE` the hot queries. Never load-test production.
- **mobile** — cold-start timing per the Expo/RN playbook (`adb shell am start -W` /
  Xcode App Launch), 5-run median; bundle via `npx react-native-bundle-visualizer`.

## Report — `docs/audits/YYYY-MM-DD-perf.md`

- Per-budget table: measured vs budget, PASS / FAIL / n/a, and the method used.
- **Top-5 fixes ranked by user-impact-per-effort** — each names the performance-engineer
  playbook section that implements it.
- Headline-first in chat: overall PASS/FAIL, worst offender, report path.

## Exit code

- `0` — all applicable budgets met.
- `1` — any budget exceeded (safe to wire into CI as a failing gate).

## Guardrails

- Report-only: no code, config, infra, or DB edits — all fixes route to performance-engineer.
- Writes limited to the `docs/audits/` report path, nothing else.
- Against production: GET/read-only measurement only; anything state-changing or load-shaped on
  prod is out of scope for this command.
