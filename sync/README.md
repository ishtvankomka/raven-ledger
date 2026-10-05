# sync/ — the sync mesh

Keeps this collection and every project that uses it in sync, automatically and in
both directions. All scripts are macOS bash-3.2 compatible and offline-safe: when
the network is down, commits stay local and are pushed on the next opportunity.

## How it flows

```
project A ── PostToolUse hook (capture.sh) ──▶ incoming/A/        (local only)
                                                   │
                                          /promote │ human review
                                                   ▼
project B ◀── SessionStart hook (pull.sh) ◀── library/ ── commit+push ──▶ GitHub
```

**Nothing leaves this machine without a human.** Hooks only stage into `incoming/`;
`flush.sh` is the single publisher and is never called from a hook — `/promote`
calls it after review, or you run it yourself.

1. **Capture (project → collection).** Each wired project has a `PostToolUse` hook
   on `Write|Edit`. When a file under `.claude/agents/`, `.claude/commands/`, or
   `.claude/skills/` is written — by you or by an agent that just invented a new
   agent/skill — `capture.sh` copies it into `incoming/<project>/…` here. It does
   NOT commit and does NOT push. What may be staged is an allow-list, not a
   deny-list: markdown that opens with frontmatter, i.e. an actual agent, command
   or skill. A skill's scripts, fixtures and reference data stay in the project —
   that is where customer data lives, and no credential regex would catch it.
   Everything refused is logged, never silently dropped. Library stubs, symlinks,
   files >1MB and secret-like content are skipped too (see `looks_secret`).
2. **Pull (collection → project).** Each wired project has a `SessionStart` hook.
   `pull.sh` fast-forwards the collection onto already-fetched updates (never blocks
   on network), re-syncs the project's vendored `.claude/library/` from `library/`
   (preserving `ACTIVE.md`), catches up on captures the live hook missed, and
   schedules a throttled read-only `git fetch` (default every 6h — override with
   `RAVEN_PULL_HOURS`). It never pushes. When items are waiting it
   prints one line telling you how many are staged for `/promote`.
3. **Curation.** Captures never touch the curated library directly. Run `/promote`
   in a Claude Code session at this repo to review `incoming/`: anything reusable is
   generalized and merged into `library/` — from where every project picks it up on
   pull — and anything project-specific is rejected and left in its home project.
   Either way the verdict's digest goes into `sync/ignore.list`, so the mesh stops
   re-staging that file on every session.

## Scripts

| script | role |
|---|---|
| `lib.sh` | shared helpers: locking, logging, capture rules, git flush |
| `ignore.list` | curation verdicts as sha256 digests — captures the mesh must never stage again |
| `capture.sh` | PostToolUse hook — instant capture on write |
| `pull.sh` | SessionStart hook — apply updates, re-sync library, catch-up capture |
| `flush.sh` | commit staged captures + push pending commits (also fine manually) |
| `push-project.sh <dir>` | manual full scan of one project, synchronous |
| `install-project.sh <dir>` | wire the mesh hooks (capture, pull, router, ledger, digest, worker note) and the token tuning into a project's — and its existing worktrees' — `.claude/settings.local.json` (idempotent) |
| `secret-scan.sh <path>` | standalone run of the same secret gate |
| `on-prompt.sh` | UserPromptSubmit hook — injects the tools that match this message |
| `router-lib.sh` | `router_match` — local retrieval over the library index (no network, no LLM) |
| `build-index.sh` | rebuilds `library/index.json`; run it after ANY library change |
| `handoff-lib.sh` | `context_occupancy` — measure the live transcript when YOU ask; never speaks on its own |
| `session-ledger.sh` | Stop hook — one line per turn into `.claude/handoff/sessions/<date>-<session>.md` |
| `session-digest.sh` | SessionStart hook — hands a new session a short digest of recent ones |
| `worker-note.sh` | SessionStart hook — ~150-token note that the Gemini worker exists; silent unless keys are configured |
| `upstream-check.sh` | template copies: throttled check of the original repo, one-line update suggestion (`--merge` applies it) |
| `validate-library.sh` | mechanical contract check over `library/` (CI-friendly with `--quiet`) |

## Wiring a new project

```bash
/Users/ishtvan/files/work/other/raven-ledger/sync/install-project.sh /path/to/project
```

Hooks go into `.claude/settings.local.json` (machine-local, auto-gitignored) because
they reference this machine's collection path. Claude Code will ask to approve the
new hooks on the next session start — that's expected, approve once.

## Token tuning and the Gemini worker

Measured over 60 days of real sessions, every call re-reads the whole context: calls made with a
200K+ prompt were ~42% of calls and ~70% of weighted cost. Two machine-local levers, both applied by
`install-project.sh` to the project **and its existing worktrees** (each worktree keeps its own copy
of `settings.local.json`, and most sessions run in worktrees):

- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000` — caps the context so auto-compaction fires near 355K
  instead of near the model's full window (modelled saving ≈ 23% of weighted cost, about five
  compactions a day across ten projects). It never overrides a value set in the shell, the project's
  `settings.json` or `~/.claude/settings.json`. `RAVEN_COMPACT_WINDOW=<n> install-project.sh …`
  picks another size, `=0` skips it. The variable is read by the Claude Code binary but is not in its
  public docs; where unsupported it is simply ignored.
- The Gemini worker (`library/skills/gemini-worker/`): `worker-note.sh` tells every session it exists,
  so bulk reads go to Gemini Flash and only the answer enters context. Keys live in
  `~/.config/raven-ledger/gemini.env` (outside every repo, mode 600); without keys the note is
  silent. Any data may be sent except env keys and secret values, which the CLI redacts or refuses.
  A project switches the worker off with `touch .claude/no-worker` — the CLI itself then refuses to
  send, not just the note. The installer also adds a scoped allow rule for the worker command
  (`Bash(python3 <collection>/library/skills/gemini-worker/scripts/gw.py:*)`) to each local settings
  file, so calls do not stop at a permission prompt; `RAVEN_WORKER_ALLOW=0` skips it.

## Staying current with the template origin

A copy created from the template has no link back to the original repo until its
owner adds one: `git remote add upstream <original repo URL>`. Once that remote
exists, `pull.sh` also runs `upstream-check.sh` at session start — a throttled
read-only fetch (default every 24h, `RAVEN_UPSTREAM_HOURS`) and a one-line note
when upstream has commits the copy lacks. Applying them is always a deliberate
step: `sync/upstream-check.sh --merge` (clean tree on `main` required; conflicts
stop the merge and say so). Without an `upstream` remote the check is silent,
which is why the original repo itself never nags.

## State & logs

Everything operational lives outside the repo in `~/.cache/raven-ledger/`:
`sync.log` (every capture/flush/pull decision), `last-fetch` (fetch throttle), and
`git.lock` (mkdir-based lock, stale-stolen after 10 min).
