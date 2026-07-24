# GLCDI Open Questions

A living list of decisions that are pending across the GLCDI project — surfaced from the rest of `management/` so a reviewer joining the project can see, in one place, what is not yet decided and who needs to decide it. Items resolved by the Dataspace Authority or the project team move out of this list and into the relevant doc.

Everything below is a proposal for the project team and Dataspace Authority to review; nothing here is a decided commitment.

Grouped by decision-maker.

---

## Needs a decision from the Dataspace Authority (once seated)

Governance-body items — cadence, cohorts, and ratifications of the vocabularies + onboarding sequences the code already relies on.

### Governance body operating mode

| # | Question | Currently marked | Source |
|---|----------|------------------|--------|
| 1 | Dataspace Authority standing-session cadence | "Monthly (indicative — to be agreed)" | [`authority.md`](authority.md) |
| 2 | Cohort 3 composition + timing (participant type mix) | `TBD` (expanded institutional participation, Q3 2026) | [`../README.md` § Cohort Timeline](../README.md#cohort-timeline-proposal) |
| 3 | Post-prototype onboarding cadence and criteria | `TBD` (rolling institutional + corporate onboarding, 2027+) | [`../README.md` § Cohort Timeline](../README.md#cohort-timeline-proposal) |

### Ratifications the code already relies on

These are documented as proposals; the code and realm JSON already encode them for the M1 subset. Ratification is a formality but load-bearing for downstream governance work.

| # | Ratification | Status | Source |
|---|--------------|--------|--------|
| 4 | GLCDI kebab-case vocabulary for statuses / types / outcomes (`producer`, `researcher`, `data-steward`, `regenerative-verified`, etc.) | Proposal encoded in `context.jsonld` + realm JSON | [`../IMPLEM_PLAN.md` § 1](../build/implementation-plan.md) |
| 5 | PascalCase ODRL purpose vocabulary (`InternalAnalysis`, `ModelTraining`, etc.) | Proposal encoded in `context.jsonld` | [`../IMPLEM_PLAN.md` § 1](../build/implementation-plan.md) |
| 6 | Tier-1 onboarding sequence (form → admin approval → KC group + user + temp password mail) | Proposal, local smoke passing | [`../IMPLEM_PLAN.md` § 2.7](../build/plan/phase-2-keycloak-claims.md#27-integration-with-the-onboarding-flow-tier-1-out-of-band) |
| 7 | Trust Framework v0 wording (DSA template, participant obligations, refund adjudication scope) | Deliverable pending governance-body approval | [`../IMPLEM_PLAN.md` § 6.1](../build/plan/phase-6-governance.md) |
| 8 | Trust Framework compliance section (self-attestation, audit rights, escalation) | Deliverable pending governance-body approval | [`../IMPLEM_PLAN.md` § 6.2](../build/plan/phase-6-governance.md) |
| 9 | Revocation procedure (consent revocation, agreement invalidation) | Deliverable pending governance-body approval | [`../IMPLEM_PLAN.md` § 6.3](../build/plan/phase-6-governance.md) |
| 10 | Rollout / cohort-sequencing proposal for policies (which policies land at which cohort) | Proposal in `policies/plan.md` | [`../reference/policies/plan.md`](../reference/policies/plan.md) |
| 11 | Human-user onboarding proposal at Tier 2 (post-M1) | Proposal, not ratified; only triggers when Tier 2 is approved | [`../IMPLEM_PLAN.md` § 7.2.5](../build/plan/phase-7-future.md#725-tier-2-onboarding-flow) |

---

## Resolved

Kept here as a short changelog so a reviewer can see recent decisions without diffing history.

| # | Question | Resolution | Date |
|---|----------|------------|------|
| — | Governance body naming: "Authority" vs. "Committee" / "Council" / "Trust Body" | Keep **Dataspace Authority** (working name) | 2026-07-24 |
| — | Tier-1 Authority cutover (cutover date, rollback owner, cutover-vs-parallel strategy) | Completed — `governance-*` → `authority-*` rename applied to staging; cutover strategy used. The migration runbook has been removed as it no longer applies. | 2026-07-24 |

---

## Not tracked here (out of scope for this document)

The following are known deferred items but do not need a decision — they are scheduled work or waiting on external dependencies. They live in `../IMPLEM_PLAN.md`, not here:

- Phase 5.1 EDC-extension unit tests
- Participant-UI `tems-transfers-list` component wiring (Track F deferred finding)
- Dataplane split into its own runtime module (Phase 7+, only if independent scaling is needed)
- `w3id.org` namespace redirect registration (post-prototype)
- Federated Catalogue (XFSC) deployment (external dependency; currently deferred from the governance stack)
- Tier-3 Verifiable Credentials design details (long-term direction; specified as target, not as design proposal)

---

## Editing conventions

- **When a question is resolved**, move its row into the *Resolved* section with the decision + date.
- **When a new question surfaces**, add a row and link back to the source doc so a reviewer can read the context.
- **Do not use this document for backlog tracking** — that's [`../IMPLEM_PLAN.md`](../build/implementation-plan.md). Only add items here that genuinely need a decision.
