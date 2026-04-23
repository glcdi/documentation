# GLCDI Identity & Authentication

Identity management, authentication, and the technical standards the dataspace relies on for them. Consolidated here so the architecture, rationale, and standards mapping live in one place.

For the overall governance model and policy design this feeds into, see [`README.md`](README.md). For the step-by-step implementation plan (realm JSON, protocol mappers, EDC policy functions), see [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) — Phase 2 covers Keycloak claim configuration and Phase 3 covers the EDC-side claim extraction.

## Architecture

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
                        │   ├── participant-a (OIDC)    │
                        │   ├── participant-b (OIDC)    │
                        │   └── …                        │
                        └──────────┬───────────────────┘
                                   │ OIDC broker
                    ┌──────────────┼──────────────┐
                    │              │              │
          ┌─────────▼──┐  ┌───────▼────┐  ┌─────▼────────┐
          │ Participant │  │ Participant│  │ Participant  │
          │ A Keycloak  │  │ B Keycloak │  │ C Keycloak   │
          │ (edc realm) │  │ (edc realm)│  │ (edc realm)  │
          │             │  │            │  │              │
          │ Local auth  │  │ Local auth │  │ Local auth   │
          └─────────────┘  └────────────┘  └──────────────┘
```

**Flow:** A user authenticates at their participant's local Keycloak, which brokers to the
governance Keycloak via OIDC. The governance Keycloak adds GLCDI-specific claims (roles,
membership, certification) to the token. The token is then used by the EDC connector to
evaluate policies.

## Participant Identity Claims

Each participant's identity token carries three GLCDI-specific claims:

| Claim | Type | Source | Purpose |
|-------|------|--------|---------|
| `glcdi_membership` | String | Hardcoded mapper (prototype) or user attribute | Checked by all access policies — is this participant an active member? |
| `glcdi_roles` | String array | Realm role mapper (prefix `glcdi_`) | Determines participant type — producer, researcher, data steward, etc. |
| `glcdi_certification_status` | String | User attribute mapper | Regenerative certification — used by the `regenerative-producers` access policy |

## Realm Roles

| Role | Assigned to | What it unlocks |
|------|------------|-----------------|
| `glcdi_member` | All onboarded participants | Access to `members-only` offers |
| `glcdi_producer` | Ranches, farming organisations | Access to `regenerative-producers` offers (with certification), benchmarking |
| `glcdi_researcher` | Universities, research NGOs | Access to `researchers-only` offers (e.g., raw SOC data for model training) |
| `glcdi_data_steward` | Monitoring alliances | Access to `researchers-only` offers, data stewardship role |
| `glcdi_conservation_org` | Conservation organisations | General membership access |
| `glcdi_technology_provider` | Ag-tech platforms, MRV tools | General membership access |
| `glcdi_corporate` | Food companies, ESG teams | Access to `corporate-partners` offers |
| `glcdi_certification_body` | Certification/verification bodies | Access to `corporate-partners` offers |
| `glcdi_supply_chain_partner` | Procurement, Scope 3 analysts | Access to `corporate-partners` offers |
| `glcdi_funder` | Funding bodies / public sector partners | General membership access |

## Proposed Participant Role Assignments

Specific participant-to-role assignments are left to onboarding time and are proposed (not yet finalised) to follow this pattern:

| Participant type | Proposed roles | Proposed certification |
|------------------|---------------|-----------------------|
| Regenerative producer | `glcdi_member` + `glcdi_producer` | `regenerative-verified` (or equivalent) |
| Research institution | `glcdi_member` + `glcdi_researcher` | `not-applicable` |
| Data steward / monitoring alliance | `glcdi_member` + `glcdi_data_steward` | `not-applicable` |

Additional participant types (`conservation_org`, `technology_provider`, `corporate`, `certification_body`, `supply_chain_partner`, `funder`) would follow the same pattern as their declared type role is added, with certification status set to `not-applicable` unless they hold a recognised regenerative/organic credential.

## Onboarding Flow (Proposed)

This is the proposed onboarding flow, to be validated with the governance body before implementation:

```
1. Participant submits application  ──→  Onboarding app (governance-services)
2. Governance body reviews          ──→  Approval UI (proposed)
3. On approval (proposed actions):
   a. Keycloak user created/updated
   b. glcdi_member role assigned
   c. Participant type role assigned (e.g., glcdi_producer)
   d. Certification status attribute set
4. Participant receives credentials  ──→  Can authenticate and access catalog
```

---

## Identity Standards Mapping

Each identity / authentication mechanism in GLCDI is backed by one or more open specifications. This table maps **what the dataspace does** to **which standard enables it**.

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Federated authentication** | Participants authenticate at their local IdP, brokered to central governance | [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) | Keycloak-to-Keycloak identity brokering. Governance Keycloak is an OIDC Relying Party for each participant's Keycloak (OIDC Provider). |
| **Token-based authorisation** | Identity claims carried in signed tokens, evaluated by provider's connector | [OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749) + [JWT (RFC 7519)](https://datatracker.ietf.org/doc/html/rfc7519) | Access tokens contain `glcdi_roles`, `glcdi_membership`, `glcdi_certification_status` claims. EDC policy functions extract and evaluate them. |
| **Role-based access control** | Participant type (producer, researcher, corporate) determines catalog visibility | [OIDC Claims](https://openid.net/specs/openid-connect-core-1_0.html#Claims) via Keycloak realm roles | `members-only.json`, `researchers-only.json`, `regenerative-producers.json`. Roles serialised as OIDC claims in JWT. |
| **Decentralised identity** (future) | Participants identified by DIDs, claims carried in Verifiable Credentials | [W3C DID Core 1.0](https://www.w3.org/TR/did-core/) + [W3C VC Data Model 2.0](https://www.w3.org/TR/vc-data-model-2.0/) | Post-prototype. Currently `did:web:<participant>.glcdi.startinblox.com` is configured in EDC but VCs are not yet issued. |
| **Gaia-X compliance** (future) | Self-descriptions, trust anchors, credential issuance aligned with Gaia-X | [Gaia-X Trust Framework](https://docs.gaia-x.eu/policy-rules-committee/trust-framework/) | Post-prototype. GLCDI architecture is designed to be Gaia-X-compatible (Self-Descriptions, Federated Catalogue, Compliance Service). |

---

## Why OpenID Connect (and not OID4VC / Verifiable Credentials)

The GLCDI prototype uses **OpenID Connect (OIDC)** with Keycloak for identity management
rather than the newer OID4VC (OpenID for Verifiable Credentials) stack. This is a deliberate
choice, not a shortcut. This section explains the reasoning.

### What is OIDC?

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

### What is OID4VC?

The OID4VC family is a set of newer specifications building on OIDC to support
**Verifiable Credentials (VCs)** and **Decentralised Identifiers (DIDs)**:

| Specification | Purpose | Status (as of March 2026) |
|---------------|---------|--------------------------|
| [OID4VCI](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html) (OpenID for Verifiable Credential Issuance) | How an issuer delivers a VC to a holder's wallet | Implementer's Draft. Active development, not yet a final standard. |
| [OID4VP](https://openid.net/specs/openid-4-verifiable-presentations-1_0.html) (OpenID for Verifiable Presentations) | How a holder presents a VC to a verifier | Implementer's Draft. Several interop profiles exist but no convergence yet. |
| [SIOPv2](https://openid.net/specs/openid-connect-self-issued-v2-1_0.html) (Self-Issued OpenID Provider v2) | Holder acts as their own OIDC provider using a DID | Implementer's Draft. Minimal production adoption. |
| [W3C DID Core 1.0](https://www.w3.org/TR/did-core/) | Decentralised Identifiers | W3C Recommendation, but the DID method ecosystem is fragmented (`did:web`, `did:key`, `did:ion`, etc.). |
| [W3C VC Data Model 2.0](https://www.w3.org/TR/vc-data-model-2.0/) | Verifiable Credentials structure | W3C Recommendation. The data model is stable, but the encoding (JSON-LD vs JWT-VC vs SD-JWT-VC) and trust frameworks around it are not settled. |

### Why OIDC is the right choice for the GLCDI prototype

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

With OIDC + Keycloak, the proposal is that the **governance Keycloak serves as the trust anchor**. Under this proposal the Dataspace Authority would approve participants and the governance admin would assign roles — simple, auditable, and sufficient for a small participant set.

**5. OIDC gives us everything we need now**

For the GLCDI prototype, the identity requirements are:
- Authenticate participants (**OIDC** does this)
- Carry participant type and membership status in tokens (**OIDC claims** do this)
- Evaluate claims in EDC policy functions (**JWT extraction** does this)
- Federate identity across participant Keycloaks (**OIDC identity brokering** does this)

There is no functional requirement that OIDC cannot satisfy for the prototype scope.

### Migration path to OID4VC

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

### References

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

---

## Annex: Participant Identity Stack Comparison

This table compares the identity stack options available for dataspace participants,
from the simplest (what GLCDI uses now) to the most decentralised (future target).

| | **OIDC + Keycloak** (current) | **OIDC + VCs (hybrid)** | **Full OID4VC + DID** |
|---|---|---|---|
| **Identity provider** | Keycloak (centralised) | Keycloak issues VCs via OID4VCI | Participant's own DID + wallet |
| **Credential format** | JWT access token with custom claims | JWT-VC or SD-JWT-VC | VC (format varies by ecosystem) |
| **Trust anchor** | Governance Keycloak (proposed: Dataspace Authority would assign roles) | Governance authority issues VCs (Keycloak acts as issuer) | Gaia-X Compliance Service or Trust List |
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
