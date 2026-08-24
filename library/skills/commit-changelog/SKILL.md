---
name: commit-changelog
description: >-
  The per-commit changelog convention — one new, dated file per commit, staged in the same
  commit, explaining in plain language what changed, why, and how it was proven. Use in a repo
  that requires a changelog entry per commit, immediately before running git commit; the commit
  is incomplete without it. Also use when introducing the convention to a repo that keeps losing
  the "why" behind its diffs.
always_on: false
activation: "before every git commit in a repo that requires a per-commit changelog entry, or when adopting the convention"
context_cost: low
---

# Per-commit changelog

A diff says what changed. It never says why, and it never says whether anyone checked. The
per-commit changelog is the cheapest durable fix: **one new file per commit, staged in that same
commit**, written for the person who arrives six months later without the conversation you had.

Adopt it as a repo rule (state it in the contributor instructions) or follow it where it already
exists — either way, a commit without an entry is treated as incomplete.

## The file

```
changelogs/YYYY-MM-DD-HHMM-<slug>.md
```

- Date and 24-hour local time of the commit; slug matching the commit subject.
- **One file per commit.** Never edit a previous commit's file — an entry is a record of a
  moment, not a living document. A later correction is a new entry that names the old one.
- Append-only as a directory: the sort order is the history.

Why a directory of files rather than one `CHANGELOG.md`: a single shared file is a merge-conflict
magnet across branches and parallel worktrees, and every conflict resolution quietly loses an
entry. Separate files never collide.

## Template

```markdown
# <commit subject, imperative mood>

- **Date:** YYYY-MM-DD HH:MM
- **Area:** <the repo's own area vocabulary — one or more>

## What changed
2-6 bullets a teammate can follow without reading the diff. Name the user-visible behaviour
first, mechanics second.

## Why
The reason this change exists — the product need, the bug, the decision it implements. Reference
the decision record or spec section where one exists, so the next reader can find the argument
rather than re-having it.

## Verification
How this was proven to work: typecheck, which tests ran, previewed in a browser, migration
applied, which verification skill was run — whatever actually happened.
"Not verified" is an allowed, and required, entry when nothing was checked.
```

Derive the **Area** vocabulary from the repo's own top-level structure (its apps, packages, and
concerns) the first time you write an entry, and then keep using that set. Do not invent a new
label per commit.

## Rules that make it worth the keystrokes

- **Write it for the other person**, including the non-engineer who reads these to know what
  shipped. Lead with product meaning; keep plumbing in Verification.
- **Stage the changelog file in the same commit it describes.** A changelog committed separately
  is a changelog that drifts.
- **Commit subject and changelog title match**, word for word. That is what makes
  `git log --oneline` and the changelog directory the same list.
- **Verification is honest or worthless.** The section exists precisely so that "I did not check"
  is recordable without shame. An entry that claims a test run that did not happen is worse than
  no changelog at all — it is the thing the next reader will trust.
- **Follow the repo's attribution rules** for commit authorship and trailers; do not add tooling
  or assistant attribution the repo has not asked for.

## When a commit genuinely does not need one

Mechanical commits that carry no decision — a lockfile refresh, a generated-file update, a
revert that restores a previous state exactly. Say so in the commit body in one line rather than
writing an empty entry. Everything else gets a file.
