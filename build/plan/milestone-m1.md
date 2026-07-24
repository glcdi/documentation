# 🚦 Milestone M1: Regenerative-Only Access + Internal-Use-Only Contract - End-to-End on Tier 1

**Gate before Phase 7.1 (Payment-required workflow) starts.** M1 ships on **Tier 1 identity** (§ Identity Tiering Strategy) - `iam-oauth2` between connectors, `X-Api-Key` on the UI, no end-user OIDC. Tier 2 (§ 7.2) and Tier 3 (§ 7.3) sit as post-M1 candidate workstreams; neither is required for M1 sign-off.

M1 is demonstrable when, against a deployed three-participant cluster - **`caney-fork`** (regenerative producer, provider), **`white-buffalo`** (regenerative producer, positive consumer), **`point-blue`** (researcher, negative-test consumer) - the following all pass:

- [ ] Authority Keycloak has 3 connector clients + service-account users (per § 1.5.4):
  - `glcdi-connector-caney-fork` and `glcdi-connector-white-buffalo`: SAs carry `glcdi_member`, `glcdi_producer` realm roles and `glcdi_certification_status = regenerative-verified`.
  - `glcdi-connector-point-blue`: SA carries `glcdi_member`, `glcdi_researcher` realm roles and `glcdi_certification_status = not-applicable`.
  - All 3 clients have `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false` and the `glcdi-claims` default scope.
- [ ] `iam-oauth2` is wired in each participant's connector (§ 3.5) against Authority KC. A `client_credentials` token mint at startup decodes to a JWT carrying the org's `glcdi_*` claims (verified per § 2.5).
- [ ] `caney-fork` connector publishes an asset whose **access policy** is `regenerative-producers-only` (Phase 4) and whose **contract policy** is `internal-use-only` (Phase 4).
- [ ] `white-buffalo` (regen producer) sees the asset in the catalog query against `caney-fork`. **Positive case.**
- [ ] `point-blue` (researcher) does **not** see the asset in the catalog query - filtered out by the access policy. **Negative case (the policy is doing its job).**
- [ ] `white-buffalo` negotiates with `caney-fork` declaring `purpose = InternalAnalysis` → reaches `FINALIZED`. With a different purpose → reaches `TERMINATED`.
- [ ] Transfer succeeds against the agreed contract (`white-buffalo` ← `caney-fork`).
- [ ] The Bruno collection (§ 4.5.E) executes all of the above non-interactively against the management API with `X-Api-Key` only - green run.
- [ ] The participant UI (§ 4.5.F) surfaces asset / policy / contract / history / transfer-process components correctly under API-key login. **No OIDC envvars set anywhere.**
- [ ] Per-participant Keycloak and oauth2-proxy are gone from the deployed compose stack (§ 1.5.2). The participant compose is `connector + identity-hub + UI + nginx + 2× postgres` only.

Once M1 is signed off, three workstreams become candidates: **Phase 7.1** (payment-required workflow per [`design/payment-gating.md`](../../design/payment-gating.md)), **Phase 7.2** (Tier 2: add user OIDC to the UI), and **Phase 7.3** (Tier 3: VC/DCP migration). Sequencing among them is a stakeholder decision, not a technical one - they don't block each other. Phase 6 (governance-level enforcement) continues in parallel throughout.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 5: Testing & Validation](phase-5-testing.md) · [next: Phase 6: Governance-Level Enforcement (Non-Technical) - Proposal →](phase-6-governance.md)
