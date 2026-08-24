---
name: business-plan
description: >-
  The pre-release planning gate — one command, one adversarially-validated business plan:
  market-demand verdict, deep product spec, unit economics, GTM plan, then a devils-secretary
  challenge pass over all of it, synthesized to docs/product/BUSINESS_PLAN-<slug>.md with a
  GO / ITERATE / KILL recommendation. Trigger before building or releasing a product or major
  feature. Recommends only — the operator decides.
allowed-tools: Read, Grep, Glob, Write, Bash, Task
model: sonnet
source: 'this library (original)'
always_on: false
activation: 'before building or releasing a product/major feature — full pre-release business analysis'
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /business-plan [product-or-feature] [markets...]

The pre-release planning gate: builds that skip it start on `hope`. Orchestrates; never analyzes
itself — every stage runs as a `Task` subagent (isolated context, only summaries return).

- `[markets...]` seeds demand, economics, and GTM per market; if omitted, fall back to the
  LEGAL_FACTS block in the project's CLAUDE.md (installed by INSTALL_PROMPT.md).
- Input too fuzzy even to frame (no nameable problem)? Route to
  [`../agents/brainstormer.md`](../agents/brainstormer.md) first — do not plan a blank.

## Stages — in order

### 1 · MARKET & DEMAND — [`../agents/business-analyst.md`](../agents/business-analyst.md), DISCOVER
Problem statement, target segment, JTBD, dated competitor scan, differentiator hypothesis —
plus the **hungry-user evidence verdict**: does demand clear the 3-of-5 evidence bar (at least
3 of business-analyst's 5 independent demand signals verified, not hoped)? Verdict + evidence
table return; raw research stays in the subagent.

### 2 · PRODUCT SPEC — business-analyst, DEFINE + SPEC-DEEP on the core flows
Feature map with an explicit MVP cut, then the core flows specified to the screen/button/text
level. Every flow element is either **specified** or listed as an **open question** — never
silently glossed. NON-GOALS mandatory, per business-analyst's own rules.

### 3 · ECONOMICS — [`../agents/unit-economics-analyst.md`](../agents/unit-economics-analyst.md)
Cost structure per billable surface, pricing hypothesis, margin (average AND marginal),
break-even user count. Prices verified live or labeled `[est]` per that agent's rules.

### 4 · PROMOTION — [`../agents/growth-marketer.md`](../agents/growth-marketer.md), CHANNELS + PLAN
Channel table for the segment (paid lane + the mandatory free lane, each with a kill threshold),
then a $0-budget plan AND a small-budget plan, and a 90-day experiment calendar — every experiment
carrying its own kill threshold. (MEASURE is a post-launch mode — no actuals exist at this gate.)

### 5 · DEVIL'S ADVOCATE — [`../agents/devils-secretary.md`](../agents/devils-secretary.md), over EVERYTHING above
Stages 1–4 arrive as one plan: steelman first, then the six-step challenge pass, then the
**counter-proposal loop** — each **HIGH** flaw gets 2–3 solution variants, each variant re-validated
by the same challenge mode. Per-HIGH-flaw verdict: **validated mitigation** or **open risk**;
MEDIUM/LOW flaws land as improvement candidates for `backlog-curator`.

- This stage may send stages 1–4 back for **one revision round, max one loop**. After it,
  remaining flaws ship in the report as open risks — adversarial validation terminates; it
  never iterates indefinitely.

### 6 · SYNTHESIS — write `docs/product/BUSINESS_PLAN-<slug>.md`
In the context/ scaffold (created by INSTALL_PROMPT.md). Sections, in order:

1. **Demand verdict** + evidence table (stage 1)
2. **Validated spec summary** + open questions (stage 2)
3. **Economics** — cost/user, margin, break-even (stage 3)
4. **GTM** — both budget levels + experiment calendar (stage 4)
5. **Devil's-advocate report** — flaws → mitigations → per-flaw verdicts (stage 5)
6. **Kill criteria + revisit date** — measurable signal, dated; stage 5 refuses to close without one
7. **Final recommendation: GO / ITERATE / KILL** — recommendation only; the operator decides.
   The decision lands in `docs/product/DECISIONS.md` via devils-secretary's SECRETARY pass —
   this command never writes that file itself.

## Rules

- **No silent skips.** A stage that can't run (no markets from args or LEGAL_FACTS, WebSearch
  returns nothing usable, a needed agent missing) is reported as a **gap in the plan** with the
  reason — never omitted, never assumed fine.
- **No fabricated market numbers.** Every market/demand claim is cited and dated by the
  producing agent or marked `ASSUMPTION` in the report. An ASSUMPTION load-bearing enough to
  flip the recommendation is itself a top-3 risk.
- **Recommend, never decide.** GO starts nothing; build begins only when the operator says so —
  then the spec routes to `delivery-orchestrator` (via `/backlog`), which builds only what
  carries a `docs/product/DECISIONS.md` record (backlog-curator enforces this gate — a
  specced-but-unchallenged PRD is routed back to devils-secretary, never suggested for build).
- Safety posture per GLOBAL_PREFERENCES throughout — subagents inherit it; nothing here relaxes it.
- **Cost note:** this is a heavy multi-agent run (5+ subagents, live web research). Stage
  isolation keeps the caller's context lean — budget a full session anyway; at ~55% context,
  `/handoff`.

## Chat output — headline first

1. **Recommendation** — GO / ITERATE / KILL, one line.
2. **Top 3 risks** — sharpest first, one line each; open risks outrank mitigated ones.
3. **Report path** + per-stage one-liners (demand verdict · margin · lead channel · flaw count).
