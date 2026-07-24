# Phase 6: Governance-Level Enforcement (Non-Technical) - Proposal

Some policy obligations cannot be technically enforced by the connector. These would need
governance-level support through the Trust Framework and Data Sharing Agreements. The items
in this phase are proposals for the governance body to consider and refine.

## 6.1 Embed policy obligations in Data Sharing Agreement templates

| Item | Detail |
|------|--------|
| **Task** | Propose updates to MOU/DSA templates that include clauses mapping to ODRL obligations; validate with legal counsel and the governance body |
| **Proposed clauses** | Anonymisation requirements (what counts as anonymised, at what geographic granularity), attribution format and placement, data retention/deletion procedures and confirmation process, non-redistribution commitments, purpose limitations |
| **Deliverable** | Updated DSA template in the Trust Framework (v0 → v1), pending governance-body approval |
| **Status** | [ ] Not started |

## 6.2 Define audit and compliance mechanisms

| Item | Detail |
|------|--------|
| **Task** | Propose how governance-level obligations (anonymisation, deletion, attribution) could be verified, for governance-body sign-off |
| **Options to consider** | Self-attestation (lightweight, suitable for prototype), periodic review by the governance body, automated checks where possible (e.g., scanning published papers for attribution) |
| **Deliverable** | Compliance section in Trust Framework v1, pending governance-body approval |
| **Status** | [ ] Not started |

## 6.3 Design consent revocation flow

| Item | Detail |
|------|--------|
| **Task** | Propose what would happen when a producer wants to revoke consent for a previously shared dataset |
| **Considerations** | Contracts already finalized cannot be technically un-done, but new transfers can be blocked. Retention limits (e.g., `data-retention-limit.json`) provide a natural expiry. It is proposed that revocation trigger a notification to the consumer with a deletion request. |
| **Deliverable** | Revocation procedure documented in Trust Framework, pending governance-body approval |
| **Status** | [ ] Not started |

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: 🚦 Milestone M1: Regenerative-Only Access + Internal-Use-Only Contract - End-to-End on Tier 1](milestone-m1.md) · [next: Phase 7: Future Enhancements (Post-Prototype) →](phase-7-future.md)
