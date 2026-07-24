# Phase 1: GLCDI Vocabulary & Namespace

Before any policy can be evaluated, the custom terms used in constraints need to be formally
defined and resolvable.

## 1.1 Register the `glcdi:` namespace

| Item | Detail |
|------|--------|
| **Task** | Define the JSON-LD context file mapping the `glcdi:` prefix to its namespace URI and aliasing the GLCDI properties / value terms used by the policies and the EDC IAM layer |
| **Namespace URI (term identifier base)** | `https://w3id.org/glcdi/v0.1.0/ns/` (kept stable so existing inline policy `@context` blocks continue to resolve to the same term URIs) |
| **Hosted context document** | `https://cdn.startinblox.com/owl/glcdi/context.jsonld` - the canonical JSON-LD context that policies reference via `"@context": "https://cdn.startinblox.com/owl/glcdi/context.jsonld"` |
| **Source file** | [`./context.jsonld`](../../context.jsonld) - checked into this repo; deployed to the CDN URL above |
| **Content (matches `./context.jsonld`)** | Namespace prefixes (`glcdi`, `edc`, `odrl`, `dcat`, `dct`/`dcterms`, `foaf`, `xsd`, `skos`); GLCDI properties (`participantType`, `certificationStatus`, `contributionStatus`, `membership`, `organisation`, `roles`, `accessOutcome`, `shareBack`); ODRL property aliases with type coercion (`purpose`, `elapsedTime`, `payAmount`, `paymentStatus`, `dateTime`); GLCDI value terms (participant types, certification statuses, contribution statuses, purpose taxonomy, access outcomes - see § 1.2 and § 1.3 for the canonical lists) |
| **w3id.org redirect (deferred)** | Registering the `https://w3id.org/glcdi/v0.1.0/ns/` redirect via the [w3id PR process](https://github.com/perma-id/w3id.org) makes the term URIs themselves dereferenceable. Not required for EDC to function - EDC uses the URIs as identifiers, not for HTTP fetch - but a good post-prototype step for namespace stewardship. The hosted context at `cdn.startinblox.com` is sufficient for the prototype. |
| **Status** | [x] Source file generated · [ ] Deployed to CDN · [ ] Existing policies migrated to reference the hosted URL |

## 1.2 Document participant types and certification statuses

| Item | Detail |
|------|--------|
| **Task** | Propose the canonical list of `participantType` and `certificationStatus` values to the Dataspace Authority for agreement |
| **Proposed participant types** | `producer`, `researcher`, `data-steward`, `conservation-org`, `technology-provider`, `corporate`, `certification-body`, `supply-chain-partner`, `funder` |
| **Proposed certification statuses** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Deliverable** | Enumeration documented in the vocabulary context and in the Trust Framework (v0) |
| **Status** | [x] Documented as proposal (this section) · [x] Encoded in [`context.jsonld`](../../context.jsonld) value aliases · [x] Realm roles + group/user attributes for the M1 subset (`producer`, `researcher`, `data-steward`, `regenerative-verified`, `not-applicable`) declared in `authority-services/resources/keycloak/realms/glcdi-realm.json` · [ ] Ratified by the Dataspace Authority |

## 1.3 Define ODRL purpose taxonomy

| Item | Detail |
|------|--------|
| **Task** | Formalise the set of purpose values that consumers can declare in contract offers |
| **Proposed values** | `InternalAnalysis`, `ScientificResearch`, `AgronomicModelTraining`, `EcosystemModelCalibration`, `RegionalBenchmarking`, `EducationalUse`, `ConservationPlanning`, `Scope3Reporting`, `ESGCompliance`, `CertificationVerification`, `ModelOutput` |
| **Why** | Purpose constraints in policies (e.g., `purpose-model-training.json`) rely on consumers declaring a purpose from this controlled vocabulary. Without agreement on the terms, policies cannot be consistently evaluated. |
| **Status** | [x] Documented as proposal (this section) · [x] Encoded in [`context.jsonld`](../../context.jsonld) value aliases (PascalCase per JSON-LD value-class convention) · [ ] Ratified by the Dataspace Authority |

---

---

**Navigation:** [← index](../implementation-plan.md) · [next: Phase 1.5: Identity (Tier 1) - Single-tier auth + Authority cleanup →](phase-1.5-identity-tier1.md)
