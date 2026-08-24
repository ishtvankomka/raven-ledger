---
type: handoff-capsule
task: "<kebab-slug>"
created: "<YYYY-MM-DD HH:MM>"
from_session: "<session id or short label>"
token_budget: "<=1500 tokens — this file is a CAPSULE, not a transcript"
---

# Handoff Capsule — <task title>

> Read this file + `.claude/library/GLOBAL_PREFERENCES.md`, load ONLY the modules listed in
> "Load on resume", then start from "Next action". Do not re-derive what's already decided here.

## 1. Objective
<One paragraph: what we are ultimately trying to achieve. The "done" condition.>

## 2. Constraints & preferences
- Inherits `.claude/library/GLOBAL_PREFERENCES.md` (velocity posture, secrets = gitignored single
  env file, reversible=autonomous / irreversible=CONFIRM gate). Do not restate it.
- <Any task-specific constraint, deadline, or veto the next session must honor.>

## 3. Decisions already locked (do NOT relitigate)
- <decision> — <one-line why>
- <decision> — <one-line why>

## 4. Current state
- Branch: `<branch>`  ·  Base: `<base>`  ·  Last commit: `<sha / one-line>`
- Files changed so far: `<path>` (<what/why>), `<path>` (<what/why>)
- Environment / servers running: <none | port X — remember to stop per dev-server hygiene>
- What is verified vs. assumed: <green: ...>  <unverified: ...>

## 5. Next action (the single most important line)
<The exact next step the fresh session should take. One concrete action, not a plan.>

## 6. Load on resume (context budget)
- Agents: `<e.g. delivery-orchestrator, runtime-db-operator>`
- Stack modules: `<e.g. nestjs-prisma-postgres, nextjs-app-router>`
- Skills: `<e.g. check-translations>`
- Files to read first: `<paths — keep to the 3-5 that matter>`
- Do NOT load: <the heavy/irrelevant modules to keep out of context>

## 7. Open questions / blockers
- <question needing the user, or blocker + the specific unblock>

## 8. Resume prompt (paste into the fresh session)
```
Read .claude/handoff/HANDOFF-<slug>-<YYYY-MM-DD>.md and .claude/library/GLOBAL_PREFERENCES.md.
Load only the modules it lists. Continue from "Next action". Ask me only about the items under
"Open questions".
```
