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
├── AGENTS.md           # Context file for AI agents
├── TODO.md             # Implementation plan (7 phases)
└── policies/
    ├── README.md       # Policy catalogue documentation
    ├── access/         # Access policies (catalog visibility)
    ├── contract/       # Contract policies (usage terms)
    ├── combined/       # End-to-end scenario examples
    └── diagrams/       # PlantUML sequence diagrams
```

---

## Governance Model

### Trust Framework

GLCDI is a multi-stakeholder data space built on **consent-governed, permissioned data sharing**.
Participants retain ownership and control over their data. The governance model is structured
around:

- **Membership** — participants are onboarded through a formal process (application, review
  by Steering Committee, signed MOU/Data Sharing Agreement)
- **Roles** — each participant has a declared type (producer, researcher, data steward, etc.)
  that determines what data they can discover and under what terms
- **Policies** — ODRL-based rules attached to data assets that enforce access control and
  usage conditions at the technical level
- **Trust Framework** — a living document (v0 in Q1 2026, v1 in Q2) that codifies the
  governance norms, templates, and compliance expectations

### Governance Bodies

| Body | Role | Cadence |
|------|------|---------|
| **Project Team** | Technical implementation, infrastructure, standards | Ongoing |
| **Steering Committee** | Governance decisions, participant approval, Trust Framework review | Monthly |
| **Cohort participants** | Data sharing, feedback, co-design | Per cohort phase |

### Cohort Timeline

| Phase | Period | Participants | Focus |
|-------|--------|-------------|-------|
| Cohort 1 | Q1 2026 | Point Blue, Caney Fork, White Buffalo | Foundational validation, Trust Framework v0 |
| Cohort 2 | Q2 2026 | + PASA, University of Florida, TSIP | Cross-context testing, Trust Framework v1 |
| Cohort 3 | Q3 2026 | + World Wildlife Fund, The Nature Conservancy, Soil Health Institute | Institutional stress-testing |
| Post-prototype | 2027+ | + American Farmland Trust, US Roundtable for Sustainable Beef, corporates | Broader onboarding |

---

## Identity & Authentication

### Architecture

GLCDI uses a **federated identity model** with Keycloak as the identity provider at two levels:

```
                        ┌─────────────────────────────┐
                        │   Governance Keycloak        │
                        │   (glcdi realm)              │
                        │                              │
                        │   Source of truth for:        │
                        │   - GLCDI membership          │
                        │   - Participant roles          │
                        │   - Certification status       │
                        │                              │
                        │   Identity Providers:          │
                        │   ├── caney-fork (OIDC)       │
                        │   └── point-blue (OIDC)       │
                        └──────────┬───────────────────┘
                                   │ OIDC broker
                    ┌──────────────┼──────────────┐
                    │              │              │
          ┌─────────▼──┐  ┌───────▼────┐  ┌─────▼────────┐
          │ Caney Fork  │  │ Point Blue │  │ White Buffalo │
          │ Keycloak    │  │ Keycloak   │  │ Keycloak     │
          │ (edc realm) │  │ (edc realm)│  │ (edc realm)  │
          │             │  │            │  │              │
          │ Local auth  │  │ Local auth │  │ Local auth   │
          └─────────────┘  └────────────┘  └──────────────┘
```

**Flow:** A user authenticates at their participant's local Keycloak, which brokers to the
governance Keycloak via OIDC. The governance Keycloak adds GLCDI-specific claims (roles,
membership, certification) to the token. The token is then used by the EDC connector to
evaluate policies.

### Participant Identity Claims

Each participant's identity token carries three GLCDI-specific claims:

| Claim | Type | Source | Purpose |
|-------|------|--------|---------|
| `glcdi_membership` | String | Hardcoded mapper (prototype) or user attribute | Checked by all access policies — is this participant an active member? |
| `glcdi_roles` | String array | Realm role mapper (prefix `glcdi_`) | Determines participant type — producer, researcher, data steward, etc. |
| `glcdi_certification_status` | String | User attribute mapper | Organic/regenerative certification — used by the `organic-producers` access policy |

### Realm Roles

| Role | Assigned to | What it unlocks |
|------|------------|-----------------|
| `glcdi_member` | All onboarded participants | Access to `members-only` offers |
| `glcdi_producer` | Ranches, farming organisations | Access to `organic-producers` offers (with certification), benchmarking |
| `glcdi_researcher` | Universities, research NGOs | Access to `researchers-only` offers (e.g., raw SOC data for model training) |
| `glcdi_data_steward` | Monitoring alliances (Point Blue, TSIP) | Access to `researchers-only` offers, data stewardship role |
| `glcdi_conservation_org` | Conservation organisations | General membership access |
| `glcdi_technology_provider` | Ag-tech platforms, MRV tools | General membership access |
| `glcdi_corporate` | Food companies, ESG teams | Access to `corporate-partners` offers |
| `glcdi_certification_body` | Certification/verification bodies | Access to `corporate-partners` offers |
| `glcdi_supply_chain_partner` | Procurement, Scope 3 analysts | Access to `corporate-partners` offers |
| `glcdi_funder` | Walmart Foundation, USDA, NSF | General membership access |

### Prototype Participant Assignments

| Participant | Roles | Certification |
|-------------|-------|---------------|
| Caney Fork Farms | `glcdi_member` + `glcdi_producer` | `regenerative-verified` |
| Point Blue Conservation Science | `glcdi_member` + `glcdi_researcher` | `not-applicable` |
| White Buffalo Land Trust | `glcdi_member` + `glcdi_producer` | `regenerative-verified` |
| TSIP (Q2) | `glcdi_member` + `glcdi_data_steward` | `not-applicable` |
| University of Florida (Q2) | `glcdi_member` + `glcdi_researcher` | `not-applicable` |

### Onboarding Flow

```
1. Participant submits application  ──→  Onboarding app (governance-services)
2. Steering Committee reviews       ──→  Approval UI
3. On approval:
   a. Keycloak user created/updated
   b. glcdi_member role assigned
   c. Participant type role assigned (e.g., glcdi_producer)
   d. Certification status attribute set
4. Participant receives credentials  ──→  Can authenticate and access catalog
```

---

## Data Exchange & Policy Enforcement

### How Data Flows Between Participants

```
  Consumer                                                  Provider
  ────────                                                  ────────

  1. Browse catalog
     ───── DSP Catalog Query ────────────────────────────►
                                                    ┌──────────────────┐
                                                    │ ACCESS POLICY    │
                                                    │ evaluation       │
                                                    │ (per asset)      │
                                                    └───────┬──────────┘
     ◄─── Filtered catalog (only visible offers) ──────────┘

  2. Select offer, declare purpose
     ───── DSP Contract Negotiation ─────────────────────►
                                                    ┌──────────────────┐
                                                    │ CONTRACT POLICY  │
                                                    │ evaluation       │
                                                    │ (purpose, time,  │
                                                    │  obligations)    │
                                                    └───────┬──────────┘
     ◄─── Contract Agreement (FINALIZED) or TERMINATED ────┘

  3. Request data
     ───── DSP Transfer Request ─────────────────────────►
     ◄─── Data payload ─────────────────────────────────────┘

  4. Consumer fulfills obligations
     (anonymise, attribute, delete after retention period, etc.)
```

### Policy Types

Policies are documented in detail in [`policies/README.md`](policies/README.md). Summary:

#### Access Policies (catalog visibility)

| Policy | Who can see the offer | Typical use |
|--------|-----------------------|-------------|
| [`members-only`](policies/access/members-only.json) | Any active GLCDI participant | Default for most assets |
| [`organic-producers`](policies/access/organic-producers.json) | Certified organic/regenerative producers only | Sensitive competitive practices |
| [`researchers-only`](policies/access/researchers-only.json) | Researchers and data stewards only | Raw data for model training |

#### Contract Policies (usage terms)

| Policy | What it enforces | Typical use |
|--------|-----------------|-------------|
| [`time-limited`](policies/contract/time-limited.json) | Usage until a specific date | Prototype phase boundary |
| [`internal-use-only`](policies/contract/internal-use-only.json) | No redistribution | Peer sharing with trust |
| [`anonymisation`](policies/contract/anonymisation.json) | Must anonymise farm-identifiable data | Research, corporate reporting |
| [`payment-required`](policies/contract/payment-required.json) | Payment before access | Corporate consumers (post-prototype) |
| [`attribution`](policies/contract/attribution.json) | Cite provider and GLCDI | Publications, reports |
| [`non-commercial`](policies/contract/non-commercial.json) | No commercial exploitation | Protect producers from misuse |
| [`purpose-model-training`](policies/contract/purpose-model-training.json) | Model training/calibration only | Agronomic model use case |
| [`data-retention-limit`](policies/contract/data-retention-limit.json) | Delete after 12 months | Corporate, time-boxed access |

#### Combined Scenarios

End-to-end examples showing how access + contract policies compose for real use cases:

| Scenario | Access | Contract | Blueprint use case |
|----------|--------|----------|--------------------|
| [`researcher-model-feeding`](policies/combined/researcher-model-feeding.json) | researchers-only | purpose-limited + time + anonymisation + attribution | Agronomic model calibration |
| [`rancher-benchmarking`](policies/combined/rancher-benchmarking.json) | members-only | benchmarking purpose + non-commercial + attribution | Regional benchmarking |
| [`corporate-supply-chain`](policies/combined/corporate-supply-chain.json) | corporate-partners | payment + anonymisation + retention + attribution | ESG / Scope 3 reporting |

### Sequence Diagrams

Visual walk-throughs of policy enforcement from the end-user's perspective.
See [`policies/diagrams/`](policies/diagrams/) or the [diagram index in the policies README](policies/README.md#sequence-diagrams).

| Diagram | What it shows |
|---------|--------------|
| [01 — Researcher accesses SOC data](policies/diagrams/01-researcher-accesses-soc-data.puml) | Happy path: authentication → catalog → negotiation → transfer → obligations |
| [02 — Producer blocked from research data](policies/diagrams/02-producer-blocked-from-research-data.puml) | Access policy hides researcher-only assets from a producer |
| [03 — Rancher benchmarking](policies/diagrams/03-rancher-benchmarking.puml) | Two ranchers share and compare grazing data |
| [04 — Wrong purpose rejected](policies/diagrams/04-wrong-purpose-rejected.puml) | Contract negotiation fails on purpose mismatch |
| [05 — Organic producers exclusive](policies/diagrams/05-organic-producers-exclusive.puml) | Same asset, three different visibility outcomes by participant type |
| [06 — Time-limited expiry](policies/diagrams/06-time-limited-expiry.puml) | Contract works in July, fails in October, renewal flow |
| [07 — Corporate supply chain](policies/diagrams/07-corporate-supply-chain-flow.puml) | Payment, anonymisation, retention limit, deletion confirmation |

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

## Implementation Status & Roadmap

See [`TODO.md`](TODO.md) for the full implementation plan. Summary:

| Phase | Scope | Status |
|-------|-------|--------|
| 1. Vocabulary & Namespace | Define `glcdi:` JSON-LD context, agree on controlled vocabularies | Not started |
| 2. Keycloak Claims | Realm roles, protocol mappers, participant assignments | Not started |
| 3. EDC Extension | `glcdi-policy-functions` extension (membership, type, certification checks) | Not started |
| 4. Seeding Scripts | Replace open-research with per-asset policy assignments | Not started |
| 5. Testing | Unit tests, integration tests, end-to-end scenario validation | Not started |
| 6. Governance (legal) | DSA templates, audit mechanisms, consent revocation | Not started |
| 7. Future | Payment infra, Verifiable Credentials, Federated Catalogue, policy UI | Post-prototype |

Phases 1–2 can start immediately (no infrastructure dependency). Phase 3 depends on 1.
Phase 6 can proceed in parallel with all technical phases.
