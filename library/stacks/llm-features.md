---
name: llm-features
type: stack-module
description: Specialized guidance for data engineers, ML engineers, and LLM architects building net-new ML pipelines, feature stores, data infrastructure, and LLM-backed systems. Covers data validation, model training orchestration, inference patterns, prompt engineering iteration, and safe data handling. Activates when machine-learning surfaces, data pipelines, or LLM-integration work appears in scope.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF an ML or data-pipeline surface exists"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Data Pipeline & Validation

- **Schema first**: Validate schema at pipeline entry; fail loudly on type mismatches, nulls, outliers before ML stages.
- **Lineage tracking**: Log data source, transformations, versioning. Enable root-cause analysis on model drift.
- **Irreversible DB ops require CONFIRM**: deletions, truncations, resets in production data stores need one-token gate before execute.

## Feature Engineering & Store

- **Modular feature definitions**: version features independently; enable backfill, replay, A/B testing.
- **No raw-secret features**: redact PII, credentials before storing; use reference tokens if cross-dataset joins needed.
- **Monitoring**: set up diffs on feature distributions; alert on statistical drift early.

## Model Training & Lifecycle

- **Experiment tracking**: log hyperparams, metrics, artifacts to a versioned store (MLflow, W&B, or custom). Make reproducibility cheap.
- **Train/val/test split**: always stratified for imbalanced targets; hold-out test set locked until final eval.
- **Reversibility**: keep training code immutable; tag releases; enable rollback if new model underperforms in canary.

## Inference & Serving

- **Batch vs. real-time trade-offs**: explicit SLA, latency, throughput targets before choosing pattern.
- **Graceful degradation**: fallback rules, circuit breakers, stale-cache rules if inference service fails.
- **Input validation at serve boundary**: same schema checks as training pipeline.

## LLM Integration Patterns

- **Prompt versioning**: treat prompts as code; version, test, diff in version control.
- **Retrieval-augmented generation (RAG)**: validate chunk quality, measure relevance; monitor hallucination metrics.
- **Token budgeting**: track input/output token costs; set per-request caps; use cheaper model for filtering if applicable.
- **Few-shot example curation**: validate example quality; ablate to find minimal effective set; rotate examples if drift detected.

## LLM Prompt Discipline (generalized)

Vendor-agnostic rules for any LLM-backed feature (multi-provider routing mechanics live in the
`llm-provider-router` module):

- **Structured-output schemas**: every model call declares an output schema; validate before use, reject-and-retry on mismatch — never parse free text by hope.
- **Cached-prefix design**: split prompts into a stable system prefix (task spec, format rules, few-shots — cache-hit) and a variable per-request payload; never interleave the two.
- **Thinking budget & temperature per action class**: deterministic extraction/classification → low temperature, minimal thinking; open generation/evaluation → higher budget. Set both explicitly per action class, never one global default.
- **Two-pass self-verify**: for high-stakes outputs, a second pass checks the first against the schema and source material before the result is surfaced.
- **Evidence-linked outputs**: claims cite their source (input span, doc ID, retrieval chunk); unsupported claims are dropped, not shipped.
- **Golden-set regression tracking**: keep a versioned set of input→expected pairs; run it on every prompt or model change and diff scores before shipping.

## Monitoring & Observability

- **Model performance tracking**: log predictions, actuals, latency, error rates; detect performance regression in production.
- **Data quality SLOs**: define acceptable null rates, outlier frequencies, distribution shifts; alert before retraining needed.
- **Cost tracking**: ML spend per use case, per inference query; flag cost anomalies.

## Secrets & Data Governance

- **No plaintext credentials in code or notebooks**: use credential managers (vault, envvars, KMS).
- **Data access controls**: enforce row/column-level filters; audit data exports.
- **Lineage for compliance**: maintain audit trail of who accessed what data, when, for regulatory reviews.

## Iteration & Velocity

- **Local simulation before cloud**: test pipelines, feature logic, inference on small local datasets first.
- **Dry-run mode**: separate code deploys (no data impact) from pipeline executions (data change).
- **Lightweight validation before commit**: type checks, schema validation, linting on code; never push broken pipelines.
