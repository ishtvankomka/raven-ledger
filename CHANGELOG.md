# Changelog

Versions follow [semver](https://semver.org) and live as git tags; each release
gets an entry here.

## 1.0.0 — 2026-08-24

First public release.

- `library/`: 27 agents, 16 commands, 21 skills (plus 5 vendored design skills),
  19 stack modules, 8 guardrails, 4 harness hooks.
- `sync/`: the two-way mesh — capture hook, session-start pull, `/promote`
  curation, shared secret gate, session ledger and digest, per-turn skill router,
  contract validator, upstream template check.
- Distributed as a GitHub template repository: create your own copy and run your
  own ledger (see `PUBLISHING.md`).
