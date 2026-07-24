# GLCDI Dataspace Management

Governance, policy design, and identity management resources for the
**Grazing Lands Carbon Data Initiative (GLCDI)** dataspace.

This directory is the working space for designing the rules, roles, and trust mechanisms
that govern how data flows between participants. It is not a deployable service - it feeds into the three deployable sub-projects of the GLCDI workspace:

| Sub-project | What it deploys | What it takes from here |
|-------------|----------------|------------------------|
| `edc-connector/` + `edc-glcdi-extension/` | EDC connector runtime + GLCDI-specific extensions | Custom policy function extension (Phase 3) |
| `authority-services/` (formerly `governance-services/`) | Authority Keycloak + onboarding portal | Realm roles, protocol mappers, connector service-account clients (Phase 2) |
| `participant-agent-services/` | Per-participant Docker Compose stack | Policy-aware seeding scripts + Bruno test collection (Phase 4) |
| `participant-ui/` | Catalogue UI image | Catalogue UI configuration + policy-aware components |

## Contents

Grouped by intent.

**Start here.**

| Doc | For |
|-----|-----|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Head document for the "Data Space Architecture Design" deliverable - topology, components, data flows, standards, tiering, enforcement boundary. **Read this first.** |
| [`strategy/authority.md`](strategy/authority.md) | Proposed responsibilities, composition, and operating mode of the Dataspace Authority (for the body to review and ratify). |
| [`strategy/open-questions.md`](strategy/open-questions.md) | Decisions pending — cutover date, cohort composition, vocabulary + framework ratifications. |
| [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) | Phased implementation plan - the master backlog. Current status per phase in the TL;DR. |

**Reference (as-designed).**

| Doc | Covers |
|-----|--------|
| [`reference/identity.md`](reference/identity.md) | Identity architecture, tiering rationale, claim model, OIDC-vs-OID4VC-vs-VC decision. |
| [`reference/authentication.md`](reference/authentication.md) | Per-tier authentication roadmap. |
| [`strategy/standards.md`](strategy/standards.md) | Full traceability from GLCDI mechanisms to public specifications (ODRL, DSP, DCAT, JSON-LD, OIDC, VC). |
| [`reference/policies/`](reference/policies/) | ODRL policy templates (access, contract, combined scenarios) + PlantUML sequence diagrams. |
| [`reference/assets/workshop-inputs-2026.md`](reference/assets/workshop-inputs-2026.md) | Frozen workshop-phase participant policy inputs (Jan–Sep 2026). |

**Design proposals (under review, not yet as-built).**

| Doc | Covers |
|-----|--------|
| [`design/payment-gating.md`](design/payment-gating.md) | Payment-required contract policy - connector extension, storage model, governance carve-outs. |

**Build.**

| Path | For |
|------|-----|
| [`scripts/`](scripts/) | Local-stack orchestrator (`glcdi.sh`) + deploy helpers. |
| [`bruno/`](bruno/) | HTTP test collection driving the M1 scenario end-to-end. |

**Operate.**

| Doc | For |
|-----|-----|
| [`ops/deployment.md`](ops/deployment.md) | Deployment runbook + local end-to-end validation (with the `glcdi.sh` fast-path). |
| [`ops/authority-migration.md`](ops/authority-migration.md) | Operator checklist for the in-flight `governance-*` → `authority-*` rename + Tier-1 cutover. |
| [`ops/staging-wipe.md`](ops/staging-wipe.md) | Staging-participant full-reset runbook. |
| [`ops/demo-vm.md`](ops/demo-vm.md) | Plan for the co-located demo staging VM. |

**Meta.**

| Doc | For |
|-----|-----|
| [`AGENTS.md`](AGENTS.md) | Context file for AI agents working in this directory. |
| [`presentations/`](presentations/) | Slide decks (reveal.js) generated from these docs. |

---

## Architecture at a glance

GLCDI runs on a **one Authority + N participants** topology: the Authority publishes governance (identity, roles, membership) and hosts onboarding; each participant deploys the same self-contained Compose stack and exposes its datasets to peers over the Dataspace Protocol (DSP). Identity ships in tiers - the M1 prototype uses `X-Api-Key` at the UI edge and an Authority-signed JWT on the DSP edge; per-user OIDC (Tier 2) and Verifiable Credentials via DCP (Tier 3) are deliberately deferred.

The full architecture - topology diagram, per-component role, data-flow walkthrough, interoperability standards, tier evolution, deployment layout - lives in **[`ARCHITECTURE.md`](ARCHITECTURE.md)**. Read that first; the rest of this README covers the governance and enforcement model that sits on top of it.

---

## Governance Model (Proposal)

The governance model described below is put forward as a proposal for the Dataspace Authority and wider project team to validate and refine. Nothing here is a decided commitment.

### Trust Framework

GLCDI is proposed to be a multi-stakeholder data space built on **consent-governed, permissioned data sharing**.
Participants would retain ownership and control over their data. The proposed governance model is structured
around:

- **Membership** - the proposal is that participants are onboarded through a formal process (application, review by a governance body, signed MOU/Data Sharing Agreement).
- **Roles** - each participant would have a declared type (producer, researcher, data steward, etc.) that determines what data they can discover and under what terms.
- **Policies** - ODRL-based rules attached to data assets that enforce access control and usage conditions at the technical level.
- **Trust Framework** - a living document (proposed v0 in Q1 2026, v1 in Q2) that would codify the governance norms, templates, and compliance expectations.

### Governance Bodies (Proposed)

| Body | Proposed role | Proposed cadence |
|------|---------------|------------------|
| **Project Team** | Technical implementation, infrastructure, standards | Ongoing |
| **Dataspace Authority** | Governance decisions, participant approval, Trust Framework review | To be agreed - indicative monthly |
| **Cohort participants** | Data sharing, feedback, co-design | Per cohort phase |

A standalone proposal for the Dataspace Authority's responsibilities, composition, operating mode, and explicit out-of-scope items lives in [`strategy/authority.md`](strategy/authority.md) - to be reviewed, amended, and ratified by the body itself once seated. The name "Dataspace Authority" is a working label; alternatives (Council, Committee, Trust Body) are on the table and discussed in that document.

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

Identity management, authentication, the GLCDI claim model (realm roles, certification status, membership), the OIDC-vs-OID4VC rationale, the proposed onboarding flow, the identity standards mapping, and the migration path to Verifiable Credentials all live in a dedicated document: [`reference/identity.md`](reference/identity.md).

At a glance:
- **Tiered rollout** - Tier 1 (M1 default) is a single Authority Keycloak with one `client_credentials` service-account client per connector; the Catalogue UI uses `X-Api-Key` only. Tier 2 (post-M1) adds per-user OIDC at the UI. Tier 3 migrates connector identity to Verifiable Credentials via DCP. See [`IMPLEM_PLAN.md` § Identity Tiering Strategy](IMPLEM_PLAN.md#identity-tiering-strategy) for the full argument.
- **GLCDI token claims** on connector service-account tokens: `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`, `glcdi_contribution_status`, `glcdi_organisation` - consumed by EDC policy functions.
- **OIDC for the prototype**; Verifiable Credentials / OID4VC considered but deliberately deferred to Tier 3 - see [`reference/identity.md`](reference/identity.md).

---

## Data Exchange & Policy Enforcement

Policies (access, contract, combined scenarios), the DSP data-exchange flow, and the sequence diagrams walking through each scenario are documented in [`reference/policies/README.md`](reference/policies/README.md) and [`reference/policies/diagrams/`](reference/policies/diagrams/). See also [`reference/policies/plan.md`](reference/policies/plan.md) for the proposed rollout across cohorts.

---

## Technical vs. Governance Enforcement

Not all policy obligations can be technically enforced by the connector. This table clarifies
the enforcement boundary:

| Mechanism | Enforced by | Examples |
|-----------|------------|---------|
| **Access policy filtering** | EDC connector (automatic) | Hiding offers from non-researchers, non-members |
| **Contract constraint evaluation** | EDC connector (at negotiation) | Purpose check, temporal check |
| **Payment status recording & transfer gating** | Connector extension (v0 request filter on transfer initiation; v1 ODRL constraint functions) + external billing/payment system + v2 scheduled DSP termination of overdue agreements | `payment-required` policy. Design: [`design/payment-gating.md`](design/payment-gating.md). Sequence: [`reference/policies/diagrams/09-payment-gated-data-exchange.puml`](reference/policies/diagrams/09-payment-gated-data-exchange.puml) |
| **Refund obligation (recording vs. execution)** | Recording: connector (clause is part of the immutable DSP agreement; audit endpoints expose it). Adjudication: Dataspace Authority. Execution: external billing/payment system | Refund clause in `payment-required` agreement; see [`design/payment-gating.md` § 3.3](design/payment-gating.md) |
| **Anonymisation** | Data Sharing Agreement (legal) | Anonymisation obligation |
| **Attribution** | Data Sharing Agreement (legal) | Citation duty |
| **Data deletion** | Data Sharing Agreement (legal) | Retention limit obligation |
| **Non-redistribution** | Data Sharing Agreement (legal) | Internal-use-only prohibition |

The **Trust Framework** bridges this gap: it documents the governance-level obligations,
how compliance is verified (self-attestation, audit, review), and what happens on breach.

---

## Trust & Control Mechanisms - Specification Mapping

The standards-mapping reference (ODRL, DSP, DCAT, JSON-LD, identity standards) has moved to [`strategy/standards.md`](strategy/standards.md) - with identity-specific standards detailed in [`reference/identity.md`](reference/identity.md).

---

## Implementation Status & Roadmap

See [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) for the full seven-phase implementation plan and current status. Cohort-level policy rollout sequencing lives in [`reference/policies/plan.md`](reference/policies/plan.md).
