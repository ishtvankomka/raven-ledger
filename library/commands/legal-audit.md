---
name: legal-audit
description: >-
  /legal-audit [markets...] — run the legal-shield guardrail in AUDIT mode for the given target
  markets (default: detect from locales + operator LEGAL_FACTS). Writes docs/audits/YYYY-MM-DD-legal.md
  listing each gap with severity + the one-line implement command that fixes it. Exit 1 on any
  high-severity gap, so it slots into CI and the /pre-launch gate.
allowed-tools: Read, Grep, Glob, Bash, Write, Task
model: haiku
source: this library (original)
always_on: false
activation: "on-demand any repo"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# /legal-audit [markets...]

## Steps

1. **Resolve target markets.** Use the `[markets...]` args if given (e.g. `eu us cz`). Otherwise:
   read the LEGAL_FACTS block in CLAUDE.md (installed by INSTALL_PROMPT.md step 9, fallback
   `docs/launch/`), and detect from the repo's locale set (`locales/`, `messages/`, i18n config). If neither
   resolves, default to `eu us` and say so in the report header.
2. **Run legal-shield AUDIT mode** — spawn `guardrails/legal-shield.md` via Task (or load it
   directly if subagents are unavailable) scoped to AUDIT only: data-flow inventory → obligations
   matrix for the resolved markets → ranked gap report. Never let it slide into IMPLEMENT here.
3. **Write the report** to `docs/audits/YYYY-MM-DD-legal.md` (today's date; create `docs/audits/`
   if missing).
4. **Print the summary** — one line per gap, most severe first, then the exit code.

## Report format

```
# Legal audit — <date> — markets: <list>

[HIGH] <gap one-liner> (<jurisdiction + rule>)
  Fix: <one-line legal-shield IMPLEMENT invocation>
[MED]  ...
[LOW]  ...
```

Each gap MUST carry the exact implement command — the report is a work list, not an essay.

## Exit codes

- `0` — no high-severity gaps (mediums/lows may remain; they're listed).
- `1` — at least one high-severity gap. CI-usable: wire into the /pre-launch gate or a pipeline step.

## Rules

- AUDIT only — this command never writes to app code; implementation goes through legal-shield
  IMPLEMENT on operator confirmation.
- Missing LEGAL_FACTS is not a blocker for AUDIT (report it as a gap); it IS a blocker for IMPLEMENT.
- Findings are legal-risk rankings, not legal advice — the report footer states drafts/findings
  require counsel review.
