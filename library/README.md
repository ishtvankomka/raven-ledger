# The library

Every agent, command, skill, stack module, and guardrail the collection ships — filed
individually, all general-purpose. **This file is the manifest: a file not listed here does not
exist.** Every module inherits [`GLOBAL_PREFERENCES.md`](GLOBAL_PREFERENCES.md) (velocity posture,
git-ignored env files, reversible=autonomous / irreversible=CONFIRM).

**Install into any project:** paste the prompt from [`INSTALL_PROMPT.md`](INSTALL_PROMPT.md) into a
Claude Code session at the target project root. Re-pasting upgrades an existing install.

## Folder map
```
library/
  GLOBAL_PREFERENCES.md      # shared contract — referenced by every file, never copied
  README.md                  # this manifest (inventory + routing + context budget)
  INSTALL_PROMPT.md          # the one prompt that installs/upgrades the library in a project
  settings.template.json     # .claude/settings.json baseline (deny/ask/allow + effort env)
  agents/                    # role agents (build, ops, business layer)
  commands/                  # slash commands
  stacks/                    # rule modules that load only when their activation condition matches
  skills/                    # workflow skills, registered into .claude/skills/ as stubs
                             # (+ skills/design/ — vendored, trigger-loaded, see its MANIFEST.md)
  guardrails/                # security/legal tools (Tier A always-on · Tier B gated)
  hooks/                     # deterministic lifecycle hooks (harness-enforced, outside the model)
  handoff/                   # context-capsule template + mechanism docs
```

## Three enforcement layers + the feedback loop
The contract holds at three strengths, and the library *learns* from what breaks:
- **Hooks** (`hooks/`) — the harness runs shell commands at fixed events (PreToolUse, Stop,
  PreCompact, SessionStart). A hook can't be forgotten under context pressure: `pre-bash-guard.sh`
  mechanically blocks force-pushes to a protected branch, bare protected-root deletions,
  `curl … | sh`, and any commit carrying a staged secret (the rest of the hard-deny list is held by
  the permission layer below); `stop-hygiene.sh` enforces the dev-server rule; `precompact-handoff.sh`
  leaves a breadcrumb that `sessionstart-handoff.sh` turns into the `/handoff` reminder after
  compaction. This is what makes the dev-time direct-token convention *safe* rather than hopeful.
- **Permission rules** (`settings.template.json`) — the harness's deny/ask/allow gatekeeper.
- **Prose contract** (`GLOBAL_PREFERENCES.md`) — what agents are instructed to obey.
- **Self-improving loop** — `self-improver` (`/retro`) mines the artifacts the library already
  emits (`context/bugs/`, `docs/audits/`, request log, git history), finds recurring pain, and
  moves each fix *down* to the strongest durable layer — a prose rule that recurs after being
  written gets promoted to a hook. `/overnight` runs a pre-approved backlog unattended (isolated
  branches, gated by test+perf, never pushes/deploys) and feeds `/retro` each morning.

## Context-budget strategy — how this stays lean when the team runs
The whole point of the filing is that **almost nothing is loaded by default.** Three registration tiers:

| Tier | What | When it enters context |
|---|---|---|
| **T0 · always-on core** | `code-reviewer`, `secret-scanner`, `dependency-vuln-audit`, `ship-closer`, `handoff-coordinator` | registered globally — all cheap (`context_cost: low`) |
| **T1 · project-scoped** | the reusable `agents/*` + the `stacks/*` whose trigger matches THIS repo | loaded only in a matching repo, on trigger |
| **T2 · on-demand only** | Tier-B guardrails, `skills/design/*` (esp. `taste-skill`, ~1200 lines), heavy niche | never auto-registered — invoked explicitly or by a gate |

Rules the orchestrator follows:
1. **Match before load.** A `stacks/*` module loads only when its `activation:` condition is true for the
   current repo. Never load all niche modules "just in case."
2. **Delegate heavy work to subagents.** Subagents have isolated context — the orchestrator keeps only
   their *summaries*, not their working set. This is the primary defense against bloat.
3. **One design skill at a time.** `design-taste-motion` design skills are `context_cost: high`; load a single skill for
   the task, never the whole `skills/design/` set.
4. **Hand off before you're full.** When a session crosses ~55%, run [`/handoff`](commands/handoff.md) →
   it writes a ≤1500-token capsule to `.claude/handoff/` and seeds a fresh session
   (see [`handoff/README.md`](handoff/README.md)).
5. **Every module file carries `context_cost` + `always_on` + `activation` frontmatter** so a loader can
   budget mechanically. Exceptions: vendored files under `skills/design/` are unmodified upstream copies —
   their budget metadata lives in [`skills/design/MANIFEST.md`](skills/design/MANIFEST.md); non-module
   files (this README, `GLOBAL_PREFERENCES.md`, `settings.template.json`, and
   `handoff/HANDOFF_TEMPLATE.md`, whose frontmatter is the capsule's own schema) are exempt.

Frontmatter vocabulary (mechanical loader contract):
- `context_cost:` enum is exactly `low | medium | high`.
- `always_on: true|false`; `auto_arm:` (optional) names a condition that flips a gated guardrail to
  armed (e.g. compliance-auditor arms when specialized-domains fintech/healthcare is active).
- Every file is general-purpose: no project names, paths, domains, brand values, or locale sets.
  Project-specific tooling lives in its own project, never here.
- Subagent fan-out tool is named `Task`.

## Model tiers (cost/latency, per wshobson strategy)
`opus`/`inherit` = analysis-critical (`unit-economics-analyst`, `delivery-orchestrator`,
`backend-architect`, `business-analyst`, `brainstormer`, `devils-secretary`, `self-improver`,
`growth-marketer`) · `sonnet` = build/review/debug + deep/implementation guardrails
(`test-automator`, `backlog-curator`, `legal-shield`,
`app-security-hardener`, `launch-rotation-runbook`, `security-auditor`, `/pre-launch`, `/business-plan`) · `haiku` =
ops/mechanical (`project-scribe`, `ship-closer`, most commands, Tier-A guardrails, report-only
Tier-B scans `penetration-tester`/`compliance-auditor`, niche docs). Set per file in `model:`.

## Routing table (trigger → load)
| Trigger | Load |
|---|---|
| 2+ bundled change requests in one message | `delivery-orchestrator` (fans out to subagents) |
| idea generation / "what could we build" | `brainstormer` → winners to `business-analyst` |
| define a feature / PRD / MVP scope / market question | `business-analyst` (demand verdict + SPEC-DEEP) |
| before committing to build a plan / "challenge this" / pre-mortem | `devils-secretary` (auto on every PRD; flaws get counter-proposals, re-validated) |
| promotion / ads budget / launch / "how do we get users" | `growth-marketer` ($0 plan always included) |
| full pre-release business plan (market + spec + economics + GTM, adversarially validated) | `/business-plan` |
| fill / curate the autonomous backlog | `backlog-curator` (`/backlog`) — suggests only; operator approves |
| cost / margin / unit-economics question | `unit-economics-analyst` |
| design/extend API, service, or data model | `backend-architect` (+ the matching stack module) |
| build page/component/form in an app | `frontend-developer` (+ `nextjs-app-router` if Next.js) |
| failing test/build/error, cause unknown | `debugger` |
| run API locally / touch the DB | `runtime-db-operator` + the matching stack module (`nestjs-prisma-postgres` for NestJS+Prisma) |
| build/lift shared UI, or review UI | `design-system-engineer` (+ `ui-conventions-contract`, `design-taste-motion`) |
| i18n extract/translate/audit | `i18n-engineer` + `i18n-dictionary-architecture` / `locale-routing-hreflang` (or `/check-translations`) |
| audit running app / SEO / recurring bug | `qa-auditor` (+ `sentry-observability`) |
| write/run tests — web, mobile, API, zero-human | `test-automator` (or `/test-sweep`) |
| "slow" / perf regression / bundle / web vitals / cold start | `performance-engineer` (or `/perf-audit`) |
| privacy / cookies / GDPR / ToS / country rules | `legal-shield` (or `/legal-audit`); analysis-only: `compliance-auditor` |
| harden the app (headers, rate limits, authz, sessions) | `app-security-hardener` |
| any diff / PR | `code-reviewer` (T0) + `secret-scanner` (T0) |
| wrong commit author · build rejects a committer · seat/team check fails | `skills/git-authorship` (commits belong to the operator; the guard enforces it) |
| close out a change set | `ship-closer` (launch-shaped → `/pre-launch` first) |
| production launch / public release | `/pre-launch` → all 9 gates incl. `launch-rotation-runbook` |
| payments / billing / subscriptions | `payments` + `unit-economics-analyst` |
| LLM feature / prompt / provider change | `llm-features` · multi-provider routing/fallback: `llm-provider-router` |
| polishing visuals / motion | `design-taste-motion` → one skill from `skills/design/` (per `MANIFEST.md`) |
| deep security review / pentest | Tier-B `security-auditor` / `penetration-tester` (gated) |
| deploy / push to production / "is it actually live?" | `deploy-verifier` (proves the live bundle changed — never a green status alone) |
| "use the old one" / rebuild a pre-rewrite feature | `legacy-scout` (fetches geometry/values from the legacy ref, keeps dead code out of context) |
| clone/replicate an existing website exactly | `replica-scout` → `replica-builder` + the 8-skill replica pipeline (`skills/clickable-inventory` … `final-validate`) |
| a numbered batch of owner/client corrections in one message | `skills/punch-list` |
| share-as-image / download feature (esp. iOS share sheet) | `skills/web-share-capture` |
| Spotify Web API work | `spotify-web-api` (PKCE-only auth, restricted endpoints, redirect-URI rules) |
| scaffold a new route/page in an existing convention | `/add-page` |
| verify a change before shipping (build, types, lint, runtime) | `skills/verify-change` → `pre-ship-sweep` for the full gate |
| add/rename/remove a route and catch every derived surface | `skills/feature-lifecycle` |
| OAuth login that must be verified without handling credentials | `skills/oauth-login-verification` |
| deploy pipeline check (CI → platform → live domain) | `skills/paas-deploy-check` |
| prove a data-isolation / least-privilege invariant on a live DB | `skills/data-isolation-verify` |
| run the app locally against a remote API | `skills/local-preview` |
| resist UI embellishment / hold a restrained design | `skills/ui-restraint` |
| per-commit changelog discipline | `skills/commit-changelog` |
| stale brand values, wrong locale codes, unsized images, bypassed components | `/check-brand-residue` · `/check-locale-codes` · `/check-image-sizing` · `/check-component-contract` |
| pricing page / refund or lifecycle email / landing or legal-surface copy | `product-copywriter` |
| message-catalog edits, a new namespace, or adding a locale | `skills/i18n-catalogs` |
| TypeScript correctness gate before a commit | `/typecheck` |
| "what did we decide last week" / resuming earlier work / why is it built this way | `skills/session-history` (reads the auto-recorded ledger) |
| "remember/log this" / change summary / test impact | `project-scribe` |
| "learn from this" / stop repeating a mistake / periodic review | `self-improver` (or `/retro`) |
| unattended run of a pre-approved backlog | `/overnight` (branches only, gated, never pushes) |
| context filling up (~55%) | `/handoff` → `handoff-coordinator` |

## Safety posture (consistent across all turns of this build)
Security/compliance tools are **routed, not disabled**: Tier A stays on in every stage (cheap, and it
catches exactly the loose-secret / direct-DB failure modes of the baseline); Tier B is gated to on-demand +
pre-launch. Dev-time direct token use is the accepted velocity convention; its exit ramp is
`guardrails/launch-rotation-runbook.md` inside `/pre-launch` — every dev credential rotated or re-issued
least-privilege, old ones verified dead. No file in this library commits secrets to git, force-executes
destructive ops, or deactivates security tooling — forbidden by `GLOBAL_PREFERENCES.md`. If you want a
specific tool dark for one throwaway local repo, scope an opt-in override there — never as the library
default that ships to clients.

## File index
- **Agents (27):** backend-architect · backlog-curator · brainstormer · business-analyst ·
  code-reviewer · debugger · delivery-orchestrator · deploy-verifier · design-system-engineer ·
  devils-secretary · frontend-developer · growth-marketer · handoff-coordinator · i18n-engineer ·
  legacy-scout · performance-engineer · pre-ship-sweep · product-copywriter · project-scribe ·
  qa-auditor · replica-builder · replica-scout · runtime-db-operator · self-improver · ship-closer ·
  test-automator · unit-economics-analyst
- **Commands (16):** handoff · typecheck · retro · overnight · backlog · business-plan ·
  legal-audit · perf-audit · pre-launch · test-sweep · check-translations · add-page ·
  check-brand-residue · check-component-contract · check-image-sizing · check-locale-codes
- **Stack modules (19):** nestjs-prisma-postgres · nextjs-app-router · expo-react-native ·
  cms-page-sections-revalidation · i18n-dictionary-architecture · locale-routing-hreflang ·
  ui-conventions-contract · payments · telegram-auth · spotify-web-api · sentry-observability ·
  cloud-infra-iac · llm-features · llm-provider-router · language-specialists ·
  specialized-domains · mcp-servers · project-scaffolding · design-taste-motion
- **Skills (21 + vendored):** replication pipeline — clickable-inventory · content-capture ·
  media-harvest · replication-plan · exact-implement · replica-compare · replica-fix ·
  final-validate — shipping — verify-change · feature-lifecycle · paas-deploy-check ·
  data-isolation-verify · local-preview · commit-changelog · oauth-login-verification — craft —
  punch-list · ui-restraint · web-share-capture · i18n-catalogs · session-history · git-authorship — plus `skills/design/`
  (5 vendored design skills; budget in `MANIFEST.md`, provenance in `ATTRIBUTION.md`)
- **Guardrails (8 + shared pattern list):** `secret-patterns.txt` is the single secret-pattern
  source read by the mesh, the pre-commit hook and secret-scanner — Tier A: secret-scanner · dependency-vuln-audit — Tier B: security-auditor ·
  penetration-tester · compliance-auditor (`auto_arm`: specialized-domains) · legal-shield ·
  app-security-hardener · launch-rotation-runbook
- **Hooks (4):** hooks/README.md (the pack's spec) · hooks.template.json + scripts/{pre-bash-guard,
  stop-hygiene, precompact-handoff, sessionstart-handoff}.sh — deterministic, harness-enforced
- **Install & baseline:** INSTALL_PROMPT.md · settings.template.json
- **Provenance & routing data:** CURATION.md (append-only ledger: what was captured from a
  project, what was promoted, merged or rejected, and why — the loop's only evidence of value) ·
  index.json (generated by `sync/build-index.sh`; the retrieval index the per-turn skill router
  reads — rebuild it after any library change)
