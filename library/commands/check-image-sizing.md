---
name: check-image-sizing
description: 'Report-only audit of how images are sized in the UI. Flags absolute-fill images with a contain-fit inside fixed-ratio containers (the pattern that leaves dead space in cards), images shipped without intrinsic dimensions (layout shift), and stretched aspect ratios — judging each hit by its surrounding container so intentional full-bleed heroes, lightboxes, and gallery overlays report as OK. Emits file:line plus the suggested rewrite for batch remediation.'
allowed-tools: Read, Grep, Glob, Bash
model: haiku
source: generalized from a project command overlay
always_on: false
activation: "invoke when auditing UI images, chasing unexplained whitespace inside cards, or investigating layout shift before a release"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## What this looks for

Three defects, in order of how often they ship:

1. **Fill + contain inside a fixed-ratio box.** An absolutely-filled image told to preserve its aspect
   ratio inside a container whose ratio differs *always* letterboxes — the dead space above/below is
   the symptom users report as "the card looks broken". The fix is intrinsic sizing: declare the real
   width/height and let the image scale in flow.
2. **No intrinsic dimensions.** An image without width/height (or an equivalent reserved ratio) has no
   reserved space until it loads — measurable layout shift, worst on slow connections.
3. **Forced ratio.** A cover-fit with a hardcoded height that crops differently at each breakpoint, or
   a stretch-fit that distorts the subject.

## Steps

1. **Locate candidates.** Grep the UI source for image elements and for fit/fill utilities and props
   (contain, cover, fill, and the framework's own fill/layout prop). List every file:line.
2. **Judge by container, not by the match.** For each hit read ~5 lines around it and classify the
   parent:
   - Full-bleed hero/banner, lightbox, gallery overlay, or a deliberately square avatar/logo slot →
     **OK**, and say which one. Absolute fill with a cover-fit is correct there.
   - Card, tile, list row, or any box with a fixed height or forced aspect ratio → **violation**.
   - Cannot tell from context → **review**, with the question to answer. Never guess.
3. **Check the declared convention.** If the repo's UI-conventions module declares an image sizing
   rule and named exceptions, that declaration wins over the defaults above — cite it in the report.
4. **Propose the rewrite.** For each violation give the current snippet and the corrected one:
   intrinsic width/height plus full-width, height-auto scaling, keeping whatever optimization flags
   the repo already uses on its other images. Do not introduce a new prop the codebase never uses.

## Output

Markdown, grouped by file, ordered violations → review → OK:

```
path/to/file:LINE  VIOLATION  fill + contain inside a fixed-ratio card
  current:  <snippet>
  suggest:  <snippet with intrinsic dimensions>

path/to/file:LINE  OK  full-bleed hero — cover-fit is intentional
```

Close with counts per class and a one-line verdict. If nothing is wrong, say so plainly rather than
padding the report.

## Rules

- Report only; no edits. Remediation routes to `frontend-developer`.
- Never flag a full-bleed surface just because it uses absolute fill — that is the correct tool there,
  and false positives here train people to ignore the report.
- Non-UI images (email templates, generated documents, test fixtures) are out of scope unless asked.
