---
name: replication-plan
description: >
  Turn captured content + harvested media into a precise per-page plan for EXACT replication —
  the same page, not a similar one. Specifies, section by section, the structure, the exact text,
  which local media asset goes where, the design tokens, the components to build/reuse, the
  interactions/states, the responsive behavior, and explicit acceptance criteria. Use during
  website recon, after content-capture and media-harvest.
always_on: false
activation: "stage 4 of the replication pipeline — invoked by replica-scout after content-capture and media-harvest; also invoke whenever a page's captured content plus local media must become a per-page plan complete enough for a builder to reproduce the page blind"
context_cost: low
---

# Per-page exact-replication plan

Goal: a `recon/<route-slug>/PLAN.md` so complete that the builder reproduces the SAME page blind.
This plans exact replication — not "how to build something similar."

## Inputs
`content.md`, `states.md`, `media-manifest.json` for the route, and `recon/BRAND-DIFF.md` (the only
allowed differences). Cross-reference the live page once more to confirm section order.

## PLAN.md structure
1. **Header** — route, original URL, page `<title>` + meta, intended brand changes that apply here
   (cite BRAND-DIFF), and overall layout (header/footer/hero/columns).
2. **Section-by-section breakdown** (in document order). For EACH section:
   - Purpose + structure (grid/columns/component type).
   - **Exact content**: the verbatim text/headings/list items/table data (from content.md), with
     rebrand spots marked.
   - **Media**: the exact local asset to use (`media/…` path from the manifest) and how (hero bg,
     inline img, video poster, embed URL, sprite slice). Note dimensions/aspect.
   - **Design tokens**: fonts, sizes, weights, colors (hex), spacing, radius, shadows for this
     section (from the computed-style capture).
   - **Interactions/states**: hover, click, expand, carousel timing, form behavior, validation.
   - **Responsive**: what changes at mobile (stack/hide/drawer), exact breakpoint.
   - **Links**: every destination in this section (from clickable-map) and where it points.
3. **Components** — which existing app components to reuse (Header, Footer, PageHero, content kit,
   sliders) and which new ones to create; the props each needs.
4. **Acceptance criteria** — a concrete checklist the builder/comparator will verify. Write each
   line as a checkable shape, filling every placeholder from THIS page's capture (`content.md`,
   `media-manifest.json`, the computed-style block) rather than from memory:
   - "`<carousel/gallery>` has N slides in this order: …"
   - "`<named section>` heading uses `<font-family>` `<size>` `<color-token-or-hex>`"
   - "`<named table>` has N rows in this order, with these cell values"
   - "primary CTA links to `<route>`"
   - "matches the original at desktop AND mobile"

   Be specific and checkable: a criterion the comparator cannot fail is not a criterion. Numbers,
   orders, exact strings, exact routes, exact token values — never "looks right".
5. **Gaps** — anything recon couldn't get (missing media, auth-walled content) + the chosen
   fallback, so the builder doesn't invent.

## Rules
- Plan for the SAME page: same sections, order, text, media, layout, tokens, behavior. Only the
  BRAND-DIFF items may differ.
- Reference media by local manifest path, never by remote URL.
- Don't hand-wave ("a hero section") — specify the actual content, asset, and tokens.
- Keep verbatim original text verbatim in the plan; the builder paraphrases nothing unless the
  plan explicitly says to (e.g., a rebrand substitution).

**Done when:** the PLAN.md + the media folder, with no live site, are sufficient to rebuild the
page exactly and to write the comparator's checklist.
