---
name: overnight
description: >-
  /overnight [budget] — the unsupervised night shift. Works a prioritized, PRE-APPROVED backlog
  autonomously with no human in the loop: each item runs the full delivery loop on its own branch,
  gated by /test-sweep + /perf-audit, committed only if green. Touches no remote state, opens no
  PRs, deploys nothing. Writes a morning report of what shipped, what's blocked, and what it learned.
allowed-tools: Read, Grep, Glob, Write, Bash, Task
model: sonnet
source: this library (original)
always_on: false
activation: "explicit: operator starts an unattended run (usually via a scheduled/cron agent)"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /overnight [budget]

Autonomy is maximal here **because the scope is bounded in advance** — the safety comes from *what
it's allowed to touch*, not from a human watching. `budget` = token ceiling or a wall-clock hint
(e.g. `8h`); default: work the queue until dry or budget runs out.

## The queue (pre-approved only)
Reads `context/tasks/overnight.md` — items the operator explicitly marked `overnight-ok`.
`backlog-curator` (`/backlog suggest`) is the standing mechanism that fills this queue with
`[suggested]` items; only items the operator has flipped to `overnight-ok` run — `[suggested]`
alone never does. If empty,
it does NOT invent product work; it falls back to the safe self-maintenance set: `/retro`, filing
new tests for uncovered critical paths (via test-automator), and refreshing the audit baselines
(`/perf-audit`, `/legal-audit`). A vague or missing backlog is a no-op night, never a guess.
Fallback work follows the **same per-item discipline** as the queue: each fallback task runs on its
own `overnight/<slug>` branch/worktree and is committed there (or reverted) before the next — never
on the session's working branch. (`/retro`'s safe-class commits and test-automator's test files
land on that branch, not on local `main`.)

## Per-item loop (isolated `Task` subagent each)
1. Branch: `overnight/<slug>` (its own git worktree — items never collide).
2. `delivery-orchestrator` in **close-out-suppressed mode** — this is the load-bearing safety step,
   not narration. The sub-task prompt MUST: (a) carry a GLOBAL_PREFERENCES veto token verbatim
   (`local only, no push, no merge`) so the orchestrator's own veto branch fires and it never calls
   ship-closer; (b) instruct it to **stop after VERIFY and return status — do NOT run CLOSE OUT**.
   Without both, the orchestrator's default flow pushes and merges to the integration branch before
   control returns here. Scope it to decompose → mechanically-testable DoD → implement to green.
   Inside this close-out-suppressed mode the orchestrator runs its full Team loop
   (plan → design → code → test, max-3-iteration bound per task).
3. Gate: `/test-sweep full` + `/perf-audit` on the changed surface. Red → **revert the branch**,
   file the failure to `context/bugs/OPEN.md`, move on. Never leave red committed. Note: with no
   dev server running at night, `/perf-audit` can only enforce server-free budgets (bundle size via
   `next build`/bundler stats, `EXPLAIN` on a local DB); server-dependent metrics (Lighthouse, API
   latency) report **not-measured**, and the morning report says so — never a false `perf ✓`.
4. Green → `overnight` itself does a local `git commit` on the branch (trailer per
   GLOBAL_PREFERENCES). **No push, no merge, no PR** — the commit stays local for morning review.
5. Record outcome; continue until the queue is dry or budget is exhausted.

## Hard boundaries (the whole safety model)
Safety here comes from **bounded scope + suppressed close-out**, not from a watching human:
- **Local only, enforced mechanically.** The veto-token/stop-after-VERIFY handoff in step 2 is what
  actually prevents push/merge — because ship-closer's standard commit→push→merge is *reversible*
  and therefore NOT CONFIRM-gated, and `pre-bash-guard` only blocks *force*-push, a plain
  `git push`/`git merge` would otherwise sail through. So the boundary is the delegation contract,
  and it must be honored on every item.
- **No deploy, no remote-state mutation, no destructive DB op.** These stay CONFIRM-gated and there
  is no human to CONFIRM, so they don't happen. Everything lands on isolated local branches.
- **Never disables a guardrail** to make an item pass (FORBIDDEN); a blocked item is reported blocked.
- **Never edits secrets/env or touches production.** `pre-bash-guard` still enforces the hard-deny
  list (force-push to main, curl|sh, rm -rf on a protected root, secret-in-commit) even here.
- **No unattended dependency installs.** test-automator runs in **no-bootstrap mode** at night: a
  missing test framework is filed to `context/bugs/OPEN.md` / the backlog, never `npm install`ed
  unattended (network fetch + arbitrary postinstall scripts have no place in a no-human run). This
  is why backlog-curator's `unattended-safe` class excludes "new deps" — the two agree.
- **Stops at a task boundary** on budget exhaustion (never mid-task); emits a `/handoff` capsule so
  a following run or the morning session resumes cleanly.

## Morning report — `docs/launch/overnight-YYYY-MM-DD.md`
Per item: **SHIPPED-TO-BRANCH** `<branch>` (DoD ✓, tests ✓, perf ✓/not-measured) | **BLOCKED**
`<precise reason>` | **REVERTED** `<red gate + bug id>`. Then: branches awaiting review, bugs filed,
retro proposals queued, budget used. Headline-first in chat so the operator triages in one glance.

## Scheduling
Kick off via a scheduled cloud agent / cron routine (see the harness `schedule`/`loop` skills) that
runs `/overnight` at night; this command is the *body* of that run, not the scheduler.
