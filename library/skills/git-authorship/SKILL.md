---
name: git-authorship
description: Make every commit in a repo belong to the operator's own git identity, never the assistant — no Co-Authored-By trailer, no --author override, no rewriting user.name/user.email. Use when setting up a new repo, when a deploy platform rejects a build or counts an unexpected committer against a paid seat, when commits show the wrong author or email, or when existing history already carries an assistant co-author that needs removing.
keywords: "co-authored-by, commit author, git identity, wrong author, vercel seat, build rejected, committer, authorship, user.email, git config identity"
always_on: false
activation: "invoke when setting up commit identity in a repo, when a build or seat check rejects a committer, or when history carries an assistant co-author"
context_cost: low
inherits: ../../GLOBAL_PREFERENCES.md
---

# git-authorship — commits belong to the operator

## The rule

Commit as whatever `git config user.email` already resolves to in that repo. Never append a
`Co-Authored-By` trailer naming the assistant, never pass `--author`, never set `user.name`
or `user.email` to an assistant identity.

This is enforced, not merely requested: `hooks/scripts/pre-bash-guard.sh` blocks a `git
commit` carrying an assistant co-author trailer or `--author` override, and blocks any
attempt to point the repo's identity at one.

## Why it matters more than it looks

Seat-billed platforms bill and gate on **distinct commit identities**. Vercel is the common
case: a build triggered by a commit whose author or co-author is not a member of the paid
team can be refused, and the failure message talks about team membership rather than about
the trailer that caused it — so it reads as a billing problem and gets debugged in the wrong
place. The same shape appears in CODEOWNERS checks, DCO/CLA bots, and signed-commit policies.

Attribution to the tool is fine — it just does not belong in git metadata. Put it in the PR
description or the changelog, where nothing bills on it.

## Setting a repo up

```bash
git config user.name  "Your Name"          # repo-local, not --global
git config user.email "you@example.com"    # must match the platform account that pays
git config user.email                       # verify: this is what commits will carry
```

Use the repo-local form. A `--global` identity is a footgun across client work: the wrong
address ends up on a commit in someone else's repository and cannot be fixed without a
history rewrite.

If the machine has no global identity at all (a good default), every fresh clone needs this
once — otherwise git refuses to commit, which is the safe failure.

## Checking what history actually contains

```bash
git log --format='%an <%ae>' | sort | uniq -c              # every author in the repo
git log --format='%b' | grep -ci 'co-authored-by'          # trailers present at all
git log --format='%H %b' | grep -i 'co-authored-by.*claude' # the ones that matter
```

Run the first one before connecting a repo to a seat-billed platform. It is five seconds and
it answers the question the build failure will not.

## Cleaning history that already carries it

This rewrites commits, so it is the operator's call, never an autonomous one. State plainly
what it costs before proposing it: every existing clone must re-clone, and open pull requests
against the rewritten range will need rebasing.

- **Only the last commit, not yet pushed:** `git commit --amend` and delete the trailer line.
- **A range, or already pushed:** `git filter-repo --message-callback` (or
  `git rebase -i` for a handful) to strip matching trailer lines, then a force-push — which
  the guard hard-denies on `master`/`main`, so it needs an explicit, deliberate operator
  action on a protected branch rather than an agent doing it.
- **Not worth rewriting:** if the trailer is on old commits nobody builds from, adding the
  co-author's address to the paid team is often cheaper than rewriting shared history. Say so
  rather than defaulting to the rewrite.

## What not to do

Do not "fix" this by adding the assistant to the paid team. That converts a metadata mistake
into a recurring bill, and it still leaves the commits misattributed.
