---
name: mcp-servers
type: stack-module
description: Harness four production MCP servers for browser automation (Playwright), UI code generation (Magic), up-to-date library/framework docs (Context7), and semantic code retrieval/editing with project memory (Serena). Routes credentials through sandbox isolation; read-only by default on external state.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the MCP server is wired in .mcp.json"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Playwright (Browser Automation)

**Purpose:** Headless browser control for crawling, screenshots, form filling, interaction testing.

**Scope:**
- Navigate URLs, capture DOM/accessibility trees, extract text/metadata
- Interact: click, type, submit forms, wait for elements
- Screenshot/video recording of state changes
- Read-only by default; write actions (clicks, form fills) require explicit user intent

**Test-environment carve-out:** against local/test environments, autonomous clicks and form fills are allowed as part of an iterate-until-green loop driven by `agents/test-automator.md`. Explicit user intent is still required for production sites.

**No override:** Browser history/cache cleared per-session unless explicitly persisted for test continuity.

---

## Magic (UI Code Generation)

**Purpose:** Convert design mockups or screenshots into component code (React/Vue/HTML).

**Scope:**
- Screenshot → HTML/component scaffolding
- Extract layout, typography, colors from visual input
- Generate tailored JSX/template + style bindings
- Integrated with Figma/design tokens when available

**Constraint:** Output is template-grade; always review for accessibility, responsiveness, and brand compliance before shipping.

---

## Context7 (Library & Framework Docs)

**Purpose:** Up-to-date documentation for libraries and frameworks — version-specific API references and code snippets, fetched live instead of relying on stale training data.

**Scope:**
- Resolve a library/framework name to its docs, pinned to the version in use
- Retrieve current API signatures, config options, and code snippets
- Read-only; no mutation of any docs

**Usage:** Prefer Context7 over memory when the library has moved fast or the version matters; cite the retrieved doc in responses.

---

## Serena (Semantic Code Retrieval & Editing)

**Purpose:** LSP-based semantic code retrieval and editing — find/edit symbols by meaning rather than grep, plus project memory files that persist project knowledge across sessions.

**Scope:**
- Symbol-level search: find definitions, references, and usages via language-server intelligence
- Targeted semantic edits (rename, insert-at-symbol) instead of whole-file rewrites
- Project memory files: read on session start, write learned project facts at checkpoints

**Credential handling:** Token (if any) stored in `env/<env>.env` (git-ignored) per GLOBAL_PREFERENCES; rotate before launch per `guardrails/launch-rotation-runbook.md`.

---

## Credential & Sandbox Rules

- **Storage:** All MCP tokens live in `env/<env>.env` (git-ignored, per GLOBAL_PREFERENCES) or a locked vault; never hardcoded or logged.
- **Scope:** Playwright sandbox isolated per user; Magic outputs reviewed; Context7 read-only; Serena memory files scoped to the project.
- **Rotation:** rotate on leak per GLOBAL_PREFERENCES; rotate all dev-time tokens before launch per `guardrails/launch-rotation-runbook.md`.

---

## Integration Checklist

- [ ] Each server you intend to use is wired in `.mcp.json` (endpoint, auth key names)
- [ ] `env/<env>.env` populated with sandbox tokens (git-ignored, not in git)
- [ ] First-run: load Serena project memory files if Serena is wired
- [ ] Playwright: confirm headless + sandbox mode enabled
- [ ] Magic: test one screenshot → code roundtrip
- [ ] Context7: fetch one library's docs as smoke test
