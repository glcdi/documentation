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

### Why OpenID Connect (and not OID4VC / Verifiable Credentials)

The GLCDI prototype uses **OpenID Connect (OIDC)** with Keycloak for identity management
rather than the newer OID4VC (OpenID for Verifiable Credentials) stack. This is a deliberate
choice, not a shortcut. This section explains the reasoning.

#### What is OIDC?

[OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) is an
identity layer on top of OAuth 2.0. It lets a client application verify a user's identity
based on authentication performed by an authorisation server, and obtain basic profile
information in an interoperable way. It is the most widely deployed federated identity
standard on the web.

In GLCDI, OIDC is used at two levels:
1. **Participant-to-governance federation** — each participant's Keycloak authenticates
   users locally and brokers to the governance Keycloak via OIDC
2. **Connector-to-connector authorisation** — EDC connectors present OIDC tokens during
   DSP interactions; the provider's connector extracts claims to evaluate policies

#### What is OID4VC?

The OID4VC family is a set of newer specifications building on OIDC to support
**Verifiable Credentials (VCs)** and **Decentralised Identifiers (DIDs)**:

| Specification | Purpose | Status (as of March 2026) |
|---------------|---------|--------------------------|
| [OID4VCI](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html) (OpenID for Verifiable Credential Issuance) | How an issuer delivers a VC to a holder's wallet | Implementer's Draft. Active development, not yet a final standard. |
| [OID4VP](https://openid.net/specs/openid-4-verifiable-presentations-1_0.html) (OpenID for Verifiable Presentations) | How a holder presents a VC to a verifier | Implementer's Draft. Several interop profiles exist but no convergence yet. |
| [SIOPv2](https://openid.net/specs/openid-connect-self-issued-v2-1_0.html) (Self-Issued OpenID Provider v2) | Holder acts as their own OIDC provider using a DID | Implementer's Draft. Minimal production adoption. |
| [W3C DID Core 1.0](https://www.w3.org/TR/did-core/) | Decentralised Identifiers | W3C Recommendation, but the DID method ecosystem is fragmented (`did:web`, `did:key`, `did:ion`, etc.). |
| [W3C VC Data Model 2.0](https://www.w3.org/TR/vc-data-model-2.0/) | Verifiable Credentials structure | W3C Recommendation. The data model is stable, but the encoding (JSON-LD vs JWT-VC vs SD-JWT-VC) and trust frameworks around it are not settled. |

#### Why OIDC is the right choice for the GLCDI prototype

**1. Production maturity**

OIDC has been a final specification since 2014. Every major identity provider implements it
(Keycloak, Auth0, Azure AD, Okta, Google). Libraries exist for every language. Debugging tools
are abundant. The failure modes are well-understood.

OID4VC, by contrast, is still in Implementer's Draft status. The specifications are actively
changing. Breaking changes between drafts are common. The number of production deployments
is extremely limited — mostly pilot projects and government-backed identity wallets (EUDIW)
that are not yet generally available.

**2. Wallet ecosystem is not ready**

OID4VC assumes participants have a **credential wallet** — an application that holds VCs and
can present them on demand. As of early 2026:
- There is no dominant open-source wallet with production-grade stability
- Wallet interoperability (accepting VCs from different issuers, in different formats) is
  still being tested in interop events, not in production
- GLCDI participants (ranchers, small research NGOs) do not have organisational wallets
  and cannot be expected to set one up for a 9-month prototype

**3. Credential format fragmentation**

The VC ecosystem has not converged on a single credential format:
- **JSON-LD VCs** (W3C VC Data Model with JSON-LD proofs)
- **JWT-VC** (VC wrapped in a JWT, used by Microsoft Entra Verified ID)
- **SD-JWT-VC** (Selective Disclosure JWT, gaining traction in EUDIW/HAIP)
- **mdoc/mDL** (ISO 18013-5, used for mobile driving licenses)

EDC itself is navigating this fragmentation. The EDC Identity Hub supports `did:web` and
JWT-based VCs, but the integration points with OID4VCI/OID4VP are experimental and evolving
with each EDC release. Building on this moving target for a prototype with a fixed deadline
(September 2026) would introduce significant delivery risk.

**4. Trust anchors are undefined for agriculture**

OID4VC works best when there is a **trust framework** that defines who can issue credentials,
what credentials mean, and how verifiers should evaluate them. In the European context,
this is being built by eIDAS 2.0 and the EU Digital Identity Wallet Architecture (ARF).
In the U.S. agricultural context, no such framework exists. There is no recognised authority
that would issue a "regenerative-verified producer" credential that other participants would
trust. GLCDI would have to build this from scratch — which is a governance problem, not a
technology problem.

With OIDC + Keycloak, the **governance Keycloak is the trust anchor**. The Steering Committee
approves participants; the governance admin assigns roles. This is simple, auditable, and
sufficient for 3–10 participants.

**5. OIDC gives us everything we need now**

For the GLCDI prototype, the identity requirements are:
- Authenticate participants (**OIDC** does this)
- Carry participant type and membership status in tokens (**OIDC claims** do this)
- Evaluate claims in EDC policy functions (**JWT extraction** does this)
- Federate identity across participant Keycloaks (**OIDC identity brokering** does this)

There is no functional requirement that OIDC cannot satisfy for the prototype scope.

#### Migration path to OID4VC

The OIDC-first approach does not close the door on VCs. The architecture is designed for
incremental migration:

```
Prototype (2026)                    Post-Prototype (2027+)
────────────────                    ──────────────────────
Keycloak realm roles          →     VCs issued by governance authority
OIDC claims in JWT            →     VP tokens (OID4VP)
Governance Keycloak as        →     DID-based trust anchors +
  trust anchor                        Gaia-X Compliance Service
EDC IdentityService reads     →     EDC Identity Hub resolves
  OIDC tokens                         VCs from participant wallets
```

The policy definitions in `policies/` are **already expressed in ODRL**, which is
credential-format agnostic. The `leftOperand` values (`glcdi:membership`,
`glcdi:participantType`) will remain the same whether the claim comes from a JWT issued
by Keycloak or from a VC issued by a future GLCDI credential authority. Only the
**policy function implementation** (how the claim is extracted from the identity) needs to
change — the policy definitions themselves do not.

#### References

| Specification | URL |
|---------------|-----|
| OpenID Connect Core 1.0 | https://openid.net/specs/openid-connect-core-1_0.html |
| OAuth 2.0 (RFC 6749) | https://datatracker.ietf.org/doc/html/rfc6749 |
| JWT (RFC 7519) | https://datatracker.ietf.org/doc/html/rfc7519 |
| OID4VCI (Implementer's Draft) | https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html |
| OID4VP (Implementer's Draft) | https://openid.net/specs/openid-4-verifiable-presentations-1_0.html |
| SIOPv2 (Implementer's Draft) | https://openid.net/specs/openid-connect-self-issued-v2-1_0.html |
| W3C DID Core 1.0 | https://www.w3.org/TR/did-core/ |
| W3C VC Data Model 2.0 | https://www.w3.org/TR/vc-data-model-2.0/ |
| HAIP (High Assurance Interoperability Profile) | https://openid.net/specs/openid4vc-high-assurance-interoperability-profile-1_0.html |
| Gaia-X Trust Framework | https://docs.gaia-x.eu/policy-rules-committee/trust-framework/ |
| EDC Identity Hub | https://github.com/eclipse-edc/IdentityHub |

### Annex: Participant Identity Stack Comparison

This table compares the identity stack options available for dataspace participants,
from the simplest (what GLCDI uses now) to the most decentralised (future target).

| | **OIDC + Keycloak** (current) | **OIDC + VCs (hybrid)** | **Full OID4VC + DID** |
|---|---|---|---|
| **Identity provider** | Keycloak (centralised) | Keycloak issues VCs via OID4VCI | Participant's own DID + wallet |
| **Credential format** | JWT access token with custom claims | JWT-VC or SD-JWT-VC | VC (format varies by ecosystem) |
| **Trust anchor** | Governance Keycloak (Steering Committee assigns roles) | Governance authority issues VCs (Keycloak acts as issuer) | Gaia-X Compliance Service or Trust List |
| **How provider verifies consumer** | Extract claims from OIDC token | Verify VC signature + extract claims | Resolve DID → verify VP → extract claims |
| **Participant requirement** | Keycloak account | Keycloak account + VC in wallet | DID + wallet + VCs from trusted issuer |
| **Onboarding complexity** | Low: create user, assign roles | Medium: create user, issue VC, participant stores in wallet | High: participant creates DID, requests VCs, configures wallet |
| **Revocation** | Immediate: remove role in Keycloak | VC revocation list (latency) | VC revocation list or status list |
| **Offline verification** | No (requires Keycloak to be reachable) | Partial (VC signature can be verified offline, revocation check needs network) | Yes (VC + DID resolution can be cached) |
| **EDC support** | Mature (OIDC extension) | Experimental (Identity Hub + OID4VP) | Experimental, evolving per release |
| **Maturity for production** | Production-ready | Early adopter (pilots) | R&D / pilot only |
| **Best for** | Prototype with 3–10 managed participants | Transition phase, when wallet infra stabilises | Scaled dataspace with 50+ autonomous participants |

**GLCDI recommendation:** Start in the left column. Move to the middle column when the
EDC Identity Hub stabilises and a GLCDI credential schema is defined (post-prototype).
The right column is a long-term target aligned with Gaia-X and DSBA interoperability goals.

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

## Trust & Control Mechanisms — Specification Mapping

Each trust and control mechanism used in the GLCDI dataspace is backed by one or more
open specifications. This section maps **what the dataspace does** to **which standard
enables it**, providing traceability from governance intent to technical implementation.

### Data Consent & Usage Control

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Policy expression** | Encodes access rules, usage constraints, obligations, prohibitions as machine-readable policies | [ODRL 2.2](https://www.w3.org/TR/odrl-model/) (W3C Recommendation) | All policy JSON files in `policies/`. ODRL `Permission`, `Prohibition`, `Obligation` structures express what is allowed, forbidden, or required. |
| **Purpose constraint** | Consumer declares intended purpose; provider checks it against allowed purposes | [ODRL 2.2 — `odrl:purpose`](https://www.w3.org/TR/odrl-vocab/#term-purpose) | `purpose-model-training.json`, `internal-use-only.json`, `non-commercial.json`. Consumer includes purpose in contract offer; EDC evaluates at negotiation time. |
| **Temporal constraint** | Usage permitted only within a time window | [ODRL 2.2 — `odrl:dateTime`](https://www.w3.org/TR/odrl-vocab/#term-dateTime) | `time-limited.json`. Native EDC support — evaluated at negotiation and transfer time. |
| **Duration / retention constraint** | Data must be deleted after an elapsed period | [ODRL 2.2 — `odrl:elapsedTime`](https://www.w3.org/TR/odrl-vocab/#term-elapsedTime) | `data-retention-limit.json`. Requires custom policy function (ISO 8601 duration from transfer date). |
| **Duty (obligation)** | Consumer must perform an action (anonymise, attribute, delete, inform) | [ODRL 2.2 — `odrl:duty`](https://www.w3.org/TR/odrl-model/#rule-duty) | `anonymisation.json`, `attribution.json`, `data-retention-limit.json`. Governance-level enforcement via DSA. |
| **Prohibition** | Consumer must NOT perform an action (redistribute, commercialise) | [ODRL 2.2 — `odrl:prohibition`](https://www.w3.org/TR/odrl-model/#rule-prohibition) | `internal-use-only.json`, `non-commercial.json`. Contractual enforcement. |
| **Compensation / payment** | Access requires financial payment | [ODRL 2.2 — `odrl:compensate`](https://www.w3.org/TR/odrl-vocab/#term-compensate) | `payment-required.json`. ODRL defines the vocabulary; requires external payment system + custom policy function. |

### Identity, Authentication & Role-Based Access

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Federated authentication** | Participants authenticate at their local IdP, brokered to central governance | [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) | Keycloak-to-Keycloak identity brokering. Governance Keycloak is an OIDC Relying Party for each participant's Keycloak (OIDC Provider). |
| **Token-based authorisation** | Identity claims carried in signed tokens, evaluated by provider's connector | [OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749) + [JWT (RFC 7519)](https://datatracker.ietf.org/doc/html/rfc7519) | Access tokens contain `glcdi_roles`, `glcdi_membership`, `glcdi_certification_status` claims. EDC policy functions extract and evaluate them. |
| **Role-based access control** | Participant type (producer, researcher, corporate) determines catalog visibility | [OIDC Claims](https://openid.net/specs/openid-connect-core-1_0.html#Claims) via Keycloak realm roles | `members-only.json`, `researchers-only.json`, `organic-producers.json`. Roles serialised as OIDC claims in JWT. |
| **Decentralised identity** (future) | Participants identified by DIDs, claims carried in Verifiable Credentials | [W3C DID Core 1.0](https://www.w3.org/TR/did-core/) + [W3C VC Data Model 2.0](https://www.w3.org/TR/vc-data-model-2.0/) | Post-prototype. Currently `did:web:<participant>.glcdi.startinblox.com` is configured in EDC but VCs are not yet issued. |
| **Gaia-X compliance** (future) | Self-descriptions, trust anchors, credential issuance aligned with Gaia-X | [Gaia-X Trust Framework](https://docs.gaia-x.eu/policy-rules-committee/trust-framework/) | Post-prototype. GLCDI architecture is designed to be Gaia-X-compatible (Self-Descriptions, Federated Catalogue, Compliance Service). |

### Catalog Discovery & Contract Negotiation

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Catalog protocol** | Consumer queries provider's catalog; provider filters offers based on access policies | [Dataspace Protocol (DSP) — Catalog](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/catalog) (IDSA) | EDC implements DSP. Catalog queries carry the consumer's identity; the provider's connector evaluates access policies per-asset. |
| **Contract negotiation** | Consumer and provider agree on usage terms via a state machine | [DSP — Contract Negotiation](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/contract-negotiation) | EDC handles the negotiation state machine (REQUESTED → OFFERED → AGREED → VERIFIED → FINALIZED or TERMINATED). Contract policies are evaluated at the REQUESTED/OFFERED transition. |
| **Data transfer** | Data payload delivered after contract agreement | [DSP — Transfer Process](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/transfer-process) | EDC HTTP data plane. Transfer only proceeds if a valid contract agreement exists. |
| **Asset description** | Rich metadata on shared datasets (keywords, spatial, temporal, format) | [DCAT 3](https://www.w3.org/TR/vocab-dcat-3/) (W3C) + [Dublin Core Terms](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/) | Seeding scripts attach `dcat:keyword`, `dcterms:description`, `dcterms:temporal`, content type. Used for catalog search and discovery. |

### Data Sovereignty & Consent

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Data sovereignty by design** | Data never leaves the provider without an explicit contract agreement | DSP + EDC architecture | No "open API" — every data transfer requires catalog query → negotiation → agreement → transfer. The provider's connector is the gatekeeper. |
| **Consent-as-policy** | Producer's consent is encoded as ODRL policies attached to their assets | ODRL 2.2 | A producer publishes an asset with specific policies. Changing or removing the policy effectively revokes consent for new contracts. |
| **Consent revocation** | Producer can stop sharing at any time by removing the contract definition or updating the access policy | EDC Management API + ODRL | Existing contracts remain valid (data already transferred), but no new negotiations can succeed. Time-limited policies provide natural expiry. |
| **Selective disclosure** | Different consumers see different assets depending on their role | ODRL constraints + DSP catalog filtering | A single provider can publish the same dataset with multiple contract definitions, each targeting different audiences with different terms. |
| **Non-extractive data sharing** | Data is shared for specific purposes, not bulk-harvested | ODRL purpose constraints + prohibitions | Purpose-limited policies (`purpose-model-training.json`) + redistribution prohibitions (`internal-use-only.json`) ensure data is used as intended. |

### Semantic Interoperability

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Linked data context** | Policies and assets use shared vocabularies with unambiguous URIs | [JSON-LD 1.1](https://www.w3.org/TR/json-ld11/) (W3C) | All policy files use `@context` with `odrl:`, `edc:`, `glcdi:` prefixes. Asset metadata uses `dcat:`, `dcterms:`. |
| **Policy vocabulary** | Standardised terms for actions, constraints, duties | [ODRL Vocabulary & Expression 2.2](https://www.w3.org/TR/odrl-vocab/) | Actions: `use`, `distribute`, `derive`, `commercialize`, `anonymize`, `attribute`, `compensate`, `delete`, `inform`. |
| **Custom namespace** | GLCDI-specific terms not covered by ODRL | JSON-LD `@context` extension | `https://w3id.org/glcdi/v0.1.0/ns/` — defines `membership`, `participantType`, `certificationStatus`, purpose values. |

### Summary: Specification Stack

```
┌─────────────────────────────────────────────────────────┐
│                    Governance Layer                       │
│  Trust Framework · Data Sharing Agreements · MOU          │
│  (enforcement: legal/contractual)                         │
├─────────────────────────────────────────────────────────┤
│                    Policy Layer                           │
│  ODRL 2.2 — permissions, prohibitions, obligations        │
│  (enforcement: EDC connector at negotiation time)         │
├─────────────────────────────────────────────────────────┤
│                    Protocol Layer                         │
│  Dataspace Protocol (DSP) — catalog, negotiation,         │
│  transfer state machines                                  │
│  (enforcement: EDC runtime)                               │
├─────────────────────────────────────────────────────────┤
│                    Identity Layer                         │
│  OIDC / OAuth 2.0 / JWT  (prototype)                      │
│  DID + Verifiable Credentials  (post-prototype)           │
│  (enforcement: Keycloak + EDC identity service)           │
├─────────────────────────────────────────────────────────┤
│                    Semantic Layer                         │
│  JSON-LD · DCAT 3 · Dublin Core · ODRL Vocabulary         │
│  GLCDI namespace (https://w3id.org/glcdi/v0.1.0/ns/)     │
│  (enforcement: shared understanding between connectors)   │
└─────────────────────────────────────────────────────────┘
```

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
