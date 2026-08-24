---
name: hooks-pack
description: >-
  Deterministic lifecycle hooks for the library. Hooks are shell commands the Claude Code
  HARNESS executes at fixed events (before a tool runs, when a turn ends, before context
  compaction) — they enforce rules outside the model, so a guardrail moves from "the agent was
  asked to remember" to "the runtime guarantees it". Merged into .claude/settings.json by
  INSTALL_PROMPT step 6.
model: haiku
source: this library (original)
always_on: false
activation: "reference doc; the hooks themselves run on every matching event once installed"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# Hooks — enforcement outside the model

A prompt rule can be forgotten under context pressure; a hook cannot. The library keeps its
contract in three enforcement layers, strongest first:

1. **Hooks** (this pack) — the harness runs them deterministically; exit code 2 blocks the action
   and feeds the reason back to the agent.
2. **Permission rules** (`settings.template.json` deny/ask/allow) — the harness's own gatekeeper.
3. **Prose contract** (`GLOBAL_PREFERENCES.md`) — what the agents are instructed to obey.

Hooks 1+2 overlap by design (defense-in-depth): permission rules can be loosened by a broad Bash
allow; the hook still fires.

## Shipped hooks (`hooks.template.json` → scripts in `scripts/`)

| Event | Script | What it guarantees |
|---|---|---|
| PreToolUse (Bash) | `pre-bash-guard.sh` | Blocks GLOBAL_PREFERENCES hard-denies no matter what was prompted: force-push to `master`/`main`, `curl\|bash` / `wget\|sh`, `rm -rf` on `/`, `~`, `$HOME`. Before any `git commit`: staged-diff secret scan (gitleaks if installed, pattern fallback from secret-scanner) — a committed secret becomes mechanically impossible, which is what makes the dev-time direct-token convention safe. |
| Stop | `stop-hygiene.sh` | Dev-server hygiene rule made real: if a known dev port (3000/5173/8081/…) is still listening when the agent tries to end its turn, the stop is bounced back once with the instruction to shut the server down (loop-protected via `stop_hook_active`; skip is allowed only if the user asked to keep it running). |
| PreCompact + SessionStart | `precompact-handoff.sh` + `sessionstart-handoff.sh` | The deterministic "~55%, run `/handoff`" rule. PreCompact can't inject context (its output is ignored), so it drops a `.compaction-pending` breadcrumb; the SessionStart hook — which *does* honor `additionalContext` when a session resumes from a compaction — reads the breadcrumb and reminds the agent to resume from a `.claude/handoff/` capsule instead of the lossy auto-summary, then clears it. |

## Notes

- Scripts parse hook stdin JSON with `python3` (no jq dependency) and fail open (`exit 0`) if
  parsing fails — a broken hook must never brick the session.
- Paths in `hooks.template.json` use `$CLAUDE_PROJECT_DIR`, so they work from any cwd.
- INSTALL_PROMPT merges the `hooks` block into existing settings (union — existing project hooks
  are kept) and `chmod +x` the scripts.
- Adding a new always-on rule? Prefer encoding it here (or in permission rules) over adding prose
  to CLAUDE.md — deterministic layers don't consume context and can't be forgotten. This is also
  where `self-improver` escalates repeat offenses (prose rule that failed twice → hook).
- Never add a hook that disables or bypasses another guardrail — FORBIDDEN per GLOBAL_PREFERENCES.
