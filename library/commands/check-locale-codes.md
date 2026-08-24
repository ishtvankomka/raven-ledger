---
name: check-locale-codes
description: 'Report-only audit of locale identifiers across a repo. Derives the canonical set from the project''s own locale registry, then flags every code outside it — near-miss variants, deprecated ISO aliases, separator/case drift, region forms used where a bare language is expected — plus any place an internal locale identifier is emitted to the browser without being mapped to a valid BCP-47 tag. Complements /check-translations, which compares keys inside a locale rather than the codes themselves.'
allowed-tools: Read, Grep, Glob, Bash
model: haiku
source: generalized from a project command overlay
always_on: false
activation: "invoke when locale identifiers may have drifted across config, routes, dictionaries, or markup — especially after adding a locale or when a language loads wrongly"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Why

Locale bugs are rarely translation bugs. They are identifier bugs: one file says `en-US`, another
`en_US`; a route uses a code the dictionary does not define; markup emits an internal identifier that
is not a valid language tag. Each is invisible to a key-parity checker and each breaks a real user or
crawler path.

## Step 1 — derive the canonical set (never assume one)

Find the repo's locale registry: a union type, a `LANGUAGES`/`locales` config array, an i18n config
block, or the set of dictionary files. Extract, per locale:

- the **internal identifier** used in code, routes, and dictionary keys;
- the **emitted tag** used in markup (`lang` attribute, hreflang, sitemap, `Content-Language`,
  social/OG locale) — often the same string, sometimes deliberately different;
- whether the locale is publicly routable.

If two competing lists exist, that is finding #1 — report it before anything else; everything
downstream drifts from it.

## Step 2 — find codes outside the canonical set

Grep locale-shaped identifiers where locales are used — i18n config, dictionaries and catalog
filenames, route definitions and middleware, language switchers, cookie/header handling, sitemap and
metadata builders, tests and seed data. Flag:

- **Near-miss variants** of a canonical code — a different two-letter code for the same language, or a
  bare language where the registry defines a region form (and vice versa). Report the file:line and
  which canonical code it should be.
- **Deprecated ISO aliases** — `iw` for `he`, `in` for `id`, `ji` for `yi`, and similar legacy codes
  that runtimes still accept but standards retired.
- **Separator and case drift** — underscore instead of hyphen, uppercase language subtag, lowercase
  region subtag. Canonical form is lowercase language, hyphen, uppercase region.
- **Orphans** — a code with a dictionary but no route, or a route but no dictionary, or an entry in
  the switcher that is in neither.

## Step 3 — internal identifier vs emitted tag

A project may legitimately use an internal identifier that is not the standard tag (legacy choice, a
type-enforced enum, a directory name). It is only safe while it stays internal. Verify:

- every externally emitted tag passes through the registry's mapping, not a raw interpolation of the
  internal code;
- no `lang`/hreflang/sitemap/metadata call site hand-writes a tag string;
- every canonical locale has a mapping — a missing one must fail the build, not fall through.

Report any raw internal identifier reaching markup as **high severity**: it is user- and crawler-visible.

## Output

```
CANONICAL SET (source: <path>)
  <internal> → <emitted tag>   [routable?]

VIOLATIONS (<count>)
  path:LINE  <found>  →  expected <canonical>   [class]

REVIEW (<count>)
  path:LINE  <found>  — <question>

SUMMARY  <n> canonical locales · <v> violations · <o> orphans · <m> unmapped emitted tags
```

## Rules

- Report only — no edits. Fixes route to `i18n-engineer` (dictionaries) or the locale-routing stack
  module (routes, hreflang, `lang`).
- Do not "correct" a project's internal identifier to the ISO code. Internal divergence is a decision
  the project owns; the defect is an unmapped identifier escaping to the browser, not the choice itself.
- Ignore matches that are not locales: two-letter tokens in unrelated enums, country codes in address
  forms, currency codes. Check the surrounding key before flagging.
