---
name: install-prompt
description: The one prompt that installs this library into any project. Copy the block below into a fresh Claude Code session at the target project root.
model: sonnet
context_cost: low
always_on: false
activation: "used once per project (and re-run to upgrade); never loaded at runtime"
---

# Install Prompt — add the library to any project

**How to use:** open a Claude Code session at the root of the target project, paste the entire
prompt block below, and set `LIBRARY_SOURCE` to this repo's `library/` directory on your machine.
Re-running the same prompt later **upgrades** an existing install (it is idempotent).

What the install gives the project: always-on cheap guardrails (diff review, secret scan, dependency
audit), routed specialist agents (build/debug/perf/i18n/design/testing), the four startup shields
(`/legal-audit`, `/pre-launch` + rotation runbook, `/perf-audit`, `/test-sweep`), the handoff
mechanism for long sessions, and a mechanical settings baseline — with almost nothing loaded into
context by default.

---

## THE PROMPT (copy everything inside the fence)

```text
Install the raven-ledger library into this project.

LIBRARY_SOURCE = <absolute path to this repo>/library

Execute these steps in order. Everything here is reversible file work in this repo — proceed
autonomously, no pushes, no remote-state changes, never print secret values. If a step conflicts
with something that already exists in this repo, adapt to the repo (never destroy existing config)
and note it in the final report.

1. VENDOR THE LIBRARY (structure intact — the relative links inside it depend on this):
   Copy LIBRARY_SOURCE/ wholesale to .claude/library/ (agents/, commands/, stacks/, guardrails/,
   hooks/, skills/, handoff/, GLOBAL_PREFERENCES.md, README.md, settings.template.json,
   INSTALL_PROMPT.md).
   Skip .DS_Store. If .claude/library/ already exists, replace it — but preserve ACTIVE.md if
   present (step 3 will refresh it; everything else in the folder holds no project state).

2. DETECT THE STACK: inspect package.json / tsconfig.json / next.config.* / nest-cli.json /
   app.json+expo / prisma/ / go.mod / pyproject.toml / Gemfile / tailwind config / i18n or locales
   config / payment SDKs (stripe, paddle, revenuecat) / sentry / telegram / Dockerfile / *.tf /
   CI workflows. Also detect the existing env-file convention (env/*.env vs .env.local vs .env).

3. SELECT MODULES: read the frontmatter of every file under .claude/library/stacks/, commands/,
   agents/, guardrails/, skills/. Every library file is general-purpose; match each `activation:`
   condition against the detected stack. Write the result to .claude/library/ACTIVE.md: detected
   stack facts, activated stack modules, matched T1 agents, and anything deliberately not
   registered (with the reason). This file is the per-project activation map.

4. REGISTER AGENTS as thin stubs (keeps context cheap; the full spec is read on demand):
   Register T0 always: code-reviewer, ship-closer, handoff-coordinator. Then walk EVERY file in
   .claude/library/agents/ and register each one whose `activation:` condition matches this repo —
   do not work from a hardcoded roster, or the install silently drifts as the library grows. An
   agent with no stack precondition (the business/delivery/QA/scribe layer) matches everywhere;
   stack-gated ones (design-system-engineer, i18n-engineer, runtime-db-operator,
   unit-economics-analyst, deploy-verifier, replica-scout/replica-builder, …) register only on a
   match. Record every deliberate non-registration, with its reason, in ACTIVE.md. For each, create
   .claude/agents/<name>.md containing: the library file's frontmatter (name, description, tools,
   model — agents use the key `tools:`; commands do NOT, see step 5) PLUS, as the last frontmatter
   line, the stub marker `source_spec: .claude/library/agents/<name>.md` (the sync mesh uses it to
   recognize stubs — never omit it), plus a 3-line body:
     "Follow your full specification at .claude/library/agents/<name>.md.
      Inherit .claude/library/GLOBAL_PREFERENCES.md as your standing operating contract.
      Consult .claude/library/ACTIVE.md for this repo's active stack modules."
   Guardrails secret-scanner and dependency-vuln-audit are also T0: register them the same way
   (source dir .claude/library/guardrails/).

5. REGISTER COMMANDS: same stub pattern into .claude/commands/ for every portable command —
   handoff, typecheck, check-translations, perf-audit, test-sweep, legal-audit, pre-launch, retro,
   overnight, business-plan, backlog, add-page, check-brand-residue, check-image-sizing,
   check-locale-codes, check-component-contract — skipping any whose activation doesn't match
   this stack.
   CRITICAL frontmatter difference from step 4: slash commands declare their tool restriction under
   `allowed-tools:`, NOT `tools:`. Claude Code recognises `tools:` for AGENTS only; on a command it
   is an unrecognised key that still parses as valid YAML, so the restriction is silently inert and
   the command runs with the session's full tool access. Copy the library file's `allowed-tools:`
   value verbatim and never emit a bare `tools:` key under .claude/commands/.

5b. REGISTER SKILLS: a skill is only discoverable from .claude/skills/ — vendoring it under
   .claude/library/skills/ makes it available to read but never loads it. For every
   .claude/library/skills/<name>/SKILL.md whose `activation:` matches this repo (skip the vendored
   .claude/library/skills/design/ set — those are trigger-loaded through the design-taste-motion
   stack module, not registered), create .claude/skills/<name>/SKILL.md containing the library
   file's `name:` and `description:` VERBATIM (the description is what the harness matches on, so
   never paraphrase or truncate it) plus the loader keys `always_on`/`activation`/`context_cost`,
   and this body:
     "Follow the full skill at .claude/library/skills/<name>/SKILL.md — read it before acting.
      Inherit .claude/library/GLOBAL_PREFERENCES.md as your standing operating contract."
   Same budget logic as the agent stubs: only the description sits in context until the skill fires.
   If the repo already has a skill directory of that name, LEAVE IT — local wins, and note the
   collision in the report.

6. SETTINGS + HOOKS BASELINE: merge .claude/library/settings.template.json into
   .claude/settings.json — union the deny/ask/allow permission lists and env keys with whatever
   exists; existing project entries always win on conflict; never remove an existing deny rule.
   Then merge .claude/library/hooks/hooks.template.json's `hooks` block into the same settings
   (union with existing hooks — keep project entries) and `chmod +x
   .claude/library/hooks/scripts/*.sh`. The hooks enforce the hard-deny list, pre-commit secret
   scan, dev-server hygiene, and the pre-compact handoff reminder deterministically.

7. SCAFFOLD THE RUNTIME TREE (create only what's missing, with a one-line README in each):
   context/qa/  context/bugs/OPEN.md  context/bugs/RESOLVED.md  context/requests/  context/tasks/
   context/tasks/overnight.md (empty backlog; only items the operator marks `overnight-ok` run
   unattended)  context/architecture/  context/recurring-issues/  docs/audits/  docs/product/
   docs/launch/  .claude/handoff/
   Env convention: if the repo already has one, keep it. If none, create env/.env.example and a
   scaffold-env script per GLOBAL_PREFERENCES (git-ignored env/*.env, committed example).

8. GITIGNORE: ensure these are ignored: env/*.env, .env, .env.*, !.env.example,
   .claude/settings.local.json, .claude/handoff/. Never loosen an existing ignore rule.

9. CLAUDE.MD WIRING: append to CLAUDE.md (create if missing) a section delimited by
   <!-- master-agent-library:start --> and <!-- master-agent-library:end --> (replace the section
   if the markers already exist — that is the upgrade path). The section contains, condensed:
   - Contract: every agent inherits .claude/library/GLOBAL_PREFERENCES.md (velocity posture,
     git-ignored env files, reversible=autonomous / irreversible=CONFIRM, veto tokens, FORBIDDEN list).
   - Routing: the trigger→load table from .claude/library/README.md, filtered to what ACTIVE.md
     activated, PLUS the four shields: legal/privacy/cookies→/legal-audit + legal-shield ·
     "slow"/perf→/perf-audit + performance-engineer · testing→/test-sweep + test-automator ·
     any launch→/pre-launch (security+legal+rotation+tests+perf gate).
   - Context budget: match-before-load, delegate heavy work to subagents, one design skill at a
     time, /handoff at ~55% context.
   - A LEGAL_FACTS block (company legal name, address, registration id, contact/DPO email, target
     markets) filled with TODO placeholders — legal-shield refuses to generate documents until the
     operator fills it. UPGRADE RULE: if the existing marked section already contains a
     LEGAL_FACTS block with non-TODO values, read those values BEFORE replacing the section and
     carry them into the new block verbatim — only still-missing fields get TODO placeholders.

10. REPORT: print an install report — modules activated, overlays skipped, agents/commands
    registered, scaffolds created, settings merged — then exactly these next steps:
    a) fill LEGAL_FACTS in CLAUDE.md
    b) /test-sweep smoke   (baseline the test harness)
    c) /perf-audit all     (baseline the performance budgets)
    d) before any public launch: /pre-launch
    Do NOT run the heavy audits yourself now; installation must stay fast.
```

---

## After installing: wire the sync mesh (recommended)

The collection repo ships a two-way sync mesh (see `sync/README.md` at the
collection root). One command wires the target project into it:

```bash
/Users/ishtvan/files/work/other/raven-ledger/sync/install-project.sh /path/to/project
```

This adds two hooks to the project's `.claude/settings.local.json`: new
agents/commands/skills written in the project are captured back into the
collection's `incoming/` and pushed automatically, and every session start
re-syncs `.claude/library/` from the latest collection. Approve the new hooks
once when Claude Code asks on the next session start.

## Upgrade / uninstall

- **Upgrade:** pull the latest library at `LIBRARY_SOURCE`, paste the same prompt again. Step 1
  replaces `.claude/library/` (preserving `ACTIVE.md`), step 9's markers replace the CLAUDE.md
  section, stubs regenerate. `context/` and filled LEGAL_FACTS survive — the LEGAL_FACTS
  preservation rule is inside step 9 of the prompt itself.
- **Uninstall:** delete `.claude/library/`, the generated stubs in `.claude/agents/` and
  `.claude/commands/`, the marked CLAUDE.md section. `context/` and `docs/` hold project history —
  keep them.

## Design notes (why it installs this way)

- The library is copied **intact** because every file's `inherits: ../GLOBAL_PREFERENCES.md` and
  the stacks/skills cross-links assume the folder shape. Flattening into `.claude/agents/` breaks
  inheritance — that's what the stubs are for.
- Stubs keep the always-on context footprint to a few lines per agent; the full spec enters context
  only when that agent actually runs. This is the T0/T1/T2 budget model from `README.md`.
- Everything in the library is general-purpose: it carries no project names, paths, or values.
  Project-specific tooling stays in its own project's `.claude/`, where the install never touches it.
- The installer never runs audits, never pushes, never touches remote state — installation is
  always the cheap, reversible step; the gates run when you invoke them.
