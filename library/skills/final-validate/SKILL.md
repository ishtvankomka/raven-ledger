---
name: final-validate
description: >
  Whole-site acceptance gate for an exact website clone — confirms every original route has a
  matching local route, every page passes comparison (only intended brand differences remain),
  the build/lint/types are clean, no console errors, all links resolve, the media manifest is fully
  satisfied, and desktop + mobile reach parity. Produces a sign-off report. Use once all pages are
  built and individually compared.
always_on: false
activation: "stage 8 of the replication pipeline — invoked by replica-builder once every page is built and individually compared; also invoke whenever a whole-site clone needs its acceptance gate and a ship/blocked sign-off report"
context_cost: low
---

# Final validation / sign-off

Goal: prove the whole clone is an exact replica (minus the intended brand differences) and produce
a report the user can trust as "done".

## Checklist
1. **Coverage** — every route in `recon/clickable-map.json` / `recon/INDEX.md` has a matching local
   route; every destination link resolves (no 404s/dead internal links). Gated flows reproduced
   per recon. List any original route with no local counterpart.
2. **Per-page parity** — re-run (or confirm the latest) `replica-compare` for each page; every page
   must read PARITY (only `BRAND-DIFF` differences). Aggregate the blocker count; it must be 0.
3. **Media** — every `media-manifest.json` entry is `downloaded` (or justified `embedOnly`) and the
   asset is actually used on its page; no broken images/videos; favicons/OG images set.
4. **Build health** — the production build succeeds (e.g. `npm run build`); type-checker clean (e.g.
   `npx tsc --noEmit`); lint clean; the static route list matches the expected page set.
5. **Runtime** — load every route on the dev server; zero console errors/warnings; no hydration
   mismatches; forms/cart/search/interactions work.
6. **Responsive** — spot-check each template at **desktop (≥1280)** and **mobile (≤414)**; header
   drawer, sliders, grids and tables behave as the original does.
7. **Brand sweep** — the ONLY differences from the original are the `recon/BRAND-DIFF.md` allowlist
   (renamed brand, new domain, new logo, new contact details). Grep for any stray old-brand strings
   or leftover HTML entities.

## Output — `recon/FINAL-REPORT.md`
- A per-page table: route | compare verdict | media OK | responsive OK | notes.
- A punch list of anything outstanding (with the page + the specific gap).
- A top-line verdict: SHIP (0 blockers) or BLOCKED (n blockers) — and exactly what remains.

## Rules
- Sign off only when blockers = 0 and the only diffs are the intended brand ones.
- If something fails, route it back to `replica-fix` (or `replica-scout` for missing source data),
  then re-run this gate — don't paper over it in the report.
