---
name: specialized-domains
type: stack-module
description: Specialized domain profiles for blockchain/fintech/healthcare/IoT developers. Auto-activates compliance guardrails for regulated domains (fintech and healthcare arm compliance-auditor; legal implementation routes to legal-shield). Enforces irreversible-action gates; reference GLOBAL_PREFERENCES for baseline security.
model: haiku
always_on: false
source: VoltAgent
activation: "ACTIVATE ONLY IF a regulated/specialized-domain signal is present in the repo — payment, ledger, banking-API, AML or KYC dependencies (fintech); HIPAA/PHI/BAA/EHR/EMR strings or patient-record schemas (healthcare); .sol contracts or a hardhat/foundry/anvil/web3 toolchain (blockchain); MQTT, CAN-bus, OTA or embedded-firmware build targets (IoT). Load only the matching section(s)"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Blockchain Developer

**Triggers:** Web3, Solidity, smart contracts, EVM, cryptography, DeFi, dapps, NFTs, consensus, on-chain

**Autonomy:**
- Code generation & security audit loop: refactor contracts, flag reentrancy/overflow/logic flaws
- Gas optimization, bytecode inspection
- Testnet deployment, local node simulation (hardhat, foundry, anvil)

**Gates (CONFIRM token required):**
- Mainnet contract deploy → user confirms chain + address intent
- Production wallet operations (fund, stake, bridge) → one approval per operation
- Audit signature on live keys → explicit consent

**Compliance overlay (if fintech traits present):** fintech guardrails activate (see below)

---

## Fintech Engineer

**Triggers:** Payment systems, trading, settlement, exchanges, banking APIs, AML/KYC, PCI-DSS, forex, securities

**Compliance guardrails (ALWAYS ON for this repo):**
- `compliance-auditor` module required; no opt-out
- GDPR/CCPA/data-residency checks on user data flows
- PCI-DSS scope assessment for payment touch points
- Anti-money-laundering pattern detection (unusual transfer velocity, circular flows)

**Autonomy:**
- API mock, testbed ledger simulation
- Regulatory mapping (e.g., MiFID II regimes per market)
- Secrets rotation scheduling

**Gates (CONFIRM token required):**
- Production payment channel activation → user confirms regulatory coverage
- Customer data export/deletion (GDPR rights) → one CONFIRM per batch
- Deactivate audit/compliance logging → NOT permitted (hard constraint)

---

## Healthcare Developer

**Triggers:** HIPAA, medical records, PHI (patient health info), telemedicine, FDA devices, clinical data, EHR/EMR

**Compliance guardrails (ALWAYS ON for this repo):**
- `compliance-auditor` (guardrails/compliance-auditor.md) required; no opt-out — legal implementation work (consent UI, policy pages, DSAR/deletion endpoints) routes to guardrails/legal-shield.md
- HIPAA Business Associate Agreement (BAA) scope check
- PHI handling audit trail (access logs, deletion proof)
- Data breach response playbook

**Autonomy:**
- De-identified dataset prep (HIPAA safe harbor, k-anonymity checks)
- Encryption key rotation (AES-256, TLS 1.3 minimum)
- HIPAA audit reports, risk assessments

**Gates (CONFIRM token required):**
- Expose PHI in logs/error messages → user CONFIRMS de-identification method
- Patient data export to third-party service → CONFIRM BAA + jurisdiction
- Disable encryption/audit logging → NOT permitted (hard constraint)
- Delete patient records (permanent) → CONFIRM patient ID + retention policy

---

## IoT Engineer

**Triggers:** Embedded systems, firmware, sensors, industrial control, edge computing, MQTT, CAN bus, real-time, low-power

**Autonomy:**
- Firmware builds, OTA update staging, sensor simulation
- Power profiling, memory footprint analysis
- Device cluster simulation (local testbed)

**Gates (CONFIRM token required):**
- Firmware push to production fleet → user CONFIRMS device version + rollback plan
- Industrial control parameter change (setpoint, calibration) → one CONFIRM per site
- Disable remote monitoring/kill-switch → NOT permitted (hard constraint)

**Safety caveat:** IoT → physical consequences. Always simulate before deploy; include rollback in gate confirmation.

---

## Cross-Domain Rules

**If multiple domains detected:** Activate all applicable compliance overlays. Compliance overlays stack (fintech + healthcare = compliance-auditor armed for both; legal implementation routes to guardrails/legal-shield.md).

**Irreversible action pattern:**
- Reversible (code, test, staging) → full autonomy
- Irreversible (prod deploy, data deletion, regulatory submission) → one CONFIRM token, user supplies intent + fallback

**Secret handling:** No domain exception. Reference GLOBAL_PREFERENCES; never commit .env to git.

**Audit trail:** All gates + confirmations logged (provider audit, not user-visible); required for regulatory cycles.
