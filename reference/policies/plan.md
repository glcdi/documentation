# GLCDI Policy Rollout - Proposal

A proposal for which policies could go live in which cohort, and what technical + governance work each wave would unlock. Everything below is put forward for discussion with the Dataspace Authority and the wider project team; nothing here is a decided commitment.

This document joins three pieces that live separately elsewhere:
- the **cohort timeline** (participants and focus) - [`../../README.md` §Cohort Timeline](../../README.md#cohort-timeline-proposal)
- the **technical implementation phases** (vocabulary → Keycloak → extension → seeding → testing → governance) - [`../IMPLEM_PLAN.md`](../../build/implementation-plan.md)
- the **per-policy feasibility & priority** - [`README.md` §Implementation Feasibility](README.md#implementation-feasibility). Effort ratings in the cohort tables below mirror that authoritative source.

For use-case → policy-stack mapping and end-to-end workflow illustrations, see [`README.md` §Relation to GLCDI Use Cases](README.md#relation-to-glcdi-use-cases) and [`README.md` §Sequence Diagrams](README.md#sequence-diagrams).

It is a proposed **sequencing** document, not a re-plan. The phase work is still defined in `../IMPLEM_PLAN.md`; this document proposes *when* each policy might become a blocker.

---

## TL;DR

The proposal is to roll out GLCDI policies across **two prototype onboarding cohorts (C1, C2) followed by a rolling post-prototype phase**. Under this proposal the policy surface would grow **4 → 11 → 14** across the three phases.

**Cohort 1 (Q1 2026, in progress) - 4 policies, deliberately small.** A sensitive-first stack would validate the technical infrastructure and demonstrate the end-to-end workflow. Access would be filtered by `regenerative-producers` (sensitive grazing-practice data) and `members-only` (default baseline); contracts would carry `internal-use-only` (no redistribution) and `time-limited` (expiry before C2). Three new Keycloak claims, ~200 LOC of connector Java, one DSA clause drafted. Participants would see no UI choice yet - the project team would seed everything.

**Cohort 2 (Q2 2026) - +7 policies, 11 total, the ambitious cohort.** C2 would onboard a second wave of participants and **nearly triple the policy surface** on top of C1's infrastructure. Proposed additions: role-filtering (`researchers-only`), access-level reciprocity (`contributing-members`), the commercial-misuse prohibition (`non-commercial`), purpose-filtered research contracts (`purpose-model-training`), and the full duty-clause set (`attribution`, `anonymisation`, `reciprocal-insights`). Technically cheap - most policies would reuse the C1 infrastructure (+30 LOC Java, one new Keycloak claim); the real weight is DSA v1 full release and Trust Framework v1. Participants would get their first UI choice: 3 access templates + 5 contract templates.

**Post-prototype (Q3 2026 onwards) - +3 policies, 14 total, plus a significant engineering scope.** No longer an onboarding cohort; institutional and corporate participants would land on a rolling basis. The proposal is to add the three remaining policies (`data-retention-limit`, `payment-required`, and a newly-defined `corporate-partners` access policy) and - more importantly - the engineering workstreams described below. DSA v2, Trust Framework v2.

**Guiding philosophy (proposed).** Earn sophistication: ship fewer, enforceable policies early and grow the library as the governance pipeline proves it can absorb each wave. Ship technical enforcement (connector constraints) before contractual obligation (DSA duties). Keep access-policy self-service narrower than contract-policy self-service because the blast radius of a wrong access choice is larger than a wrong contract choice. Never enable a purpose-based contract policy for participant self-service before the UI can surface purpose declaration - a silently-passing constraint is worse than none at all.

---

## Guiding principles (proposed)

1. **Earn sophistication.** Cohort N+1 would only introduce a policy if Cohort N's governance pipeline (onboarding → token → DSA → audit) has demonstrably absorbed the prior wave. The proposal is not to stack unenforced obligations.
2. **Ship technical enforcement before contractual obligation.** A policy that the connector will actually evaluate (e.g. `members-only`) is proposed as safer to introduce than a policy that only exists in the Data Sharing Agreement - the DSA, GLCDI's per-transfer legal contract - such as `reciprocal-insights`. The second kind risks creating trust debt if no-one is monitoring compliance.
3. **Don't expose a purpose-based contract policy to participants for self-service before the participant UI surfaces purpose declaration.** Until then, the proposal is that purpose-based policies stay attached by project-team seeding, with the consumer-side purpose wired in programmatically. A silently-passing purpose constraint in participant-authored contracts is worse than no policy at all.
4. **Limit the number of new Keycloak claims introduced per cohort.** Each new user-attribute claim (`certificationStatus`, `contributionStatus`…) would require a governance workflow to populate. Introducing several at once risks overwhelming onboarding.
5. **Keep `time-limited` on every contract from C1 onwards.** It is the cheapest consent-renewal hook and would give the governance body a natural re-contracting point between cohorts.

---

## Current state (as of 2026-04-22)

- **Cohort 1 is in progress** - the first prototype participants are onboarded and the connector plumbing (DSP catalog query → contract negotiation → transfer → HTTP data plane) has been proven at the protocol level. Still outstanding for C1:
  - wiring the baseline policy stack into the seeding scripts
  - demonstrating the end-to-end workflow (authentication → filtered catalog → negotiation → transfer → expiry) to the governance body.
- **Seeding scripts currently apply a single `glcdi:policy:open-research` policy** (`"action": "use"`, no constraints). No catalog filtering, no negotiation-time checks - any authenticated participant sees everything.
- **No GLCDI-specific constraint is yet evaluated in the connector.** `../IMPLEM_PLAN.md` Phases 1–6 are "not started".
- **Cohort 2 ramp-up is underway in parallel** - the composition of C2 is still under discussion; targeting a Q2 start.

The rollout below proposes what remains to be delivered for C1 before it closes out, what C2 would add on top, and what a subsequent **post-prototype phase** could absorb - institutional onboarding, cert-evidence formalisation, the participant purpose-declaration UI, and the last three technical policies (`corporate-partners`, `data-retention-limit`, `payment-required`). The prototype itself targets just two onboarding cohorts: C1 and C2.

---

## Cohort 1 - Q1 2026 (in progress)

**Proposed goal:** close out C1 with a **deliberately small** sensitive-first policy stack - the headline `regenerative-producers` access policy, the headline `internal-use-only` contract policy, and the two minimum companions (`members-only` + `time-limited`) - plus a demonstration of the full end-to-end workflow. Every policy added here should earn its place; the richer library would land in C2.

| Field | Value |
|-------|-------|
| Participants | 3 (prototype onboarding cohort) |
| Focus | Foundational validation, Trust Framework v0, **end-to-end workflow demo**, sensitive-data protection |
| Policies live | 4 |
| New Keycloak claims needed | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` |
| New Java code | ~200 LOC (membership + participant-type + certification-status functions, shared base class) |

### Policies proposed for this cohort

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`regenerative-producers`](access/regenerative-producers.json) | Access | **Low** | **Headline access policy.** With the small C1 participant set, the proposal is that the governance body self-certifies informally - the formal cert-evidence workflow could wait for post-prototype institutional onboarding. |
| [`members-only`](access/members-only.json) | Access | **Low** | Minimal companion baseline so non-producer participants still see general-membership assets. Without it, C1 would have an empty catalogue for everyone except certified producers. |
| [`internal-use-only`](contract/internal-use-only.json) | Contract (purpose) | **None** (native) + gov | **Headline contract policy - default tone.** Data shared under GLCDI is for internal analysis, not redistribution. Native EDC `odrl:purpose` handles the permission check (consumer declares `InternalAnalysis`); the `distribute` prohibition is proposed to be DSA-enforced. |
| [`time-limited`](contract/time-limited.json) | Contract | **None** | Every C1 contract could carry a prototype-end expiry (`2026-09-30`), giving the governance body a natural re-contracting moment before C2. |

### Proposed implementation approach for C1 close-out

Mapped to `../IMPLEM_PLAN.md` phases:

| TODO phase | Proposed C1 scope | Blocker for C1 close-out? |
|------------|-------------------|:-:|
| **Phase 1** Vocabulary | Define `glcdi:membership`, `glcdi:participantType`, `glcdi:certificationStatus`, and the **minimum** purpose-taxonomy subset needed by C1 (`InternalAnalysis` only). Other purpose values would arrive in C2. | Yes |
| **Phase 2** Keycloak claims | Realm roles (`glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`) + `glcdi_certification_status` user attribute. Hardcoded membership mapper (every authenticated user = `"active"`). The governance body would informally self-certify the C1 participants (producer participants: `regenerative-verified`; research participants: `not-applicable`). Defer `glcdi_contribution_status` (C2). | Yes |
| **Phase 3** EDC extension | Ship `MembershipConstraintFunction`, `ParticipantTypeConstraintFunction`, and `CertificationStatusConstraintFunction` (with `isAnyOf` support) - three functions sharing a claim-extraction base class. `internal-use-only` would use the native EDC `odrl:purpose` mechanism - no function. | Yes |
| **Phase 4** Seeding | Rewrite the per-participant seeding scripts. Attach `regenerative-producers` + `time-limited` + `internal-use-only` to sensitive grazing-practice assets; `members-only` + `time-limited` + `internal-use-only` to general-membership assets. Seeding would wire the declared purpose (`InternalAnalysis`) into the consumer-side contract offer for `internal-use-only` to evaluate. | Yes |
| **Phase 5** Testing | Integration tests: (a) a certified producer sees the sensitive grazing-practice asset, a non-producer does not; (b) a contract offer with a non-`InternalAnalysis` purpose is rejected; (c) an expired contract is rejected. **Plus** the end-to-end workflow demo to the governance body. | Yes (gates close-out) |
| **Phase 6** Governance | **First DSA draft (v1 pre-release).** Trust Framework v0 would ship with clause wording for `internal-use-only` (`distribute` prohibition) - the prohibition half the connector cannot technically enforce. Full duty-policy clause set would arrive with C2. MOU updated to reference the policy stack. | Parallel, gates close-out |
| **Phase 7** Future | - | - |

### Explicitly deferred past C1 (proposal)

- **`researchers-only`** - technically free (shares the participant-type function with `regenerative-producers`) but pulled to C2 to keep the C1 demo narrative tight: sensitive-data filtering by certification first, participant-type role filtering as C2 adds researcher participants.
- **`non-commercial`** - pairs naturally with `internal-use-only` but would require its own DSA clause. Moved to C2 so C1's DSA drafting is just one prohibition clause, not two.
- **`contributing-members`** - needs `glcdi_contribution_status` user attribute and the governance workflow that flips it once a participant publishes their first asset. Not useful until C2 brings in participants who haven't yet contributed.
- **Duty-based policies** (`attribution`, `anonymisation`, `reciprocal-insights`) - no connector work needed, but the DSA clause set is not proposed to be finalised at C1 close-out. Land with C2's governance push.
- **`purpose-model-training`** - uses the same native-purpose mechanism C1 pilots. Proposed for C2 alongside the researcher-model-feeding combined scenario once research participants onboard.
- **Participant purpose-declaration UI, cert-evidence formalisation, corporate participation, payment, retention** - all post-prototype.

---

## Cohort 2 - Q2 2026 (proposed, ramp-up underway)

**Proposed goal:** the **ambitious cohort**. C2 would onboard a second participant wave (composition under discussion), introduce access-level reciprocity, add role-based researcher filtering, round out the sensitive-data contract bundle, and ship the full duty-based DSA clause set. Policies added at C2 would draw on the C1 technical infrastructure - the connector code would grow by ~30 LOC, but the *policy surface* would grow from 4 to 11.

| Field | Value |
|-------|-------|
| Participants | ~6 (C1 onboarding + a proposed second wave - specific participants TBD) |
| Focus | Cross-context testing, Trust Framework v1, full duty-policy DSA release, access-level reciprocity, researcher role filtering |
| Policies live | +7 (total 11) |
| New Keycloak claims needed | `glcdi_contribution_status` (user attribute) |
| New Java code | ~30 LOC (`ContributionStatusConstraintFunction`, sharing the base class with C1's functions) |

### Policies proposed to add

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`researchers-only`](access/researchers-only.json) | Access | **Low** (function already built) | Role-based filtering for the Agronomic Model Calibration use case. Reuses the participant-type function built for C1's `regenerative-producers`, so technical cost is near-zero. |
| [`contributing-members`](access/contributing-members.json) | Access | **Low** (enforced) | **First enforced reciprocity gate.** Non-contributors would not see benchmarking-pool assets. Requires the new `glcdi_contribution_status` user attribute; for ~6 participants the governance body could maintain it manually. |
| [`non-commercial`](contract/non-commercial.json) | Contract (purpose) | **None** (native) + gov | Pairs with `internal-use-only` on sensitive producer data - beyond prohibiting redistribution, also rules out commercial exploitation. Addresses producer stakeholder concerns about "harmful use of data by buyers or competitors". Reuses the native-purpose mechanism C1 piloted. |
| [`purpose-model-training`](contract/purpose-model-training.json) | Contract (purpose) | **None** (native) | Also reuses C1's native-purpose infrastructure. Matches the researcher-model-feeding use case, assuming C2 onboards research participants. |
| [`attribution`](contract/attribution.json) | Contract (duty) | **None** (gov) | Lowest-cost DSA clause. First duty the governance body would have to actually track - proves the governance pipeline can absorb compliance monitoring. |
| [`anonymisation`](contract/anonymisation.json) | Contract (duty) | **None** (gov) | Required for the researcher-model-feeding combined scenario. |
| [`reciprocal-insights`](contract/reciprocal-insights.json) | Contract (duty) | **None** (gov) | Contract-level reciprocity obligation. Pairs with the access-level `contributing-members` above so both sides of reciprocity land in the same cohort. |

### Proposed implementation approach for C2

| TODO phase | Proposed C2 scope |
|------------|-------------------|
| **Phase 1** Vocabulary | Extend the context with `glcdi:contributionStatus`, the custom `glcdi:shareBack` action used by `reciprocal-insights`, and the full purpose-taxonomy subset needed beyond C1's `InternalAnalysis` (`AgronomicModelTraining`, `EcosystemModelCalibration`, plus the commercial-purpose values used to reject `non-commercial` offers). |
| **Phase 2** Keycloak claims | Add `glcdi_contribution_status` user attribute + protocol mapper. Define a proposed governance workflow for flipping it to `"contributing"` once a participant has published their first asset. Assign C1 roles + initial contribution status to C2's onboarding wave. |
| **Phase 3** EDC extension | Add `ContributionStatusConstraintFunction` (shares base class with C1's functions). `non-commercial` and `purpose-model-training` both use the native EDC purpose mechanism already piloted by `internal-use-only` in C1 - no new functions needed. `researchers-only` reuses the C1 participant-type function. |
| **Phase 4** Seeding | Attach `contributing-members` to benchmarking-pool assets. Expand researcher-oriented SOC datasets to combine `researchers-only` + `purpose-model-training` + `attribution` + `anonymisation`. Add `non-commercial` to sensitive producer datasets alongside C1's `internal-use-only`. Attach `reciprocal-insights` where share-back is expected. |
| **Phase 5** Testing | (a) a non-contributor's catalog query hides the benchmarking-pool asset; (b) a researcher sees SOC data that a producer does not (new researchers-only regression); (c) a contract offer declaring `Scope3Reporting` is rejected for a model-training asset; (d) a commercial-purpose contract offer is rejected for a `non-commercial` asset; (e) duty-policy clauses are correctly stored and surfaced in catalog responses. |
| **Phase 6** Governance | **Main delivery (proposed).** DSA v1 full release - extends C1's `internal-use-only` clause with `non-commercial`'s `commercialize` prohibition and the three duty clauses (`attribution`, `anonymisation`, `reciprocal-insights`). Audit/monitoring workflow proposed (who checks, how often, what evidence). Governance workflow for contribution-status updates documented. |
| **Phase 7** Future | - |

### Explicitly deferred past C2 (→ post-prototype)

- **Certification-evidence formalisation** - under the proposal, C1 self-certification would be informal and C2 would inherit that approach for its new participants. Formal cert-evidence workflow (what proof is acceptable, how it's reviewed) would land post-prototype as institutional participants whose claims need external evidence begin onboarding.
- **Participant UI purpose dropdown** - under the proposal, at C2 purpose is still declared in consumer tooling / seeding scripts. The end-user-facing UI would ship post-prototype, unlocking the sensitive-data contract policies (`internal-use-only`, `non-commercial`, `purpose-model-training`) as selectable UI templates.
- **Corporate participation, payment, retention, `corporate-partners` access policy** - unchanged, post-prototype.

---

## Post-prototype - Q3 2026 onwards (ambitious)

**Proposed goal:** take GLCDI from a small-cohort prototype to a production-grade dataspace. The prototype itself ends with C2; post-prototype would be the **ambitious phase** dependent on follow-on funding and institutional/corporate onboarding. Post-prototype is **not a cohort** - onboarding is proposed to be rolling, not phased.

| Field | Value |
|-------|-------|
| Participants | 10+ rolling (institutional + corporate onboarding; specific participants TBD) |
| Focus | Institutional scale, formal governance, participant self-service, corporate onboarding, post-grant sustainability |
| Policies added | +3 (total 14, including a newly-defined `corporate-partners` access policy) |
| New Keycloak claims | - (roles extended to include corporate variants) |
| New engineering scope | Substantial - see workstreams below |

### New policies proposed to add

| Policy | Type | Effort | Why post-prototype |
|--------|------|:------:|--------------------|
| [`data-retention-limit`](contract/data-retention-limit.json) | Contract | **Medium** | Needed for corporate data consumers. Custom function tracks transfer timestamps against `odrl:elapsedTime`. |
| [`payment-required`](contract/payment-required.json) | Contract | **High** | Needed for corporate ESG / Scope 3 use case. Requires external payment integration. |
| `corporate-partners` access policy (new definition) | Access | **Low** (policy file) + design | Does not exist as a JSON file yet - propose to define alongside the post-prototype onboarding of the first corporate participant. Targets `corporate`, `certification-body`, `supply-chain-partner` roles. |

### Candidate engineering workstreams / interesting topics

Post-prototype is where GLCDI would move from "works for a small trusted participant set" to "works for dozens of institutions and corporates at production scale". A non-exhaustive list of interesting topics to explore, in no particular priority order:

- **Payment + retention infrastructure** - external payment/invoicing gateway integration, reconciliation, `data-retention-limit` custom function with persisted transfer timestamps, delete-attestation reporting.
- **Verifiable Credentials integration** (`../IMPLEM_PLAN.md` §7.2) - move from Keycloak roles to VC-based identity for participant type, membership, and certification. Enables cross-dataspace portability and removes the governance-Keycloak bottleneck.
- **Federated Catalogue policy metadata** (`../IMPLEM_PLAN.md` §7.3) - publish each participant's policies as catalogue metadata so consumers can filter by policy before negotiating. Would require adopting or forking an XFSC-style federated catalogue.
- **Participant UI - policy composer** - beyond a simple purpose-declaration dropdown: full composition UI where participants could attach any access + contract policy template to their assets, preview the effective policy, and see who would/wouldn't match. Would replace all project-team seeding.
- **Certification-broker integration** - automated validation of `glcdi_certification_status` against third-party certification bodies (USDA Organic, Regenerative Organic Certified, etc.). Would replace the C1 self-certification and the C2 informal-review approach.
- **Contribution-status automation** - replace manual governance maintenance of `glcdi_contribution_status` with a periodic catalogue crawler that detects when a participant has published its first asset. Scales beyond ~10 participants.
- **Compliance / audit framework** - machine-readable audit trail of policy decisions (who tried what, what was evaluated, what was enforced vs DSA-deferred). Dashboards, SLAs, incident-response runbooks. Likely required for corporate and certification-body participation.
- **Onboarding automation** - self-service participant enrollment to replace manual Keycloak provisioning. Workflow: signed DSA → automated Keycloak user creation → per-participant compose stack provisioned → notification.
- **Corporate onboarding** - first corporate partner (food company / certification body) would land in this phase. Needs `corporate-partners` access policy, `payment-required`, `data-retention-limit`, and a governance model for data-as-product terms.
- **DSA v2** - corporate-grade clauses for `payment-required`, `data-retention-limit`, institutional refinements of `non-commercial`. Signed by all post-prototype participants.
- **Trust Framework v2** - publishable document incorporating C1–C2 learnings and the post-prototype corporate experience. Intended as input to any follow-on production-grade dataspace.
- **Certification-evidence formalisation** - formal process replacing C1–C2 informal self-cert. Would document acceptable proof (third-party audit, USDA Organic, Regenerative Organic Certified, reviewed self-declaration). Institutional certification claims would be the first that need to hold up under scrutiny.
- **Stress tests at institutional scale** - exercise every policy under a combined 10+-participant deployment: e.g. an institutional researcher blocked from a proprietary producer asset by `regenerative-producers`; a researcher negotiating a model-training contract under `purpose-model-training`; a newly onboarded institution blocked from the benchmarking pool by `contributing-members`; a corporate ESG consumer purchasing SOC data under `payment-required` + `data-retention-limit`.

### Implementation approach (proposed)

Maps to `../IMPLEM_PLAN.md` Phase 7 (Future Enhancements) plus the workstreams above. Governance + UI workstreams could begin during or shortly after C2; payment + VC + federated-catalogue work is firmly post-grant.

**Not in scope for post-prototype (proposal):** compute-to-data (data never leaves the provider), zero-knowledge policy evaluation, cross-dataspace federation with sister dataspaces. All interesting topics for a further phase.

---

## Summary: policies × cohorts (proposal)

The prototype itself targets **C1 (small) and C2 (ambitious)**; everything after is a continuous post-prototype phase.

| | C1 (Q1, in progress) | C2 (Q2, ambitious) | Post-prototype (Q3 2026+) |
|---|---|---|---|
| **Participants** | 3 (prototype onboarding) | ~6 (C1 + a proposed second wave, TBD) | 10+ (rolling institutional + corporate onboarding, TBD) |
| **Access policies** | `regenerative-producers`, `members-only` | +`researchers-only`, `contributing-members` | +`corporate-partners` |
| **Contract policies** | `time-limited`, `internal-use-only` | +`non-commercial`, `purpose-model-training`, `attribution`, `anonymisation`, `reciprocal-insights` | +`data-retention-limit`, `payment-required` |
| **Total policies live** | 4 | 11 | 14 |
| **Policies added in this phase** | 4 (from 0) | +7 | +3 (incl. new `corporate-partners` definition) |
| **New Keycloak claims** | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` | `glcdi_contribution_status` | - (roles extended for corporates) |
| **New connector code** | ~200 LOC Java | ~30 LOC Java | Substantial (payment gateway + retention custom fn + VC integration + federated catalogue) |
| **Trust Framework version** | v0 | v1 | v2 |
| **DSA template** | v1 pre-release (`internal-use-only` distribute clause) | v1 full (adds `non-commercial` commercialize + three duty clauses) | v2 (payment / retention clauses + institutional refinements) |
| **Dominant workstream** | Technical (extension + seeding) + one DSA clause | Mixed - governance (full DSA v1) + technical (contribution attr, researcher filter, purpose pilot expansion) | Technical (external systems, VC, federated catalogue, UI composer) + governance (cert-evidence formalisation) |
| **First enforced in this phase** | Access filtering (membership + cert), contract expiry, native-purpose contract rejection | Role-based access, access-level reciprocity, commercial-purpose rejection | Retention, payment, corporate access gate |

---

## Participant-facing template library per cohort (proposal)

A policy being *live* (seeded on someone's assets) is not the same as a policy being *choosable* (offered as a template in the participant UI when publishing a new dataset). Under this proposal, C1 would seed everything by project team; genuine participant choice would begin at C2 and grow. Each template in the UI is a template the governance body would have to be able to audit, explain in the DSA, and answer helpdesk questions about - so growth is proposed to be deliberate.

| Phase | Access templates offered | Contract templates offered | Rationale |
|---|---|---|---|
| **C1** | **0** - project team seeds both access policies directly on participants' assets | **0** - project team seeds both contract policies | Small participant set, workflow-demo focus, pre-UI. Seeding is the source of truth. Sensitive-data policies (`regenerative-producers`, `internal-use-only`) are proposed to be especially team-curated because the governance body would vet them individually. |
| **C2** | **3** - `members-only`, `researchers-only`, `contributing-members` | **5** - `time-limited`, `attribution`, `anonymisation`, `reciprocal-insights`, `purpose-model-training` | First real participant choice at asset-publication time. The proposal keeps `regenerative-producers` project-team-seeded so the governance body curates who receives sensitive-asset visibility. Keeps `internal-use-only` + `non-commercial` project-team-seeded too - they are proposed as the default contractual protection bundle on sensitive assets, not a menu item to opt out of. |
| **Post-prototype** | **5** - +`regenerative-producers`, `corporate-partners` | **8** - +`internal-use-only`, `non-commercial`, `data-retention-limit`, `payment-required` | Sensitive-data policies would graduate into the UI once the participant purpose-declaration UI ships and the cert-evidence workflow is formalised. The policy composer UI (see post-prototype workstreams) would make the full library user-selectable. |

**Design principle (proposed):** access templates grow slower than contract templates. A participant choosing the wrong contract policy annoys their consumer; a participant choosing the wrong access policy accidentally exposes sensitive data. The proposal is that the project team keep access gates project-team-seeded for longer.

---

## Decision points (proposed, for governance body consideration)

The following are **not** technical decisions and would block the rollout if left open. These are put forward for the governance body (and, where flagged, funder / legal counsel) to consider and decide:

| Decision | Needed by | Who would own it (proposed) |
|----------|-----------|-----------------------------|
| Canonical `participantType` enum | C1 close-out | Governance body + Project Team |
| Hardcoded-vs-per-user membership mapper for prototype | C1 close-out | Project Team (suggested: hardcoded for C1–C2, per-user post-prototype) |
| `certificationStatus` values + informal self-cert assignments for C1 participants | C1 close-out | Governance body (self-certifies) |
| Purpose-taxonomy subset for C1 (minimum: `InternalAnalysis`) | C1 close-out | Governance body + Project Team |
| DSA v1 pre-release clause wording for `internal-use-only` (`distribute` prohibition) | C1 close-out | Governance body + legal counsel |
| Purpose-taxonomy expansion for C2 (add `AgronomicModelTraining`, `EcosystemModelCalibration`, commercial-purpose values for `non-commercial`) | C2 start | Governance body + Project Team |
| DSA v1 full clause wording for `attribution`, `anonymisation`, `reciprocal-insights` | C2 start | Governance body + legal counsel |
| Audit mechanism for duty-based policies | C2 start | Governance body |
| `contributionStatus` values and the workflow for flipping a participant to `"contributing"` | C2 start | Governance body + Project Team |
| **Formalised** cert-evidence workflow (what proof is acceptable at institutional scale) | Post-prototype | Governance body |
| Participant UI purpose declaration - design + ship date | Post-prototype | Project Team + Governance body |

---

## Open questions (to resolve before finalising this plan)

1. **C1 close-out date** - when can the governance body accept that the sensitive-first policy stack is in place and the workflow demo satisfies C1? Without a named date, C2's DSA + contribution-status work cannot start in earnest.
2. **Informal-vs-formal cert-evidence boundary** - C1 and C2 both rely on self-certification under this proposal (lightweight for a small participant set). Institutional participants in post-prototype will challenge edge cases. Does the governance body accept the risk of running informal evidence through all of C2, with formalisation starting only as institutional participants onboard?
3. **Contribution-status automation threshold** - C2 assumes manual maintenance for ~6 participants. At what participant count (post-prototype) does automated catalog crawling become necessary, and who would own building it?
4. **Participant UI purpose declaration** - who would own this deliverable, and what's the target ship date? C1–C2 work around it with seeding-script wiring. Without the UI, the purpose-based policies (`internal-use-only`, `non-commercial`, `purpose-model-training`) stay project-team-seeded and cannot graduate into the UI template library.
5. **Does shipping `internal-use-only` at C1 (alone, without the permissive alternative of members-only assets under `time-limited` only) set the right default tone?** Strong protection for producers, but may feel restrictive to researchers expecting collaborative data sharing. Is `members-only` + `time-limited` (no `internal-use-only`) an acceptable C1 alternative for some asset classes?
