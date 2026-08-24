---
name: llm-provider-router
type: stack-module
description: Architecture rules for a provider-agnostic LLM router — the adapter layer that sits between application code and one or more model vendors. Covers the adapter contract, task-to-model tiering (cheap/fast vs. quality/judge), cached-prefix request shaping, deterministic structured output, the mock/fixture swap seam, key handling, and the procedure for adding or switching a provider without touching callers. Complements llm-features (prompt and data discipline); this module is about the routing layer itself.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo calls an LLM through its own router/adapter layer, or a second model tier, provider, or bring-your-own-key path is being added"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## When this module applies

A repo qualifies when model calls do **not** go straight from feature code to a vendor SDK, but pass
through a local routing module that picks a provider and model per task. If there is exactly one call
site and no intent to add a second provider, skip this module — use llm-features's prompt discipline alone
and revisit when a second tier appears.

## Module layout (convention, not a fixed path)

Keep the routing layer in one server-side directory, never split across feature folders:

```
<server>/llm/
  router.ts        # the only entry point feature code imports; dispatch + task→model policy
  providers/       # one file per vendor adapter, each implementing the same interface
  schema.ts        # output schemas, one per task; the single source of truth for parsing
  prompts/         # or an external prompt spec — see "Prompt residence" below
  mock.ts          # fixture responses + the swap seam
```

Rules:
- Feature code imports `router` only. A vendor SDK imported anywhere outside `providers/` is a defect.
- Never let a provider type leak into a caller's signature (no vendor request/response types in the
  application layer) — that is how "provider-agnostic" quietly stops being true.

## Adapter contract

Two interfaces, kept deliberately small so a new vendor is a day's work, not a refactor:

```ts
interface RouteRequest {
  task: string              // action class: e.g. 'generate' | 'evaluate' | 'classify'
  systemPrompt: string      // stable, cacheable prefix
  userPrompt: string        // per-request variable payload
  model?: string            // explicit override; otherwise resolved from task policy
  temperature?: number      // otherwise resolved from the task's action class
}

interface RouteResponse {
  model: string             // which model actually served it — always echoed back
  output: Record<string, unknown>  // schema-validated, never raw text
  usage?: { inputTokens: number; outputTokens: number }
}

interface ProviderAdapter {
  initialize(apiKey: string): Promise<void>
  route(req: RouteRequest): Promise<RouteResponse>
}
```

- `model` on the response is not optional — cost attribution and regression triage both need to know
  which tier answered.
- `usage` is optional at the type level only because some vendors omit it; capture it whenever the
  provider returns it, and feed it to whatever tracks per-feature model spend.

## Task → model tiering

Assign models per **action class**, not per feature, and write the policy down in one place:

- **Latency-sensitive / high-volume generation** → the cheapest model that passes the golden set.
- **Evaluation, judging, or second-pass verification** → a stronger model; a judge weaker than the
  generator produces noise, not signal.
- **Deterministic extraction/classification** → cheapest model, low temperature, minimal reasoning budget.

Changing a tier is a behavioral change: re-run the golden set (llm-features) and diff scores before it ships.
Never let a tier default silently to "whatever the SDK's default model is" — pin model identifiers in
the policy table so an upstream default rotation cannot move your behavior underneath you.

## Request shaping

- **Cached prefix vs. variable payload.** The system string is stable per task and should be byte-identical
  across requests so provider-side prefix caching hits; the per-request builder produces only the user
  payload. Interleaving the two (e.g. injecting a timestamp or user ID into the system string) destroys the
  cache hit and is the most common regression in this layer.
- **Streaming off by default** where the output is parsed as a whole. Deterministic parse beats perceived
  latency for anything a downstream step consumes structurally. Enable streaming only for surfaces that
  render tokens to a human.
- **Structured output enforced at the adapter**, not at the call site: the adapter validates against the
  task's schema and rejects (or retries once with the validation error appended) before returning.

## Prompt residence

- Prompts live in a versioned spec — a prompt directory or a docs file — never inline in `router.ts`.
- The router injects prompts; it does not author them. This keeps prompt edits reviewable as content
  changes and keeps routing edits reviewable as code changes.
- Version prompts alongside their schema: a prompt change that alters output shape must land with the
  matching schema change in the same commit.

## Mock / fixture seam

- One swap point, checked **before** the provider call, toggled by a single environment flag (e.g. an
  `LLM_MOCK` style boolean) or an explicit config value — never by scattered per-call conditionals.
- Fixtures must satisfy the same schema validation as live responses. A mock that bypasses validation
  hides exactly the bugs the seam exists to catch.
- Keep at least one fixture per task, plus one deliberately malformed fixture so the reject/retry path
  stays exercised in tests.

## Keys, failures, and cost

- **Keys via environment only** (`<PROVIDER>_API_KEY` per vendor), resolved at adapter initialization.
  Never in code, config files, or client bundles. A missing key is a startup/route error.
- **No silent fallback.** If the selected provider fails or the key is absent, propagate an explicit
  error. Do not quietly downgrade to another provider, another model, or a stub — a silent fallback
  turns an outage into an unexplained quality regression. A *declared* fallback chain is acceptable only
  when it is part of the task policy and the response's `model` field reveals which tier answered.
- **Timeouts and one bounded retry** per call; retries are for transport and schema-validation failures,
  not for "the answer looked wrong".
- Log per-task token usage so model spend can be attributed to features (hand the numbers to whatever
  unit-economics tooling the project has).

## Adding or switching a provider

1. Add `providers/<vendor>.ts` implementing `ProviderAdapter`; keep all vendor-specific request/response
   translation inside that file.
2. Register it in the router's dispatch, keyed off configuration or the presence of its key variable.
3. Map the vendor's model identifiers into the existing task tiers — do not invent new task names to fit
   a vendor's catalogue.
4. Add fixtures for the new adapter and run the golden set against it; compare scores to the incumbent
   before switching any tier's default.
5. Confirm the cached-prefix split still holds — vendors differ in how a cacheable prefix must be marked.

## Bring-your-own-key paths

If end users supply their own keys: never persist a user key in plaintext, never log it, scope it to the
request, and keep the same adapter contract — a user-supplied key selects an adapter instance, it does not
create a second code path. Attribute usage to the key owner, and surface provider errors to that user
verbatim enough to be actionable without echoing the key.

## Related

- **llm-features** — prompt versioning, golden-set regression, RAG, token budgeting, evidence-linked output.
  This module deliberately does not restate those; it covers only the routing/adapter layer.
