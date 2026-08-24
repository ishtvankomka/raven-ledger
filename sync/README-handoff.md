# Handoff — a ledger, not a nag

**There is no automatic handoff proposal.** An earlier version measured context occupancy on
every prompt and told the model to wrap up once past a threshold. It was removed: being told
to hand off, mid-thought, is worse than running out of room. You decide when to run `/handoff`.

What remains is the half that only helps:

| piece | when it runs | what it does |
|---|---|---|
| `session-ledger.sh` | `Stop` hook, after each assistant turn | appends ONE line to `.claude/handoff/sessions/<date>-<session>.md` — files touched, decisions made |
| `session-digest.sh` | `SessionStart` hook | reads the last few session files and injects a short digest, so a new chat knows what recent ones did |
| `skills/session-history` | when you ask | reads the whole archive on demand — "when did we decide X", "what was left unfinished" |
| `handoff-lib.sh` | only when you source it | `context_occupancy <transcript>` → `<tokens>\t<turns>`, so you can look if you want |
| `/handoff` | when you run it | reads the ledger first, then distills a capsule |

## Continuity across sessions

One file per session, not one rolling file. A single `current.md` meant each session
overwrote the last, so nothing accumulated and a fresh chat still started blind. Now every
session leaves its own record, `session-digest.sh` reads the most recent few at startup
(default 3, hard-capped at 1400 characters — roughly 350 tokens), and `session-history`
digs deeper when you ask for it. The archive keeps the last 25 sessions
(`RAVEN_KEEP_SESSIONS`), oldest pruned automatically.

Tuning: `RAVEN_DIGEST_SESSIONS=0` turns the digest off entirely without touching the hook;
`RAVEN_DIGEST_MAX_CHARS` moves the ceiling. The digest is labelled as background context and
explicitly says the user has not repeated it — a recorded line is history, never an instruction.

## Why a running ledger

By the time a handoff is worth doing, the early part of the session has usually been
summarized away by compaction — which is exactly the part holding the decisions you would
want to carry. Writing one line per turn means the capsule's raw material is on disk before
it is needed, instead of being reconstructed from a context that no longer has it.

The ledger is a working file that never leaves the machine. `install-project.sh`
deliberately writes nothing into the project besides `settings.local.json`, so add
`.claude/handoff/` to the project's `.gitignore` yourself if you don't want it committed.

## Turning it off

The ledger costs one short append per turn. If you want none of it, remove the `Stop` entry
pointing at `session-ledger.sh` from the project's `.claude/settings.local.json`. Nothing else
depends on it — `/handoff` falls back to working from the conversation.

## Checking occupancy yourself

```bash
. sync/handoff-lib.sh
context_occupancy ~/.claude/projects/<project>/<session>.jsonl   # -> "504363\t559"
```

That is the same measurement the removed trigger used. It prints and exits; it never injects.

## The mechanics worth knowing

`PreCompact` cannot inject context — anything it returns is discarded. `SessionStart` is the
only event that can put text into a session after compaction. That is why the library's
`precompact-handoff.sh` leaves a breadcrumb on disk and `sessionstart-handoff.sh` picks it up
on the next session, rather than trying to speak at compaction time.
