# raven-ledger

A curated, general-purpose Claude Code toolset plus the sync mesh that keeps it and
every consuming project in sync. Read this before changing anything.

## The prime directive

**The collection holds no project-specific data.** Project-local tooling stays in
its own project, with its own context. A tool enters `library/` only as a general
tool: no project names, paths, domains, brand tokens, locale sets, env details, or
business facts — even when the underlying case is niche. If a captured item has no
reusable core, it is rejected and stays home (recorded in `sync/ignore.list` so the
mesh stops re-capturing it).

## Layout

- `library/` — the curated toolset. `library/README.md` is the authoritative
  manifest: a file not listed there does not exist. Installed into projects via
  `library/INSTALL_PROMPT.md`.
- `library/stacks/` — rule modules that load only when their `activation:`
  condition matches the repo (framework, domain, or tooling).
- `incoming/<project>/` — staging area auto-filled by the mesh; enters the library
  only through `/promote`. Never edit `library/` straight from a capture.
- `sync/` — the mesh scripts (capture / pull / flush / install) and
  `sync/ignore.list`. See `sync/README.md`.
- `projects/` — untracked, gitignored source dumps. They contain credential
  locations and client facts. Never commit, never copy anywhere — the same applies
  to any narrative written from them.

## Hard rules

- **Agents use `tools:`; commands use `allowed-tools:`** — a bare `tools:` key on a
  slash command parses fine but is silently ignored, leaving the command with full
  tool access. This has bitten before; check it on every promote.
- Frontmatter is strict YAML with `context_cost:` and `activation:`.
- Any `library/` change propagates to all consuming projects on their next session
  start (pull.sh re-syncs `.claude/library/`) — treat edits as releases.
- Safe-velocity convention: never commit secrets; reversible ops are autonomous,
  irreversible remote-state ops need explicit confirmation; force-push to main is
  never OK.
