---
name: check-brand-residue
description: Report-only sweep for leftovers of a previous name, domain, palette, or asset set after a rename or rebrand — greps the working tree for each retired pattern and reports every hit as file:line with the suggested replacement, separating real residue from declared acceptable matches (historical docs, homonyms, vendor strings). Patterns come from arguments or the repo's own retired-pattern list; nothing is auto-edited.
allowed-tools: Read, Grep, Bash
model: haiku
source: generalized from a project command overlay
always_on: false
activation: "invoke after a rename/rebrand, or before a release that follows one, to prove no retired identifier survives"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Purpose

A rename is never finished when the first pass of find-and-replace is. Residue survives in metadata,
email addresses, alt text, asset filenames, seeded database content, tests, and comments — and each
survivor is visible to a user or a crawler. This command finds them; a human decides each fix.

## Inputs

```
/check-brand-residue [pattern ...]
```

With no arguments, load the retired-pattern list the repo declares (a git-ignored env file per
`GLOBAL_PREFERENCES`, or whatever list convention the repo already uses — match it, never introduce a
new one). Each entry pairs a retired pattern with its replacement where one exists.

Cover all five residue classes — a name-only sweep misses most of them:

1. **Names** — old product/company name in every casing (lower, Title, UPPER, kebab, camel, no-space).
2. **Domains and addresses** — retired domains, email addresses, social handles, deep links.
3. **Values** — retired color literals in every notation (hex short and long, `rgb()`, `hsl()`), old
   font families, old logo/asset paths and filenames.
4. **Copy** — retired taglines, legal entity names, support phone numbers.
5. **Identifiers** — package/scope names, storage bucket or bundle identifiers, CSS class prefixes,
   analytics property names.

## Where to look

Search the whole working tree, excluding dependency, build, and VCS directories and lock files.
Do **not** stop at source: include markup and content files, config, CI workflow files, seed and
fixture data, translation catalogs, test snapshots, and asset filenames (match on the path itself,
not only file contents). Note but do not fail on hits confined to changelog/history documents.

## Acceptable matches

Some hits are correct and must not be reported as bugs. Read the repo's declared exception list, and
apply judgment for these standing classes:

- **Homonyms** — the retired token is also an ordinary word, a place name, or part of a longer
  unrelated word. Report separately as "review", never as a bug.
- **Historical records** — changelogs, migration notes, and dated audit docs that describe the rename.
- **Vendor and third-party strings** — a dependency's own name, an upstream URL, a licence text.
- **Paths outside the product** — scratch directories, local fixtures of a legacy reference.

Anything not covered by an exception is residue.

## Output

Group by pattern, then by file:

```
<pattern> → <replacement>
  path/to/file:LINE: matched line
  …
  (N hits, M in acceptable-match classes)
```

End with a per-class total and a single verdict line. Flag high-visibility hits first: user-facing
copy, metadata/social tags, and email/domain strings before comments and tests.

## Rules

- Report only — no edits, no side effects, safe to re-run.
- Case-insensitive by default; note when a hit differs only in casing, since those are the ones a
  naive replace missed.
- Remediation routes to `frontend-developer` (copy/markup) or the owning agent for config and data.
