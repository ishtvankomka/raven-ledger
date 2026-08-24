---
name: i18n-dictionary-architecture
type: stack-module
description: 'Rules for apps whose UI translations live in the repo rather than a translation service: how to detect the storage shape (typed module, JSON catalogs, DB rows), how to keep locales in lockstep, and — for monorepos where several app surfaces each own a separate dictionary — the ownership boundary that stops one surface''s keys leaking into another. Supplies the per-surface config that i18n-engineer refuses to guess.'
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF UI translations are stored in-repo (typed dictionary module, JSON/YAML catalogs, or seeded DB rows) — especially when more than one app surface owns its own dictionary"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Detect before editing (never assume)

Storage shape, primary locale, and the locale set are project facts. Read them out of the repo:

| Signal | Storage shape |
|---|---|
| A `.ts`/`.js` module exporting one object per locale, plus a `Locale` union or `Translations` interface | **Typed dictionary module** |
| `locales/<code>.json`, `messages/<code>.json`, `public/locales/<code>/*.json` | **Catalog files** |
| A translations table/model with a `locale` column | **DB-backed** |

Then record, in the project's own module or `CLAUDE.md` — not here: the dictionary path per surface,
the primary/source locale, the full locale set and where it is declared, and the runtime accessor
(`t('key')`, `dict[locale][key]`, a `useI18n()` hook — detect it, do not assume `t()`).

## Ownership boundary (monorepo, multiple surfaces)

A repo can hold several dictionaries — e.g. a public site and an internal/staff app — with different
locale sets, different tone, and different owners. They are **separate scopes**:

- Exactly one module/agent owns each dictionary. Declare the owner next to the path.
- A task scoped to one surface never edits another surface's dictionary. If a string clearly belongs
  to the other surface, **skip it and report it** — do not cross-edit "while you're in there".
- Locale sets do not have to match across surfaces, and a code present in one is not evidence it is
  supported in the other. Read each surface's own declaration.
- Shared UI components take strings as **props**; they never call the i18n hook internally. That is
  what keeps a shared component usable from two surfaces with two different dictionaries.

## Typed-dictionary discipline

When the dictionary is a typed module, the compiler is the parity gate — use it:

1. Update the interface / key union **first**, then every locale object. The typecheck fails loudly
   on any locale missing the new key, which is stronger than any parity script.
2. Add a key to **all** locales in the same change. A half-added key is a runtime hole that no test
   catches until a user switches language.
3. Preserve the file's existing ordering and grouping; never reformat the whole dictionary in a
   change that adds three keys — the diff becomes unreviewable and hides drift.
4. Keep values as data. No JSX, no component references, no locale-conditional business logic inside
   the dictionary; interpolation placeholders only.

For catalog files, the compiler cannot help: run the project's parity check (or `/check-translations`
per locale) as the equivalent gate before merging.

## Missing-key behavior — pick one, declare it

| Strategy | Behavior | Use when |
|---|---|---|
| Echo the key | Renders `nav.dashbord`, obvious in review | Internal apps — typos must be visible |
| Fall back to primary | Renders source-language text | Public sites — never show users a key path |
| Undefined / empty | Renders nothing | Almost never — silent content loss |

Whichever the project uses, write it down; agents otherwise assume "falls back" and ship holes.

## Adding a locale

1. Add the code to the single locale registry (union/config), never to a second hand-kept list.
2. Copy the primary locale's keys wholesale, mark every value untranslated per the project's existing
   convention (detect it — `TODO`, empty, or a prefix — do not invent a new one).
3. Run the parity check / typecheck; expect it to report the whole locale as untranslated, not missing.
4. If the locale is publicly routable, hand off to the locale-routing module before shipping.

## Anti-patterns

- Two lists of supported locales that must be kept in sync by hand.
- Translating brand names, currency/airport codes, or pure numbers because a checker flagged them as
  "same as source" — those are correct verbatim.
- Moving an in-repo dictionary to a DB (or vice versa) as a side effect of a copy change. That is an
  architecture decision: propose it, CONFIRM, migrate deliberately.

## Handoffs

- Extract / translate / audit workflow → `i18n-engineer` (this module supplies its scope config).
- Per-locale parity report → `/check-translations`.
- Locale identifiers drifting across config, routes, and markup → `/check-locale-codes`.
- Public routing, `<html lang>`, hreflang → the locale-routing stack module.
