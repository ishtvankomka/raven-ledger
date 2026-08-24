---
name: add-page
description: Scaffold a new route in a web app by copying the repo's own page conventions — creates the route file from an existing page as the reference pattern, registers translation keys across every locale (interface/type first when the dictionary is typed), adds page metadata, offers navigation registration, and verifies with the project's typecheck. Never invents user-facing copy and never writes partial output.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash
model: haiku
source: generalized from a project command overlay
always_on: false
activation: "invoke to scaffold a new page/route in a web app that has an existing page convention to copy"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Invocation

```
/add-page <route>          # e.g. pricing · fleet · contact/corporate
```

## Step 0 — detect conventions (do this before writing anything)

Never assume a layout. Establish from the repo:

- **Route layout** — where page files live and whether locales are a path segment, a per-locale tree,
  or resolved at runtime. Pick the nearest existing page as the **reference file**.
- **Dictionary layout** — typed module vs per-locale catalogs, the full locale set, the primary
  locale, and the runtime accessor. Load the repo's i18n module/notes if it has one.
- **Metadata pattern** — grep an existing page for how title/description/social tags are exported.
- **Navigation registries** — the arrays/config a route must be added to for it to be linkable.
- **Verification command** — the project's typecheck/build script.
- **UI conventions** — tokens, container widths, heading treatment: from the repo's UI-conventions
  module. Do not invent styling.

If the reference file or the dictionary cannot be identified, stop and ask. Guessing here produces a
page that looks plausible and matches nothing.

## Step 1 — create the route file

- Copy the structure of the reference file: same imports, same section skeleton, same container and
  spacing utilities, same client/server boundary marker only if the reference needs one.
- All user-facing text goes through the i18n accessor from the start — no literals "to be replaced later".
- Keep the file minimal: the sections the request actually named, nothing speculative.

## Step 2 — register translation keys

- Typed dictionary: extend the interface / key type **first**, then add the keys to every locale
  object so the compiler enforces completeness.
- Catalog files: add the keys to every locale file, preserving each file's ordering convention.
- **Do not invent copy.** Ask the requester for the real strings; where they are not yet available,
  insert the repo's existing untranslated marker (detect it — never introduce a new convention) and
  list those keys in the summary as needing human copy.
- Preserve every existing key. Never reformat a whole dictionary file for this change.

## Step 3 — metadata

Add title/description and social/preview tags following the reference file's exact pattern, sourced
from the new translation keys where the pattern does that. Use the repo's configured asset/CDN base
for any image reference rather than a hardcoded host.

## Step 4 — navigation

Ask whether the route belongs in primary navigation and footer. If yes, add it to each registry found
in step 0 — with its label as a translation key, not a literal.

## Step 5 — verify and report

- Run the project's typecheck/build; a failing typecheck means the dictionary is out of lockstep — fix
  before reporting done.
- Report: files created, files modified, keys awaiting human copy, navigation registries touched, and
  anything deliberately skipped.

## Rules

- **Idempotent.** If the route already exists, report the conflict and exit — never overwrite.
- **No partial writes.** If a required file is missing or ambiguous, stop before the first write.
- Reversible local edits — proceed autonomously; nothing here is deployed.
