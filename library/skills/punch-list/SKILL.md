---
name: punch-list
description: Procedure for numbered feedback batches — many cross-cutting corrections from an owner, client, or reviewer arriving in one message. Split them into tracked items before touching code, partition the work by FILE rather than by feature, run the verification gate, then record each accepted reversal in the project's decision record with the author's own words and a date. Use when a message arrives as a numbered list of UI or product corrections, when continuing one ("continue", "what is left?"), or before spawning parallel agents over one repo.
always_on: false
activation: "invoke when one message carries a numbered list of cross-cutting UI or product corrections from an owner, client or reviewer, when a follow-up asks to continue or asks what is left of such a batch, or before fanning parallel agents out over a single repo"
context_cost: medium
---

# The punch list

**The item you drop is item 11.** Not item 1, which you read carefully, and
not item 21, which you were still holding when you wrote the summary — the
ones in the middle, that looked small, that you meant to come back to. Every
mechanic below exists to stop that: split first, track each item by number,
report per item, and let the file system rather than your memory decide who
touches what.

The shape is stable across projects: a spread of corrections across unrelated
routes, mixing "move this 2px" with "delete this feature" in one message.

## Split the batch before touching code

Do this before the first edit, not after the first three.

1. Read the whole message. Do not start on item 1 while still reading.
2. Break it into **one tracked item per clause**. One numbered line often
   carries two corrections ("columns too big, and make the tabs icons") —
   that is two items, because they land in different files and can fail
   independently.
3. Assign each item a stable number that survives to the final report. Use
   the author's numbering where they gave one; append letters for the splits
   (`7a`, `7b`) so a reply of "7 is still wrong" is still answerable.
4. Only then plan the file partition (below) and start.

Report at the end **per item, in the author's order**, each with a verdict:
done / done-differently-and-why / not-done-and-why. A prose paragraph that
says "handled the feedback" is how items go missing silently. A batch where
19 of 21 are done and 2 are named as skipped is a good outcome; a batch where
21 are claimed and 2 are silently missing is a bad one, and the author finds
out next session.

## Surface truncated or ambiguous items; never guess

Feedback arrives truncated, mid-sentence, or with a pronoun whose referent
died two items earlier ("and that one should be smaller too"). A guessed
interpretation costs a whole round trip and re-opens a settled question.

- If an item is cut off, quote the fragment back and ask. Do not infer the
  rest.
- If an item could mean two things, name both readings and ask which — one
  sentence, not a design memo.
- If an item contradicts a standing verdict in the project's decision record,
  say so explicitly and treat the new instruction as winning **only** once
  the author confirms. That confirmation is what you later record as a dated
  reversal.
- Keep working the unambiguous items while the question is outstanding. Do
  not block 20 items on 1.

Ask everything you need in **one** batched question. Drip-feeding one
question per item is the other way to burn a round trip.

## Partition by file, not by feature

Parallel agents collide on files, not on concepts. Two items that sound
unrelated ("fix the hero's waterline", "make the CTA stars less flat") can
both land in the global stylesheet and will clobber each other.

Before fanning out, list this repo's **collision magnets**: the global
stylesheet, any 500+-line component, the copy/message files, and — always —
the design-decision record itself, because every batch writes to it.

Rules:

- **Two items touching the same file go in the same agent, or in different
  waves.** Never in two concurrent agents.
- Group by file first, then check the grouping still makes sense as work. A
  file-coherent agent with three unrelated items beats two feature-coherent
  agents fighting over the stylesheet.
- The decision record is written by the **main thread only**, in one pass at
  the end. Sub-agents report their reversals up; they do not each append.
- Give every agent its item numbers verbatim and require the same per-item
  verdict format back, so the numbers survive the fan-in.

### Route each item kind to the agent that already owns it

Do not spawn generic sub-agents for work a specialized one was built for —
visual items to the UI agent, verification to the gate/sweep agent,
translation drift to the i18n agent, deploys to the deploy agent. They keep
their bulk out of your context, which is the scarce resource during a batch.

The main thread still owns the decomposition, the file partition and the
decision-record write-up. Those cannot be delegated: a sub-agent cannot see
the other items, so it cannot know which file it is about to collide on.

### Splitting an over-large shared file is a legitimate move

If a file is a collision magnet because it is doing too many jobs, splitting
it is foundation work, not scope creep — record the reason in a header
comment so the next session knows why. Do the split in the foundation wave,
before the fan-out, never concurrently with edits to the file being split.

## Foundation first: the primitives that already exist

Run a short serial wave before any fan-out: token or primitive changes that
several items depend on, plus any file split. Then fan out.

Maintain (and hand each agent) the repo's **need → existing primitive**
inventory. Every batch produces at least one agent that hand-rolls a toolbar
or a label/value row it did not know existed; a ten-line table prevents it.

## Do not trust a verification agent's pass

A sub-agent reporting "verified, all good" is a claim, not evidence. Confirm
independently before it reaches the author. Two recurring failure shapes:

1. **The validator that validated someone else's work.** Parallel agents
   sharing one scratchpad can overwrite each other's check scripts mid-run —
   an agent then reports green for a target it never opened. Structural fix:
   the check runs **outside** the fan-out, owned by the orchestrator.
2. **The review that measured the wrong thing.** An element checked in
   isolation, at the wrong opacity, on the wrong background, at the wrong
   width — everything passes, and the shipped result is wrong.

Both share one root: the check ran on something other than what ships. So:
**re-measure the thing itself, on its real ground, at its real strength.**
Read the DOM, compute the number, diff the file — do not accept a screenshot
plus a confident sentence. Contrast and size claims especially: numbers an
agent will call "clearly distinguishable" without ever computing them.

## The gate before reporting

Run the project's verification gate (typecheck, tests/checks, build, and any
project-specific sweeps) **before** the per-item report reaches the author,
not after. A report that lists 19 items done and then fails the typecheck
costs you the batch.

Know the gate's **baseline failures** — checks that exit non-zero on a clean
tree — and diff your run against that baseline. Reporting a known-baseline
item as a regression sends the next reader chasing a ghost; do not "fix" a
baseline by editing files you were not asked to touch.

## Record the reversals, and where

**In the same turn the work lands**, write every accepted reversal into the
project's design/decision record. This is not documentation housekeeping —
it is what stops the next session re-litigating a question the author already
answered, and re-earning the same correction.

Each entry needs four things:

1. the author's **verbatim words**, in quotes — paraphrase drifts, quotes do
   not;
2. the **date**;
3. the **rule it overturns**, named, so the old rule cannot be read as still
   live;
4. where it is enforced in code, if anywhere.

Where a verdict has flipped more than once, say so and mark which one is
current ("reversed twice; this is the standing version"). A reversal recorded
without the reversal count reads as a first-time decision and invites a third
flip.

Only the main thread edits this record. Every batch touches it; concurrent
appends from sub-agents are the single most likely merge collision in a
fan-out.

## Copy edits strand other locales

In a localized project, any copy change lands in the primary locale and
**immediately puts every other locale out of date** — and per-key fallback
means the failure mode is silent mixed-language, not an error. Hand the
translation off in the same batch rather than letting it strand. Key parity
is not correctness: if you changed a string's *meaning* without changing its
key, name that key explicitly in the handoff — no parity check will ever
catch it.

## Stale files to distrust

**A backlog or TODO ledger is a historical document, not current state.**
Partial annotations make the un-annotated stale rows more convincing, not
less. Answer "is all done?" from the tree, never from the ledger:

```bash
git log --oneline -20
ls <the directories the ledger claims things live in>   # does the component exist?
grep -n "<token>" <stylesheet>                          # does the token exist?
<the project's gate commands>
```

**Work strands on unmerged branches.** Before writing a tool or re-fixing a
bug, check whether it already exists elsewhere:

```bash
git branch -a
git log --all --oneline --grep="<thing>" -i
```

Prefer merging an existing fix to writing a third one.

When you find an instruction file that contradicts the decision record, fix
it in that turn rather than noting it somewhere — a TODO parked in a
reference document stays wrong until someone happens to read the document.
