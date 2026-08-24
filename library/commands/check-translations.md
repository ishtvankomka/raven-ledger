---
name: check-translations
description: Audit a single locale's translation file against the base (English) source, reporting missing keys, untranslated strings (value equals English, minus a translation-exempt ignore list), placeholder drift, and orphaned key names. Run in parallel per locale to verify i18n coverage before deployment. Exits 1 on missing keys or placeholder drift so CI can gate on it.
allowed-tools: Read, Grep, Bash
model: haiku
source: project command (promoted to generic)
always_on: false
activation: "repo has locale dictionaries or i18n config — detect: locales/ dir, i18n config file, or t() usage"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
keywords: "translations out of sync, missing translation, untranslated strings, locale drift"

---

## Task

Validate one translation locale against English source. Do not modify files. Report findings only.

## Inputs

- `LOCALE`: target locale code (e.g., `de`, `es`, `fr`)
- Base-locale source file: detect from the repo — common layouts are `locales/en.json`,
  `src/i18n/en.json`, `messages/en.json`, `public/locales/en/*.json`, or a typed
  dictionary module — detect the layout, never assume one
- Target locale file path: the detected layout's file for `LOCALE`

## Translation-exempt ignore list

A leaf value that equals the English source verbatim is **correct, not a bug** when it falls into
any of these buckets — never flag it as untranslated:

1. **Brand strings** — product/company names, domains, support emails, phone numbers.
2. **Pure numbers and numeric-ish tokens** — digits, percentages (`100%`), ratios (`24/7`),
   years, dial codes (`+420`).
3. **Proper nouns universal across languages** — product/model/trim names (e.g. car models,
   SKU names). Only the *description around* them translates, never the noun itself.
4. **Currency codes** — `EUR`, `USD`, `CZK`, …
5. **Codes used as labels** — airport/city/country codes (`PRG`, `MUC`). Full city names may
   have native forms; treat those as translatable.
6. **ICU / template placeholders** — `{name}`, `{count}`, `%s` must stay literally identical.

Anything else that matches the English string verbatim is an untranslated bug. If the repo defines
its own exempt list (env var or config), prefer it over these defaults.

## Steps

1. **Locate files**
   - Find English source translation file in repo
   - Find target locale file
   - Exit early if either file missing

2. **Parse both files**
   - JSON layouts: parse directly.
   - Typed-module layouts (dictionaries as `.ts`/`.js` objects): run the project's typecheck and
     treat any type error referencing the locale file as **Blocking** (missing keys / wrong shapes
     surface there first), then walk the object literals for the value comparison.

3. **Audit and report**

   **Missing keys:** Keys present in English but absent in locale file

   **Untranslated strings:** Keys where locale value equals English value AND the value is not on
   the translation-exempt ignore list

   **Placeholder drift:** Keys where the set of ICU/template placeholders differs between English
   and the locale (missing, extra, or renamed — `{name}` vs `{user}`). Fail loudly: drifted
   placeholders break runtime interpolation silently.

   **Orphaned keys:** Keys present in locale but absent in English (likely left behind by refactors)

4. **Output format**
   ```
   LOCALE AUDIT: <LOCALE>

   Missing keys (<count>):
   - key1
   - key2

   Untranslated (equal to English) (<count>):
   - key3 = "English text here"

   Placeholder drift (<count>):
   - key4: en uses "{name}" but <LOCALE> uses "{user}"

   Orphaned keys (not in English source) (<count>):
   - orphaned_key1

   OK-by-ignore-list (informational, not bugs) (<count>):
   - brand.name = "ACME" — brand
   - common.currency = "EUR" — currency code

   Summary: <total_keys> English keys, <locale_keys> in <LOCALE>, <missing> missing, <untranslated> untranslated, <drift> placeholder drift, <orphaned> orphaned
   ```

## Notes

- No file modifications; audit only
- Exit code contract (CI-usable): `0` = no missing keys and no placeholder drift; `1` = missing
  keys or placeholder drift found. Untranslated and orphaned keys report as warnings and do not
  fail the run — pass `--strict` to exit 1 on those too.
- Run once per locale, can parallelize across locales
- Designed for the i18n-engineer agent
