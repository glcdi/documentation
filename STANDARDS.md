# GLCDI Trust & Control Mechanisms — Specification Mapping

Each trust and control mechanism used in the GLCDI dataspace is backed by one or more
open specifications. This document maps **what the dataspace does** to **which standard
enables it**, providing traceability from governance intent to technical implementation.

Identity and authentication standards (OIDC, OAuth 2.0 / JWT, DID / VC, Gaia-X) are covered separately in [`IDENTITY.md`](IDENTITY.md). This document covers the policy, protocol, sovereignty, and semantic layers.

## Data Consent & Usage Control

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Policy expression** | Encodes access rules, usage constraints, obligations, prohibitions as machine-readable policies | [ODRL 2.2](https://www.w3.org/TR/odrl-model/) (W3C Recommendation) | All policy JSON files in `policies/`. ODRL `Permission`, `Prohibition`, `Obligation` structures express what is allowed, forbidden, or required. |
| **Purpose constraint** | Consumer declares intended purpose; provider checks it against allowed purposes | [ODRL 2.2 — `odrl:purpose`](https://www.w3.org/TR/odrl-vocab/#term-purpose) | `purpose-model-training.json`, `internal-use-only.json`, `non-commercial.json`. Consumer includes purpose in contract offer; EDC evaluates at negotiation time. |
| **Temporal constraint** | Usage permitted only within a time window | [ODRL 2.2 — `odrl:dateTime`](https://www.w3.org/TR/odrl-vocab/#term-dateTime) | `time-limited.json`. Native EDC support — evaluated at negotiation and transfer time. |
| **Duration / retention constraint** | Data must be deleted after an elapsed period | [ODRL 2.2 — `odrl:elapsedTime`](https://www.w3.org/TR/odrl-vocab/#term-elapsedTime) | `data-retention-limit.json`. Requires custom policy function (ISO 8601 duration from transfer date). |
| **Duty (obligation)** | Consumer must perform an action (anonymise, attribute, delete, inform) | [ODRL 2.2 — `odrl:duty`](https://www.w3.org/TR/odrl-model/#rule-duty) | `anonymisation.json`, `attribution.json`, `data-retention-limit.json`. Governance-level enforcement via DSA. |
| **Prohibition** | Consumer must NOT perform an action (redistribute, commercialise) | [ODRL 2.2 — `odrl:prohibition`](https://www.w3.org/TR/odrl-model/#rule-prohibition) | `internal-use-only.json`, `non-commercial.json`. Contractual enforcement. |
| **Compensation / payment** | Access requires financial payment; the connector tracks payment status, gates transfer until paid, records the refund obligation on the agreement, and (v2) terminates overdue agreements via DSP `ContractNegotiationTermination` | [ODRL 2.2 — `odrl:compensate`](https://www.w3.org/TR/odrl-vocab/#term-compensate), [`odrl:pay`](https://www.w3.org/TR/odrl-vocab/#term-pay), [`odrl:payAmount`](https://www.w3.org/TR/odrl-vocab/#term-payAmount), [`odrl:invalidate`](https://www.w3.org/TR/odrl-vocab/#term-invalidate) | `payment-required.json`; design: [`PAYMENT_GATING.md`](PAYMENT_GATING.md); sequence: [`policies/diagrams/09-payment-gated-data-exchange.puml`](policies/diagrams/09-payment-gated-data-exchange.puml) |

## Identity, Authentication & Role-Based Access

Covered in [`IDENTITY.md` § Identity Standards Mapping](IDENTITY.md#identity-standards-mapping): OIDC federation, OAuth 2.0 / JWT token-based authorisation, realm-role-to-claim RBAC, and the future DID / Verifiable Credentials / Gaia-X targets.

## Catalog Discovery & Contract Negotiation

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Catalog protocol** | Consumer queries provider's catalog; provider filters offers based on access policies | [Dataspace Protocol (DSP) — Catalog](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/catalog) (IDSA) | EDC implements DSP. Catalog queries carry the consumer's identity; the provider's connector evaluates access policies per-asset. |
| **Contract negotiation** | Consumer and provider agree on usage terms via a state machine | [DSP — Contract Negotiation](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/contract-negotiation) | EDC handles the negotiation state machine (REQUESTED → OFFERED → AGREED → VERIFIED → FINALIZED or TERMINATED). Contract policies are evaluated at the REQUESTED/OFFERED transition. |
| **Data transfer** | Data payload delivered after contract agreement | [DSP — Transfer Process](https://docs.internationaldataspaces.org/ids-knowledgebase/dataspace-protocol/transfer-process) | EDC HTTP data plane. Transfer only proceeds if a valid contract agreement exists. |
| **Asset description** | Rich metadata on shared datasets (keywords, spatial, temporal, format) | [DCAT 3](https://www.w3.org/TR/vocab-dcat-3/) (W3C) + [Dublin Core Terms](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/) | Seeding scripts attach `dcat:keyword`, `dcterms:description`, `dcterms:temporal`, content type. Used for catalog search and discovery. |

## Data Sovereignty & Consent

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Data sovereignty by design** | Data never leaves the provider without an explicit contract agreement | DSP + EDC architecture | No "open API" — every data transfer requires catalog query → negotiation → agreement → transfer. The provider's connector is the gatekeeper. |
| **Consent-as-policy** | Producer's consent is encoded as ODRL policies attached to their assets | ODRL 2.2 | A producer publishes an asset with specific policies. Changing or removing the policy effectively revokes consent for new contracts. |
| **Consent revocation** | Producer can stop sharing at any time by removing the contract definition or updating the access policy | EDC Management API + ODRL | Existing contracts remain valid (data already transferred), but no new negotiations can succeed. Time-limited policies provide natural expiry. |
| **Selective disclosure** | Different consumers see different assets depending on their role | ODRL constraints + DSP catalog filtering | A single provider can publish the same dataset with multiple contract definitions, each targeting different audiences with different terms. |
| **Non-extractive data sharing** | Data is shared for specific purposes, not bulk-harvested | ODRL purpose constraints + prohibitions | Purpose-limited policies (`purpose-model-training.json`) + redistribution prohibitions (`internal-use-only.json`) ensure data is used as intended. |

## Semantic Interoperability

| Mechanism | What it does in GLCDI | Specification | How it's used |
|-----------|----------------------|---------------|---------------|
| **Linked data context** | Policies and assets use shared vocabularies with unambiguous URIs | [JSON-LD 1.1](https://www.w3.org/TR/json-ld11/) (W3C) | All policy files use `@context` with `odrl:`, `edc:`, `glcdi:` prefixes. Asset metadata uses `dcat:`, `dcterms:`. |
| **Policy vocabulary** | Standardised terms for actions, constraints, duties | [ODRL Vocabulary & Expression 2.2](https://www.w3.org/TR/odrl-vocab/) | Actions: `use`, `distribute`, `derive`, `commercialize`, `anonymize`, `attribute`, `compensate`, `delete`, `inform`. |
| **Custom namespace** | GLCDI-specific terms not covered by ODRL | JSON-LD `@context` extension | `https://w3id.org/glcdi/v0.1.0/ns/` — defines `membership`, `participantType`, `certificationStatus`, purpose values. |

## Summary: Specification Stack

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
│  See IDENTITY.md for details.                             │
├─────────────────────────────────────────────────────────┤
│                    Semantic Layer                         │
│  JSON-LD · DCAT 3 · Dublin Core · ODRL Vocabulary         │
│  GLCDI namespace (https://w3id.org/glcdi/v0.1.0/ns/)     │
│  (enforcement: shared understanding between connectors)   │
└─────────────────────────────────────────────────────────┘
```
