---
description: Review incoming/ captures and promote worthy items into the curated library, updating the manifest. Project-specific items are rejected and stay in their home projects.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# /promote — curate incoming/ into the library

You are working inside the raven-ledger repo. `incoming/<project>/…` holds
agents, commands, and skills auto-captured from live projects by the sync mesh.
Promote the worthy ones into the curated library that every project re-syncs from.

**Prime directive: the collection holds NO project-specific data.** A tool enters
the library only as a GENERAL tool — every project path, brand name, URL, port,
locale set, env detail, and business fact stripped. Project-local tooling stays in
its home project with its context; the collection is not its backup.

Work through every file under `incoming/`, newest project first:

1. **Re-scan for secrets** with `sync/secret-scan.sh <file>`. Anything flagged:
   do not promote; delete it from `incoming/` and note it in the report.
2. **Dedupe against the library.** If an item with the same name or purpose exists,
   diff them. Promote only a genuine improvement — merge the delta into the
   existing file rather than replacing wholesale.
3. **Generalize or reject — there is no middle.** If a reusable core exists (even
   for a niche case), rewrite the item as a general tool and promote that. If the
   item only makes sense in its home project, REJECT it: delete it from
   `incoming/` AND append its verdict digest to `sync/ignore.list` so the mesh never
   re-captures it —
   `printf '%s' '<project>/<category>/<path>' | shasum -a 256 | cut -d' ' -f1`
   (digests, not paths: the verdict list must not become a roster of project names).
   The same digest is appended for an item whose reusable core you just generalized,
   so the project original stops being re-staged. Never use `portable: false` — that
   mechanism is retired.
4. **Enforce the frontmatter contract** (this is the known failure point):
   - strict YAML; block scalars keep their line breaks
   - AGENTS declare tool restrictions under `tools:`
   - COMMANDS declare them under `allowed-tools:` — a bare `tools:` key on a
     command is silently inert
   - `context_cost: low|medium|high` and an `activation:` condition are required
   - `Task` is the fan-out tool name
   YAML-parse every file you touch before declaring success.
5. **Place it**: agents → `library/agents/`, commands → `library/commands/`,
   skills → `library/skills/<name>/`, stack rules → `library/stacks/`. Then update
   the manifest `library/README.md` (it is authoritative — an unlisted file does
   not exist) and, if routing changed, the trigger→load table.
6. **Delete the processed file from `incoming/`** so the staging area only ever
   holds pending work.

When everything is processed: one commit `promote: <short list>` covering the
library + `incoming/` + `sync/ignore.list`, then `git push origin main`. Finish
with a report: promoted / merged / rejected-stays-local (and why).

Skip-list: never promote anything referencing `.claude/library/` (that's a stub
that slipped through), and never touch `projects/` (untracked source dumps).
