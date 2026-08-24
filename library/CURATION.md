# The curation ledger

`capture → curate → distribute` is a claim. This file is the only evidence for it.

The mesh stages captures into `incoming/`, `/promote` rules on each one, and the
library re-syncs into every project. From the outside, that loop is indistinguishable
from a library that accepts whatever lands in it — the inventory looks the same
either way. **The rejections are the product.** A verdict that leaves an item in its
home project is the loop working; nothing in `library/` records that it happened, and
`sync/ignore.list` records it only as a one-way digest with no reason attached.

So without this ledger:

- nobody can tell whether `/promote` is curating or just forwarding;
- nobody can tell whether the prime directive ("the collection holds no
  project-specific data") is enforced or merely stated;
- the author cannot see the loop's own failure modes — the same item bouncing back
  three times, a category that never produces anything reusable, a generalization
  that turned out to be wrong;
- and a reader deciding whether to trust the library has only its size to go on.

A ledger entry costs one line at the moment the verdict is made. Reconstructing it
later costs what the "Baseline" section below cost: a day of inference, and rows that
have to say *unknown*.

## Rules

1. **Append-only.** Never edit or delete a row. A verdict that turns out wrong gets a
   new row referencing the old one (`reverses 2026-09-04 · <item>`).
2. **Written at verdict time**, by `/promote`, as part of the same pass that moves or
   rejects the file — not reconstructed afterwards.
3. **One row per verdict**, including rejections. Especially rejections.
4. **No project or client names — ever.** Same reason `sync/ignore.list` stores
   digests rather than paths: this file is as public as the repo. A promotion names
   the *library file that resulted*; a rejection names the *shape* of the thing
   ("a deploy script wired to one host"), never whose it was.
5. **Unknown beats plausible.** If a field cannot be verified from something in the
   repo, write `unknown`. A ledger with invented specifics is worse than no ledger,
   because it cannot be audited.

## Columns

| column | meaning |
|---|---|
| `date` | ISO date of the verdict. `—` only in the reconstructed baseline below. |
| `item` | the library file that resulted, or the shape of what was rejected |
| `source kind` | `project-capture` · `upstream` (third-party set) · `library-native` · `vendored` · `merge` |
| `verdict` | `promoted` (entered as a new file) · `merged` (folded into an existing file) · `rejected` (stayed in its home project) |
| `reason` | one line. For a rejection, what made it unreusable. For a promotion, what the reusable core was. |

---

## Baseline — reconstructed 2026-08-23

The ledger starts after the library does. Everything below was reconstructed from
evidence that still exists in the repo: the `source:` frontmatter each file carries,
`skills/design/ATTRIBUTION.md`, `sync/ignore.list`, and the state of `incoming/`.

**Per-item history before this date is not recoverable**, so the baseline is written
as summary rows, each marked `(summary)`. They are deliberately not expanded into
per-item rows — that would mean inventing dates and reasons that no longer exist
anywhere. Do not backfill them later; start real rows below the baseline.

| date | item | source kind | verdict | reason |
|---|---|---|---|---|
| — | 12 files whose `source:` names a project origin outright — 5 `commands/check-*` + `add-page`, `agents/replica-scout` + `replica-builder`, `agents/deploy-verifier`, `agents/legacy-scout`, `agents/product-copywriter`, `commands/typecheck` + `check-translations` (summary) | project-capture | promoted | each had a reusable core once the project's paths, brands and locale sets were stripped; the generalized rewrite is what entered |
| — | 3 files whose `source:` records a project capture folded into existing work — `agents/business-analyst`, `agents/code-reviewer`, `agents/qa-auditor` (summary) | project-capture | merged | the capture contributed a delta, not a new tool; merging kept one file per role instead of two near-duplicates |
| — | 8 files that each absorb several predecessors — `delivery-orchestrator` (5), `project-scribe` (6), `i18n-engineer` (3), `qa-auditor` (3), `design-system-engineer` (2), `runtime-db-operator` (2), `ship-closer` (2), `unit-economics-analyst` (2): 25 predecessors in total (summary) | merge | merged | consolidation, not capture: overlapping agents collapsed into one file each so the routing table has a single answer per trigger |
| — | 11 files adopted from third-party sets (wshobson/agents, VoltAgent, superpowers) — the 5 Tier-A/B guardrails, `backend-architect`, `frontend-developer`, `debugger`, `performance-engineer`, `stacks/specialized-domains`, and `code-reviewer` in part (summary) | upstream | promoted | adopted rather than written, then re-fitted to this library's frontmatter contract and safety posture |
| — | 21 library-native originals — 17 marked `this library (original)` plus `handoff-coordinator`, `test-automator`, `commands/handoff`, `skills/design/MANIFEST.md` (summary) | library-native | promoted | written here for a gap nothing else covered; no capture involved |
| 2026-07-08 | `skills/design/` — 5 design skills vendored verbatim, licenses and provenance in `ATTRIBUTION.md`, budgeting metadata held out-of-file in `MANIFEST.md` | vendored | promoted | vendored unmodified, so the loader metadata this library requires had to live in a sidecar; upstream commit SHAs were not recorded and are now `unknown` |
| — | 70 verdicts recorded in `sync/ignore.list` (summary) | unknown | rejected + promoted, unsplittable | the list stores one-way digests with no reason field, so the count is certain and the split is not — its own header says entries are either project-local rejections or originals whose core was already generalized |
| 2026-08-23 | `incoming/` holds no pending captures | — | — | the staging area is drained: every capture taken so far has a verdict, even if 70 of them are only recoverable as digests |

### What the baseline cannot tell you

Recorded here so the gaps are not mistaken for absences:

- **No dates.** Only the vendoring date (2026-07-08) survives in a document. Every
  other baseline row is undated.
- **The 70 digests cannot be split** into rejected-as-project-local versus
  core-already-generalized, and carry no reasons. This is the single largest piece of
  missing evidence, and it is missing by design — the digests exist to avoid
  publishing a roster of project names. The ledger is the intended replacement:
  the digest keeps the mesh quiet, the row says why.
- **38 modules carry no `source:` at all** — all 19 curated skills, 18 of 19 stack
  modules, and `agents/pre-ship-sweep`. Their provenance is unrecoverable from the
  repo. That the skills — the newest and largest category — are the least documented
  is itself the finding that motivated this file.
- **Nothing records what was rejected and later re-captured**, so loop churn before
  2026-08-23 is invisible.

### Verifying the baseline

Every count above is recomputable; do not take them on trust.

```bash
# provenance tally by source: (the basis for the summary rows)
python3 - <<'PY'
import os, collections, yaml
t = collections.Counter()
for root, _, files in os.walk('library'):
    for fn in files:
        p = os.path.join(root, fn)
        try: txt = open(p, encoding='utf-8').read()
        except Exception: continue
        if not txt.startswith('---\n'): continue
        d = yaml.safe_load(txt[4:txt.find('\n---', 3)])
        if isinstance(d, dict): t[str(d.get('source'))] += 1
for k, v in t.most_common(): print(v, k)
PY

grep -cE '^[0-9a-f]{64}$' sync/ignore.list   # 70 verdict digests
find incoming -type f                        # pending captures (README.md only = drained)
sync/validate-library.sh                     # the contract the promoted files must hold
```

---

## Entries

Append below. Newest at the bottom — this is a log, not a report.

| date | item | source kind | verdict | reason |
|---|---|---|---|---|
| 2026-08-23 | `sync/validate-library.sh` + this ledger | library-native | promoted | the frontmatter contract was prose-only and the curation loop left no record; both are now mechanical |
