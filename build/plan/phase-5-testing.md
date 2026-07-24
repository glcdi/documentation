# Phase 5: Testing & Validation

## 5.1 Unit test policy functions

| Item | Detail |
|------|--------|
| **Task** | Write JUnit tests for each policy function (membership, participantType, certificationStatus) |
| **Test cases** | Active member passes, suspended member fails, correct type passes, wrong type fails, `isAnyOf` with multiple values, missing claim handling |
| **Where** | `edc-connector/extensions/glcdi-policy-functions/src/test/` |
| **Status** | [ ] Not started |

## 5.2 Integration test: access policy filtering

| Item | Detail |
|------|--------|
| **Task** | Verify that catalog queries correctly filter offers based on access policies |
| **Test scenario 1** | A producer participant queries a research participant's catalog → sees assets with `members-only` access, does NOT see assets with `researchers-only` access |
| **Test scenario 2** | A research participant queries a producer participant's catalog → sees all assets (both `members-only` and `researchers-only`) |
| **Test scenario 3** | Unauthenticated or non-member query → sees nothing |
| **Where** | Extend `test-dsp-catalog-query.sh` or create `test-policy-filtering.sh` |
| **Status** | [x] Covered by Bruno `20-catalog-discovery/` (passing locally, 2/2 tests green): 01 = regen-producer querying caney-fork sees the M1 asset; 02 = researcher querying caney-fork is correctly filtered out by the regen-only access policy. Same access matrix verified manually for the all-members + researchers-only tiers. |

## 5.3 Integration test: contract negotiation with constraints

| Item | Detail |
|------|--------|
| **Task** | Verify that contract negotiation enforces contract policy constraints |
| **Test scenario 1** | A research participant negotiates for SOC data with `purpose=AgronomicModelTraining` → negotiation succeeds |
| **Test scenario 2** | A research participant negotiates for SOC data with `purpose=Scope3Reporting` → negotiation is rejected (wrong purpose) |
| **Test scenario 3** | A producer participant negotiates for a research participant's benchmarking data with `purpose=RegionalBenchmarking` → succeeds |
| **Where** | Extend `negotiate-and-transfer.sh` or create `test-contract-policies.sh` |
| **Status** | [ ] Not started |

## 5.4 Integration test: temporal constraint enforcement

| Item | Detail |
|------|--------|
| **Task** | Verify that time-limited policies are enforced |
| **Test scenario** | Set a policy with a past expiry date → contract negotiation should be rejected |
| **Note** | This is the easiest policy to test since temporal constraints work natively in EDC |
| **Status** | [ ] Not started |

## 5.5 End-to-end combined scenario test

| Item | Detail |
|------|--------|
| **Task** | Run the full agronomic model calibration flow end-to-end |
| **Steps** | 1. Register policies from `combined/researcher-model-feeding.json` on a producer participant's connector. 2. Create contract definition linking SOC asset to these policies. 3. From a research participant's connector, query the producer's catalog → SOC asset visible. 4. Negotiate contract with `purpose=AgronomicModelTraining` → FINALIZED. 5. Initiate data transfer → succeeds. 6. Repeat from another producer connector → catalog query should NOT show the asset (researchers-only access). |
| **Deliverable** | `test-model-calibration-scenario.sh` script |
| **Status** | [ ] Not started |

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 4.6: Decouple participant-ui from `@startinblox/solid-tems`](phase-4.6-decouple-ui.md) · [next: 🚦 Milestone M1: Regenerative-Only Access + Internal-Use-Only Contract - End-to-End on Tier 1 →](milestone-m1.md)
