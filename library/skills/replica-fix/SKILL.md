---
name: replica-fix
description: >
  Resolve the discrepancies a comparison found between a local replica page and the original —
  edit the page/components/design tokens, re-place or re-harvest missing media — then re-run the
  comparison on that page and loop until the only remaining differences are the intended brand
  ones. Keeps the build green. Use after replica-compare reports findings.
always_on: false
activation: "stage 7 of the replication pipeline — invoked by replica-builder whenever replica-compare reports findings; also invoke whenever a recon/<route-slug>/diff.md must be driven to parity, fix by fix, with a re-compare closing each one"
context_cost: low
---

# Fix replica discrepancies

Goal: drive a page from "has findings" to "parity" (only intended brand differences remain),
verifying each fix rather than assuming it.

## Process
1. Load `recon/<route-slug>/diff.md`. Work blockers first, then minor.
2. For each finding, apply the right fix:
   - **MISSING content** → add the exact text/section/list/table/row from `content.md`/`PLAN.md`.
   - **DIFFERENT text** → correct to the original wording (unless it's an intended brand change).
   - **DIFFERENT tokens** (font/size/color/spacing) → match the captured value; extend the theme
     config (e.g. `tailwind.config`/`globals.css`) only if the token is genuinely missing.
   - **MISSING/wrong media** → use the correct `media/` asset; if it was never harvested, request
     a targeted re-run of **media-harvest** for that URL, then place it. Don't substitute a
     look-alike.
   - **EXTRA** (something the local page invented) → remove it so it matches the original.
   - **Interaction/responsive** → fix the behavior/breakpoint to match the captured states.
3. Keep the build green: real Unicode punctuation in markup, type-checker clean (e.g.
   `npx tsc --noEmit`), route loads without console errors.
4. **Re-run `replica-compare` on this page.** A finding is only closed when the re-compare no
   longer reports it. Loop fix → compare until the verdict is PARITY.

## Rules
- Don't mark a page fixed without re-comparing it — no "should be good now".
- Never fabricate to close a gap; escalate missing source data to a re-scout.
- Don't introduce new differences while fixing (re-compare catches regressions — heed them).
- Touch only what the findings require; keep shared components stable for the other pages.
