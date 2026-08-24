---
name: handoff
description: >-
  Snapshot the current session into a small context capsule and start a fresh session from it —
  so work continues without carrying the full transcript. Run it when you judge the moment right —
  switching phases (explore→implement→verify), splitting a batch across sessions, or when replies
  start losing earlier detail.
  Produces .claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md and seeds a new session with a resume prompt.
allowed-tools: Read, Write, Bash, Task
model: haiku
source: library-native
always_on: false
activation: "on-demand — you decide when; nothing proposes this for you"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /handoff — context capsule + fresh-session seed

## Steps
0. **Read the running ledger first.** If `.claude/handoff/current.md` exists, it holds one line per
   turn written as the session went: files touched, decisions as they were made. It is the cheapest
   and most accurate source you have — by the time a handoff is needed, the early part of the
   session has usually been summarized away, and the ledger is the only place those details survive
   verbatim. Use it as the raw material for step 1. If it does not exist, work from the conversation.
1. **Distill, don't dump.** Delegate to the `handoff-coordinator` agent (isolated formatter) with
   the raw facts of the session: objective, decisions locked, files changed, branch, next action,
   open questions. Do NOT paste the transcript.
2. **Fill the template.** Coordinator returns a capsule following `../handoff/HANDOFF_TEMPLATE.md`,
   capped at ~1500 tokens. Reject and re-run if it exceeds budget or includes conversation history.
3. **Name the load-set.** The capsule must list ONLY the agents / stack modules / skills / files the
   next session needs (see context-budget rules in `../README.md`). Add a "Do NOT load" line.
4. **Write it** to `.claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md` in the target project
   (create the directory if missing).
5. **Seed a fresh session**, using whichever is available:
   - In-app: use the session `spawn_task` tool with the capsule's "Resume prompt" as the opening
     message (creates a new chat carrying the capsule reference, not this context).
   - CLI: tell the user to open a new `claude` session and paste the "Resume prompt", or run
     `claude "$(cat .claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md)"`. (`claude --resume` takes a
     session id — it cannot load a capsule file.)
6. **Confirm** the capsule path + how to resume. Then stop — do not keep working in the old context.

## Rules
- The capsule is a CAPSULE. If it reads like a log, it's wrong.
- Never write secret values into the capsule — reference env-var names + `GLOBAL_PREFERENCES.md`.
- If a `delivery-orchestrator` batch is being split, the capsule's "Next action" carries the exact
  remaining items; never push a half-done set between sessions.
