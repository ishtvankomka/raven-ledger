# Design Skills — Attribution

These skills are **vendored verbatim** from their upstream repositories (final state, not links),
loaded on trigger only. Original authors retain credit; licenses below permit local use/redistribution.
Vendored-state recorded 2026-07-08; upstream commit SHA unknown — pin on next re-sync.
Loader/budgeting metadata (model, context_cost, always_on, activation, alias mapping) lives in
[`MANIFEST.md`](MANIFEST.md) — the vendoring policy forbids adding it in-file.

| Vendored path | Upstream | Author | License |
|---|---|---|---|
| `emil-design-eng/SKILL.md` | github.com/emilkowalski/skills | Emil Kowalski | MIT |
| `review-animations/SKILL.md` + `STANDARDS.md` | github.com/emilkowalski/skills | Emil Kowalski | MIT |
| `animation-vocabulary/SKILL.md` | github.com/emilkowalski/skills | Emil Kowalski | MIT |
| `impeccable/SKILL.md` | github.com/pbakaus/impeccable | Paul Bakaus | Apache-2.0 |
| `taste-skill/SKILL.md` | github.com/leonxlnx/taste-skill | leonxlnx | MIT |

Notes:
- Files are unmodified. Do **not** prepend content above their YAML frontmatter (it would break
  skill parsing) — attribution lives here instead.
- License texts are vendored per skill: `LICENSE` in each MIT skill's directory,
  `LICENSE-NOTICE.md` (Apache-2.0 short-form) for `impeccable`.
- `impeccable` and `taste-skill` also ship additional command/reference files and scripts upstream
  (impeccable's `scripts/` + `reference/`, taste-skill's `blocks/` library); only the primary
  `SKILL.md` is vendored here. If you want the full toolchains, run their installers pinned to an
  explicit version (`npx impeccable@<version> install`, `npx skills@<version> add`) — unpinned
  `npx` executes latest third-party code in the repo (supply-chain risk); review before running.
- `taste-skill/SKILL.md` is large (~1200 lines). It is **trigger-loaded only** (via the
  `design-taste-motion` stack module, `stacks/design-taste-motion.md`) and must
  never sit in the always-on set — see `../../README.md` context-budget rules.
