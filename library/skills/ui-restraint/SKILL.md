---
name: ui-restraint
description: The restraint rules that keep a data-heavy product UI from looking generic — one accent reserved for things you can act on, charts that separate by ink weight instead of hue, third-party brand assets used the way their guidelines require, logged-out previews drawn as skeletons instead of borrowed data, exported share artefacts composed rather than screenshotted, and copy discipline that cuts subtitles and fact strings. Use BEFORE writing or changing UI, adding a colour, building a chart, designing a preview or an export image, or writing a project's design charter.
always_on: false
activation: "invoke before writing or changing UI, adding a colour or chart encoding, designing a logged-out preview or an export image, or writing a design charter"
context_cost: medium
---

# Restraint as a design system

The look this produces is an **editorial page with one accent**: neutrals carry
every surface and every chart, and the brand colour appears only where you can
act. It is not a style preference — it is the cheapest way to keep a product
that shows a lot of data from reading as a dashboard template.

Process note: the rules below are the *shape* of a charter. The **values** —
which hue, which type scale, which counts — are decided by whoever owns the
product, written down verbatim with a date, and only changed by them. See the
`punch-list` skill for how to record a reversal so the next session cannot
re-litigate it, and `design-system-engineer` for reviewing an existing surface
against a charter that already exists.

## The anti-goals

Most drift lands in one of four buckets. Name them in the charter so a reviewer
can point at the bucket instead of arguing taste:

1. **Accent everywhere** — accent washes, accent-tinted cards, accent chart
   fills, accent stripes. Reads as cheap and generated.
2. **A categorical rainbow in data** — six hues in every chart because the
   palette had six slots. Charts should separate by ink weight, not by hue.
3. **Gradient soup on chrome** — multi-stop gradients on headings and UI
   furniture. Chrome stays neutral.
4. **Undesigned** — hardcoded pixel values, one breakpoint, duplicated
   mobile/desktop trees, no spacing scale.

**Rule of thumb: everything is ink, except what you can click.**

## Colour

All tokens live in one place (a theme block or token file). **Never hardcode a
hex in a component** — if a colour is not in the theme, it does not belong on
the page.

- **Neutrals do the work**: a page background, a deeper well, a card surface, a
  raised surface, one line colour, and three ink weights (primary, muted,
  faint). That is the entire palette for 95% of the product.
- **One hue, interactive only.** Links, active nav and tab states, focus rings,
  primary buttons, the one indicator that reports a state the user set. Not page
  washes, not tinted cards, not chart fills, not "key numbers", not accent words
  in headings. If a static element wants to feel special, use type scale and
  spacing.
- **The alternate theme adjusts lightness, not identity.** Same hue, same
  saturation, lightness moved until it clears contrast on the other ground.
  Measure both.
- **Solid accent fills take the page-background ink**, not white — check the
  ratio rather than assuming.

### A stated brand value outranks a sampled one

If the product owner names the brand colour, that value is the brand colour, and
sampling a "better" one out of a logo, a screenshot or a competitor is how a
design gets quietly reskinned twice. Record the stated value, the date, and the
fact that it is stated. Write the counter-rule down too, because the correct
rule — *a stated brand outranks a sampled one* — is exactly the sentence that
gets applied backwards.

### Beware a neighbouring third-party colour

When the product sits beside a platform whose brand colour is a near neighbour
of yours, the two only stay legible as different things because the platform's
colour dresses **platform-branded elements and nothing else**. Never put the two
side by side doing the same job, and never darken or lighten the platform's
value for your themes — their guidelines fix it.

### Data — ink weight, never hue

Series separate by **ink at decaying opacity by rank**. A highlighted value is
full-strength ink against a muted field; everything else steps down. Put the
ramp in one module so every chart shares it.

**Never encode meaning in weight alone**: pair it with the label and the number
that are already in the row.

Hue in data is allowed only as a **named, enumerated exception**, each with a
reason written next to it. Three that legitimately qualify:

1. **The colour IS the data** — a feature whose subject is literally colour
   (sampled artwork, a palette, a paint mixer). Everything else on that page
   stays neutral.
2. **Shades of the one accent, for exactly one internally ranked series.**
   Every value is the same hue at a different strength, so it can only express
   rank *inside one measurement*; two unrelated series through it would read as
   steps of a scale that does not exist. Prefer stroke over fill for summary
   tiles — a row of solid accent plates makes three summary numbers the loudest
   thing on the page, and a filled tile claims "you can act on this" about a
   reading.
3. **A positional ramp where position is the meaning** — a depth or severity
   scale. Ship a paired "ink on this band" token per step so nobody has to guess
   which text colour clears AA on it, and put the measured ratios in the token
   comment.

Rank still may not be carried by colour alone in any of them.

### No decorative stripes

A coloured stripe or bar glued to the edge of a card, ticket or block is
decoration pretending to be structure. Borders and spacing separate things.

## Third-party brand assets are not yours to bend

When you display another platform's content, their design guidelines outrank
every visual preference you have — breaking them risks API access.

- **Use the right primitive per subject**: album/product artwork square at the
  radii the provider specifies; a person or artist circular; the user's own
  photo circular. Never hand-roll an `<img>`.
- **Nothing may be drawn on top of artwork** — no rank badges, no play buttons,
  no text, no logos, no gradient scrims. Put them beside it.
- Never crop, stretch, blur, animate or recolour artwork; keep metadata legible
  and unaltered (truncate, do not rewrite).
- **Route every appearance of their mark through one component** that enforces
  the correct cut (light mark on dark, dark on light), the published minimum
  sizes, and the required clear space. A raw image tag is how a white icon ends
  up on white paper.

Two amendments worth building into that component:

- **Clear space may be SHARED with the layout's own gap.** The guideline asks
  for empty space around the mark; it does not ask you to reserve it twice. Let
  the caller declare the gap it already supplies, in the same unit as the
  layout's spacing scale, and subtract it from the component's own padding,
  never below zero. The mark's size never changes.
- **A dense list may drop the per-item mark at small widths** when attribution
  survives elsewhere — each row links to a detail page that carries the full
  mark, and the footer carries the provider line. A mark that eats 13% of a
  phone row is squeezing the data. This is the only place a mark may be absent;
  sign-in buttons, detail pages and exported images keep theirs at every width.

Audit both with a grep for the mark's asset names and for the props above.

### When a capability is removed, the element's meaning changes

If a write action goes away (scope removed, endpoint retired), the control
becomes a **mark, not a control**: no hover affordance, no pressed state, no
focus stop, and a name that reads as a state rather than a verb. Give it three
honest states — on, off, and *not yet known* — and render the last two
identically, because an outline icon that fills in a moment later is a lie the
user cannot correct. The cascade for the rest of that removal is the
`feature-lifecycle` skill.

## Type

- One sans family for everything; at most one display face, scoped to the one
  surface that earns it.
- Display sizes get tight tracking; small-caps labels get generous tracking.
- **Headings are plain ink** — never a gradient across a line. If the charter
  grants an animated/gradient heading, it is granted to **named callers by
  name**, and the list is closed.
- Exactly **one `h1` per page**, owned by the page-header primitive.

### Chart labels are HTML, not SVG text

SVG `<text>` scales with the viewBox, which is how one chart ends up rendering
its labels at 25px while another's sit at 11px. Keep marks in SVG and position
HTML labels over them by percentage, with exactly two utilities (a small one and
a strong one) for the whole product.

## Space and shape

- The spacing scale only. No arbitrary pixel values in components.
- One card radius, pills fully round, third-party artwork at the radii its
  guidelines require.
- Page rhythm: one container width, sections separated by one or two steps of
  the scale.
- **Borders do the work of separation; shadows are used almost never.**

## The page contract

Every titled page is built the same way, so a user learns the furniture once and
finds it in the same corner on all twenty pages:

```
page header (title)  +  toolbar( period → view/style → share → export )
```

- The toolbar holds one to four controls **in that order**, and takes a full row
  under the title at small widths so a two-line title never collides with a
  range switcher.
- Decide once **which pages get share and export** — e.g. every feature page and
  no summary page — and hold it. Blocks on a summary page have feature pages
  behind them; that is where their controls live.
- **Controls are icon-only**, one size, verb in the `aria-label`. A toolbar is a
  row of equal round buttons.
- **Share and export travel together** in one non-wrapping container. The
  toolbar may wrap the pair as a unit; it may not wrap through the middle of it.
- **Every control that runs says so**: a spinner that occupies exactly the box
  of the icon it replaces, and the control goes inactive until the action ends,
  so a round button never changes size when it starts working.

### Preview counts

A preview list shows **3, 5 or 10** items. Not 6, not 8 — those read as
"whatever fit" rather than as a decision. The one exception is a count that is a
**shape**: nine faces in a three-by-three grid, with the grid pinned to three
columns so it can never break to four and leave one face on a row of its own. If
a count cannot be defended as a shape, it is 3, 5 or 10.

Two blocks side by side should end level: let the shorter one distribute its
rows so neither block trails the other.

### No single-line fact strings

`142 items · 12 flagged · 3 archived` is banned everywhere. It reads as a
caption, aligns nothing, and hands a screen reader one run-on line. Use a
label/value list primitive (or a two-to-four-item grid for short facts).

### Feature blocks share one wrapper and one promise

Each must carry a real graphic that symbolises the block. A title over a
paragraph of text is not a feature block; it is an announcement that a feature
is missing.

## The exported share artefact

**A share image is a BUILT ARTEFACT, not a screenshot.** It is composed from
scratch: not the page clipped, not the page cloned, not the page at another
width. The platform mechanics — off-screen staging, activation rules, download
anchors — are the `web-share-capture` skill. What belongs here is its anatomy:

1. the platform's mark, large, in the platform's own colour,
2. a **short title** naming the feature — not the page's `h1`, which is a
   heading in a navigation context; a picture travelling on its own has to
   introduce itself. No count in it: the rows are right there to be counted.
   Omit the title entirely where the body already sets a name in display type.
3. an optional **subtitle** — the feature's own second line where a reading has
   one,
4. an optional **period/scope line**, the quietest line on the card. Welding it
   into the title with a middot gives a caveat the same weight as the subject.
5. **the content**, clipped to the deliberate preview count,
6. a **credit line** (what this is and where it came from),
7. the **product wordmark** — one of the very few surfaces where the accent
   dresses something that is not a control.

A generous gap separates the content from **both** marks; the clear space a
platform requires around its mark absorbs some of it at the top and nothing
absorbs it at the bottom.

**None of those may appear on the page itself.** They exist so a picture
travelling without you can say where it came from; on the page they are clutter,
because the user is already here.

Give the card body a small set of shared primitives (rows, tiles, a figure, a
facts block) so fifteen cards do not become fifteen layouts, and hand-roll only
when the feature **is** a picture — then reuse the page's own graphic component.
Anything inside the card is sized by its **container**, never by viewport
breakpoints: the card is a fixed width wherever it is built, so a viewport
breakpoint inside it asks a question about a box it cannot see.

Decide which features are readings (share + export) and which are tools you
*act* with (neither). A builder or a recommender is not a reading.

### Share vs export are different verbs

- **Share** sends a **picture** somewhere.
- **Export** takes a **list** out of the app as data (CSV/XLSX/JSON) — its own
  verb, its own glyph, always.

Never use the share sign for an export. Choose the share/download face by
**platform** (phone → share sheet, desktop → download), not by a capability
query: desktop browsers answer yes to "can share" and then open a sheet nobody
asked for.

## The logged-out preview is the core feature, alone

A preview shows the feature and **nothing else** — no range switcher, no
view/style toggle, no share, no export, no info tooltip, no "see more", no
secondary call to action. A shell primitive owns the heading, an `inert` wrapper
around the demo, the fading skeleton and the sign-in call to action; the page
owns the demo.

**And the demo is a DRAWN SKELETON, not sample records.** Both halves bind:

- No real third-party data or artwork for preview purposes — a locked roster of
  real names and covers is a licensing problem and it dates.
- A stack of grey bars is equally out: it reads as a loading state and looks
  nothing like the block it is standing in for.

What ships instead: each page's logged-out branch reproduces **its own feature's
geometry** and replaces only the words. Same components where they can be
reused, same row heights, same breakpoints, same radii, with skeleton
primitives standing where names, figures and artwork go. A preview row must be
exactly as tall as a real one.

Words that survive are the ones belonging to nobody: column and field labels,
category names, rank numerals. A name, a title, a cover or a count is data and
gets a bar. Bar widths are hand-set and unequal per row — an even stack reads as
loading.

**Reuse the feature's own component before rebuilding its geometry.** If the
real component can be taught to draw itself empty, teach it; a two-hundred-line
replica of a scene will drift from the page on any change to either.

**Skeleton variation is DETERMINISTIC.** "Randomised" means the shapes vary so
the block does not read as a spinner — it does not mean `Math.random()`. Use an
integer hash of the item's index; never `Math.random()`, and never a
`Math.sin`-based hash. Both break hydration, the second one subtly.

And if there is no sample data, there is no "* Sample data" note. Delete the
disclaimer with the thing it disclaimed.

## Charts answer a hover

A bar or a point that means something must say what it means when you point at
it — the label and the value, in a real panel, straight away. Take a hint per
column/point and render it through CSS that also responds to `:focus-within`.
**Never a native SVG `<title>`**: it waits a second, the OS styles it, and over
a narrow bar most people never see one.

A long run of columns needs **contrast between neighbours**: alternate two ink
weights band to band on a grouping key. That is weight, never hue, and it
encodes a *grouping* rather than a rank. Sparse axis labels are never truncated
— they overhang their own column, because nothing beside them is labelled.

## Width and boxes

- The page column has one width. A feature that is one picture gets the whole
  column.
- **Do not box a single feature.** A page whose entire content is one chart must
  not wrap it in a card, and certainly not in a card inside a bordered plate.
  Components that appear both alone and inside a grid take a `bare` flag and let
  the caller own the surface.
- Wide is not unbounded: a drawing scaled to the full column becomes an
  apparatus. **Cap the drawing, never the page.**
- A standalone image gets air, not a frame: no bordered figure, no caption bar
  welded to its edge. Captions in adjacent columns should be the same component
  at the same step so the columns end level.
- **Things under a picture must line up with the picture.** If a caption belongs
  to a part of a drawing, derive its position from the drawing's own geometry
  (export the channel widths) — a grid of even columns puts a caption in the
  middle of nothing.

## Painting a whole route

A route may re-colour the header, footer and document, and the mechanism is
worth copying: the page marks itself with a data attribute, and the stylesheet
uses `:has()` to **re-base the neutral tokens** on those elements. It never
restyles a component and never invents a colour; every value is a mix of that
route's ramp with the ink the ramp already ships. Measure the result: text AA,
borders 3:1, in both themes.

If that route exports a picture, **keep the picture in its weather** — and take
the ink the ramp ships *for* that band, or the alternate theme composes
near-black on navy. Bleed by **paint, not layout**: let the background paint the
full card width behind a normally-margined body, rather than pulling the body
out with a negative margin. Every card owes its content the same margin.

## Motion and accessibility floor

- Subtle and short: colour transitions of 150–250ms, one entrance animation for
  section arrivals. No parallax, no bouncing, no auto-playing gradients. Respect
  `prefers-reduced-motion` — and where an animation is granted by name, reduced
  motion keeps the colour and stops the travel.
- All ink tones clear AA on every surface; record the measured ratios beside the
  tokens.
- Every interactive element reachable and visible on keyboard focus; icon-only
  buttons carry an `aria-label`.
- **Never encode meaning in colour or weight alone** — pair it with text or
  shape. This matters more when charts separate by opacity.

## Checklist before shipping a screen

1. Is the accent on anything that is not clickable or selected? Remove it.
2. Is any hue anywhere outside the enumerated exceptions? Remove it.
3. Is any gradient on UI chrome more than two stops? Replace it.
4. Is a third-party colour on a non-third-party element, or their mark rendered
   outside the one mark component? Fix both.
5. Is anything sitting on top of artwork? Move it beside. Is the primitive the
   right shape for the subject?
6. Do all chart labels use the two label utilities?
7. Header + toolbar in the standard order, controls icon-only, share and export
   in one container?
8. Any preview showing 6 or 8 items? Make it 3, 5 or 10.
9. Any `a · b · c` fact string? Replace with the label/value list.
10. Any subtitle, tagline or lead paragraph? Delete it or move it behind the
    info tooltip. More than one tooltip on the screen, or a heading repeating
    the one above it? Cut it.
11. Are the export-only marks (platform mark, credit line, product wordmark) on
    the page? They belong only in the exported image.
12. Does it hold at the narrowest supported width, and at the widest without
    becoming a lonely column?
13. One `h1`, sensible heading order, alt text decided (meaningful or `""`).
14. Would this look at home in a design magazine, or in a crypto dashboard?

## Copy

The screen should **show** the thing, not describe it. A page gets a title and
the data; the "why" goes behind an info tooltip on hover/focus. No lead
paragraphs under headings, no bullet lists explaining a feature rendered
directly below. If an explanation cannot fit in a tooltip, it belongs in the
FAQ.

**No subtitles.** A block is: name → picture → numbers. A sentence describing a
picture that is already on the screen goes behind the tooltip or it does not
ship. The bar for an exception is a **figure under a figure** (a percentage
under the number it qualifies), never a sentence about one.

**One info tooltip per feature.** A page title with a tooltip, then a card whose
eyebrow repeats the title verbatim with its own tooltip, is three headings for
one reading. The route composes the explanation if it has two halves to say.

Numbers are shown, never narrated. A count belongs in a labelled row, not glued
to two other counts with middots.
