# The skill router

Session start loads every skill description into context whether or not the session ever
needs one. This library has **26 skills carrying ~12,000 characters** of description (plus
27 agents, 16 commands and 19 stack modules). The harness caps
that listing at `skillListingBudgetFraction` = **1%** of the context window, so the skills
alone already sit at the edge of the budget, and every skill added past that point either
pushes the listing over or crowds out a description that mattered.

The router inverts it: keep most skills out of the listing entirely, and inject the two or
three that are actually relevant to *this turn*, computed locally from the prompt.

```
UserPromptSubmit ─▶ router_match "<prompt>" ─▶ 0-3 lines ─▶ additionalContext
                         │
                         └── library/index.json  (built by sync/build-index.sh)
```

Retrieval is keyword overlap with IDF weighting — no network, no embeddings, no model call.
One `python3` process per turn: **24ms** measured with a conda python3, **43ms** with
`/usr/bin/python3`, on a 96-entry index.

## The two settings you must set

The router only pays for itself if the listing is actually shrunk. Both settings go in
`.claude/settings.json`.

**1. Demote the tail to `name-only`.** A `name-only` skill keeps its name in the listing
and stays model-invocable, but costs no description budget — the router supplies the
description when it is relevant.

```json
{
  "skillOverrides": {
    "clickable-inventory": "name-only",
    "content-capture": "name-only",
    "data-isolation-verify": "name-only",
    "exact-implement": "name-only",
    "final-validate": "name-only",
    "media-harvest": "name-only",
    "replica-compare": "name-only",
    "replica-fix": "name-only",
    "replication-plan": "name-only"
  }
}
```

**2. Decide what stays `on`.** A skill stays `on` when the cost of *missing* it exceeds the
cost of carrying it — typically the ones that fire on a phrasing the router cannot predict,
or that must fire on the first turn before any hook has seen a prompt. Good defaults to keep
`on` here: `verify-change`, `commit-changelog`, `ui-restraint`, `punch-list`.

The other two modes are for skills you want *out* of the model's reach: `user-invocable-only`
(only the human may run it) and `off`. Both are free listing-wise, but the router cannot rescue
an `off` skill — if it matches one, the model still cannot run it.

## Wiring it

The library ships this as `sync/on-prompt.sh`, and `install-project.sh` wires it in
automatically. A minimal custom `UserPromptSubmit` hook built from the same pieces looks
like this — it must exit 0 always, and print nothing when nothing matches:

```bash
#!/usr/bin/env bash
set -u
. "$(dirname "$0")/router-lib.sh"
prompt="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0
hits="$(router_match "$prompt" "" 3 2>/dev/null)" || exit 0
[ -n "$hits" ] || exit 0
HITS="$hits" python3 -c '
import json, os
lines = [l.split("\t") for l in os.environ["HITS"].strip().split("\n")]
txt = "Possibly relevant library items for this turn:\n" + "\n".join(
    "- %s %s: %s" % (k, n, d) for k, n, d in lines)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit", "additionalContext": txt}}))'
exit 0
```

Verified against real hook stdin: it prints one JSON object on a match, prints nothing and
exits 0 on a non-match, on malformed stdin, and on empty stdin.

`router_match <query> [index.json] [max]` echoes at most `max` lines of
`kind<TAB>name<TAB>description`, best first, and **echoes nothing when nothing clears the
relevance floor** — which is the common case and the intended answer. Exit status is 0 for
both "matched" and "did not match"; 1 only on a real fault (no index, no `python3`), with one
line on stderr. With an empty second argument it falls back to `$ROUTER_INDEX` (read at call
time) and then to `../library/index.json` next to the script. Floors are overridable per
call: `ROUTER_MIN_SCORE`, `ROUTER_SINGLE`, `ROUTER_REL_CUT`.

## Rebuilding the index

```bash
sync/build-index.sh                       # -> library/index.json
sync/build-index.sh <lib-dir> <out.json>  # or point it somewhere else
```

Run it after **any** change to a description, an `activation:` line, or the set of library
files — a stale index silently routes to the old wording. Output is sorted and untimestamped,
so a no-op rebuild produces an empty diff and a real change produces a readable one.

`build-index.sh` and `router-lib.sh` each carry a copy of the same tokenizer, stamped
`"tokenizer": "v1"` in the index. If you change one copy, change both and bump the version:
the router refuses to score against an index built by different rules rather than quietly
returning wrong matches.

## Caveats — read these before trusting it

- **It costs a python3 start on every single turn.** ~25-45ms and one process, forever, on
  every prompt including "yes" and "thanks". That is the price of the listing budget it buys
  back; if the listing is not actually shrunk, the router is pure loss.
- **It cannot enable a skill mid-session.** The listing is computed once at session start and
  cannot be refreshed. `name-only` skills stay invocable, which is what makes this work at all
  — but a skill set to `off` is unreachable no matter how well it matches, and injected
  context is visible for that turn only. It does not persist and does not survive compaction.
- **Retrieval is only as good as the descriptions.** It matches words, not meaning. "why is
  the bundle so big" returns nothing here, because no library description contains "bundle
  size" — the fix is to write the words users actually type into the `description:` and
  `activation:` lines, not to make the matcher cleverer.
- **A rare word shared by accident is a false positive.** "handshake" appears in exactly one
  description (a CMS webhook handshake), so a question about TCP handshakes used to match it.
  Floors were raised until it stopped, but the failure mode is structural, not fixed.
- **Ranking is weaker than recall.** For "the site feels slow on the product page" the right
  answer (`performance-engineer`) is in the top 5 but not first. Treat the output as
  candidates for the model to choose from, not as a decision.
- **Never inject more than about three.** Each line carries a full description (~450 chars);
  five is already a third of a listing's worth of budget spent every turn.
