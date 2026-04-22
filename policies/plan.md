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
3. **Don't enable a purpose-based contract policy before the participant UI surfaces purpose declaration.** A silently-passing purpose constraint is worse than no policy at all.
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

The rollout below proposes what remains to be delivered for C1 before it closes out, then what C2 / C3 / post-prototype add on top.

---

## Cohort 1 — Q1 2026 (in progress)

**Goal:** close out C1 by replacing the placeholder `open-research` policy with a baseline policy stack that actually filters the catalog, and demonstrate the full end-to-end workflow to the Steering Committee. The minimum set that answers *"does the policy stack actually filter, and does the workflow hold together from login to expiry?"*

| Field | Value |
|-------|-------|
| Participants | 3 (Caney Fork, Point Blue, White Buffalo) |
| Focus | Foundational validation, Trust Framework v0, **end-to-end workflow demo** |
| Policies live | 3 |
| New Keycloak claims needed | `glcdi_membership`, `glcdi_roles` |
| New Java code | ~150 LOC (membership + participant-type functions, shared base class) |

### Policies to enable

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`time-limited`](contract/time-limited.json) | Contract | **None** | Works in vanilla EDC. Immediate value as consent-renewal hook between cohorts. No blocker. |
| [`members-only`](access/members-only.json) | Access | **Low** | Baseline for the federated catalog. Without it, the "consent-governed" claim in the blueprint is a fiction, and the workflow demo has nothing to show on the access-filtering side. |
| [`researchers-only`](access/researchers-only.json) | Access | **Low** | Required for the Agronomic Model Calibration use case — lets Point Blue access raw SOC data that Caney Fork wouldn't share with everyone. Shares the same function pattern as `members-only`. Critical for the workflow demo because it produces a visible difference between a producer's and a researcher's catalog view. |

### Implementation approach for C1 close-out

Mapped to `../TODO.md` phases:

| TODO phase | C1 scope | Blocker for C1 close-out? |
|------------|----------|:-:|
| **Phase 1** Vocabulary | Define `glcdi:membership` and `glcdi:participantType`. Defer `certificationStatus`, `contributionStatus`, full purpose taxonomy. | Yes |
| **Phase 2** Keycloak claims | Realm roles: `glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`. Hardcoded membership mapper (every authenticated user = `"active"` for the prototype). **Skip** user attributes entirely. | Yes |
| **Phase 3** EDC extension | Ship `MembershipConstraintFunction` and `ParticipantTypeConstraintFunction` with a shared base. Register for the two namespace URIs. Skip certification and elapsed-time functions. | Yes |
| **Phase 4** Seeding | Rewrite `seed-caney-fork.sh` / `seed-point-blue.sh` to use `members-only` + `time-limited` on benchmarking-style assets, `researchers-only` + `time-limited` on SOC data. | Yes |
| **Phase 5** Testing | Integration tests: (a) researcher sees SOC asset, producer doesn't; (b) expired contract is rejected. **Plus** the end-to-end workflow demo to the Steering Committee. | Yes (gates close-out) |
| **Phase 6** Governance | Trust Framework v0 references the enabled policies. MOU in place. No DSA clauses yet (those arrive with C2). | Parallel |
| **Phase 7** Future | — | — |

### Explicitly deferred past C1

- **All purpose-based contract policies** (`purpose-model-training`, `non-commercial`, `internal-use-only`) — the participant UI doesn't surface purpose declaration yet. Enabling them without UI support would produce silent pass/fail.
- **`regenerative-producers`** — needs `glcdi_certification_status` user attribute populated by the Steering Committee for every producer. Not ready by C1 close-out.
- **`contributing-members`** — needs the reciprocity workflow (SC verification that a participant has published) — C3 item.
- **Duty-based policies** (`attribution`, `anonymisation`, `reciprocal-insights`) — no connector work needed, but DSA templates aren't drafted yet. Defer until DSA v1 lands with C2.

---

## Cohort 2 — Q2 2026 (now starting)

**Goal:** onboard the second wave of participants, exercise the DSA pipeline for the first time, **and give both the access and contract layers real teeth**. C2 mixes three governance-only (DSA-enforced) duties with two connector-enforced policies — one access, one contract — so the cohort proves enforcement and governance in parallel.

| Field | Value |
|-------|-------|
| Participants | 6 (C1 + PASA, University of Florida, TSIP) |
| Focus | Cross-context testing, Trust Framework v1 **draft**, first DSA-enforced duties, **first reciprocity and purpose enforcement** |
| Policies live | +5 (total 8) |
| New Keycloak claims needed | `glcdi_contribution_status` (user attribute) |
| New Java code | ~30 LOC (`ContributionStatusConstraintFunction`, sharing the base class with C1's functions) |

### Policies to add

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`attribution`](contract/attribution.json) | Contract (duty) | **None** (gov) | Lowest-cost DSA clause. First duty the Steering Committee has to actually track — proves the governance pipeline can absorb compliance monitoring. |
| [`anonymisation`](contract/anonymisation.json) | Contract (duty) | **None** (gov) | Required for the researcher-model-feeding combined scenario. DSA clause only. |
| [`reciprocal-insights`](contract/reciprocal-insights.json) | Contract (duty) | **None** (gov) | Contract-level reciprocity obligation. Pairs with `contributing-members` below — access-level and contract-level reciprocity land in the same cohort. |
| [`contributing-members`](access/contributing-members.json) | Access | **Low** (enforced) | **First enforced reciprocity gate.** Non-contributors do not see benchmarking-pool assets in the catalog. Requires `glcdi_contribution_status` user attribute; for 6 participants the Steering Committee can maintain it manually. |
| [`purpose-model-training`](contract/purpose-model-training.json) | Contract (purpose) | **None** (native) | **First enforced contract-negotiation check.** Native EDC `odrl:purpose` evaluation rejects offers that don't declare the right purpose. Consumer tooling / seeding scripts wire the purpose in programmatically — no participant UI required until C3. |

### Implementation approach for C2

| TODO phase | C2 scope |
|------------|----------|
| **Phase 1** Vocabulary | Extend the context to include `glcdi:contributionStatus`, the custom `glcdi:shareBack` action used by `reciprocal-insights`, and the subset of the purpose taxonomy needed by `purpose-model-training` (`AgronomicModelTraining`, `EcosystemModelCalibration`). |
| **Phase 2** Keycloak claims | Add `glcdi_contribution_status` user attribute + protocol mapper. Define the SC workflow that flips it to `"contributing"` once a participant has published their first asset. Assign C1 roles + initial contribution status to PASA, UF, TSIP during onboarding. |
| **Phase 3** EDC extension | Add `ContributionStatusConstraintFunction` (shares base class with C1's functions). `purpose-model-training` uses the native EDC purpose mechanism — no function needed. |
| **Phase 4** Seeding | Attach `contributing-members` + `time-limited` to the benchmarking-pool assets. Attach `purpose-model-training` (plus `attribution` / `anonymisation`) to researcher-oriented SOC datasets. Attach `reciprocal-insights` where share-back is expected. Seeding must include the declared purpose in the consumer-side contract offer for `purpose-model-training` to evaluate. |
| **Phase 5** Testing | (a) a non-contributor's catalog query hides the benchmarking-pool asset; (b) a contract offer declaring `Scope3Reporting` is rejected for a model-training asset; (c) governance/duty policies are correctly stored and surfaced. |
| **Phase 6** Governance | **Main delivery.** DSA v1 drafted and signed by C1 + C2 participants. Clause wording for `attribution`, `anonymisation`, `reciprocal-insights`. Audit/monitoring workflow defined (who checks, how often, what evidence). SC workflow for contribution-status updates documented. |
| **Phase 7** Future | — |

### Explicitly deferred past C2

- **`regenerative-producers`** and the `glcdi_certification_status` attribute — the certification-evidence workflow is heavy and belongs to C3.
- **Participant UI purpose dropdown** — at C2, purpose is declared in consumer tooling / seeding scripts; the end-user-facing UI ships with C3.
- **`non-commercial`, `internal-use-only`** — both reuse the native `odrl:purpose` mechanism that `purpose-model-training` pilots at C2. No reason to enable all three at once; land them in C3 once the UI is proven and the DSA clauses exist.
- **Corporate participation, payment, retention** — unchanged, post-prototype.

---

## Cohort 3 — Q3 2026

**Goal:** introduce certification-based access control and complete the purpose-based contract policies. Stress-test with institutional participants (WWF, TNC, Soil Health Institute) who will actually read the DSA clauses and challenge edge cases.

| Field | Value |
|-------|-------|
| Participants | 9 (C2 + WWF, TNC, Soil Health Institute) |
| Focus | Institutional stress-testing, Trust Framework v1 **final**, participant UI purpose declaration |
| Policies live | +3 (total 11) |
| New Keycloak claims needed | `glcdi_certification_status` (user attribute) |
| New Java code | ~50 LOC (`CertificationStatusConstraintFunction` with `isAnyOf` support) |

### Policies to add

| Policy | Type | Effort | Why this cohort |
|--------|------|:------:|-----------------|
| [`regenerative-producers`](access/regenerative-producers.json) | Access | **Low** | Enables the sensitive-practices-data use case. Requires SC-validated certification attribute + certification-evidence workflow. |
| [`internal-use-only`](contract/internal-use-only.json) | Contract (purpose) | **Low** | Default protective contract for peer-to-peer data sharing. Reuses the purpose mechanism piloted by `purpose-model-training` in C2; adds DSA clause for the `distribute` prohibition. |
| [`non-commercial`](contract/non-commercial.json) | Contract (purpose) | **Low** | Protects producers from competitive misuse. Same pattern; adds DSA clause for the `commercialize` prohibition. |

### Implementation approach for C3

| TODO phase | C3 scope |
|------------|----------|
| **Phase 1** Vocabulary | Finalise `certificationStatus` enum and the full ODRL purpose taxonomy (C2 shipped only the model-training subset). |
| **Phase 2** Keycloak claims | Add `glcdi_certification_status` user attribute. Define the SC workflow for certification evidence (who reviews, what proof is accepted). |
| **Phase 3** EDC extension | Add `CertificationStatusConstraintFunction` with `isAnyOf` support. `internal-use-only` and `non-commercial` reuse the native EDC `odrl:purpose` mechanism piloted in C2 — no new function needed. |
| **Phase 4** Seeding | Enable the three combined scenarios: `researcher-model-feeding` (now with the full purpose + anonymisation + attribution bundle), `rancher-benchmarking`, `reciprocal-benchmarking`. |
| **Phase 5** Testing | (a) regenerative-producer sees proprietary asset, researcher doesn't; (b) contract rejected for commercial purpose on a non-commercial asset; (c) internal-use-only contract rejected for non-InternalAnalysis purposes. |
| **Phase 6** Governance | Extend DSA v1 with clauses for `internal-use-only` (`distribute` prohibition) and `non-commercial` (`commercialize` prohibition). Document the certification-evidence process. |
| **Phase 7** Future | — |

### Prerequisite ordering inside C3

```
Phase 1 (finalise cert taxonomy + full purpose taxonomy)
    │
    ├──→ Phase 2 (SC workflow for certification evidence)       ◀── starts at end of Q2
    │       │
    │       └──→ Phase 3 (cert function) ──→ Phase 4 (seeding) ──→ Phase 5 (tests)  ◀── mid-Q3
    │
    ├──→ Participant UI: purpose declaration field              ◀── ships before Phase 4
    │
    └──→ Phase 6 (DSA clause extension)                         ◀── runs all of Q3
```

The participant UI change (surfacing purpose at contract negotiation time for end users, replacing C2's seeding-script purpose wiring) is the main non-phase blocker for C3. If the UI slips, `internal-use-only` and `non-commercial` slide to post-prototype and C3 ships with only `regenerative-producers`.

---

## Post-prototype — Q4 2026+

**Goal:** onboard corporate / supply-chain consumers. Introduces the first policies that require external systems (payment) and non-trivial custom functions (retention).

| Field | Value |
|-------|-------|
| Participants | 10+ (C3 + American Farmland Trust, USRSB, first corporates) |
| Focus | Broader onboarding, post-grant sustainability |
| Policies live | +3 (total 14) |
| New Java code | ~200 LOC (elapsed-time function + payment gateway integration) |

### Policies to add

| Policy | Type | Effort | Why post-prototype |
|--------|------|:------:|--------------------|
| [`data-retention-limit`](contract/data-retention-limit.json) | Contract | **Medium** | Needed for corporate data consumers. Custom function tracks transfer timestamps. |
| [`payment-required`](contract/payment-required.json) | Contract | **High** | Needed for corporate ESG / Scope 3 use case. Requires external payment integration. |
| `corporate-partners` access policy | Access | **Low** | New policy (not yet defined) targeting `corporate`, `certification-body`, `supply-chain-partner` roles. |

### Implementation approach

Maps to `../TODO.md` Phase 7 (Future Enhancements), plus a new access-policy definition. Likely requires a separate funding cycle — flagged in the blueprint as "tied to value delivered for corporate participants".

---

## Summary: policies × cohorts

| | C1 (Q1, in progress) | C2 (Q2) | C3 (Q3) | Post-prototype |
|---|---|---|---|---|
| **Participants** | 3 | 6 | 9 | 10+ |
| **Access policies** | `members-only`, `researchers-only` | +`contributing-members` | +`regenerative-producers` | +`corporate-partners` |
| **Contract policies** | `time-limited` | +`attribution`, `anonymisation`, `reciprocal-insights`, `purpose-model-training` | +`internal-use-only`, `non-commercial` | +`data-retention-limit`, `payment-required` |
| **Total policies live** | 3 | 8 | 11 | 14 |
| **New Keycloak claims** | `glcdi_membership`, `glcdi_roles` | `glcdi_contribution_status` | `glcdi_certification_status` | — (roles extended for corporates) |
| **New connector code** | ~150 LOC Java | ~30 LOC Java | ~50 LOC Java | ~200 LOC Java + payment integration |
| **Trust Framework version** | v0 | v1 (draft) | v1 (final) | v2 |
| **DSA template** | MOU only | v1 (duty clauses) | v1 extended (purpose clauses) | v2 (payment / retention clauses) |
| **Dominant workstream** | Technical (extension + seeding) | Mixed — governance (DSA v1) + technical (contribution attr, native purpose pilot) | Technical + governance + participant UI | Technical + external systems |
| **First enforced in this cohort** | Access filtering, contract expiry | Access-level reciprocity, purpose-based contract rejection | Certification-based access | Retention, payment |

---

## Decision points the Steering Committee owns

The following are **not** technical decisions and will block the rollout if left open:

| Decision | Needed by | Who |
|----------|-----------|-----|
| Canonical `participantType` enum | C1 close-out | SC + Project Team |
| Hardcoded-vs-per-user membership mapper for prototype | C1 close-out | Project Team (recommendation: hardcoded for C1, per-user from C3) |
| DSA v1 clause wording for `attribution`, `anonymisation`, `reciprocal-insights` | C2 start | SC + legal counsel |
| Audit mechanism for duty-based policies | C2 start | SC |
| `contributionStatus` values and the SC workflow for flipping a participant to `"contributing"` | C2 start | SC + Project Team |
| Which subset of the purpose taxonomy ships with C2 (minimum: `AgronomicModelTraining`, `EcosystemModelCalibration`) | C2 start | SC + Project Team |
| `certificationStatus` values and evidence required to set them | C3 start | SC |
| Participant UI purpose declaration — design + ship date | C3 start | Project Team + SC |
| Go/no-go on C3's purpose-based contract policies (depends on UI readiness) | C3 mid-quarter | Project Team + SC |

---

## Open questions (to resolve before finalising this plan)

1. **C1 close-out date** — when does the Steering Committee accept that the workflow demo satisfies C1, and what is the cut-over moment to C2? Without a named date, C2's technical + DSA work cannot start in earnest.
2. **Contribution-status automation threshold** — the plan assumes manual SC maintenance for 6 C2 participants. At what participant count (C3? post-prototype?) does automated catalog crawling become necessary, and who owns building it?
3. **Participant UI purpose declaration** — who owns this deliverable, and what's the target ship date? C2 works around it with seeding-script wiring, but C3's `internal-use-only` and `non-commercial` cannot ship without it.
4. **Does C2's purpose-based pilot (`purpose-model-training` only) generalise cleanly to C3?** If the pattern proves fragile (silent pass/fail, consumer discipline issues), we may need a connector-side "purpose-required" guard before enabling more purpose-based policies.
5. **Grant runway for post-prototype** — will the Walmart Foundation grant extend past September 2026 enough to fund the payment-required work, or does that move to a follow-on grant?
