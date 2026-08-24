---
name: content-capture
description: >
  Scan the whole contents of a web page for exact replication — full text in order, heading
  hierarchy, lists, tables, forms (fields/labels/placeholders/options), meta + JSON-LD, the
  computed design tokens (fonts, colors, sizes, spacing), every UI state, and both desktop and
  mobile renderings. Use during website recon after the clickable inventory.
always_on: false
activation: "stage 2 of the replication pipeline — invoked by replica-scout after clickable-inventory; also invoke standalone when a page's full text, structure, forms, metadata and computed design tokens must be captured precisely enough to rebuild it with the live site gone"
context_cost: low
---

# Whole-page content capture

Goal: capture everything on the page as source data, precise enough to rebuild it exactly. Capture
BOTH the raw HTML (server output) and the rendered DOM (after JS) — they differ.

## 1. Raw + rendered
- Raw: `curl -s <url> -o raw.html`.
- Rendered DOM: in browser MCP, `get_page_text` (reading order) and `document.documentElement.outerHTML`
  via the JS tool for the post-JS structure. Save both.

## 2. Structure & text (in document order)
Walk the main content region and record, in order: every heading (h1–h6 with level), paragraph,
list (ordered/unordered + items), blockquote, table (as rows/cells → reproduce later as an HTML
table even if the original was an image), figure/caption, and button/link label. Preserve EXACT
wording verbatim — it is the builder's source. Note where each brand mention must be rebranded.

## 3. Forms & interactive content
For every form/field: name, type, label, placeholder, default, options (selects/radios),
required?, validation text, and the submit action. Record search, filters, sort, pagination,
carousels (slide count + order), and any embedded widgets (maps, video players, flipbooks).

## 4. Metadata & semantics
`<title>`, meta description/keywords/robots, canonical, OpenGraph/Twitter tags, favicons,
hreflang, and any JSON-LD / microdata blocks.

## 5. Design tokens (computed styles)
Via `getComputedStyle` on representative elements, record: font-family/size/weight/line-height per
text role (h1, h2, body, nav, button, footer), text + background + border colors (hex), section
padding/margins, container max-width, border-radius, box-shadow, and the breakpoints where layout
changes. These are what make a rebuild match rather than approximate.

```js
const pick = (sel) => { const e=document.querySelector(sel); if(!e) return null; const c=getComputedStyle(e);
  return {sel, font:c.fontFamily, size:c.fontSize, weight:c.fontWeight, lh:c.lineHeight,
          color:c.color, bg:c.backgroundColor, pad:c.padding, radius:c.borderRadius}; };
JSON.stringify(['h1','h2','p','nav a','button','footer'].map(pick).filter(Boolean));
```

## 6. States & viewports
Capture each meaningful state: default, hover, focus, active, expanded/collapsed, error, empty,
loading, and logged-out vs logged-in where reachable. Capture **desktop (≥1280)** and **mobile
(≤414)** renderings (resize/emulate); note what stacks, hides, or turns into a drawer. Screenshot
each state for the builder + comparator.

## 7. Output — `recon/<route-slug>/content.md` (+ `states.md`)
A structured dump: meta block, then ordered content with headings/lists/tables/forms, then a
"Design tokens" section, then a "States & responsive" section. Tables and form schemas go in
machine-friendly form. Verbatim text stays verbatim; mark rebrand spots inline.

**Done when:** the content.md alone (no live site) is enough to reproduce every word, the table
data, the form fields, the fonts/colors, and the responsive behavior of the page.
