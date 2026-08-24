---
name: ui-conventions-contract
type: stack-module
description: 'The contract a project fills in to declare its own UI conventions — color tokens and their contrast fallbacks, type ramp, spacing, the raw primitives that are banned in favour of shared components, image sizing, and form conventions — plus the rules that hold whatever the values are. design-system-engineer and frontend-developer are instructed to pull tokens from a module like this and to invent nothing; this file is the template that makes such a module exist. The library stores no project values.'
model: haiku
always_on: false
activation: "ACTIVATE ONLY when authoring or updating a repo's own UI-conventions module, or when a UI task needs conventions and the repo has none declared yet"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Why this exists

`design-system-engineer` refuses to assume tokens and defers to "the project's brand/UI module".
`frontend-developer` does the same. If no such module exists, every UI task re-derives conventions
from whatever file it happened to read — which is how a second button style is born. This template
produces the missing module; it deliberately contains **no** colors, fonts, component names, or
locale codes of its own.

## What the project module must declare

Fill these in the repo (its `CLAUDE.md` or a project-scoped module). Anything left blank will be
guessed by somebody.

| Slot | Declare |
|---|---|
| Color tokens | Token name → value → role (background, surface, border, accent, success, danger). Roles, not raw values, at call sites. |
| Contrast fallbacks | For each accent that fails AA on some surface, the sibling token to use instead, and on which surfaces. |
| Fixed-brand exceptions | The short, closed list of literals allowed to bypass tokens (logo, legal marks). If it grows, it is not an exception list. |
| Typography | Family per role, the size/weight ramp, and any heading treatment (case, tracking). |
| Geometry | Corner radius policy, elevation/shadow policy, spacing scale, container widths. |
| Component contracts | Raw primitive → required shared component (e.g. a phone/date/currency input, an internal link, a button). One row each; this table is what `/check-component-contract` enforces. |
| Image sizing | The default sizing pattern and the named exceptions. See `/check-image-sizing`. |
| Form conventions | Label/placeholder/help-text policy, error placement, required-field marking. |
| i18n surfaces | Which dictionary each surface uses, and the locale identifiers in play (details in the i18n stack modules). |

## Rules that hold regardless of the values

- **Contrast is a gate, not a preference.** Check every text/background and UI/background pair against
  WCAG AA (4.5:1 body, 3:1 large text and UI) *before* shipping. When an accent fails on a surface,
  switch to its declared sibling rather than nudging opacity — and record the swap in the change
  description so the next reader knows it was deliberate.
- **Roles over literals.** Call sites reference tokens; hardcoded values are allowed only from the
  declared exception list. A new literal in a diff is a review finding.
- **Shared components own their primitive.** Once a shared component wraps a primitive (validation,
  formatting, locale handling, analytics), the raw primitive is banned outside that component's own
  implementation. Bypasses silently lose everything the wrapper added.
- **Shared components take strings as props** and never call an i18n hook internally — that is what
  lets two surfaces with different dictionaries use the same component.
- **Intrinsic sizing by default for images.** Declare width/height and let the image scale in flow;
  reserve absolute-fill modes for surfaces that are genuinely full-bleed. Fill plus a contain-fit
  inside a fixed-ratio container always leaves dead space, and undeclared dimensions cost layout shift.
- **Dense internal forms: labels carry the meaning.** Placeholders disappear on focus and are not
  accessible substitutes for labels; explanatory paragraphs under every field are noise in a tool
  operators use all day. Public/marketing forms may justify more guidance — decide once, declare it.
- **Reconcile divergence with variants, never a fork.** Two surfaces needing different behavior is a
  prop, not a second copy.

## Bootstrapping a project's module

1. Inventory what already exists: grep for color literals, font families, radius utilities, and raw
   primitives that a shared component was supposed to replace. The most frequent values are the de
   facto system — start from reality, not aspiration.
2. Name the tokens by **role**, then map the existing literals onto them; note every value that has no
   role (those are the accidents).
3. Fill the table above. Keep it to one screen — a convention nobody reads is not a convention.
4. Wire enforcement: `/check-component-contract`, `/check-image-sizing`, and — after a rename —
   `/check-brand-residue`.
5. Re-run `design-system-engineer` in REVIEW mode against the freshly declared system to get the
   backlog of existing violations.

## Handoffs

- Build/lift/unify shared components, or review UI against the declared system → `design-system-engineer`.
- Visual polish, motion, taste → the design-taste/motion stack module and one design skill at a time.
- Dictionary and locale-routing conventions → the i18n stack modules.
