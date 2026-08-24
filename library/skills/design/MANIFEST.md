---
name: design-skills-manifest
description: Loader sidecar for the five vendored skills in skills/design/ — carries the budgeting metadata (model, context_cost, always_on, activation) that the verbatim-vendoring policy forbids adding to the skill files themselves. Read this to budget/route; never edit the vendored SKILL.md/STANDARDS.md files.
model: haiku
source: library-native (audit fix — README budgeting rule vs vendoring policy)
always_on: false
activation: "read when budgeting or routing skills/design/* via stacks/design-taste-motion.md"
context_cost: low
inherits: ../../GLOBAL_PREFERENCES.md
---

# Design Skills — Loader Manifest

Budgeting frontmatter for the vendored skills, kept out-of-file because the skills are vendored
verbatim (see `ATTRIBUTION.md`). All five: `always_on: false`, activation **explicit via the
`stacks/design-taste-motion.md` router only, one skill at a time** — never load the whole set.

| Directory | Canonical name | Frontmatter self-name | Lines (measured) | model | context_cost | always_on | activation |
|---|---|---|---|---|---|---|---|
| `emil-design-eng/` | emil-design-eng | same | 679 | sonnet | high | false | explicit via design-taste-motion only |
| `review-animations/` | review-animations | same | 112 (+188 `STANDARDS.md` = 300) | sonnet | medium | false | explicit via design-taste-motion only |
| `animation-vocabulary/` | animation-vocabulary | same | 173 | sonnet | medium | false | explicit via design-taste-motion only |
| `impeccable/` | impeccable | same | 174 | sonnet | medium | false | explicit via design-taste-motion only |
| `taste-skill/` | taste-skill | `design-taste-frontend` (alias — loaders keying on frontmatter must map it to this dir) | 1206 | sonnet | high | false | explicit via design-taste-motion only |

## Operational notes

1. **emil-design-eng — never invoke bare.** Always attach a concrete question/task; bare
   invocation triggers its mandatory course-ad response and stalls autonomous flows.
2. **impeccable — RULES-ONLY.** Its Setup, command table, pin, and hooks reference `scripts/` and
   `reference/` files NOT vendored here. Use only the self-contained sections: Design guidance,
   General rules, Absolute bans, AI slop test. Skip Setup/commands/pin/hooks.
3. **taste-skill — landing/portfolio/marketing only.** It refuses dashboards, dense product UI,
   and native mobile. Its `blocks/` library is not vendored — do not hunt for or create it.
4. **review-animations** — upstream `disable-model-invocation: true` maps to
   `always_on: false` / `activation: explicit` here. Most automatable skill in the set — pair
   with `agents/test-automator.md` screenshots for autonomous visual QA.
5. **animation-vocabulary** — its "/vocabulary page sync" line refers to the upstream project;
   it is a no-op here, ignore it.
6. **ARBITRATION (motion code):** emil-design-eng / review-animations doctrine wins over
   taste-skill / impeccable examples. Narrow any `transition: all` to explicit properties.
