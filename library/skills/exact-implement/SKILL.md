---
name: exact-implement
description: >
  Implement a page as an EXACT replica from a Replica-Scout plan + local media — matching
  structure, text, media, layout, design tokens, interactions and responsive behavior, applying
  only the intended brand differences. Reuses the clone app's existing design system and keeps the
  build green. Use during the build phase, driven by recon/<route>/PLAN.md.
always_on: false
activation: "stage 5 of the replication pipeline — invoked by replica-builder as its first build step; also invoke whenever a page is being implemented from an existing recon/<route-slug>/PLAN.md plus harvested local media"
context_cost: low
---

# Exact page implementation

Goal: build the page so it matches the original, changing only the BRAND-DIFF items. You are an
implementor of the plan — not a designer of something new.

## Process
1. **Read the plan fully** (`recon/<route-slug>/PLAN.md`) + `media-manifest.json` + `content.md`.
   Note the acceptance criteria — they define "done".
2. **Place media**: copy the assets the plan references from `recon/<route>/media/` into the app's
   static asset dir (e.g. `public/images/<area>/…`, or the path the plan specifies). For embed-only
   media, reproduce the embed/iframe (or the documented placeholder) exactly as the plan says.
3. **Build the route** (for a Next.js App Router app, `app/<route>/page.tsx`; otherwise the clone
   framework's equivalent route file):
   - Reuse existing components/design system (Header, Footer, `PageHero`, the content kit,
     sliders, `brand` config). Add new components only when the plan requires structure the kit
     lacks; match the captured design tokens (fonts/colors/spacing) — extend the theme config
     (e.g. `tailwind.config`) only if a token is genuinely missing.
   - Reproduce sections in the plan's order, with the EXACT text/lists/tables/forms from the plan.
     Recreate image-only tables as real HTML `<table>`s.
   - Wire every link to the destination the plan specifies.
   - Implement the documented interactions (carousel order/timing, hover, expand, form behavior)
     and the responsive behavior (stack/hide/drawer at the stated breakpoint).
4. **Apply ONLY the brand differences** from `recon/BRAND-DIFF.md` (renamed brand, domain/emails,
   logo, contact). Everything else stays as the original.
5. **Keep it building**: real Unicode punctuation (’ “ ” —), not HTML entities inside string
   props. Run the type-checker (e.g. `npx tsc --noEmit`) and load the route on the dev server; fix
   compile/runtime errors.

## Standards
- Match, don't approximate. If the plan gives a hex color, font size, slide order, or row of
  table data — use exactly that.
- Do not invent or "improve" content. If something needed is missing from the plan/recon, stop and
  flag it for a re-scout rather than fabricating.
- Leave the page ready for `replica-compare` (note the route + viewport to check).
