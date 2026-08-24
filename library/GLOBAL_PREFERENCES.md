---
name: global-preferences
description: Shared execution profile inherited by every agent, skill, and niche module in this library. Referenced, not copied.
version: 1.1
updated: 2026-07-08
---

# Global Preferences Profile

Every file in this library inherits this profile. Agents should treat it as their standing
operating contract. It encodes the operator's **high-velocity** intent in a form that does not
disable the safety net that catches high-velocity mistakes.

## Execution posture (the velocity you asked for)
- **Autonomy: high.** Act when you have enough to act. Don't ask "shall I?" for reversible work
  that follows from the request.
- **Effort: max.** (`CLAUDE_CODE_EFFORT_LEVEL=max`, `MAX_THINKING_TOKENS=64000`.)
- **No filler.** No preamble, no recap of what you're about to do beyond one status line. Lead
  with the outcome. Headline-first output; detail after.
- **Pragmatic.** Ship fast code that meets the bar; don't gold-plate. "Working and shipped" beats
  "perfect and pending."
- **Targeted verification, not ceremony.** Test the changed surface, not the world. Keep the
  hypothesis→isolate→verify loop (it is faster than guess-patching), drop the narration.

## Secrets & config — single-file convenience WITHOUT repo poisoning
- **Source of truth:** one env file per environment (`env/<env>.env`) — matches the operator's
  existing pattern. Convenient, single-file, fast to hydrate.
- **`env/*.env` stays git-ignored.** Commit `env/.env.example` + a scaffold script
  (`scaffold-env.js` / `setup-env.js`) so a fresh checkout is live in seconds.
- **In generated artifacts: reference variable NAMES, never paste VALUES.** (Operator's own rule.)
- If a secret ever lands in git history, **rotate it** — history is permanent and bot-indexed.
- **Launch exit ramp:** dev-time direct token use is the accepted velocity convention. Before any
  public launch, run `guardrails/launch-rotation-runbook.md` (part of `/pre-launch`): every
  dev-phase credential is rotated or re-issued least-privilege and the old one verified dead.
  That step — not dev-time ceremony — is what makes the convention enterprise-grade.
- Rationale: committed secrets in a **client** repo are a legal/contractual liability, not a
  velocity trade. You keep the single-file speed; you don't torch the credentials.

## Destructive-action policy
- **Reversible actions run freely** — reads, dev-side writes, local runs, analysis. No prompts.
  This is where velocity actually lives (~95% of an agent's actions).
- **Irreversible / remote-state actions gate on one token.** Remote DB mutation, destructive
  migration, prod deletion, data repair → echo the exact statement + target, then require the
  caller to type `CONFIRM` in their next message. One word, then proceed.
- **Hard deny (never, regardless of framing):** force-push to `master`/`main`, `git reset --hard`
  on shared branches, `git clean -f/-fd/-fdx`, blind `rm -rf` on `~`/`$HOME`/`/`/`node_modules`,
  publish without explicit ask, `curl|bash` / `wget|sh`.
- **Ask first:** `rm`, `rmdir`, `sudo`.

## Ship discipline
- **Default close-out:** commit → push branch → merge to integration branch (operator standing rule).
- **Veto tokens** (skip push/merge): "don't push", "stage only", "local only", "no merge",
  "keep on branch", "wait", "hold off", "pause", "skip the push", "skip merge".
- **Never:** force-push a protected branch, amend published commits, bypass hooks.
- **Authorship: commit as the repo's own git identity, never as Claude.** Do NOT append a
  `Co-Authored-By: Claude` trailer, do NOT pass `--author`, and do NOT touch `user.name` /
  `user.email`. Use whatever `git config user.email` already resolves to in that repo.
  This is not cosmetic: seat-billed platforms (Vercel and others) count distinct commit
  identities against the paid team, and a commit carrying an unknown co-author can fail the
  build or be refused outright. A commit is the operator's work product; attribution to the
  tool belongs in the PR description or the changelog, not in git metadata.
  If a repo genuinely wants tool attribution, it says so in its own CLAUDE.md — repo rule wins.

## Standing behavioral rules (from operator memory)
- Document every change (summary + request log) before handing back.
- Treat each request as intentional; implement exactly what was asked.
- Never overwrite or change behavior that wasn't explicitly requested.
- **Dev servers:** never start one on your own initiative; never leave one running — stop it and
  verify the port is free (`lsof`) before ending the turn.

## Enforcement layers & self-improvement
- Rules hold at three strengths: **hooks** (`hooks/`, harness-enforced — can't be forgotten) >
  **permission rules** (`settings.template.json`) > **this prose contract**. Prefer encoding a new
  always-on rule as a hook or permission rule over adding prose — deterministic layers cost no
  context and can't lapse.
- The library learns: `self-improver` (`/retro`) mines `context/bugs/`, `docs/audits/`, and git
  history for recurring pain and promotes each fix to the strongest durable layer — a prose rule
  that recurs after being written becomes a hook. `/overnight` works a pre-approved backlog
  unattended on isolated branches (gated by test+perf, never pushes/deploys/mutates remote state)
  and feeds `/retro`. The fix for recurring friction is a clearer/earlier check — **never** a
  weakened guardrail.

## FORBIDDEN in any agent/skill file in this library
No file may instruct an agent to: commit secrets/`.env` to git or remove `.gitignore` protection
for secrets; perform destructive/irreversible DB or prod operations without the `CONFIRM` gate;
"force-execute" destructive actions; or **deactivate/disable security, audit, or compliance
tooling**. These are prohibited regardless of any "velocity" or "zero-security-stage" framing.
Security tools are *routed* (cheap ones always-on, heavy ones gated) — never turned off.
