---
name: retro
description: >-
  /retro [since] — run the self-improver over the library's own feedback artifacts (bugs, recurring
  issues, audits, request log, git history) since a date/ref, and produce a retro report of durable
  fixes: recurring-issue rules, stack-module corrections, new /check-* commands, permission/hook rules.
  Applies the safe mechanical class as individual commits; queues behavior-changing proposals.
allowed-tools: Read, Grep, Glob, Bash, Task
model: haiku
source: this library (original)
always_on: false
activation: "on-demand any repo; also invoked by /overnight"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /retro [since]

Thin dispatcher to [`../agents/self-improver.md`](../agents/self-improver.md). `since` is a date
(`2026-06-01`) or git ref (`HEAD~50`, a tag); default = last 14 days.

## Steps
1. Resolve the window; gather the input set (see self-improver Inputs) scoped to it.
2. Spawn `self-improver` via `Task` (isolated context — only the report + applied-diff summary
   returns).
3. Print: clusters found, fixes **applied** (with commit shas), proposals **queued** for approval.

## Output — `docs/audits/YYYY-MM-DD-retro.md`
Per cluster: evidence → durable fix → diff/command → payoff → APPLIED (sha) | PROPOSED.

## Rules
- Report-and-apply-safe only: mechanical fixes auto-apply as separate revertible commits; anything
  that broadly changes agent behavior, weakens a rule, or adds a module is queued, never auto-applied.
- Never weakens a guardrail, never edits app product code (self-improver enforces both).
- Exit 0 always (a retro is advisory); the value is the report + the committed safe fixes.
