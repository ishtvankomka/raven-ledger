---
name: project-scaffolding
type: stack-module
description: Bootstrap agents, commands, and MCP connectors using the claude-code-templates CLI (davila7). One-shot greenfield setup for new Claude Code projects, agents, or plugin scaffolds. Includes analytics dashboard wiring. Unload after scaffold completes.
model: haiku
always_on: false
activation: "ACTIVATE ONLY on greenfield setup"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Trigger

- "scaffold a new agent" / "bootstrap an agent" / "generate a template for…"
- "set up a new MCP connector" / "create a new Claude Code command"
- "use davila7 templates" / "claude-code-templates"
- Starting a fresh project that needs agents, commands, or plugin structure

## Before Scaffolding

1. Confirm project root and target scaffold destination
2. If `.claude/settings.json` is missing, create it from the library's `settings.template.json`; run `/init` separately if `CLAUDE.md` is missing (`/init` generates CLAUDE.md, not settings)
3. Verify git is clean (no uncommitted changes in scaffold target dirs)

## Scaffold Workflow

Run via `npx` from the project root — no global install:
```bash
npx claude-code-templates@latest                    # interactive setup
npx claude-code-templates@latest --agent <name>     # install a specific agent
npx claude-code-templates@latest --command <name>   # install a specific command
npx claude-code-templates@latest --mcp <name>       # wire an MCP connector (.mcp.json)
npx claude-code-templates@latest --analytics        # local analytics dashboard
```
Flags drift between releases — verify against `npx claude-code-templates@latest --help` before relying on them.

## Post-Scaffold Checklist

- [ ] Review generated `.claude/settings.json` → adjust permissions, env vars per GLOBAL_PREFERENCES
- [ ] Verify test suite runs: `npm test`
- [ ] Check `package.json` dependencies align with project constraints
- [ ] If MCP: validate connector in `.mcp.json`
- [ ] Commit scaffold results (`.gitignore` remains unchanged)

## Env Scaffold Pattern

- `env/.env.example` documents every variable, phased by feature (core → integrations → optional); names only, never values.
- Unset vars fall back to mocks so the app always boots on a fresh checkout — a missing key degrades one feature, never startup.
- Ship a scaffold script (`scaffold-env.js` / `setup-env.js`) that copies the example into git-ignored `env/<env>.env`.
- Use the library's `settings.template.json` as the `.claude/settings.json` baseline.
- Match the existing repo convention if one exists; never introduce a new one.

## Unload

After scaffold completes and tests pass, deactivate this module:
- Remove from active context
- Recommend a `code-reviewer` agent pass over the generated boilerplate for quality
- User owns the generated project from here

## Notes

- Scaffold is non-destructive; can re-run safely to update templates
- No secrets in templates; `.env.example` only
- Analytics dashboard is opt-in; disable in settings if not needed
- davila7 templates follow Claude Code conventions (skills, permissions, hooks)
