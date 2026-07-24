# GLCDI Dataspace Authority - Proposal

A proposal for the responsibilities, composition, and operating mode of the governance body provisionally named the **Dataspace Authority**. Everything below is put forward for discussion with the body itself once seated; nothing here is a decided commitment.

This document answers: *what would the Dataspace Authority be accountable for, how would it decide, and where does its remit end?* It is intentionally separate from [`README.md`](../README.md) so the body can review, edit, and ratify its own terms of reference without sprawling across the rest of the documentation.

## Naming caveat

"Dataspace Authority" is a working name. Two things to flag for the body to weigh in on:

- **Terminological collision.** In the wider dataspace literature (Gaia-X, IDSA, DSBA), "Authority" has specific meaning - Federation Authority, Participant Authority, Sector Authority - typically bodies that *issue credentials* and act as technical trust anchors. Under this proposal the body's remit is governance-and-approvals, not credential issuance; the name may be stronger than the role.
- **Proposal tone.** This document, and the rest of `management/`, frames governance content as proposals because the body has not yet agreed its own scope. "Authority" is a firmer label than "Committee" or "Council" and may preempt that agreement.

Alternative names to consider: *Governance Council*, *Dataspace Council*, *Trust Body*, *Participant Council*. Keeping "Steering Committee" is also an option. The rest of this document uses "Dataspace Authority" as the current working name.

---

## Why a governance body exists at all

GLCDI is a **consent-governed, permissioned** dataspace - participants retain control over their data, and access is mediated by policies and by a shared Trust Framework. Several decisions cannot be automated or delegated to individual participants:

- Who is allowed into the dataspace (membership approval).
- What participant *types* and *certification statuses* mean (shared vocabulary).
- Which obligations appear in the Data Sharing Agreement and how compliance is checked.
- When a cohort is ready to close out and the next one to start.
- What to do when a participant allegedly breaches an obligation.

A standing body is proposed because these decisions recur, touch every participant, and require institutional memory. Without it, each decision would have to be reopened with the full participant set every time - which is not workable beyond a small prototype.

---

## Proposed responsibilities

Grouped by theme. "Proposed" means the project team is putting this forward as a starting point for the body to amend. Cross-references point to where each topic is treated in detail elsewhere.

### A. Membership & onboarding

| Responsibility | Detail | Cross-reference |
|----------------|--------|-----------------|
| Review participant applications | Confirm stated organisation, participant type, certification evidence; approve or reject onboarding | [`README.md` § Onboarding Flow](../README.md) (replaced - see below), [`../reference/identity.md` § Onboarding Flow (Proposed)](../reference/identity.md#onboarding-flow-proposed) |
| Approve role assignment | Assign realm roles (`glcdi_member` + participant-type role) and initial certification status on approval | [`../reference/identity.md` § Proposed Participant Role Assignments](../reference/identity.md#proposed-participant-role-assignments) |
| Suspend or offboard | Revoke membership on serious or repeated Trust Framework breach; define what "serious" means | §C below |
| Maintain the participant-type taxonomy | Own the canonical list of participant types (`producer`, `researcher`, `data-steward`, …) | [`IMPLEM_PLAN.md` § 1.2](../IMPLEM_PLAN.md) |

### B. Identity & certification (prototype-era manual steward)

| Responsibility | Detail | Cross-reference |
|----------------|--------|-----------------|
| Self-certify producer regenerative status | For C1–C2 the Authority informally attests producer `glcdi_certification_status` values; post-prototype transitions to a formal cert-evidence workflow | [`../reference/policies/plan.md` § Cohort 1](../reference/policies/plan.md), [`../reference/identity.md` § Onboarding Flow](../reference/identity.md) |
| Maintain `glcdi_certification_status` | Set and update the per-user Keycloak attribute; define allowed values | [`IMPLEM_PLAN.md` § 2.2](../IMPLEM_PLAN.md) |
| Maintain `glcdi_contribution_status` | Flip to `contributing` once a participant has published their first asset (manual for prototype; automated crawler later) | [`IMPLEM_PLAN.md` § 2.2](../IMPLEM_PLAN.md), [`../reference/policies/README.md` § contributing-members](../reference/policies/README.md) |
| Formalise cert evidence post-prototype | Define what third-party proof (USDA Organic, Regenerative Organic Certified, self-declaration rules) counts once institutional participants onboard | [`../reference/policies/plan.md` § Post-prototype](../reference/policies/plan.md) |

### C. Trust Framework, DSAs & policy curation

| Responsibility | Detail | Cross-reference |
|----------------|--------|-----------------|
| Author and publish the Trust Framework | Draft, review, and release v0 / v1 / v2 of the living document codifying governance norms, templates, and compliance expectations | [`README.md` § Trust Framework](../README.md#trust-framework) |
| Approve DSA template wording | Sign off on Data Sharing Agreement clauses (alongside legal counsel) for each ODRL duty and prohibition that the connector cannot technically enforce | [`IMPLEM_PLAN.md` § 6.1](../IMPLEM_PLAN.md) |
| Approve the ODRL purpose taxonomy | Own the canonical set of `odrl:purpose` values (`InternalAnalysis`, `AgronomicModelTraining`, `Scope3Reporting`, …) | [`IMPLEM_PLAN.md` § 1.3](../IMPLEM_PLAN.md) |
| Curate the participant-facing policy template library | Decide which policies are selectable in the UI vs. project-team-seeded at each phase | [`../reference/policies/plan.md` § Participant-facing template library per cohort](../reference/policies/plan.md) |
| Approve hardcoded-vs-per-user membership mapper | Decide prototype-era membership representation | [`IMPLEM_PLAN.md` § 2.3](../IMPLEM_PLAN.md) |

### D. Compliance, monitoring & incident response

| Responsibility | Detail | Cross-reference |
|----------------|--------|-----------------|
| Monitor duty-based obligations | Oversee compliance with `attribution`, `anonymisation`, `reciprocal-insights` - obligations the connector cannot technically enforce | [`../reference/policies/README.md` § Implementation Feasibility](../reference/policies/README.md#implementation-feasibility) |
| Define audit mechanism | Choose between self-attestation, periodic review, and automated checks; document the chosen mix in Trust Framework v1 | [`IMPLEM_PLAN.md` § 6.2](../IMPLEM_PLAN.md) |
| Handle incident and breach reports | Receive complaints, investigate, propose remediation; escalate to legal counsel only where the DSA warrants it | *to be documented in Trust Framework* |
| Approve consent revocation procedures | Document how a producer revokes consent for a previously shared dataset (contracts, deletion notification, audit trail) | [`IMPLEM_PLAN.md` § 6.3](../IMPLEM_PLAN.md) |
| Adjudicate refund claims & monitor `payment-required` obligations (post-prototype) | Receive consumer claims that payment was completed but access was denied; review the per-connector audit endpoints (`/v3/contractnegotiations/{id}/obligations` and `/audit`); rule on whether refund is owed. The connector records the refund obligation as part of the immutable agreement; the Authority adjudicates; the external billing/payment system executes the refund. An aggregating audit service + UI on the Authority side is **proposed** as the operational consumer of these endpoints | [`../design/payment-gating.md` § 3.3](../design/payment-gating.md), [`IMPLEM_PLAN.md` § 7.1](../IMPLEM_PLAN.md) |

### E. Cohort & phase decisions

| Responsibility | Detail | Cross-reference |
|----------------|--------|-----------------|
| Declare cohort close-out | Decide when a cohort's close-out criteria are met (technical demos, DSA clauses, governance pipeline health) | [`../reference/policies/plan.md` § Cohort 1 close-out](../reference/policies/plan.md) |
| Approve the rollout plan | Accept, amend, or reject the cohort-sequencing proposal in `../reference/policies/plan.md` | [`../reference/policies/plan.md`](../reference/policies/plan.md) |
| Sign off cross-cohort scope changes | Promote or defer policies between cohorts when circumstances change | [`../reference/policies/plan.md`](../reference/policies/plan.md) |

---

## Proposed composition

Composition is harder to propose without knowing the seated participants; the shape below is a starting point.

| Seat type | Proposed purpose | Count (indicative) |
|-----------|------------------|-------------------|
| Producer representative(s) | Voice of the participants generating and sharing grazing / SOC data | 2 |
| Research institution representative(s) | Voice of data consumers whose research depends on the dataspace | 1 |
| Data steward representative | Bridges producers and researchers; maintains curated datasets | 1 |
| Project team lead (technical) | Liaison with the implementation effort; non-voting on non-technical matters (optional) | 1 |
| Project team lead (governance) | Secretariat role - agenda, minutes, action tracking (optional) | 1 |
| Funder observer (non-voting) | Strategic alignment; no veto on participant-level decisions | 0–1 |

**Open questions on composition:**
- Should institutional post-prototype participants (conservation organisations, certification bodies) be represented from the outset, or joined only when onboarded?
- Voting mechanics: simple majority, consensus, weighted by participant type?
- Term length and rotation?

---

## Proposed operating mode

### Cadence

| Mode | Cadence | Typical agenda |
|------|---------|----------------|
| **Standing session** | Monthly (indicative - to be agreed) | Cohort status, onboarding approvals, Trust Framework iterations, any pending compliance items |
| **Asynchronous queue** | Rolling | Time-sensitive approvals - certification-status updates, contribution-status flips, onboarding green-lights that do not warrant a full session |
| **Ad-hoc session** | On demand | Incident / breach response, scope-change proposals, urgent disputes |

### Decision-making

- **Default:** rough consensus during standing sessions; proposed actions recorded in minutes with a 5-business-day objection window for async ratification.
- **Escalation:** items where consensus cannot be reached in two standing sessions proceed to a recorded vote under whichever voting rule the body agrees (simple majority / supermajority / etc.).
- **Transparency:** minutes and material decisions are shared with all participants. Commercial / personal-data-sensitive items may be redacted.

### Secretariat

The project team is proposed to provide secretariat support (agenda preparation, minutes, action tracking, async queue upkeep) so the body's members can focus on judgment rather than coordination overhead.

---

## Relationship to other bodies

| Other body | Relationship |
|------------|--------------|
| **Project Team** | Implements the Dataspace Authority's decisions. Owns technical infrastructure, CI, deployment, EDC extensions, onboarding app. The Authority does not approve individual code changes. |
| **Cohort participants** | Subject to the Trust Framework and DSAs approved by the Authority. Represented on the Authority via the seats in §Composition. |
| **Funder(s)** | Strategic partner. Observer seat proposed. The Authority does not set fundraising strategy; funders do not approve individual participant decisions. |
| **Legal counsel** | External. Consulted on DSA clause wording and on any escalation that warrants formal legal action. Not a standing member. |
| **External certification bodies** (post-prototype) | USDA Organic, Regenerative Organic Certified, etc. Feed evidence into cert-status decisions; not members of the Authority. |

---

## Explicitly not in scope

Listed explicitly to prevent scope creep and to make the body's remit auditable.

- **Day-to-day technical operations** - deploys, incident runbooks, on-call. Owned by the Project Team.
- **Individual data-sharing decisions** - the Authority does not approve or reject specific contracts between two participants; that is what access + contract policies mediate automatically.
- **Commercial / pricing decisions** - including future corporate `payment-required` amounts. Those belong to the relevant provider participant, with the Authority approving only the *policy template* wording.
- **Fundraising or grant strategy** - owned by the initiative sponsors.
- **Legal prosecution of breach** - the Authority documents and refers; it does not litigate.
- **Technical architecture choices** - e.g. OIDC vs. DCP / VC migration timing. The Authority endorses a direction proposed by the Project Team; it does not design the stack itself.

---

## Open questions

1. **Name.** Does the body accept "Dataspace Authority", or prefer another name (Council, Committee, Trust Body)? See §Naming caveat.
2. **Voting.** What decision rule applies - rough consensus, majority, supermajority, weighted by participant type?
3. **Seats.** Who sits on the first instance of the body, and how are seats filled / refreshed over time?
4. **Async ratification window.** Is 5 business days right for async decisions, or too long / too short?
5. **Funder observer.** Include from the outset, or introduce only if a dedicated institutional funder is named?
6. **Cohort-representation model.** Should the body expand as institutional / corporate participants onboard, or stay small with representatives speaking for classes of participant?

---

## References

- [`README.md`](../README.md) - governance overview (high-level)
- [`../reference/identity.md`](../reference/identity.md) - identity, onboarding flow, role assignments
- [`IMPLEM_PLAN.md`](../IMPLEM_PLAN.md) - phased implementation plan; Phase 2 (Keycloak claims), Phase 6 (governance-level enforcement)
- [`ops/authority-migration.md`](../ops/authority-migration.md) - operator checklist for renaming the live `governance-*` infrastructure once this proposal is ratified
- [`../reference/policies/plan.md`](../reference/policies/plan.md) - cohort-level policy rollout proposal, including Authority-owned decision points
- [`../reference/policies/README.md`](../reference/policies/README.md) - per-policy implementation feasibility and governance-vs-technical enforcement
