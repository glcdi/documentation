# GLCDI Dataspace Management

Governance, policy design, and identity management resources for the
**Grazing Lands Carbon Data Initiative (GLCDI)** dataspace.

This directory is the working space for designing the rules, roles, and trust mechanisms
that govern how data flows between participants. It is not a deployable service — it feeds
into the three deployable sub-projects of the GLCDI workspace:

| Sub-project | What it deploys | What it takes from here |
|-------------|----------------|------------------------|
| [`edc-connector/`](../edc-connector/) | EDC connector runtime | Custom policy function extension (Phase 3) |
| [`governance-services/`](../governance-services/) | Keycloak, onboarding app | Realm roles, protocol mappers, user attributes (Phase 2) |
| [`participant-agent-services/`](../participant-agent-services/) | Per-participant stack | Policy-aware seeding scripts (Phase 4) |

## Contents

```
management/
├── README.md           # This file — governance overview
├── AUTHORITY.md        # Proposed responsibilities & operating mode of the Dataspace Authority
├── IDENTITY.md         # Identity, authentication & standards (OIDC, OID4VC, Keycloak)
├── STANDARDS.md        # Trust & control mechanisms — specification mapping (ODRL, DSP, DCAT, JSON-LD)
├── AGENTS.md           # Context file for AI agents
├── IMPLEM_PLAN.md      # Implementation plan (7 phases)
└── policies/
    ├── README.md       # Policy catalogue documentation
    ├── access/         # Access policies (catalog visibility)
    ├── contract/       # Contract policies (usage terms)
    ├── combined/       # End-to-end scenario examples
    └── diagrams/       # PlantUML sequence diagrams
```

---

## Governance Model (Proposal)

The governance model described below is put forward as a proposal for the Dataspace Authority and wider project team to validate and refine. Nothing here is a decided commitment.

### Trust Framework

GLCDI is proposed to be a multi-stakeholder data space built on **consent-governed, permissioned data sharing**.
Participants would retain ownership and control over their data. The proposed governance model is structured
around:

- **Membership** — the proposal is that participants are onboarded through a formal process (application, review by a governance body, signed MOU/Data Sharing Agreement).
- **Roles** — each participant would have a declared type (producer, researcher, data steward, etc.) that determines what data they can discover and under what terms.
- **Policies** — ODRL-based rules attached to data assets that enforce access control and usage conditions at the technical level.
- **Trust Framework** — a living document (proposed v0 in Q1 2026, v1 in Q2) that would codify the governance norms, templates, and compliance expectations.

### Governance Bodies (Proposed)

| Body | Proposed role | Proposed cadence |
|------|---------------|------------------|
| **Project Team** | Technical implementation, infrastructure, standards | Ongoing |
| **Dataspace Authority** | Governance decisions, participant approval, Trust Framework review | To be agreed — indicative monthly |
| **Cohort participants** | Data sharing, feedback, co-design | Per cohort phase |

A standalone proposal for the Dataspace Authority's responsibilities, composition, operating mode, and explicit out-of-scope items lives in [`AUTHORITY.md`](AUTHORITY.md) — to be reviewed, amended, and ratified by the body itself once seated. The name "Dataspace Authority" is a working label; alternatives (Council, Committee, Trust Body) are on the table and discussed in that document.

### Cohort Timeline (Proposal)

Specific participant composition per cohort is under discussion and intentionally omitted here. The proposed shape is:

| Phase | Period | Participant count (indicative) | Focus |
|-------|--------|-------------------------------|-------|
| Cohort 1 | Q1 2026 | ~3 (prototype onboarding) | Foundational validation, Trust Framework v0 |
| Cohort 2 | Q2 2026 | ~6 (C1 + a proposed second wave, TBD) | Cross-context testing, Trust Framework v1 |
| Cohort 3 | Q3 2026 | Expanded institutional participation (TBD) | Institutional stress-testing |
| Post-prototype | 2027+ | Rolling institutional + corporate onboarding (TBD) | Broader onboarding |

---

## Identity & Authentication

Identity management, authentication, the GLCDI claim model (realm roles, certification status, membership), the OIDC-vs-OID4VC rationale, the proposed onboarding flow, the identity standards mapping, and the migration path to Verifiable Credentials all live in a dedicated document: [`IDENTITY.md`](IDENTITY.md).

At a glance:
- **Federated OIDC** with Keycloak at two tiers (per-participant realm `edc` → governance realm `glcdi`).
- Three GLCDI-specific token claims (`glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`) consumed by EDC policy functions.
- OIDC for the prototype; Verifiable Credentials / OID4VC considered but deliberately deferred — see [`IDENTITY.md`](IDENTITY.md) for the full argument.

---

## Data Exchange & Policy Enforcement

Policies (access, contract, combined scenarios), the DSP data-exchange flow, and the sequence diagrams walking through each scenario are documented in [`policies/README.md`](policies/README.md) and [`policies/diagrams/`](policies/diagrams/). See also [`policies/plan.md`](policies/plan.md) for the proposed rollout across cohorts.

---

## Technical vs. Governance Enforcement

Not all policy obligations can be technically enforced by the connector. This table clarifies
the enforcement boundary:

| Mechanism | Enforced by | Examples |
|-----------|------------|---------|
| **Access policy filtering** | EDC connector (automatic) | Hiding offers from non-researchers, non-members |
| **Contract constraint evaluation** | EDC connector (at negotiation) | Purpose check, temporal check |
| **Payment verification** | Custom policy function + external system | Payment-required policy |
| **Anonymisation** | Data Sharing Agreement (legal) | Anonymisation obligation |
| **Attribution** | Data Sharing Agreement (legal) | Citation duty |
| **Data deletion** | Data Sharing Agreement (legal) | Retention limit obligation |
| **Non-redistribution** | Data Sharing Agreement (legal) | Internal-use-only prohibition |

The **Trust Framework** bridges this gap: it documents the governance-level obligations,
how compliance is verified (self-attestation, audit, review), and what happens on breach.

---

## Trust & Control Mechanisms — Specification Mapping

The standards-mapping reference (ODRL, DSP, DCAT, JSON-LD, identity standards) has moved to [`STANDARDS.md`](STANDARDS.md) — with identity-specific standards detailed in [`IDENTITY.md`](IDENTITY.md).

---

## Implementation Status & Roadmap

See [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) for the full seven-phase implementation plan and current status. Cohort-level policy rollout sequencing lives in [`policies/plan.md`](policies/plan.md).
