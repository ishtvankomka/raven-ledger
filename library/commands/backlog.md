---
name: backlog
description: >-
  /backlog [suggest|plan] — thin dispatcher to backlog-curator. suggest (default) mines the
  project's own signals (bugs, specs, decisions, audits, retro proposals, coverage gaps,
  scoped TODOs) into context/tasks/backlog.md and appends unattended-safe candidates to the
  overnight queue as [suggested]; plan orders the operator-approved overnight-ok set into a
  budgeted run plan. Nothing runs unattended until the operator marks it overnight-ok.
allowed-tools: Read, Grep, Glob, Task
model: haiku
source: this library (original)
always_on: false
activation: 'on-demand any repo; suggested when the overnight queue is empty'
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /backlog [suggest|plan]

Thin dispatcher to [`../agents/backlog-curator.md`](../agents/backlog-curator.md). Default
mode: `suggest`.

## Modes

- **`suggest`** (default) — spawn `backlog-curator` via `Task` (isolated context; only the
  summary returns) to mine its source list → update `context/tasks/backlog.md` (well-formed
  BL-### items: source, DoD, size, risk class, deps) and append `unattended-safe` items to
  `context/tasks/overnight.md` marked `[suggested]`.
- **`plan`** — spawn `backlog-curator` in PLAN mode over the items the operator already
  marked `overnight-ok`, with any budget hint passed through → dependency-first,
  value-dense ordering with a stop-line, written back as ordering + comments only.

## Prints (headline-first)

1. **New suggestions**: count added to backlog + count appended to the overnight queue as
   `[suggested]`.
2. **Stale items flagged**: items whose source no longer exists.
3. **The reminder, every run**: nothing runs unattended until the operator marks it
   `overnight-ok` in `context/tasks/overnight.md` — `[suggested]` entries are inert (per the
   `/overnight` queue contract).

## Rules

- The curator suggests; the operator approves. This command never writes `overnight-ok` and
  never triggers implementation.
- If all sources are dry, report "sources dry — nothing to suggest" and stop; never invent
  items to fill the queue.
- Exit 0 always — curation is advisory; the value is the updated backlog + suggestions.
