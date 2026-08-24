# incoming/ — auto-captured staging area

Everything here was captured **automatically** from a live project by the sync mesh
(see [`sync/README.md`](../sync/README.md)): the moment a new agent, command, or skill
is written in any wired project, it lands in `incoming/<project>/<category>/…` —
and stays local. Nothing is committed or pushed by a hook; publication happens only
when a human runs `/promote` (which calls `flush.sh`) or `flush.sh` directly.

Nothing in here is part of the curated library yet. The curated library is `library/`
and only changes through deliberate promotion:

- open a Claude Code session in this repo and run **`/promote`** — it reviews each
  item and either rewrites it as a general tool and merges it into the library, or
  rejects it as project-specific. A rejected item stays in its home project and is
  recorded in `sync/ignore.list` so the mesh stops re-capturing it. Either way the
  file leaves this folder.

Library stubs (files pointing at `.claude/library/…`) and secret-like files are
filtered out before capture, so what you see here is genuinely project-authored work.
