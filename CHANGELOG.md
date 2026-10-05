# Changelog

Versions follow [semver](https://semver.org) and live as git tags; each release
gets an entry here.

## Unreleased

- `library/skills/gemini-worker`: Orchestrator-Worker offload — a stdlib-only CLI (`gw.py`) that
  sends a question plus files or piped output to Gemini Flash and prints only the answer. Key
  rotation on 429 with cooldowns shared across calls, backoff on 5xx, distinct exit codes, secret
  redaction and a refusal list mirroring the `Read` deny rules, a per-project opt-out
  (`.claude/no-worker`), and 25 offline tests.
- `sync/worker-note.sh`: SessionStart note (~150 tokens) that reaches every wired project and
  worktree; silent unless keys exist.
- `sync/install-project.sh`: also wires the note and applies machine-local token tuning
  (`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`) to the project and its existing worktrees.
- Docs: handoff threshold restated in absolute tokens; token-economy rules in `GLOBAL_PREFERENCES.md`.

## 1.0.0 — 2026-08-24

First public release.

- `library/`: 27 agents, 16 commands, 21 skills (plus 5 vendored design skills),
  19 stack modules, 8 guardrails, 4 harness hooks.
- `sync/`: the two-way mesh — capture hook, session-start pull, `/promote`
  curation, shared secret gate, session ledger and digest, per-turn skill router,
  contract validator, upstream template check.
- Distributed as a GitHub template repository: create your own copy and run your
  own ledger (see `PUBLISHING.md`).
