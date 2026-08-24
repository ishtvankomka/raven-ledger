---
name: payments
type: stack-module
description: Paddle (Merchant of Record for checkout & tax) and RevenueCat (mobile subscription lifecycle). Keep sandbox mode until launch. Model payment fees as revenue reductions. Coordinate webhooks, test full flow locally, validate tax jurisdiction rules.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo integrates Paddle and/or RevenueCat"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Paddle (MOR + Checkout)

**Sandbox-first rule:** `PADDLE_ENVIRONMENT=sandbox` until production launch. Test all flows in sandbox.

- **Keys:** `PADDLE_API_KEY` (server-side), `PADDLE_CLIENT_TOKEN` (frontend) — these are Paddle's own names, keep them.
- **Checkout target:** the checkout also needs the price/product identifier it opens with (a value from your Paddle catalog, per plan and per environment — sandbox and live IDs differ). Paddle defines no env-var name for it: store it under whatever variable name the repo already uses, and never introduce a second name for the same value.
- **Tax handling:** Paddle auto-computes VAT/GST/sales tax by jurisdiction; respect its jurisdiction rules in checkout
- **Webhooks:** Configure IP whitelist + webhook signing secret; validate `X-Paddle-Signature` on every event
- **Events to monitor:** `transaction.created`, `transaction.completed`, `transaction.billed`, `subscription.created`, `subscription.updated`, `subscription.paused`, `subscription.canceled`
- **No custom tax override:** Paddle's rules are binding; don't circumvent them

## RevenueCat (Mobile Subscriptions)

- **Keys:** `REVENUECAT_API_KEY`, `REVENUECAT_PUBLIC_SDK_KEY`
- **Entitlements:** Define product-to-entitlement mapping (e.g., `premium` → unlock features)
- **Webhooks:** Subscribe to `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `BILLING_ISSUE` events
- **Sync with Paddle:** RevenueCat may handle iOS/Android; Paddle handles web. Keep user subscription state consistent across both
- **No double-charge:** Ensure a user is not billed on both platforms for the same period

## Payment Fee Modeling

- **Revenue impact:** Payment fees reduce net revenue — Paddle ~5% + $0.50 per transaction; app stores (Apple/Google) take 15–30% commission; RevenueCat ~1% of tracked revenue above its free tier. Verify current pricing at integration time.
- **Unit economics:** Track gross vs. net separately; delegate margin analysis to the `unit-economics-analyst` agent (an agent, not a slash command)
- **Do NOT hide fees** in reporting; surface them clearly in financial dashboards

## Testing & Validation

- **Local sandbox flow:** Use test card numbers (Paddle provides them); validate webhook delivery via ngrok/local tunnel
- **Full subscription cycle:** Create → renew → cancel → reactivate; verify state consistency
- **Tax edge cases:** Test US (state-specific), EU (VAT reverse-charge), CA (GST/PST); confirm Paddle applies correct rates
- **Error paths:** Test declined payments, expired cards, subscription pause/downgrade

## Integration Checklist

- [ ] Paddle + RevenueCat API keys in `env/<env>.env` (git-ignored; match the existing repo convention if one exists) and validated with a sandbox test call
- [ ] Webhook endpoints public + signature-verified; delivery validated in sandbox via tunnel before go-live
- [ ] Entitlements/products defined in both systems
- [ ] Revenue reporting pipeline includes fee deductions
- [ ] Go-live: switch `PADDLE_ENVIRONMENT` to `live`, repoint the checkout at the live catalog's price/product identifier (sandbox IDs are not valid in live), rotate all payment keys per `guardrails/launch-rotation-runbook.md`, enable real webhooks
