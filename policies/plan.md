# GLCDI Policy Rollout Plan

Which policies go live in which cohort, and what technical + governance work each wave unlocks.

This document joins three pieces that live separately elsewhere:
- the **cohort timeline** (participants and focus) — [`../README.md` §Cohort Timeline](../README.md#cohort-timeline)
- the **technical implementation phases** (vocabulary → Keycloak → extension → seeding → testing → governance) — [`../TODO.md`](../TODO.md)
- the **per-policy feasibility & priority** — [`README.md` §Implementation Feasibility](README.md#implementation-feasibility)

It is a **sequencing** document, not a re-plan. The phase work is still defined in `../TODO.md`; this document decides *when* each policy becomes a blocker.

---

## TL;DR

GLCDI's policy rollout fits into **two prototype onboarding cohorts (C1, C2) followed by a rolling, ambitious post-prototype phase** that depends on follow-on funding (~$1.5M — roughly 12× the prototype budget). Policy surface grows **4 → 11 → 14** across the three phases.

**Cohort 1 (Q1 2026, in progress) — 4 policies, deliberately small.** A sensitive-first stack validates the technical infrastructure and demonstrates the end-to-end workflow to the Steering Committee. Access is filtered by `regenerative-producers` (sensitive grazing-practice data) and `members-only` (default baseline); contracts carry `internal-use-only` (no redistribution) and `time-limited` (expiry before C2). Three new Keycloak claims, ~200 LOC of connector Java, one DSA clause drafted. Participants see no UI choice yet — the project team seeds everything.

**Cohort 2 (Q2 2026) — +7 policies, 11 total, the ambitious cohort.** C2 onboards PASA, UF, and TSIP and **nearly triples the policy surface** on top of C1's infrastructure. Adds role-filtering (`researchers-only`), access-level reciprocity (`contributing-members`), the commercial-misuse prohibition (`non-commercial`), purpose-filtered research contracts (`purpose-model-training`), and the full duty-clause set (`attribution`, `anonymisation`, `reciprocal-insights`). Technically cheap — most policies reuse the C1 infrastructure (+30 LOC Java, one new Keycloak claim); the real weight is DSA v1 full release and Trust Framework v1. Participants get their first UI choice: 3 access templates + 5 contract templates.

**Post-prototype (Q3 2026 onwards) — +3 policies, 14 total, plus major engineering scope.** No longer an onboarding cohort; institutional and corporate participants land on a rolling basis (WWF, TNC, Soil Health Institute, AFT, USRSB, first corporates). Adds the three remaining policies (`data-retention-limit`, `payment-required`, and a newly-defined `corporate-partners` access policy) and — more importantly — the engineering that the follow-on budget unlocks: verifiable-credentials integration, federated-catalogue policy metadata, a full participant policy composer UI, certification-broker automation, compliance / audit framework, onboarding automation. DSA v2, Trust Framework v2.

**Guiding philosophy.** Earn sophistication: ship fewer, enforceable policies early and grow the library as the governance pipeline proves it can absorb each wave. Ship technical enforcement (connector constraints) before contractual obligation (DSA duties). Keep access-policy self-service narrower than contract-policy self-service because the blast radius of a wrong access choice is larger than a wrong contract choice. Never enable a purpose-based contract policy for participant self-service before the UI can surface purpose declaration — a silently-passing constraint is worse than none at all.

---

## Guiding principles

1. **Earn sophistication.** Cohort N+1 is only allowed to introduce a policy if Cohort N's governance pipeline (onboarding → token → DSA → audit) has demonstrably absorbed the prior wave. Do not stack unenforced obligations.
2. **Ship technical enforcement before contractual obligation.** A policy that the connector will actually evaluate (e.g. `members-only`) is safer to introduce than a policy that only exists in the Data Sharing Agreement — the DSA, GLCDI's per-transfer legal contract — such as `reciprocal-insights`. The second kind creates trust debt if no-one is monitoring compliance.
3. **Don't expose a purpose-based contract policy to participants for self-service before the participant UI surfaces purpose declaration.** Until then, purpose-based policies are attached by project-team seeding with the consumer-side purpose wired in programmatically. A silently-passing purpose constraint in participant-authored contracts is worse than no policy at all.
4. **Limit the number of new Keycloak claims introduced per cohort.** Each new user-attribute claim (`certificationStatus`, `contributionStatus`…) requires Steering Committee workflow to populate. Introducing several at once overwhelms onboarding.
5. **Keep `time-limited` on every contract from C1 onwards.** It is the cheapest consent-renewal hook and gives the Steering Committee a natural re-contracting point between cohorts.

---

## Current state (as of 2026-04-22)

- **Cohort 1 is in progress** 3 participants (Caney Fork, Point Blue, White Buffalo) are onboarded and the connector plumbing (DSP catalog query → contract negotiation → transfer → HTTP data plane) has been proven at the protocol level. Still outstanding for C1:
  - wiring the baseline policy stack into the seeding scripts
  - demonstrating the end-to-end workflow (authentication → filtered catalog → negotiation → transfer → expiry) to the Steering Committee.
- **Seeding scripts currently apply a single `glcdi:policy:open-research` policy** (`"action": "use"`, no constraints). No catalog filtering, no negotiation-time checks — any authenticated participant sees everything.
- **No GLCDI-specific constraint is yet evaluated in the connector.** `../TODO.md` Phases 1–6 are "not started".
- **Cohort 2 ramp-up is underway in parallel** — PASA, University of Florida, and TSIP are discussing onboarding, targeting Q2 start.

The rollout below proposes what remains to be delivered for C1 before it closes out, what C2 adds on top, and what a subsequent **post-prototype phase** absorbs — institutional onboarding (WWF, TNC, Soil Health Institute, AFT, USRSB, corporates), cert-evidence formalisation, the participant purpose-declaration UI, and the last three technical policies (`corporate-partners`, `data-retention-limit`, `payment-required`). The prototype itself targets just two onboarding cohorts: C1 and C2.

---

## Cohort 1 — Q1 2026 (in progress)

**Goal:** close out C1 with a **deliberately small** sensitive-first policy stack — the headline `regenerative-producers` access policy, the headline `internal-use-only` contract policy, and the two minimum companions (`members-only` + `time-limited`) — plus a demonstration of the full end-to-end workflow to the Steering Committee. Every policy added here has to earn its place; the richer library lands in C2.

| Field | Value |
|-------|-------|
| Participants | 3 (Caney Fork, Point Blue, White Buffalo) |
| Focus | Foundational validation, Trust Framework v0, **end-to-end workflow demo**, sensitive-data protection |
| Policies live | 4 |
| New Keycloak claims needed | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` |
| New Java code | ~200 LOC (membership + participant-type + certification-status functions, shared base class) |

### Policies to enable

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`regenerative-producers`](access/regenerative-producers.json) | Access | **Low** | **Headline access policy.** Restricts sensitive grazing-practice data to certified producers. With 3 C1 participants the SC self-certifies informally — the formal cert-evidence workflow waits for post-prototype institutional onboarding. Evaluates three constraints: membership + producer type + certification status. |
| [`members-only`](access/members-only.json) | Access | **Low** | Minimal companion baseline so non-producer participants (Point Blue) still see general-membership assets. Without it, C1 would have an empty catalogue for everyone except certified producers. |
| [`internal-use-only`](contract/internal-use-only.json) | Contract (purpose) | **None** (native) + gov | **Headline contract policy — default tone.** Data shared under GLCDI is for internal analysis by the receiving participant, not for redistribution. Native EDC `odrl:purpose` handles the permission check (consumer must declare `InternalAnalysis`); the `distribute` prohibition is DSA-enforced. |
| [`time-limited`](contract/time-limited.json) | Contract | **None** | Works in vanilla EDC. Every C1 contract carries a prototype-end expiry (`2026-09-30`), giving the Steering Committee a natural re-contracting moment before C2. |

### Implementation approach for C1 close-out

Mapped to `../TODO.md` phases:

| TODO phase | C1 scope | Blocker for C1 close-out? |
|------------|----------|:-:|
| **Phase 1** Vocabulary | Define `glcdi:membership`, `glcdi:participantType`, `glcdi:certificationStatus`, and the **minimum** purpose-taxonomy subset needed by C1 (`InternalAnalysis` only). Other purpose values arrive in C2. | Yes |
| **Phase 2** Keycloak claims | Realm roles (`glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`) + `glcdi_certification_status` user attribute. Hardcoded membership mapper (every authenticated user = `"active"`). SC informally self-certifies the 3 C1 participants (Caney Fork: `regenerative-verified`, White Buffalo: `regenerative-verified`, Point Blue: `not-applicable`). Defer `glcdi_contribution_status` (C2). | Yes |
| **Phase 3** EDC extension | Ship `MembershipConstraintFunction`, `ParticipantTypeConstraintFunction`, and `CertificationStatusConstraintFunction` (with `isAnyOf` support) — three functions sharing a claim-extraction base class. `internal-use-only` uses the native EDC `odrl:purpose` mechanism — no function. | Yes |
| **Phase 4** Seeding | Rewrite `seed-caney-fork.sh` / `seed-point-blue.sh`. Attach `regenerative-producers` + `time-limited` + `internal-use-only` to sensitive grazing-practice assets; `members-only` + `time-limited` + `internal-use-only` to general-membership assets. Seeding wires the declared purpose (`InternalAnalysis`) into the consumer-side contract offer for `internal-use-only` to evaluate. | Yes |
| **Phase 5** Testing | Integration tests: (a) certified producer sees the sensitive grazing-practice asset, non-producer Point Blue does not; (b) contract offer with a non-`InternalAnalysis` purpose is rejected; (c) expired contract is rejected. **Plus** the end-to-end workflow demo to the Steering Committee. | Yes (gates close-out) |
| **Phase 6** Governance | **First DSA draft (v1 pre-release).** Trust Framework v0 ships with clause wording for `internal-use-only` (`distribute` prohibition) — the prohibition half the connector cannot technically enforce. Full duty-policy clause set arrives with C2. MOU updated to reference the policy stack. | Parallel, gates close-out |
| **Phase 7** Future | — | — |

### Explicitly deferred past C1

- **`researchers-only`** — technically free (shares the participant-type function with `regenerative-producers`) but pulled to C2 to keep the C1 demo narrative tight: sensitive-data filtering by certification first, participant-type role filtering as C2 adds UF / TSIP researchers.
- **`non-commercial`** — pairs naturally with `internal-use-only` but requires its own DSA clause. Moved to C2 so C1's DSA drafting is just one prohibition clause, not two.
- **`contributing-members`** — needs `glcdi_contribution_status` user attribute and the SC workflow that flips it once a participant publishes their first asset. Not useful until C2 brings in participants who haven't yet contributed.
- **Duty-based policies** (`attribution`, `anonymisation`, `reciprocal-insights`) — no connector work needed, but the DSA clause set is not finalised at C1 close-out. Land with C2's governance push.
- **`purpose-model-training`** — uses the same native-purpose mechanism C1 pilots. Added in C2 alongside the researcher-model-feeding combined scenario once UF and TSIP onboard.
- **Participant purpose-declaration UI, cert-evidence formalisation, corporate participation, payment, retention** — all post-prototype.

---

## Cohort 2 — Q2 2026 (now starting)

**Goal:** the **ambitious cohort**. C2 onboards the second participant wave, introduces access-level reciprocity, adds role-based researcher filtering, rounds out the sensitive-data contract bundle, and ships the full duty-based DSA clause set. Policies added at C2 draw on the C1 technical infrastructure — the connector code grows by ~30 LOC, but the *policy surface* grows from 4 to 11.

| Field | Value |
|-------|-------|
| Participants | 6 (C1 + PASA, University of Florida, TSIP) |
| Focus | Cross-context testing, Trust Framework v1, full duty-policy DSA release, access-level reciprocity, researcher role filtering |
| Policies live | +7 (total 11) |
| New Keycloak claims needed | `glcdi_contribution_status` (user attribute) |
| New Java code | ~30 LOC (`ContributionStatusConstraintFunction`, sharing the base class with C1's functions) |

### Policies to add

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`researchers-only`](access/researchers-only.json) | Access | **Low** (function already built) | Role-based filtering for the Agronomic Model Calibration use case — lets Point Blue, UF and TSIP access raw SOC data that Caney Fork wouldn't share with general members. Reuses the participant-type function built for C1's `regenerative-producers`, so technical cost is near-zero. |
| [`contributing-members`](access/contributing-members.json) | Access | **Low** (enforced) | **First enforced reciprocity gate.** Non-contributors do not see benchmarking-pool assets in the catalog. Requires `glcdi_contribution_status` user attribute; for 6 participants the Steering Committee can maintain it manually. |
| [`non-commercial`](contract/non-commercial.json) | Contract (purpose) | **None** (native) + gov | Pairs with `internal-use-only` on sensitive producer data: beyond prohibiting redistribution, it also rules out commercial exploitation. Addresses Caney Fork's stakeholder concern about "harmful use of data by buyers or competitors". Reuses the native-purpose mechanism C1 piloted. |
| [`purpose-model-training`](contract/purpose-model-training.json) | Contract (purpose) | **None** (native) | Also reuses C1's native-purpose infrastructure. Rejects offers that don't declare `AgronomicModelTraining` / `EcosystemModelCalibration` — matches the researcher-model-feeding use case, now that C2 onboards UF and TSIP. |
| [`attribution`](contract/attribution.json) | Contract (duty) | **None** (gov) | Lowest-cost DSA clause. First duty the Steering Committee has to actually track — proves the governance pipeline can absorb compliance monitoring. |
| [`anonymisation`](contract/anonymisation.json) | Contract (duty) | **None** (gov) | Required for the researcher-model-feeding combined scenario. DSA clause only. |
| [`reciprocal-insights`](contract/reciprocal-insights.json) | Contract (duty) | **None** (gov) | Contract-level reciprocity obligation. Pairs with the access-level `contributing-members` above so both sides of reciprocity land in the same cohort. |

### Implementation approach for C2

| TODO phase | C2 scope |
|------------|----------|
| **Phase 1** Vocabulary | Extend the context with `glcdi:contributionStatus`, the custom `glcdi:shareBack` action used by `reciprocal-insights`, and the full purpose-taxonomy subset needed beyond C1's `InternalAnalysis` (`AgronomicModelTraining`, `EcosystemModelCalibration`, plus the commercial-purpose values used to reject `non-commercial` offers). |
| **Phase 2** Keycloak claims | Add `glcdi_contribution_status` user attribute + protocol mapper. Define the SC workflow that flips it to `"contributing"` once a participant has published their first asset. Assign C1 roles + initial contribution status to PASA, UF, TSIP during onboarding. |
| **Phase 3** EDC extension | Add `ContributionStatusConstraintFunction` (shares base class with C1's functions). `non-commercial` and `purpose-model-training` both use the native EDC purpose mechanism already piloted by `internal-use-only` in C1 — no new functions needed. `researchers-only` reuses the C1 participant-type function. |
| **Phase 4** Seeding | Attach `contributing-members` to benchmarking-pool assets. Expand researcher-oriented SOC datasets to combine `researchers-only` + `purpose-model-training` + `attribution` + `anonymisation`. Add `non-commercial` to sensitive producer datasets alongside C1's `internal-use-only`. Attach `reciprocal-insights` where share-back is expected. |
| **Phase 5** Testing | (a) a non-contributor's catalog query hides the benchmarking-pool asset; (b) a researcher sees SOC data that a producer does not (new researchers-only regression); (c) a contract offer declaring `Scope3Reporting` is rejected for a model-training asset; (d) a commercial-purpose contract offer is rejected for a `non-commercial` asset; (e) duty-policy clauses are correctly stored and surfaced in catalog responses. |
| **Phase 6** Governance | **Main delivery.** DSA v1 full release — extends C1's `internal-use-only` clause with `non-commercial`'s `commercialize` prohibition and the three duty clauses (`attribution`, `anonymisation`, `reciprocal-insights`). Audit/monitoring workflow defined (who checks, how often, what evidence). SC workflow for contribution-status updates documented. |
| **Phase 7** Future | — |

### Explicitly deferred past C2 (→ post-prototype)

- **Certification-evidence formalisation** — at C1 the SC self-certified informally and C2 inherits that approach for the 3 new participants. Formal cert-evidence workflow (what proof is acceptable, how it's reviewed) lands post-prototype as institutional participants (WWF, TNC, SHI) whose claims need external evidence begin onboarding.
- **Participant UI purpose dropdown** — at C2, purpose is still declared in consumer tooling / seeding scripts. The end-user-facing UI ships post-prototype, unlocking the sensitive-data contract policies (`internal-use-only`, `non-commercial`, `purpose-model-training`) as selectable UI templates.
- **Corporate participation, payment, retention, `corporate-partners` access policy** — unchanged, post-prototype.

---

## Post-prototype — Q3 2026 onwards (ambitious)

**Goal:** take GLCDI from a 6-participant prototype to a production-grade dataspace. The prototype itself ends with C2; post-prototype is the **ambitious phase** that earns and uses the follow-on funding (~$1.5M order-of-magnitude against the $120k prototype — roughly 12× the budget, which buys roughly 12× the engineering scope). Post-prototype is **not a cohort** — onboarding is rolling, not phased.

| Field | Value |
|-------|-------|
| Participants | 10+ rolling (WWF, TNC, Soil Health Institute, American Farmland Trust, USRSB, first corporates, certification bodies) |
| Focus | Institutional scale, formal governance, participant self-service, corporate onboarding, post-grant sustainability |
| Policies added | +3 (total 14, including a newly-defined `corporate-partners` access policy) |
| New Keycloak claims | — (roles extended to include corporate variants) |
| New Java code | Substantial — see workstreams below |
| Budget assumption | ~$1.5M, ~12× the prototype budget |

### New policies to add

| Policy | Type | Effort | Why post-prototype |
|--------|------|:------:|--------------------|
| [`data-retention-limit`](contract/data-retention-limit.json) | Contract | **Medium** | Needed for corporate data consumers. Custom function tracks transfer timestamps against `odrl:elapsedTime`. |
| [`payment-required`](contract/payment-required.json) | Contract | **High** | Needed for corporate ESG / Scope 3 use case. Requires external payment integration. |
| `corporate-partners` access policy (new definition) | Access | **Low** (policy file) + design | Does not exist as a JSON file yet — define alongside the post-prototype onboarding of the first corporate participant. Targets `corporate`, `certification-body`, `supply-chain-partner` roles. |

### Engineering workstreams (where the 12× budget goes)

Post-prototype is where GLCDI moves from "works for 6 trusted participants" to "works for dozens of institutions and corporates at production scale". The budget buys:

| Workstream | Scope | Budget slice (illustrative) |
|------------|-------|-----------------------------|
| **Payment + retention infrastructure** | External payment/invoicing gateway integration, reconciliation, `data-retention-limit` custom function with persisted transfer timestamps, delete-attestation reporting. | Large |
| **Verifiable Credentials integration** (`../TODO.md` §7.2) | Move from Keycloak roles to VC-based identity for participant type, membership, and certification. Enables cross-dataspace portability and removes the governance-Keycloak bottleneck. | Large |
| **Federated Catalogue policy metadata** (`../TODO.md` §7.3) | Publish each participant's policies as catalogue metadata so consumers can filter by policy before negotiating. Requires adopting or forking the XFSC Federated Catalogue (sister to TEMS). | Medium |
| **Participant UI — policy composer** | Beyond C3's purpose-declaration dropdown: full composition UI where participants can attach any access + contract policy template to their assets, preview the effective policy, and see who would/wouldn't match. Replaces all project-team seeding. | Medium |
| **Certification-broker integration** | Automated validation of `glcdi_certification_status` against third-party certification bodies (USDA Organic, Regenerative Organic Certified, etc.). Replaces the C1 self-certification and the C2 informal-review approach. | Medium |
| **Contribution-status automation** | Replace SC-manual maintenance of `glcdi_contribution_status` with a periodic catalogue crawler that detects when a participant has published its first asset. Scales beyond 10 participants. | Small |
| **Compliance / audit framework** | Machine-readable audit trail of policy decisions (who tried what, what was evaluated, what was enforced vs DSA-deferred). Dashboards, SLAs, incident-response runbooks. Required for corporate and certification-body participation. | Medium |
| **Onboarding automation** | Self-service participant enrollment (today the SC manually provisions Keycloak users). Workflow: signed DSA → automated Keycloak user creation → per-participant compose stack provisioned → notification. | Medium |
| **Corporate onboarding** | First corporate partner (food company / certification body) lands in this phase. Needs `corporate-partners` access policy, `payment-required`, `data-retention-limit`, and the governance model for data-as-product pricing. | Medium |
| **DSA v2** | Corporate-grade clauses for `payment-required`, `data-retention-limit`, institutional refinements of `non-commercial`. Signed by all 10+ participants. | Small (governance-only) |
| **Trust Framework v2** | Publishable document incorporating C1–C2 learnings and the post-prototype corporate experience. Intended as input to any follow-on production-grade dataspace. | Small |
| **Certification-evidence formalisation** | Formal SC process replacing C1–C2 informal self-cert. Documents acceptable proof (third-party audit, USDA Organic, Regenerative Organic Certified, SC-reviewed self-declaration). WWF / TNC / SHI certification claims are the first that will need to hold up under scrutiny. | Small (governance-only) |
| **Stress tests at institutional scale** | Exercise every policy under the combined 10+-participant deployment: (a) a WWF researcher trying to see a Caney Fork proprietary asset — blocked by `regenerative-producers`; (b) TNC negotiating a model-training contract — passes under `purpose-model-training`; (c) a newly onboarded institution trying to access the benchmarking pool without publishing first — blocked by `contributing-members`; (d) a corporate ESG consumer purchasing SOC data under `payment-required` + `data-retention-limit`. | Small |

### Implementation approach

Maps to `../TODO.md` Phase 7 (Future Enhancements) plus the workstreams above. The governance + UI workstreams can start on residual prototype budget if institutional onboarding begins before September 2026; the payment + VC + federated-catalogue work is firmly post-grant and depends on the $1.5M follow-on funding landing.

**Not in scope for post-prototype:** compute-to-data (data never leaves the provider), zero-knowledge policy evaluation, cross-dataspace federation with TEMS / other regenerative dataspaces. All interesting, all beyond the currently-anticipated budget.

---

## Summary: policies × cohorts

The prototype itself targets **C1 (small) and C2 (ambitious)**; everything after is a continuous post-prototype phase sized against ~12× the prototype budget.

| | C1 (Q1, in progress) | C2 (Q2, ambitious) | Post-prototype (Q3 2026+) |
|---|---|---|---|
| **Participants** | 3 | 6 | 10+ (rolling institutional + corporate onboarding) |
| **Access policies** | `regenerative-producers`, `members-only` | +`researchers-only`, `contributing-members` | +`corporate-partners` |
| **Contract policies** | `time-limited`, `internal-use-only` | +`non-commercial`, `purpose-model-training`, `attribution`, `anonymisation`, `reciprocal-insights` | +`data-retention-limit`, `payment-required` |
| **Total policies live** | 4 | 11 | 14 |
| **Policies added in this phase** | 4 (from 0) | +7 | +3 (incl. new `corporate-partners` definition) |
| **New Keycloak claims** | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` | `glcdi_contribution_status` | — (roles extended for corporates) |
| **New connector code** | ~200 LOC Java | ~30 LOC Java | Substantial (payment gateway + retention custom fn + VC integration + federated catalogue) |
| **Trust Framework version** | v0 | v1 | v2 |
| **DSA template** | v1 pre-release (`internal-use-only` distribute clause) | v1 full (adds `non-commercial` commercialize + three duty clauses) | v2 (payment / retention clauses + institutional refinements) |
| **Dominant workstream** | Technical (extension + seeding) + one DSA clause | Mixed — governance (full DSA v1) + technical (contribution attr, researcher filter, purpose pilot expansion) | Technical (external systems, VC, federated catalogue, UI composer) + governance (cert-evidence formalisation) |
| **First enforced in this phase** | Access filtering (membership + cert), contract expiry, native-purpose contract rejection | Role-based access, access-level reciprocity, commercial-purpose rejection | Retention, payment, corporate access gate |
| **Budget assumption** | Prototype ($120k order-of-magnitude) | Prototype (same budget) | Follow-on (~$1.5M order-of-magnitude) |

---

## Participant-facing template library per cohort

A policy being *live* (seeded on someone's assets) is not the same as a policy being *choosable* (offered as a template in the participant UI when publishing a new dataset). C1 seeds everything by project team; genuine participant choice begins at C2 and grows. Each template in the UI is a template the Steering Committee has to be able to audit, explain in the DSA, and answer helpdesk questions about — so growth is deliberate.

| Phase | Access templates offered | Contract templates offered | Rationale |
|---|---|---|---|
| **C1** | **0** — project team seeds both access policies directly on participants' assets | **0** — project team seeds both contract policies | 3 participants, workflow-demo focus, pre-UI. Seeding is the source of truth. Sensitive-data policies (`regenerative-producers`, `internal-use-only`) are especially team-curated because the Steering Committee vets them individually. |
| **C2** | **3** — `members-only`, `researchers-only`, `contributing-members` | **5** — `time-limited`, `attribution`, `anonymisation`, `reciprocal-insights`, `purpose-model-training` | First real participant choice at asset-publication time. Keep `regenerative-producers` project-team-seeded so the SC curates who receives sensitive-asset visibility. Keep `internal-use-only` + `non-commercial` project-team-seeded too — they are the default contractual protection bundle on sensitive assets, not a menu item to opt out of. |
| **Post-prototype** | **5** — +`regenerative-producers`, `corporate-partners` | **8** — +`internal-use-only`, `non-commercial`, `data-retention-limit`, `payment-required` | Sensitive-data policies graduate into the UI once the participant purpose-declaration UI ships and the cert-evidence workflow is formalised. The policy composer UI (see post-prototype workstreams) makes the full library user-selectable. |

**Design principle:** access templates grow slower than contract templates. A participant choosing the wrong contract policy annoys their consumer; a participant choosing the wrong access policy accidentally exposes sensitive data. The project team keeps access gates project-team-seeded for longer.

---

## Decision points the Steering Committee owns

The following are **not** technical decisions and will block the rollout if left open:

| Decision | Needed by | Who |
|----------|-----------|-----|
| Canonical `participantType` enum | C1 close-out | SC + Project Team |
| Hardcoded-vs-per-user membership mapper for prototype | C1 close-out | Project Team (recommendation: hardcoded for C1–C2, per-user post-prototype) |
| `certificationStatus` values + informal self-cert assignments for the 3 C1 participants | C1 close-out | SC (self-certifies) |
| Purpose-taxonomy subset for C1 (minimum: `InternalAnalysis`) | C1 close-out | SC + Project Team |
| DSA v1 pre-release clause wording for `internal-use-only` (`distribute` prohibition) | C1 close-out | SC + legal counsel |
| Purpose-taxonomy expansion for C2 (add `AgronomicModelTraining`, `EcosystemModelCalibration`, commercial-purpose values for `non-commercial`) | C2 start | SC + Project Team |
| DSA v1 full clause wording for `attribution`, `anonymisation`, `reciprocal-insights` | C2 start | SC + legal counsel |
| Audit mechanism for duty-based policies | C2 start | SC |
| `contributionStatus` values and the SC workflow for flipping a participant to `"contributing"` | C2 start | SC + Project Team |
| **Formalised** cert-evidence workflow (what proof is acceptable at institutional scale) | Post-prototype | SC |
| Participant UI purpose declaration — design + ship date | Post-prototype | Project Team + SC |
| Funding source for payment-required + data-retention-limit (new grant vs residual prototype budget) | End of C2 | SC + funder |

---

## Open questions (to resolve before finalising this plan)

1. **C1 close-out date** — when does the Steering Committee accept that the sensitive-first policy stack is in place and the workflow demo satisfies C1? Without a named date, C2's DSA + contribution-status work cannot start in earnest.
2. **Informal-vs-formal cert-evidence boundary** — C1 and C2 both rely on SC self-certification (lightweight for 3 → 6 participants). Institutional participants in post-prototype will challenge edge cases. Does the SC accept the risk of running informal evidence through all of C2, with formalisation starting only as WWF/TNC/SHI onboard?
3. **Contribution-status automation threshold** — C2 assumes manual SC maintenance for 6 participants. At what participant count (post-prototype) does automated catalog crawling become necessary, and who owns building it?
4. **Participant UI purpose declaration** — who owns this deliverable, and what's the target ship date? C1–C2 work around it with seeding-script wiring. Without the UI, the purpose-based policies (`internal-use-only`, `non-commercial`, `purpose-model-training`) stay project-team-seeded and cannot graduate into the UI template library.
5. **Does shipping `internal-use-only` at C1 (alone, without the permissive alternative of members-only assets under `time-limited` only) set the right default tone?** Strong protection for producers, but may feel restrictive to researchers expecting collaborative data sharing. Is `members-only` + `time-limited` (no `internal-use-only`) an acceptable C1 alternative for some asset classes?
6. **Grant runway for post-prototype** — will the Walmart Foundation grant extend past September 2026 enough to fund the payment-required work, or does that move to a follow-on grant? This decision becomes urgent at end-of-C2 since institutional onboarding starts right after.
