---
name: replica-compare
description: >
  Validate a local replica page against the live original and pinpoint every discrepancy —
  classifying each as MISSING, DIFFERENT or EXTRA with exact location and expected-vs-actual,
  across text, DOM/section order, media, layout, computed colors/fonts/spacing, interactions and
  both desktop + mobile. Excludes the intended brand differences. Use after exact-implement.
always_on: false
activation: "stage 6 of the replication pipeline — invoked by replica-builder after exact-implement and again after every replica-fix pass; also invoke whenever a local page must be diffed against a live original and each discrepancy classified MISSING/DIFFERENT/EXTRA"
context_cost: low
---

# Replica vs original comparison

Goal: a precise discrepancy list for one page. The bar: a reviewer flipping between local and
original should see ONLY the intended brand differences.

## Setup
- Local replica on the dev server (Preview MCP for controllable viewport).
- Live original (`<original-base-url>/<route>`, from `recon/BRAND-DIFF.md`) in the browser MCP.
- Load `recon/<route-slug>/PLAN.md` acceptance criteria and `recon/BRAND-DIFF.md`.

## Compare these dimensions
1. **Text/content** — diff the visible text in order (use `get_page_text` on both). Every heading,
   paragraph, list item, table cell, label, button text. Flag missing/changed/extra wording.
   (Brand name/domain/contact differences are expected — ignore those.)
2. **Structure** — section order and nesting; same components/blocks in the same sequence; same
   number of slides/cards/rows/columns.
3. **Media** — every image/video present and the SAME asset (compare by the manifest sha256 or by
   eye); correct placement, aspect, and poster; embeds reproduced.
4. **Design tokens** — `getComputedStyle` on matching elements on both sites; compare font-family,
   size, weight, line-height, text/background/border colors (hex), padding/margins, radius,
   shadows. Report concrete deltas (e.g., "h1 22px local vs 28px original").
5. **Interactions/states** — hover, focus, dropdowns, carousel order/timing, form fields/validation,
   empty/error states.
6. **Responsive** — repeat the key checks at **desktop (≥1280)** and **mobile (≤414)**; confirm the
   same stacking/hiding/drawer behavior and breakpoint.
7. **Visual** — screenshot both at the same viewport and overlay/compare region by region; note
   any layout/spacing/color drift the token check missed.

## Output — `recon/<route-slug>/diff.md`
A table, each row: `severity (blocker/minor) | dimension | location | expected (original) | actual
(local) | classification (MISSING/DIFFERENT/EXTRA)`. End with a one-line verdict: PARITY (only
brand diffs remain) or a count of blockers. Explicitly list which observed differences are the
allowed brand ones (so they're not re-reported).

## Rules
- Be exhaustive and specific — cite the exact element/section, not "the hero looks off".
- Never pass a page with hand-waving; if unsure whether something differs, measure it.
- Exclude ONLY the `BRAND-DIFF.md` allowlist; everything else that differs is a finding.
