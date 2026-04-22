# GLCDI Policy Rollout Plan

Which policies go live in which cohort, and what technical + governance work each wave unlocks.

This document joins three pieces that live separately elsewhere:
- the **cohort timeline** (participants and focus) — [`../README.md` §Cohort Timeline](../README.md#cohort-timeline)
- the **technical implementation phases** (vocabulary → Keycloak → extension → seeding → testing → governance) — [`../TODO.md`](../TODO.md)
- the **per-policy feasibility & priority** — [`README.md` §Implementation Feasibility](README.md#implementation-feasibility)

It is a **sequencing** document, not a re-plan. The phase work is still defined in `../TODO.md`; this document decides *when* each policy becomes a blocker.

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

**Goal:** close out C1 by replacing the placeholder `open-research` policy with a **sensitive-first** policy stack and demonstrating the full end-to-end workflow to the Steering Committee. The headline policies — `regenerative-producers` on the access side and `internal-use-only` + `non-commercial` on the contract side — are the strongest protections in the catalogue, appropriate for the initial trusted-inner-circle cohort. Three companion policies (`members-only`, `researchers-only`, `time-limited`) ship alongside so non-producer participants still have a catalogue view and every contract carries a natural expiry.

| Field | Value |
|-------|-------|
| Participants | 3 (Caney Fork, Point Blue, White Buffalo) |
| Focus | Foundational validation, Trust Framework v0, **end-to-end workflow demo**, sensitive-data protection |
| Policies live | 6 |
| New Keycloak claims needed | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` |
| New Java code | ~200 LOC (membership + participant-type + certification-status functions, shared base class) |

### Policies to enable

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`regenerative-producers`](access/regenerative-producers.json) | Access | **Low** | **Headline access policy.** Restricts sensitive grazing-practice data to certified producers. With 3 C1 participants the SC can self-certify informally — the heavy cert-evidence workflow waits for post-prototype institutional onboarding. Evaluates three constraints: membership + producer type + certification status. |
| [`members-only`](access/members-only.json) | Access | **Low** | Companion baseline so non-producer researchers (Point Blue) still see general-membership assets. Without it, C1 would have an empty catalogue for everyone except certified producers. |
| [`researchers-only`](access/researchers-only.json) | Access | **Low** | Required for the Agronomic Model Calibration use case — lets Point Blue access raw SOC data that Caney Fork wouldn't share with everyone. Shares the base-class pattern with `members-only`. Critical for the workflow demo because it produces a visible difference between a producer's and a researcher's catalog view. |
| [`internal-use-only`](contract/internal-use-only.json) | Contract (purpose) | **None** (native) + gov | **Headline contract policy — default tone.** Data shared under GLCDI is for internal analysis by the receiving participant, not for redistribution. Native EDC `odrl:purpose` handles the permission check (consumer must declare `InternalAnalysis`); the `distribute` prohibition is DSA-enforced. |
| [`non-commercial`](contract/non-commercial.json) | Contract (purpose) | **None** (native) + gov | **Second headline contract policy.** Pairs with `internal-use-only` on sensitive producer data: beyond prohibiting redistribution, it also rules out commercial exploitation. Directly addresses Caney Fork's stakeholder concern about "harmful use of data by buyers or competitors". Same native-purpose + DSA-prohibition pattern as `internal-use-only` — no extra technical cost to add at C1. |
| [`time-limited`](contract/time-limited.json) | Contract | **None** | Works in vanilla EDC. Every C1 contract carries a prototype-end expiry (`2026-09-30`), giving the Steering Committee a natural re-contracting moment between cohorts. |

### Implementation approach for C1 close-out

Mapped to `../TODO.md` phases:

| TODO phase | C1 scope | Blocker for C1 close-out? |
|------------|----------|:-:|
| **Phase 1** Vocabulary | Define `glcdi:membership`, `glcdi:participantType`, `glcdi:certificationStatus`, and the purpose-taxonomy subset needed by C1 (`InternalAnalysis`, plus `AgronomicModelTraining` / `EcosystemModelCalibration` for researcher offers). Defer the rest of the purpose taxonomy. | Yes |
| **Phase 2** Keycloak claims | Realm roles (`glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`) + `glcdi_certification_status` user attribute. Hardcoded membership mapper (every authenticated user = `"active"`). SC informally self-certifies the 3 C1 participants (Caney Fork: `regenerative-verified`, White Buffalo: `regenerative-verified`, Point Blue: `not-applicable`). Defer `glcdi_contribution_status` (C2). | Yes |
| **Phase 3** EDC extension | Ship `MembershipConstraintFunction`, `ParticipantTypeConstraintFunction`, and `CertificationStatusConstraintFunction` (with `isAnyOf` support) — three functions sharing a claim-extraction base class. `internal-use-only` and `non-commercial` both use the native EDC `odrl:purpose` mechanism — no function. Skip elapsed-time and payment functions. | Yes |
| **Phase 4** Seeding | Rewrite `seed-caney-fork.sh` / `seed-point-blue.sh`. Attach `regenerative-producers` + `time-limited` + `internal-use-only` + `non-commercial` to sensitive grazing-practice assets; `researchers-only` + `time-limited` + `internal-use-only` to SOC data for Point Blue; `members-only` + `time-limited` + `internal-use-only` to general-membership assets. Seeding wires the declared purpose into the consumer-side contract offer for the purpose-based policies to evaluate. | Yes |
| **Phase 5** Testing | Integration tests: (a) certified producer sees the sensitive grazing-practice asset, researcher does not; (b) researcher sees SOC asset, producer does not; (c) contract offer with a non-`InternalAnalysis` purpose is rejected; (d) contract offer declaring a commercial purpose is rejected for `non-commercial` assets; (e) expired contract is rejected. **Plus** the end-to-end workflow demo to the Steering Committee. | Yes (gates close-out) |
| **Phase 6** Governance | **First DSA draft (v1 pre-release).** Trust Framework v0 ships with clause wording for `internal-use-only` (`distribute` prohibition) **and** `non-commercial` (`commercialize` prohibition) — both prohibitions that the connector cannot technically enforce. Full duty-policy clause set arrives with C2. MOU updated to reference the policy stack. | Parallel, gates close-out |
| **Phase 7** Future | — | — |

### Explicitly deferred past C1

- **`contributing-members`** — needs `glcdi_contribution_status` user attribute and the SC workflow that flips it once a participant publishes their first asset. Not useful until C2 brings in participants who haven't yet contributed.
- **Duty-based policies** (`attribution`, `anonymisation`, `reciprocal-insights`) — no connector work needed, but the DSA clause set is not finalised at C1 close-out. Land with C2's governance push.
- **`purpose-model-training`** — uses the same native-purpose mechanism C1 pilots. Added in C2 alongside the researcher-model-feeding combined scenario once UF and TSIP onboard.
- **Participant purpose-declaration UI, cert-evidence formalisation, corporate participation, payment, retention** — all post-prototype.

---

## Cohort 2 — Q2 2026 (now starting)

**Goal:** onboard the second wave of participants, introduce access-level reciprocity, and complete the duty-based DSA clause set. All five policies added at C2 lean heavily on governance work (DSA v1 first full release) rather than new connector code — the technical infrastructure from C1 is reused.

| Field | Value |
|-------|-------|
| Participants | 6 (C1 + PASA, University of Florida, TSIP) |
| Focus | Cross-context testing, Trust Framework v1 **draft**, full duty-policy DSA release, first access-level reciprocity |
| Policies live | +5 (total 10) |
| New Keycloak claims needed | `glcdi_contribution_status` (user attribute) |
| New Java code | ~30 LOC (`ContributionStatusConstraintFunction`, sharing the base class with C1's functions) |

### Policies to add

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`contributing-members`](access/contributing-members.json) | Access | **Low** (enforced) | **First enforced reciprocity gate.** Non-contributors do not see benchmarking-pool assets in the catalog. Requires `glcdi_contribution_status` user attribute; for 6 participants the Steering Committee can maintain it manually. |
| [`purpose-model-training`](contract/purpose-model-training.json) | Contract (purpose) | **None** (native) | Reuses C1's native-purpose infrastructure. Rejects offers that don't declare `AgronomicModelTraining` / `EcosystemModelCalibration` — matches the researcher-model-feeding use case, now that C2 onboards UF and TSIP. |
| [`attribution`](contract/attribution.json) | Contract (duty) | **None** (gov) | Lowest-cost DSA clause. First duty the Steering Committee has to actually track — proves the governance pipeline can absorb compliance monitoring. |
| [`anonymisation`](contract/anonymisation.json) | Contract (duty) | **None** (gov) | Required for the researcher-model-feeding combined scenario. DSA clause only. |
| [`reciprocal-insights`](contract/reciprocal-insights.json) | Contract (duty) | **None** (gov) | Contract-level reciprocity obligation. Pairs with the access-level `contributing-members` above so both sides of reciprocity land in the same cohort. |

### Implementation approach for C2

| TODO phase | C2 scope |
|------------|----------|
| **Phase 1** Vocabulary | Extend the context with `glcdi:contributionStatus`, the custom `glcdi:shareBack` action used by `reciprocal-insights`, and the purpose values already not covered in C1. |
| **Phase 2** Keycloak claims | Add `glcdi_contribution_status` user attribute + protocol mapper. Define the SC workflow that flips it to `"contributing"` once a participant has published their first asset. Assign C1 roles + initial contribution status to PASA, UF, TSIP during onboarding. |
| **Phase 3** EDC extension | Add `ContributionStatusConstraintFunction` (shares base class with C1's functions). `purpose-model-training` uses the native EDC purpose mechanism already piloted by `internal-use-only` in C1 — no new function needed. |
| **Phase 4** Seeding | Attach `contributing-members` to benchmarking-pool assets. Expand researcher-oriented SOC datasets to combine `researchers-only` + `purpose-model-training` + `attribution` + `anonymisation`. Attach `reciprocal-insights` where share-back is expected. |
| **Phase 5** Testing | (a) a non-contributor's catalog query hides the benchmarking-pool asset; (b) a contract offer declaring `Scope3Reporting` is rejected for a model-training asset; (c) duty-policy clauses are correctly stored and surfaced in catalog responses. |
| **Phase 6** Governance | **Main delivery.** DSA v1 full release — extends C1's `internal-use-only` clauses with `attribution`, `anonymisation`, `reciprocal-insights` wording. Audit/monitoring workflow defined (who checks, how often, what evidence). SC workflow for contribution-status updates documented. |
| **Phase 7** Future | — |

### Explicitly deferred past C2 (→ post-prototype)

- **Certification-evidence formalisation** — at C1 the SC self-certified informally and C2 inherits that approach for the 3 new participants. Formal cert-evidence workflow (what proof is acceptable, how it's reviewed) lands post-prototype as institutional participants (WWF, TNC, SHI) whose claims need external evidence begin onboarding.
- **Participant UI purpose dropdown** — at C2, purpose is still declared in consumer tooling / seeding scripts. The end-user-facing UI ships post-prototype, unlocking the sensitive-data contract policies (`internal-use-only`, `non-commercial`, `purpose-model-training`) as selectable UI templates.
- **Corporate participation, payment, retention, `corporate-partners` access policy** — unchanged, post-prototype.

---

## Post-prototype — Q3 2026 onwards

**Goal:** absorb the institutional onboarding, governance formalisation, UI polish, and corporate-facing policies that were originally split between a third cohort and a vaguer "post-prototype" bucket. The prototype itself ends with C2; everything below is the path toward a production dataspace.

| Field | Value |
|-------|-------|
| Participants | 10+ (C2 + WWF, TNC, Soil Health Institute, American Farmland Trust, USRSB, first corporates) |
| Focus | Institutional scale, formal governance, participant self-service, corporate onboarding, post-grant sustainability |
| Policies added | +3 (total 13, up from 10 at end of C2) |
| New Keycloak claims | — (roles extended to include corporate variants) |
| New Java code | ~200 LOC (elapsed-time function + payment gateway integration) |

### New policies to add

| Policy | Type | Effort | Why post-prototype |
|--------|------|:------:|--------------------|
| [`data-retention-limit`](contract/data-retention-limit.json) | Contract | **Medium** | Needed for corporate data consumers. Custom function tracks transfer timestamps against `odrl:elapsedTime`. |
| [`payment-required`](contract/payment-required.json) | Contract | **High** | Needed for corporate ESG / Scope 3 use case. Requires external payment integration. |
| `corporate-partners` access policy | Access | **Low** | New policy (not yet defined) targeting `corporate`, `certification-body`, `supply-chain-partner` roles. |

### Non-policy workstreams absorbed into the post-prototype phase

These were previously scheduled inside a third onboarding cohort. They are still real deliverables — just not gated by a "next-cohort-starts" moment, since post-prototype onboarding is rolling rather than phased:

| Workstream | Delivery |
|------------|----------|
| **Certification-evidence formalisation** | Formal SC process replacing C1's informal self-cert. Document what proof is acceptable (third-party audit, USDA Organic, Regenerative Organic Certified, self-declaration with steering-committee review, etc.). WWF / TNC / SHI certification claims are the first that will need to hold up under scrutiny. |
| **Participant UI: purpose declaration** | Surface purpose declaration at contract-negotiation time in the Hubl-based catalog UI, replacing the C1–C2 seeding-script workaround. Once shipped, participants can author their own contract offers without project-team help and the purpose-based policies can graduate into the UI template library (see below). |
| **DSA v2** | Extends C2's DSA v1 with `commercialize` refinements (if C1's `non-commercial` clause needs institutional-scale tightening), plus new clauses for `data-retention-limit` and `payment-required`. |
| **Trust Framework v2** | Publishable document incorporating C1–C2 learnings and the post-prototype corporate experience. Intended as input to any follow-on production-grade dataspace. |
| **Stress tests at institutional scale** | Exercise every policy under the combined 10+-participant cohort: (a) a WWF researcher trying to see a Caney Fork proprietary asset — blocked by `regenerative-producers`; (b) TNC negotiating a model-training contract — passes under `purpose-model-training`; (c) a newly onboarded institution trying to access the benchmarking pool without publishing first — blocked by `contributing-members`. |

### Implementation approach

Maps to `../TODO.md` Phase 7 (Future Enhancements), plus a new `corporate-partners` access-policy definition and the non-policy workstreams above. The payment-required and data-retention-limit technical work likely requires a **separate funding cycle** — flagged in the blueprint as "tied to value delivered for corporate participants". The governance + UI workstreams can run on the residual prototype budget if institutional onboarding begins before September 2026.

---

## Summary: policies × cohorts

The prototype itself targets **C1 and C2**; everything after is a continuous post-prototype phase, not a third onboarding cohort.

| | C1 (Q1, in progress) | C2 (Q2) | Post-prototype (Q3 2026+) |
|---|---|---|---|
| **Participants** | 3 | 6 | 10+ (rolling institutional + corporate onboarding) |
| **Access policies** | `regenerative-producers`, `members-only`, `researchers-only` | +`contributing-members` | +`corporate-partners` |
| **Contract policies** | `time-limited`, `internal-use-only`, `non-commercial` | +`attribution`, `anonymisation`, `reciprocal-insights`, `purpose-model-training` | +`data-retention-limit`, `payment-required` |
| **Total policies live** | 6 | 10 | 13 |
| **New Keycloak claims** | `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` | `glcdi_contribution_status` | — (roles extended for corporates) |
| **New connector code** | ~200 LOC Java | ~30 LOC Java | ~200 LOC Java + payment integration |
| **Trust Framework version** | v0 | v1 | v2 |
| **DSA template** | v1 pre-release (`internal-use-only` distribute + `non-commercial` commercialize clauses) | v1 full (adds duty clauses) | v2 (payment / retention clauses + institutional refinements) |
| **Dominant workstream** | Technical (extension + seeding) + sensitive-data DSA clauses | Mixed — governance (full DSA v1) + technical (contribution attr) | Technical (external systems) + governance (cert-evidence formalisation) + UI |
| **First enforced in this cohort** | Access filtering (membership + cert), contract expiry, native-purpose contract rejection (internal use + non-commercial) | Access-level reciprocity | Retention, payment, corporate access gate |

---

## Participant-facing template library per cohort

A policy being *live* (seeded on someone's assets) is not the same as a policy being *choosable* (offered as a template in the participant UI when publishing a new dataset). C1 seeds everything by project team; genuine participant choice begins at C2 and grows. Each template in the UI is a template the Steering Committee has to be able to audit, explain in the DSA, and answer helpdesk questions about — so growth is deliberate.

| Cohort | Access templates offered | Contract templates offered | Rationale |
|---|---|---|---|
| **C1** | **0** — project team seeds all 3 access policies directly on participants' assets | **0** — project team seeds all 3 contract policies | 3 participants, workflow-demo focus, pre-UI. Seeding is the source of truth. Sensitive-data policies (`regenerative-producers`, `internal-use-only`, `non-commercial`) are especially team-curated because the Steering Committee vets them individually. |
| **C2** | **3** — `members-only`, `researchers-only`, `contributing-members` | **5** — `time-limited`, `attribution`, `anonymisation`, `reciprocal-insights`, `purpose-model-training` | First real participant choice at asset-publication time. Keep `regenerative-producers` project-team-seeded so the SC curates who receives sensitive-asset visibility. Keep `internal-use-only` + `non-commercial` project-team-seeded too — they are the default contractual protection bundle on sensitive assets, not a menu item to opt out of. |
| **Post-prototype** | **5** — +`regenerative-producers`, `corporate-partners` | **8** — +`internal-use-only`, `non-commercial`, `data-retention-limit`, `payment-required` | Sensitive-data policies graduate into the UI once the participant purpose-declaration UI ships and the cert-evidence workflow is formalised. Full library becomes user-selectable. |

**Design principle:** access templates grow slower than contract templates. A participant choosing the wrong contract policy annoys their consumer; a participant choosing the wrong access policy accidentally exposes sensitive data. The project team keeps access gates project-team-seeded for longer.

---

## Decision points the Steering Committee owns

The following are **not** technical decisions and will block the rollout if left open:

| Decision | Needed by | Who |
|----------|-----------|-----|
| Canonical `participantType` enum | C1 close-out | SC + Project Team |
| Hardcoded-vs-per-user membership mapper for prototype | C1 close-out | Project Team (recommendation: hardcoded for C1–C2, per-user post-prototype) |
| `certificationStatus` values + informal self-cert assignments for the 3 C1 participants | C1 close-out | SC (self-certifies) |
| Purpose-taxonomy subset for C1 (minimum: `InternalAnalysis`, `AgronomicModelTraining`, `EcosystemModelCalibration`) | C1 close-out | SC + Project Team |
| DSA v1 pre-release clause wording for `internal-use-only` (`distribute` prohibition) **and** `non-commercial` (`commercialize` prohibition) | C1 close-out | SC + legal counsel |
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
5. **Does shipping `internal-use-only` + `non-commercial` at C1 set the right default tone?** Strong protection for producers, but may feel restrictive to researchers expecting collaborative data sharing. Should C1 also surface a more open contract alternative (e.g. `time-limited` alone on some assets) so researchers have a gentler entry path?
6. **Grant runway for post-prototype** — will the Walmart Foundation grant extend past September 2026 enough to fund the payment-required work, or does that move to a follow-on grant? This decision becomes urgent at end-of-C2 since institutional onboarding starts right after.
