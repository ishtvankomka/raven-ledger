---
name: handoff-readme
description: Explains the handoff mechanism — the /handoff command, the handoff-coordinator agent, and the HANDOFF_TEMPLATE.md capsule shape. Documentation only, never loaded by the budgeter.
model: haiku
always_on: false
activation: "reference doc, on-demand"
context_cost: low
---

# Handoff Mechanism — continue work in a fresh session without dragging the transcript

**Problem it solves:** a long agentic session accumulates a huge transcript. When the "team"
keeps working in the same context, most of those tokens are dead weight — but they still cost
money and crowd out the model's attention. The handoff mechanism lets you **snapshot intent into a
small capsule and start clean**, carrying forward the ~1-2k tokens that matter instead of the ~100k
that don't.

## The three parts
1. **`/handoff` command** (`../commands/handoff.md`) — you (or an agent) trigger it. It distills the
   live session into a capsule file using `HANDOFF_TEMPLATE.md`, then seeds a new session.
2. **`handoff-coordinator` agent** (`../agents/handoff-coordinator.md`) — the formatter. Given the
   raw facts, it produces a tight, budget-capped capsule and refuses to dump the transcript.
3. **`HANDOFF_TEMPLATE.md`** — the fixed capsule shape (objective · locked decisions · current
   state · next action · what-to-load · open questions · resume prompt).

## How a handoff runs
1. Trigger `/handoff` (manually, or an agent triggers it when its own context crosses ~55%).
2. The capsule is written to `.claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md` in the target
   project, capped at ~1500 tokens. It captures decisions and next-action — **not** the conversation.
3. A fresh session is created and seeded with the capsule. Three ways, pick what fits:
   - **In-app (this environment):** the `spawn_task` session tool creates a new session with the
     resume prompt as its opening message. Cleanest — no copy/paste.
   - **CLI:** open a new `claude` session in the repo and paste the capsule's "Resume prompt", or
     run `claude "$(cat .claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md)"`. (`claude --resume` /
     `--continue` resume prior sessions by id / most-recent — they cannot load a capsule file.)
   - **Manual:** paste the resume prompt anywhere you continue the work.
4. The fresh session reads the capsule + `GLOBAL_PREFERENCES.md`, loads **only** the modules the
   capsule lists (see the context-budget rules in `../README.md`), and starts from "Next action".

## Why this keeps context lean
- The capsule is a **capsule**, not a log — bounded size, decisions over history.
- It names exactly which agents/stack modules/files the next session should load, so the fresh
  session doesn't re-register the whole library.
- It composes with subagents: heavy exploration still goes to isolated-context subagents; the
  capsule only records their *conclusions*.

## When to hand off
- Context crosses ~55% and the task isn't near done.
- You're switching to a distinct phase (explore → implement → verify) and don't need the old context.
- A `delivery-orchestrator` batch is being split across sessions (it must never push a half-done set
  between sessions — the capsule carries the "what's left").
