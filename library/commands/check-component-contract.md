---
name: check-component-contract
description: 'Report-only audit that every raw primitive a shared component was built to replace is actually going through that component — raw inputs of a wrapped type, plain anchors where a routing link is required, bare buttons/images/forms where a shared wrapper owns the behavior. Reads the pairs from the repo''s UI-conventions module (or takes them as arguments), reports each bypass as file:line with the prop-mapped replacement, and excludes the component''s own implementation.'
allowed-tools: Read, Grep, Glob, Bash
model: haiku
source: generalized from a project command overlay
always_on: false
activation: "invoke to verify shared-component usage across a codebase, or after adding/refactoring a shared wrapper component"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Why

A shared wrapper exists because the raw primitive is not enough: validation, formatting, locale
handling, accessibility wiring, analytics, error states. Every bypass silently drops all of it, and
the resulting inconsistency reads as a UX bug long before anyone traces it to the markup.

## Inputs

```
/check-component-contract [<primitive> => <component> ...]
```

With no arguments, read the pairs from the repo's UI-conventions module — the table mapping a raw
primitive to the shared component that must wrap it. Typical pairs (project decides the real list):

| Raw primitive | Required wrapper |
|---|---|
| An input of a type the design system wraps (phone, currency, date, search) | that shared field component |
| A plain anchor for an in-app destination | the framework's routing link, or the shared link |
| A bare button element | the shared button (variants, loading, disabled semantics) |
| A raw image element | the shared/optimized image component |
| A native form submit flow the app handles itself | the shared form wrapper |

If the repo declares no pairs and none were passed, say so and stop — do not invent a contract.

## Steps

1. **Find the wrapper.** Locate each shared component's definition and its import path; that file is
   the one legitimate home of the raw primitive. Note its props for the remediation mapping.
2. **Grep the primitive** across UI source, excluding the wrapper's own implementation, generated
   output, and vendored code.
3. **Catch the variants a plain grep misses:**
   - the primitive built from an object/config (`type: 'tel'`, a field-schema entry) rather than markup;
   - a dynamic type expression that can evaluate to the wrapped type;
   - a third-party form library rendering the primitive through its own field component;
   - fields whose label or name says the wrapped concept while the input is generic — the wrapper was
     never adopted there at all.
4. **Cross-check adoption.** List the files that import each wrapper. A UI area with zero imports and
   several near-miss fields is the real gap, not the one stray element.

## Output

```
CONTRACT  <primitive> => <component>   (defined at <path>)
  BYPASS   path/to/file:LINE
    current: <snippet>
    fix:     <wrapper with props mapped from the current attributes>
  REVIEW   path/to/file:LINE  — <why it is ambiguous>

  adopted in <n> files · <b> bypasses · <r> to review
```

Close with a one-line verdict per contract.

## Rules

- Report only; no edits. Remediation routes to `frontend-developer`, or to
  `design-system-engineer` when the finding is that the wrapper itself lacks a needed variant.
- Never propose a fix that adds a prop the wrapper does not have — flag the missing capability instead.
- The wrapper's own file, its tests, and its stories are not bypasses. Neither is a primitive in a
  context the wrapper explicitly does not cover; if that recurs, the contract needs an exception row.
