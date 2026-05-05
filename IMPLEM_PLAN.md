# GLCDI Policy Support — Implementation Plan

Implementation steps to make the ODRL policies defined in `./policies/` operational in the
GLCDI dataspace. This covers vocabulary registration, Keycloak configuration, EDC extension
development, integration into seeding scripts, and testing.

Phases are ordered by dependency. Steps within a phase can largely be parallelised.

## TL;DR

GLCDI's path from today's single open-research policy to a fully enforced ODRL policy stack runs through eight phases plus a milestone gate.

**Delivery order:**

1. **Phase 1 — Vocabulary & Namespace.** Register `glcdi:` JSON-LD context; agree on participant-type, certification-status, purpose taxonomies. Foundational; blocks Phase 3.
2. **Phase 1.5 — Authority cleanup + identity simplification.** Complete the governance→authority rename (per [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md)); remove per-participant Keycloak from the participant compose stack; switch management-API auth to `X-Api-Key` only; create operator users `caney-fork`, `point-blue`, `white-buffalo` directly in the Authority Keycloak. A read-only spike confirmed feasibility — see § Phase 1.5.
3. **Phase 2 — Keycloak claims.** Realm roles, user attributes, protocol mappers so consumer tokens carry `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`, `glcdi_contribution_status`. Now sourced from the Authority Keycloak only.
4. **Phase 3 — EDC policy functions.** Custom `AtomicConstraintFunction`s reading the claims above. ~200 LOC.
5. **Phase 4 — Seeding scripts.** Replace the current single `glcdi:policy:open-research` with per-asset access + contract policies — scoped initially to the M1 scenario.
6. **Phase 4.5 — Bruno test suite + Participant-UI configuration (parallel tracks).** (E) Bruno collection executing the M1 scenario non-interactively against the management API; (F) audit/adapt `participant-ui` for API-key login and the asset/policy/contract/history components. Both run in parallel agents and feed Phase 5.
7. **Phase 5 — Integration testing.** Anchored on the M1 scenario: regenerative-producers-only access policy + internal-use-only contract policy, full positive and negative paths.
8. 🚦 **Milestone M1 — Regenerative-only access + internal-use-only contract, end-to-end demonstrable.** Gate before payment work starts.
9. **Phase 6 — Governance-level enforcement (proposal).** DSA clause wording, audit mechanism, consent-revocation procedure. Runs in parallel with the technical phases; ratification by the Dataspace Authority (see [`AUTHORITY.md`](AUTHORITY.md)).
10. **Phase 7.1 — Payment-required workflow.** v0/v1/v2 substages per [`PAYMENT_GATING.md`](PAYMENT_GATING.md). **Starts after M1 is signed off** — not before.
11. **Phase 7.2–7.4 — Other future enhancements.** VC integration, Federated Catalogue policy metadata, participant-facing policy UI.

**Status:** Phases 1, 1.5, 2–5, 4.5, M1 are "not started" as of the current cohort. Phase 7 starts post-M1.

**Parallelisation:** up to **3 concurrent agents** at peak — main implementation track (1.5 → 2 → 3 → 4 → 5 → M1 → 7.1), Bruno track (4.5 E), Participant-UI track (4.5 F). Phase 6 also runs in parallel with the technical phases.

**Dependency highlights:** Phase 1.5 (identity simplification) blocks Phase 2 (claims now live only in the Authority KC). Phase 3 depends on Phase 1's vocabulary. Phase 4 depends on Phases 2–3. Phase 4.5's two parallel tracks feed Phase 5. M1 gates payment. For cohort-by-cohort sequencing of *which* policies land *when*, see [`policies/plan.md`](policies/plan.md).

---

## Phase 1: GLCDI Vocabulary & Namespace

Before any policy can be evaluated, the custom terms used in constraints need to be formally
defined and resolvable.

### 1.1 Register the `glcdi:` namespace

| Item | Detail |
|------|--------|
| **Task** | Define the JSON-LD context file mapping the `glcdi:` prefix to its namespace URI and aliasing the GLCDI properties / value terms used by the policies and the EDC IAM layer |
| **Namespace URI (term identifier base)** | `https://w3id.org/glcdi/v0.1.0/ns/` (kept stable so existing inline policy `@context` blocks continue to resolve to the same term URIs) |
| **Hosted context document** | `https://cdn.startinblox.com/owl/glcdi/context.jsonld` — the canonical JSON-LD context that policies reference via `"@context": "https://cdn.startinblox.com/owl/glcdi/context.jsonld"` |
| **Source file** | [`./context.jsonld`](context.jsonld) — checked into this repo; deployed to the CDN URL above |
| **Content (matches `./context.jsonld`)** | Namespace prefixes (`glcdi`, `edc`, `odrl`, `dcat`, `dct`/`dcterms`, `foaf`, `xsd`, `skos`); GLCDI properties (`participantType`, `certificationStatus`, `contributionStatus`, `membership`, `organisation`, `roles`, `accessOutcome`, `shareBack`); ODRL property aliases with type coercion (`purpose`, `elapsedTime`, `payAmount`, `paymentStatus`, `dateTime`); GLCDI value terms (participant types, certification statuses, contribution statuses, purpose taxonomy, access outcomes — see § 1.2 and § 1.3 for the canonical lists) |
| **w3id.org redirect (deferred)** | Registering the `https://w3id.org/glcdi/v0.1.0/ns/` redirect via the [w3id PR process](https://github.com/perma-id/w3id.org) makes the term URIs themselves dereferenceable. Not required for EDC to function — EDC uses the URIs as identifiers, not for HTTP fetch — but a good post-prototype step for namespace stewardship. The hosted context at `cdn.startinblox.com` is sufficient for the prototype. |
| **Status** | [x] Source file generated · [ ] Deployed to CDN · [ ] Existing policies migrated to reference the hosted URL |

### 1.2 Document participant types and certification statuses

| Item | Detail |
|------|--------|
| **Task** | Propose the canonical list of `participantType` and `certificationStatus` values to the Dataspace Authority for agreement |
| **Proposed participant types** | `producer`, `researcher`, `data-steward`, `conservation-org`, `technology-provider`, `corporate`, `certification-body`, `supply-chain-partner`, `funder` |
| **Proposed certification statuses** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Deliverable** | Enumeration documented in the vocabulary context and in the Trust Framework (v0) |
| **Status** | [ ] Not started |

### 1.3 Define ODRL purpose taxonomy

| Item | Detail |
|------|--------|
| **Task** | Formalise the set of purpose values that consumers can declare in contract offers |
| **Proposed values** | `InternalAnalysis`, `ScientificResearch`, `AgronomicModelTraining`, `EcosystemModelCalibration`, `RegionalBenchmarking`, `EducationalUse`, `ConservationPlanning`, `Scope3Reporting`, `ESGCompliance`, `CertificationVerification`, `ModelOutput` |
| **Why** | Purpose constraints in policies (e.g., `purpose-model-training.json`) rely on consumers declaring a purpose from this controlled vocabulary. Without agreement on the terms, policies cannot be consistently evaluated. |
| **Status** | [ ] Not started |

---

## Phase 1.5: Authority Cleanup + Identity Simplification

Bundles the in-flight governance→authority rename (operator checklist in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md)) with a topology simplification: drop the per-participant Keycloak, run a single-tier OIDC flow against the Authority Keycloak, and consolidate management-API auth on `X-Api-Key`.

### Why now (read-only spike summary)

Today's two-tier OIDC stack (Authority KC `glcdi` realm brokering to per-participant KC `edc` realm) was designed for a richer UI auth flow that the prototype does not exercise. A read-only spike across `participant-agent-services/`, `edc-connector/`, and `participant-ui/` confirmed the per-participant Keycloak is **not load-bearing**:

- **DSP-level identity** (connector ↔ connector) goes via the Identity Hub's STS endpoint (`edc.iam.sts.oauth.token.url`) which signs tokens with the connector's own DID/keypair — independent of any Keycloak.
- **Management-API auth** is pluggable: `web.http.management.auth.type=tokenbased` + `X-Api-Key` works without any Bearer token. oauth2-proxy is a defence-in-depth layer, not a hard requirement.
- **Catalogue-UI two-tier flow** (governance KC → silent-iframe → per-participant KC) is structurally compatible with a single tier: the iframe can target the Authority KC directly once the Authority's `catalog-ui-governance` client carries the relevant redirect URIs.
- **Authority KC already has the needed clients** (`edc-api-client`, `catalog-ui-governance`); no new realm config to invent.

Removing the per-participant Keycloak is a clean cut, not a fork.

### 1.5.1 Complete the governance → authority rename

Per [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md): finish the in-repo renames across `edc-connector/`, `governance-services/` (→ `authority-services/`), `participant-agent-services/`, `participant-ui/`, and the `management/` docs themselves. Operator checklist (DNS, TLS, live Keycloak path A vs. B, CI/CD variables, VM layout, cutover, post-cutover verification) is in that document.

**Status:** [ ] Not started

### 1.5.2 Remove per-participant Keycloak from the participant compose stack

In `participant-agent-services/docker-compose.yml`: delete the `keycloak` and `postgres-kc` services and the `keycloak-pg-data` volume. Remove `participant/keycloak/realms/edc-realm.json` and the related secrets templates (`participant/keycloak/.env.template`, etc.). Adjust the `nginx` service and any `depends_on` edges that pointed at `keycloak`.

**Status:** [ ] Not started

### 1.5.3 Repoint oauth2-proxy at the Authority Keycloak

In `participant-agent-services/docker-compose.yml`, oauth2-proxy environment block:

- `OAUTH2_PROXY_OIDC_ISSUER_URL` → `https://<authority-host>/auth/realms/glcdi`
- `OAUTH2_PROXY_OIDC_JWKS_URL` → `https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/certs`
- `OAUTH2_PROXY_CLIENT_ID` → `glcdi-ui` (Single-client mode; same client as the UI uses — see § 1.5.4)
- `OAUTH2_PROXY_CLIENT_SECRET` → Authority's `glcdi-ui` secret (rotated; see [`AUTHORITY_MIGRATION.md` § 4](AUTHORITY_MIGRATION.md))
- Drop `depends_on: keycloak`

**Status:** [ ] Not started

### 1.5.4 Rename UI client to `glcdi-ui` and repoint the UI flow at the Authority Keycloak

The current `catalog-ui-governance` client is misnamed for the simplified topology — there is no separate per-participant `catalog-ui` to disambiguate it from. Rename to `glcdi-ui` (single, generic client; same role for every participant).

**Authority KC** (`glcdi` realm):

- Rename client `catalog-ui-governance` → `glcdi-ui`.
- Ensure redirect URIs cover all participant origins (e.g. `https://caney-fork.glcdi.startinblox.com/*`, `https://point-blue.glcdi.startinblox.com/*`, …) and the `silent-callback.html` paths if the UI keeps that flow.
- Configure the protocol mappers from § 2.3 on this single client so tokens carry the `glcdi_*` claims.
- Audience: configure `glcdi-ui` to mint tokens whose audience is acceptable to oauth2-proxy (Single-client mode — one client serves both UI session and management-API calls).

**`participant-agent-services/docker-compose.yml`**, catalogue-ui environment block:

- `LINKED_PROVIDER_AUTHORITY` → `https://<authority-host>/auth/realms/glcdi`
- `LINKED_PROVIDER_CLIENT_ID` → `glcdi-ui`
- `OIDC_CLIENT_ID` (and any other place `catalog-ui-governance` was referenced) → `glcdi-ui`

The silent-iframe flow continues to work; the iframe now targets the Authority KC directly under the renamed client.

**Status:** [ ] Not started

### 1.5.5 Confirm `X-Api-Key`-only management-API auth

Verify and document that programmatic clients (Bruno collection from § 4.5.E, seeding scripts from § Phase 4) can call the management API with only `X-Api-Key` (no Bearer token), against `web.http.management.auth.type=tokenbased` + `web.http.management.auth.key=<rotated-key>`. Rotate `web.http.management.auth.key`, `edc.api.auth.key`, `edc.api.control.auth.apikey.value` from the example defaults (`123456`, `password`) per [`CLAUDE.md`](../../CLAUDE.md) "Things that will bite you".

oauth2-proxy stays in front of the catalogue-UI path as defence-in-depth; programmatic clients hit the management API directly with `X-Api-Key`.

**Status:** [ ] Not started

### 1.5.6 Model participant organisations as Keycloak groups, with a starter user per group

To support multiple operators per organisation later without a refactor, model orgs as **Keycloak groups** rather than as single user accounts. Each group carries the org's claims; users join the group and inherit them.

In the Authority KC's `glcdi` realm:

- Create groups: `caney-fork-team`, `point-blue-team`, `white-buffalo-team`.
- Assign realm roles (`glcdi_member`, `glcdi_researcher` or `glcdi_regenerative_producer` — per Phase 2) and group attributes (`glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`) at the **group level**, not the user level.
- Configure protocol mappers (§ 2.3) to serialise both group roles and group attributes into the JWT.
- Create one starter user per group: `caney-fork` (member of `caney-fork-team`), `point-blue` (member of `point-blue-team`), `white-buffalo` (member of `white-buffalo-team`). Set initial credentials.
- Adding a second operator for an org later = "create user, add to existing group". No new claim wiring needed.

**Connector service accounts** (one per participant org — used by the *connector itself* for DSP-level identity, see § 1.5.8 + § 3.5):

- Create one Keycloak client per org with `client_credentials` enabled and a service account: e.g. `glcdi-connector-caney-fork`, `glcdi-connector-point-blue`, `glcdi-connector-white-buffalo`.
- Each client's service account is mapped into its org's group (`<org>-team`) so tokens minted via `client_credentials` carry the same `glcdi_*` claims as a human operator from that org.
- Each connector authenticates against Authority KC at startup (or on token expiry) using its `client_credentials` config to obtain a JWT for itself; that JWT is what the connector presents at DSP time.

**Service accounts for Bruno / programmatic clients (§ 4.5.E):** can reuse the per-org connector service accounts to mint tokens for identity-driven scenario steps, or have their own (`glcdi-test-<org>`) if you want test traffic distinguishable in audit logs.

**Status:** [ ] Not started

### 1.5.7 Sanity-check DSP-level identity is still working

After the cuts above, run a smoke-test contract negotiation between two participant connectors. Expected: each connector's STS endpoint mints DSP tokens signed by its own DID/keypair, the remote connector validates the signature, negotiation reaches `FINALIZED`. This is a verification step, not a change — the spike showed Keycloak removal does not touch the DSP-signing path.

**Status:** [ ] Not started

### 1.5.8 Auth flow & credentials reference (post-Phase-1.5)

For future contributors and the Track-E/F agents in § 4.5: the credential model after Phase 1.5 is single-tier OIDC (Authority KC only) plus a primary `X-Api-Key` gate at the EDC management API.

**Identity flow for UI / operator API calls:**

```
Operator user (member of <org>-team group in Authority KC)
  ↓ logs in via UI → Authority KC issues OIDC token (client: glcdi-ui)
  ↓ token carries glcdi_member, glcdi_researcher | glcdi_regenerative_producer,
  ↓               glcdi_organisation, glcdi_certification_status, glcdi_contribution_status
Browser / UI
  ↓ X-Api-Key + Authorization: Bearer <token> on every management-API call
oauth2-proxy validates Bearer token against Authority KC JWKS
  ↓ passes through if valid
EDC management API (X-Api-Key gate)
  ↓ EDC IdentityService extracts claims from the Bearer token
EDC policy engine evaluates access / contract policies against those claims
```

**Role of each credential:**

| Credential | What it gates | Required for |
|------------|---------------|--------------|
| **`X-Api-Key`** | EDC management-API access at the connector | **Every** management-API call (UI, Bruno, seeding scripts). The floor; never optional. |
| **`Authorization: Bearer <Authority-KC token>`** | Identity-driven operations: claims feed EDC's IdentityService for policy evaluation | UI session; Bruno scenario steps that test identity-driven paths (catalog query as user X, negotiation as user X). **Optional for pure CRUD** (asset / policy / contract-definition seeding). |

**For Bruno (§ 4.5.E):**

- Pure CRUD steps: `X-Api-Key` only.
- Identity-driven scenario steps: `X-Api-Key` + Bearer token obtained via Keycloak `client_credentials` flow against the per-org service account from § 1.5.6.

**For seeding scripts (§ Phase 4):** typically `X-Api-Key` only — they're admin operations.

**For DSP-level (connector ↔ connector) traffic:** the EDC fork currently wires `iam-mock` (a no-op IdentityService that accepts any token and returns fixed claims). For real claim-based policy evaluation we need to replace it with **`iam-oauth2`** configured against the Authority KC — see § 3.5. The flow then becomes:

```
Connector A (e.g. point-blue's connector at startup)
  ↓ client_credentials grant against Authority KC (client: glcdi-connector-point-blue)
  ↓ Authority KC issues OIDC token carrying point-blue-team's claims
  ↓ (glcdi_member, glcdi_researcher, glcdi_organisation)
Connector A holds the token in its IAM cache
  ↓ initiates DSP request to Connector B (e.g. catalog query)
Connector B receives DSP request with Authorization: Bearer <token>
  ↓ iam-oauth2 validates against Authority KC JWKS
  ↓ extracts glcdi_* claims into ClaimToken / ParticipantContext
EDC policy engine on Connector B evaluates access policy against those claims
```

The previous DCP/IATP-shaped config (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.token.url=http://identity-hub:7084/sts/token`) is for a future direction — the prototype takes the simpler OAuth2 path. The Identity Hub stays in the compose for STS / VC features that remain on the post-prototype roadmap, but is not on the M1 critical path.

**Status:** [ ] Not started — captures the design; no implementation work in this sub-section

### Dependencies & risks

- **Blocks Phase 2** — Keycloak claim configuration now targets the Authority KC, not the per-participant KC.
- **Coordinates with [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md)** — the operator-side rename and the topology simplification benefit from a single deploy window per participant.
- **No remaining architectural unknowns** after the spike. Risk is now purely operational: cutover sequencing and config rotation.

---

## Phase 2: Keycloak Claims Configuration — Participant Types via OIDC

Policies like `members-only`, `regenerative-producers`, and `researchers-only` evaluate claims from
the consumer's identity token. For the prototype, we rely on **Keycloak realm roles** serialised
as OIDC claims in access tokens, rather than Verifiable Credentials (which are a post-prototype
goal — see Phase 7.2).

### Architecture Decision: Realm Roles vs. User Attributes

Two Keycloak mechanisms can carry participant type information into tokens:

| Approach | How it works | Pros | Cons |
|----------|-------------|------|------|
| **Realm roles** | Create roles like `glcdi_producer`, `glcdi_researcher`, assign to users. Roles appear in `realm_access.roles[]` in the token by default. | Zero mapper configuration needed. Roles are built into Keycloak's RBAC. Easy to manage in admin console. Can be assigned during onboarding. | Flat list — no structured key/value. Checking "is this user a researcher?" means looking for `glcdi_researcher` in an array. |
| **User attributes** | Set custom key/value pairs on user profiles (`glcdi_participant_type=researcher`). Add protocol mappers to serialize into token claims. | Structured data. Clean namespace. Can represent multi-valued attributes naturally. | Requires explicit protocol mapper configuration per client. Slightly more setup. |

**Recommendation for prototype:** Use **realm roles for participant type and membership** (simplest
path — no mapper config, works immediately) and **user attributes for certification status**
(since it's a structured value, not a boolean flag). This hybrid approach minimises
configuration while keeping the data model clean.

### 2.1 Create GLCDI realm roles

| Item | Detail |
|------|--------|
| **Task** | Add realm roles to the `glcdi` realm in governance Keycloak |
| **Roles to create** | `glcdi_member` (active membership), `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder` |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — in the `roles.realm[]` array |
| **Status** | [ ] Not started |

**Realm JSON snippet to add:**

```json
{
  "roles": {
    "realm": [
      { "name": "user", "description": "Default user role" },
      { "name": "admin", "description": "Admin role" },
      { "name": "glcdi_member", "description": "Active GLCDI dataspace participant" },
      { "name": "glcdi_producer", "description": "Rancher / farming organisation" },
      { "name": "glcdi_researcher", "description": "Academic or scientific research institution" },
      { "name": "glcdi_data_steward", "description": "Data steward / conservation alliance" },
      { "name": "glcdi_conservation_org", "description": "Conservation organisation" },
      { "name": "glcdi_technology_provider", "description": "Ag-tech / data platform provider" },
      { "name": "glcdi_corporate", "description": "Food company / supply chain actor" },
      { "name": "glcdi_certification_body", "description": "Certification / verification body" },
      { "name": "glcdi_supply_chain_partner", "description": "Procurement / ESG reporting partner" },
      { "name": "glcdi_funder", "description": "Funding body / public sector partner" }
    ]
  }
}
```

### 2.2 Add certification status and contribution status as user attributes

| Item | Detail |
|------|--------|
| **Task** | Define `glcdi_certification_status` and `glcdi_contribution_status` as custom user attributes |
| **Certification values** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Contribution values** | `contributing` (has published data), `observer` (onboarded but no data published yet), `pending` (awaiting verification) |
| **Where** | Set per-user in Keycloak admin console or via Admin API. Not part of the realm export by default — attributes are per-user, not schema-level. |
| **Proposed owner for contribution status** | For the prototype (small participant set): it is proposed that the Dataspace Authority sets this manually after verifying that a participant's connector has published assets. For scaling: a periodic automated service could query each participant's catalog and update the attribute. |
| **Status** | [ ] Not started |

### 2.3 Create protocol mappers for token serialisation

Realm roles are already included in tokens by default (in `realm_access.roles[]`), but we need
explicit mappers to surface claims in the format the EDC policy functions expect.

| Item | Detail |
|------|--------|
| **Task** | Add protocol mappers to relevant Keycloak clients so that GLCDI claims appear as top-level claims in access tokens |
| **Status** | [ ] Not started |

**Three mappers to create, on each of these clients:** `edc-api-client`, `participant-broker`, `catalog-ui-governance`

#### Mapper 1: Realm roles → `glcdi_roles` claim

This mapper serialises all `glcdi_*` realm roles into a dedicated array claim, separate from
the default `realm_access.roles` which also includes Keycloak internal roles.

```json
{
  "name": "glcdi-roles",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-realm-role-mapper",
  "config": {
    "claim.name": "glcdi_roles",
    "jsonType.label": "String",
    "multivalued": "true",
    "usermodel.realmRoleMapping.rolePrefix": "glcdi_",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_roles": ["glcdi_member", "glcdi_producer"]
}
```

#### Mapper 2: User attribute → `glcdi_certification_status` claim

```json
{
  "name": "glcdi-certification-status",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "claim.name": "glcdi_certification_status",
    "jsonType.label": "String",
    "user.attribute": "glcdi_certification_status",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_certification_status": "regenerative-verified"
}
```

#### Mapper 2b: User attribute → `glcdi_contribution_status` claim

```json
{
  "name": "glcdi-contribution-status",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "claim.name": "glcdi_contribution_status",
    "jsonType.label": "String",
    "user.attribute": "glcdi_contribution_status",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_contribution_status": "contributing"
}
```

#### Mapper 3 (optional): Hardcoded `glcdi_membership` claim

As a shortcut, instead of checking for the `glcdi_member` role in the roles array, add a
hardcoded claim mapper on the client scope that applies to all authenticated users:

```json
{
  "name": "glcdi-membership-active",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-hardcoded-claim-mapper",
  "config": {
    "claim.name": "glcdi_membership",
    "claim.value": "active",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true"
  }
}
```

> **Note:** This gives `glcdi_membership=active` to every authenticated user. If you need to
> distinguish `suspended` or `pending` users, use a User Attribute mapper instead (like
> certification status) and manage the value per-user. For the prototype, all onboarded
> users are active, so a hardcoded claim is the simplest path.

### 2.4 Assign roles to prototype participants

| Item | Detail |
|------|--------|
| **Task** | Assign the correct realm roles and user attributes to each prototype participant — at the **group level** per § 1.5.6, not per user — so multiple users per organisation inherit the same claims automatically |
| **Status** | [ ] Not started |

> **Note (post-Phase-1.5):** assignments target the org-level Keycloak group (`caney-fork-team`, `point-blue-team`, `white-buffalo-team`) created in § 1.5.6. The bash examples below show the user-level Admin-API endpoint for completeness; the group-level equivalent is `/admin/realms/$REALM/groups/$GROUP_ID/role-mappings/realm` and `/admin/realms/$REALM/groups/$GROUP_ID` (PUT for attributes). Adding a new operator to the org becomes "create user, add to group" with no additional role-assignment step.

The proposed assignment *pattern*, by participant type (specific participant identities are TBD and to be confirmed at onboarding):

| Participant type | Proposed realm roles | Proposed certification status | Proposed contribution status |
|------------------|----------------------|------------------------------|------------------------------|
| Regenerative producer | `glcdi_member`, `glcdi_producer` | `regenerative-verified` | `contributing` (after seeding) |
| Research institution | `glcdi_member`, `glcdi_researcher` | `not-applicable` | `contributing` (after seeding) |
| Data steward / monitoring alliance | `glcdi_member`, `glcdi_data_steward` | `not-applicable` | `observer` (until data published) |
| Newly onboarded participant (any type, no data yet) | `glcdi_member` + type role | per declared type | `observer` (until data published) |

**Via Keycloak Admin API:**

```bash
KEYCLOAK_URL="https://governance.glcdi.startinblox.com"
REALM="glcdi"

# Get admin token
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq -r '.access_token')

# Get user ID (example: a producer participant's service account — substitute the real username)
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users?username=<participant-sa>" \
  | jq -r '.[0].id')

# Get role IDs
MEMBER_ROLE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/roles/glcdi_member" \
  | jq -r '.id')
PRODUCER_ROLE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/roles/glcdi_producer" \
  | jq -r '.id')

# Assign realm roles
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID/role-mappings/realm" \
  -d "[
    {\"id\": \"$MEMBER_ROLE_ID\", \"name\": \"glcdi_member\"},
    {\"id\": \"$PRODUCER_ROLE_ID\", \"name\": \"glcdi_producer\"}
  ]"

# Set certification status attribute
curl -s -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID" \
  -d "{\"attributes\": {\"glcdi_certification_status\": [\"regenerative-verified\"]}}"
```

### 2.5 Update identity provider mappers for federation

> **Obsolete after Phase 1.5.** The two-tier OIDC topology this section was written for (Authority KC brokering to per-participant KC `edc` realm) is removed by [§ Phase 1.5](#phase-15-authority-cleanup--identity-simplification). With a single Keycloak in the picture there is no IdP-federation hop to map across — roles and attributes are assigned directly on the Authority KC group / user (per § 1.5.6 and § 2.4). No work in this sub-section.

> Historical context (the previous Option A / Option B trade-off) lives in the git history of this file if needed; collapsing it here keeps the active plan focused on the post-1.5 model.

### 2.6 Verify token contents

| Item | Detail |
|------|--------|
| **Task** | Confirm that tokens issued by governance Keycloak contain the expected GLCDI claims |
| **Status** | [ ] Not started |

**Manual verification:**

```bash
# Request a token for a participant's service account
TOKEN=$(curl -s -X POST \
  "https://governance.glcdi.startinblox.com/auth/realms/glcdi/protocol/openid-connect/token" \
  -d "client_id=edc-api-client" \
  -d "client_secret=changeme-edc-api-client-secret" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Decode and inspect (JWT is base64-encoded, middle segment is the payload)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**Expected output (relevant claims):**

```json
{
  "iss": "https://governance.glcdi.startinblox.com/auth/realms/glcdi",
  "sub": "...",
  "glcdi_membership": "active",
  "glcdi_roles": ["glcdi_member", "glcdi_producer"],
  "glcdi_certification_status": "regenerative-verified",
  "realm_access": {
    "roles": ["glcdi_member", "glcdi_producer", "user", "default-roles-glcdi"]
  }
}
```

### 2.7 Mapping from token claims to policy constraints

This table shows how each policy constraint maps to what the EDC policy function should
read from the token:

| Policy constraint | `leftOperand` | Token claim to read | Check logic |
|-------------------|---------------|---------------------|-------------|
| `glcdi:membership eq "active"` | `https://w3id.org/glcdi/v0.1.0/ns/membership` | `glcdi_membership` (string) | `claim == rightOperand` |
| `glcdi:participantType eq "producer"` | `https://w3id.org/glcdi/v0.1.0/ns/participantType` | `glcdi_roles` (array) | `"glcdi_" + rightOperand` present in array |
| `glcdi:participantType isAnyOf ["researcher","data-steward"]` | same | `glcdi_roles` (array) | any of `["glcdi_researcher","glcdi_data_steward"]` present in array |
| `glcdi:certificationStatus eq "regenerative-verified"` | `https://w3id.org/glcdi/v0.1.0/ns/certificationStatus` | `glcdi_certification_status` (string) | `claim == rightOperand` |
| `glcdi:certificationStatus isAnyOf [...]` | same | same | `claim` in `rightOperand` list |
| `glcdi:contributionStatus eq "contributing"` | `https://w3id.org/glcdi/v0.1.0/ns/contributionStatus` | `glcdi_contribution_status` (string) | `claim == rightOperand` |

> **Important:** The policy function for `participantType` needs to translate between the
> policy value (e.g., `"researcher"`) and the Keycloak role name (e.g., `"glcdi_researcher"`).
> The convention is: `"glcdi_" + participantType`. The function should handle this prefix
> transparently.

### 2.8 Integration with the onboarding flow

| Item | Detail |
|------|--------|
| **Task** | When a new participant is onboarded via the onboarding app, automatically assign appropriate GLCDI roles |
| **Where** | `governance-services/onboarding/backend/` — the proposal is that the DjangoLDP approval workflow calls the Keycloak Admin API to assign roles upon approval |
| **Status** | [ ] Not started |

**Proposed flow** (to be validated with the governance body before implementation):

1. Participant submits onboarding request (name, organisation, type, certification evidence).
2. The governance body (proposed: Dataspace Authority) reviews and approves via the approval UI.
3. On approval, the backend would call the Keycloak Admin API to:
   - Create or update the user
   - Assign `glcdi_member` + the appropriate type role (e.g., `glcdi_producer`)
   - Set `glcdi_certification_status` attribute (validated by governance team)
4. Participant receives confirmation and can now authenticate.

This would automate the role assignment from step 2.4, removing the need for manual admin
console operations as the dataspace grows beyond the initial small participant set.

---

## Phase 3: EDC Policy Extension Development

### 3.0 `edc-glcdi-extension` repository scaffolding

| Item | Detail |
|------|--------|
| **Task** | Set up the GLCDI-owned extension repository as a sibling of `edc-connector/`, following the DS4GO pattern (separate repo, build-time symlinked or path-referenced from the connector's controlplane build). |
| **Why a separate repo (not `edc-connector/extensions/`)** | Keeps GLCDI-owned Java code separate from the EDC fork (which tracks upstream). Independent versioning + git history. Mirrors `ds4go/edc-dsif-extension/` next to `ds4go/edc-connector/`. |
| **Layout (proposed)** | `edc-glcdi-extension/extensions/glcdi-policy-functions/` (the membership / participantType / certificationStatus functions of §§ 3.2–3.4) — first occupant. Future siblings (e.g. `payment-status-extension/` from [`PAYMENT_GATING.md`](PAYMENT_GATING.md), if Phase 7.1 lands) live under the same `extensions/` folder. |
| **Wire-up** | `edc-connector/runtimes/controlplane/build.gradle.kts` references the extension via relative path or via a CI symlink step that puts the extension into `edc-connector/extensions/`. Match whichever pattern this team's CI uses for DS4GO. |
| **Status** | [x] Repo created (empty) · [ ] First extension scaffolded (§ 3.1) · [ ] Wired into the controlplane runtime (§ 3.6) |



The EDC connector needs custom policy functions to evaluate GLCDI-specific constraints.
Without these, constraints referencing `glcdi:membership` or `glcdi:participantType` will be
silently ignored (default: permit) or fail closed, depending on EDC configuration.

### 3.1 Create `glcdi-policy-functions` extension

| Item | Detail |
|------|--------|
| **Task** | Create a new EDC extension in `edc-connector/extensions/glcdi-policy-functions/` |
| **Language** | Java 17 |
| **Build** | Add to `settings.gradle.kts`, create `build.gradle.kts` with EDC policy SPI dependencies |
| **Status** | [ ] Not started |

### 3.2 Implement membership policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:membership` |
| **Behaviour** | Extract the `glcdi_membership` claim from the participant's identity (via `ParticipantAgent`), compare it to the constraint's `rightOperand` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/membership"` |
| **Used by** | `access/members-only.json`, `access/regenerative-producers.json`, `access/researchers-only.json`, and all combined policies |
| **Status** | [ ] Not started |

### 3.3 Implement participant type policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:participantType` |
| **Behaviour** | Extract `glcdi_participant_type` claim, support `eq` and `isAnyOf` operators |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/participantType"` |
| **Used by** | `access/regenerative-producers.json`, `access/researchers-only.json`, `combined/corporate-supply-chain.json` |
| **Status** | [ ] Not started |

### 3.4 Implement certification status policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:certificationStatus` |
| **Behaviour** | Extract `glcdi_certification_status` claim, support `eq` and `isAnyOf` operators |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/certificationStatus"` |
| **Used by** | `access/regenerative-producers.json` |
| **Status** | [ ] Not started |

### 3.5 Replace `iam-mock` with `iam-oauth2` and configure claim extraction

| Item | Detail |
|------|--------|
| **Task** | Swap the dev-only `iam-mock` IdentityService (currently wired in `edc-connector/runtimes/controlplane/build.gradle.kts` as `libs.edc.iam.mock`) for `iam-oauth2`, configured against the Authority Keycloak. Configure the claim extractor so `glcdi_*` claims land in EDC's `ClaimToken` for the policy engine to read. |
| **Why a swap, not custom code** | `iam-mock` accepts any token and returns fixed claims — fine for development, useless for policy evaluation. `iam-oauth2` is stock EDC; the work is configuration + claim mapping, not a new Java extension. |
| **Status** | [ ] Not started |

**Build change** (`edc-connector/runtimes/controlplane/build.gradle.kts`):

- Replace `implementation(libs.edc.iam.mock)` with `implementation(libs.edc.iam.oauth2)` (or whatever the version-catalog alias is in this fork; `iam.oauth2` is the standard EDC 0.15.x module name).

**Configuration** (`participant/configuration.properties` per connector):

```properties
# Authority Keycloak as the OAuth2 IdP
edc.oauth.token.url=https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/token
edc.oauth.provider.jwks.url=https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/certs
edc.oauth.client.id=glcdi-connector-<this-org>          # e.g. glcdi-connector-caney-fork (per § 1.5.6)
edc.oauth.client.secret.alias=oauth-client-secret       # secret stored in vault, not in properties
edc.oauth.provider.audience=glcdi-connector-<this-org>  # token audience this connector accepts

# Custom claim mapping — surface glcdi_* claims to the policy engine
# (exact property names depend on the iam-oauth2 version in this fork; verify during the swap)
edc.iam.token.scope=openid profile glcdi_claims
```

**Claim extraction:** EDC's `iam-oauth2` extension extracts standard claims by default. To surface our custom claims (`glcdi_member`, `glcdi_researcher`, `glcdi_regenerative_producer`, `glcdi_certification_status`, `glcdi_contribution_status`), configure the claim mapper to copy them from the JWT into the `ClaimToken`. The policy functions in §§ 3.2–3.4 then read from `ClaimToken.getClaim("glcdi_member")` etc.

**To verify during implementation:** the exact claim-mapping config keys for the `iam-oauth2` version pinned in this fork. The principle is consistent across versions; the property names occasionally drift. A small pre-flight read of the EDC source at the pinned version (`./gradlew :runtimes:controlplane:dependencies | grep iam-oauth2`) will confirm.

**Migration note (post-prototype):** the existing DCP-shaped config (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.*`, etc.) is the future direction (decentralised identity via Identity Hub + Verifiable Credentials). For M1 it can be left in place but unused, or removed; either way it does not feed the M1 policy-evaluation path.

### 3.6 Register extension in connector runtime

| Item | Detail |
|------|--------|
| **Task** | Add `glcdi-policy-functions` as a dependency in `runtimes/controlplane/build.gradle.kts` |
| **Deliverable** | Rebuilt connector image with the policy functions available |
| **Status** | [ ] Not started |

---

## Phase 4: Update Seeding Scripts & Contract Definitions

Replace the current `glcdi:policy:open-research` (simple "use" permission with no constraints)
with the richer policies from `./policies/`.

### 4.1 Update producer-participant seeding scripts

| Item | Detail |
|------|--------|
| **Task** | Replace the single open-research policy with appropriate policies per asset on each producer participant's seeding script |
| **Typical producer asset classes and proposed policies:** | |
| **SOC measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `time-limited` + `attribution` (for model calibration use case) |
| **Grazing rotation** | Access: `members-only` / Contract: `non-commercial` + `attribution` (for benchmarking use case) |
| **Paddock boundaries** | Access: `members-only` / Contract: `internal-use-only` + `time-limited` (sensitive spatial data) |
| **NDVI time series** | Access: `members-only` / Contract: `attribution` (lower sensitivity, broader sharing) |
| **Status** | [ ] Not started |

### 4.2 Update research-participant seeding scripts

| Item | Detail |
|------|--------|
| **Task** | Replace open-research policy with policies appropriate for a research institution's data |
| **Typical research asset classes and proposed policies:** | |
| **Rangeland SOC inventory** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **GHG flux measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `attribution` |
| **Biodiversity surveys** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **Weather station data** | Access: `members-only` / Contract: `attribution` (low sensitivity) |
| **Carbon credit reports** | Access: `members-only` / Contract: `internal-use-only` + `anonymisation` (commercially sensitive) |
| **Status** | [ ] Not started |

### 4.3 Create seeding helper for policy registration

| Item | Detail |
|------|--------|
| **Task** | Add a section to seeding scripts that registers all needed policy definitions before creating contract definitions, reading from the JSON files in `management/policies/` |
| **Approach** | Loop over the required policy JSON files and POST them to `/management/v3/policydefinitions`. Then create contract definitions that reference the registered policy IDs. |
| **Status** | [ ] Not started |

---

## Phase 4.5: Bruno Test Suite + Participant-UI Configuration (Parallel Tracks)

Two independent tracks that can run in parallel with each other and with Phases 3–4. Both feed into the Phase 5 integration tests and the M1 milestone gate.

### 4.5.E Bruno test suite (Track E — parallel agent)

**Location:** [`./bruno/`](bruno/) (i.e. `management/bruno/` in this repo). Single collection; environment variables for staging vs. local; one folder per scenario step or per logical group (auth setup, catalog queries, negotiations, transfers).

A Bruno collection (or equivalent HTTP test harness) executing the M1 scenario end-to-end against the management API:

- Catalog query as a researcher (`glcdi_researcher` claim) → expect the regenerative-only asset to be **visible**.
- Catalog query as a non-regenerative producer (only `glcdi_member`) → expect the same asset to be **filtered out** (access policy hides it).
- Contract negotiation with `purpose = InternalAnalysis` → expect **AGREED → FINALIZED**.
- Contract negotiation with `purpose = ResearchAnalysis` → expect **TERMINATED** (purpose mismatch on the `internal-use-only` contract policy).
- Transfer-process initiation against the agreed contract → expect data payload returned.
- Negative auth: management-API call without `X-Api-Key` → expect `401`. With wrong `X-Api-Key` → expect `401`.

**Auth context:**

- `X-Api-Key` against the management API for every call (the floor — see § 1.5.8).
- Identity-driven scenario steps (catalog query as researcher, contract negotiation as a specific org) **also** carry `Authorization: Bearer <token>`. The token is minted via Keycloak's `client_credentials` flow against per-org service-account clients (`glcdi-connector-<org>` from § 1.5.6, or dedicated `glcdi-test-<org>` clients if test traffic should be distinguishable in audit logs).
- The Bruno collection should include a setup request that fetches a token from `https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/token` and stores it as a collection variable; subsequent identity-driven requests reuse it. Token refresh on expiry is handled by Bruno's pre-request scripting.

Bruno runs against either a single participant's connector locally, or against the staging URLs (`caney-fork.glcdi.startinblox.com`, `point-blue.glcdi.startinblox.com`).

**Owner:** parallel agent. Can begin drafting once §§ 1.5.5–1.5.6 fix the API-key contract and the per-org client_credentials shape; doesn't strictly need Phases 2–4 to run, only to be runnable.

**Status:** [ ] Not started

### 4.5.F Participant-UI configuration (Track F — parallel agent)

Audit and adapt `participant-ui/` for the simplified topology:

- Confirm the UI still renders correctly with the Authority KC as the only OIDC issuer (after § 1.5.4).
- Confirm or enable a path for **API-key login** — the operator pastes an `X-Api-Key` value that the UI uses for management-API calls. **Trust shape:** API key in browser is acceptable for a controlled demo, not for production — flag clearly in the UI copy.
- Surface the components that allow operators to: create / list assets, create / list policies, create / list contract definitions, view contract-negotiation and transfer-process history. Verify which are already in `config.json` and which need enabling. The Hubl/Lit framework drives behaviour from `config.json` + `envsubst` token substitution at container start (see [`participant-ui/docker-entrypoint.sh`](../participant-ui/docker-entrypoint.sh) per [`CLAUDE.md`](../CLAUDE.md)).
- Confirm theme/branding still renders correctly (per-participant via env vars; the runtime-configurable single image continues to work).

**Owner:** parallel agent. **Read-only investigation first** ("survey the participant-ui config surface and report which components are gated by which env / config keys; flag what breaks when participant-Keycloak goes away"), then implementation.

**Status:** [ ] Not started

### Dependencies

- Both tracks **depend on § 1.5** (auth simplification) being landed in at least one staging participant.
- 4.5.E benefits from Phases 2–4 being further along (so the test-suite assertions match real seeded data) but can be drafted in parallel against expected behaviour.
- 4.5.F's read-only audit can begin **immediately**; implementation follows § 1.5.

---

## Phase 5: Testing & Validation

### 5.1 Unit test policy functions

| Item | Detail |
|------|--------|
| **Task** | Write JUnit tests for each policy function (membership, participantType, certificationStatus) |
| **Test cases** | Active member passes, suspended member fails, correct type passes, wrong type fails, `isAnyOf` with multiple values, missing claim handling |
| **Where** | `edc-connector/extensions/glcdi-policy-functions/src/test/` |
| **Status** | [ ] Not started |

### 5.2 Integration test: access policy filtering

| Item | Detail |
|------|--------|
| **Task** | Verify that catalog queries correctly filter offers based on access policies |
| **Test scenario 1** | A producer participant queries a research participant's catalog → sees assets with `members-only` access, does NOT see assets with `researchers-only` access |
| **Test scenario 2** | A research participant queries a producer participant's catalog → sees all assets (both `members-only` and `researchers-only`) |
| **Test scenario 3** | Unauthenticated or non-member query → sees nothing |
| **Where** | Extend `test-dsp-catalog-query.sh` or create `test-policy-filtering.sh` |
| **Status** | [ ] Not started |

### 5.3 Integration test: contract negotiation with constraints

| Item | Detail |
|------|--------|
| **Task** | Verify that contract negotiation enforces contract policy constraints |
| **Test scenario 1** | A research participant negotiates for SOC data with `purpose=AgronomicModelTraining` → negotiation succeeds |
| **Test scenario 2** | A research participant negotiates for SOC data with `purpose=Scope3Reporting` → negotiation is rejected (wrong purpose) |
| **Test scenario 3** | A producer participant negotiates for a research participant's benchmarking data with `purpose=RegionalBenchmarking` → succeeds |
| **Where** | Extend `negotiate-and-transfer.sh` or create `test-contract-policies.sh` |
| **Status** | [ ] Not started |

### 5.4 Integration test: temporal constraint enforcement

| Item | Detail |
|------|--------|
| **Task** | Verify that time-limited policies are enforced |
| **Test scenario** | Set a policy with a past expiry date → contract negotiation should be rejected |
| **Note** | This is the easiest policy to test since temporal constraints work natively in EDC |
| **Status** | [ ] Not started |

### 5.5 End-to-end combined scenario test

| Item | Detail |
|------|--------|
| **Task** | Run the full agronomic model calibration flow end-to-end |
| **Steps** | 1. Register policies from `combined/researcher-model-feeding.json` on a producer participant's connector. 2. Create contract definition linking SOC asset to these policies. 3. From a research participant's connector, query the producer's catalog → SOC asset visible. 4. Negotiate contract with `purpose=AgronomicModelTraining` → FINALIZED. 5. Initiate data transfer → succeeds. 6. Repeat from another producer connector → catalog query should NOT show the asset (researchers-only access). |
| **Deliverable** | `test-model-calibration-scenario.sh` script |
| **Status** | [ ] Not started |

---

## 🚦 Milestone M1: Regenerative-Only Access + Internal-Use-Only Contract — End-to-End

**Gate before Phase 7.1 (Payment-required workflow) starts.**

M1 is demonstrable when, against a deployed two-participant cluster (e.g. `caney-fork` provider + `point-blue` researcher), the following all pass:

- [ ] Authority Keycloak has `caney-fork`, `point-blue`, `white-buffalo` users with the appropriate `glcdi_member`, `glcdi_researcher`, `glcdi_regenerative_producer` claims (per § 1.5.6 + Phase 2).
- [ ] A provider connector publishes an asset whose **access policy** is `regenerative-producers-only` (Phase 4) and whose **contract policy** is `internal-use-only` (Phase 4).
- [ ] A researcher (with `glcdi_researcher` claim) sees the asset in the catalog query.
- [ ] A non-regenerative producer (with only `glcdi_member`) does **not** see the asset.
- [ ] Contract negotiation succeeds when the consumer declares `purpose = InternalAnalysis`; fails when they declare a different purpose.
- [ ] Transfer succeeds against the agreed contract.
- [ ] The Bruno collection (§ 4.5.E) executes all of the above non-interactively — green run.
- [ ] The participant UI (§ 4.5.F) surfaces asset / policy / contract / history components correctly under API-key login.
- [ ] Per-participant Keycloak is gone from the deployed compose stack (§ 1.5.2); single-tier OIDC against the Authority Keycloak; `X-Api-Key` for the management API.

Once M1 is signed off, Phase 7.1 (payment-required workflow per [`PAYMENT_GATING.md`](PAYMENT_GATING.md)) becomes the active workstream. Phase 6 (governance-level enforcement) continues in parallel throughout.

---

## Phase 6: Governance-Level Enforcement (Non-Technical) — Proposal

Some policy obligations cannot be technically enforced by the connector. These would need
governance-level support through the Trust Framework and Data Sharing Agreements. The items
in this phase are proposals for the governance body to consider and refine.

### 6.1 Embed policy obligations in Data Sharing Agreement templates

| Item | Detail |
|------|--------|
| **Task** | Propose updates to MOU/DSA templates that include clauses mapping to ODRL obligations; validate with legal counsel and the governance body |
| **Proposed clauses** | Anonymisation requirements (what counts as anonymised, at what geographic granularity), attribution format and placement, data retention/deletion procedures and confirmation process, non-redistribution commitments, purpose limitations |
| **Deliverable** | Updated DSA template in the Trust Framework (v0 → v1), pending governance-body approval |
| **Status** | [ ] Not started |

### 6.2 Define audit and compliance mechanisms

| Item | Detail |
|------|--------|
| **Task** | Propose how governance-level obligations (anonymisation, deletion, attribution) could be verified, for governance-body sign-off |
| **Options to consider** | Self-attestation (lightweight, suitable for prototype), periodic review by the governance body, automated checks where possible (e.g., scanning published papers for attribution) |
| **Deliverable** | Compliance section in Trust Framework v1, pending governance-body approval |
| **Status** | [ ] Not started |

### 6.3 Design consent revocation flow

| Item | Detail |
|------|--------|
| **Task** | Propose what would happen when a producer wants to revoke consent for a previously shared dataset |
| **Considerations** | Contracts already finalized cannot be technically un-done, but new transfers can be blocked. Retention limits (e.g., `data-retention-limit.json`) provide a natural expiry. It is proposed that revocation trigger a notification to the consumer with a deletion request. |
| **Deliverable** | Revocation procedure documented in Trust Framework, pending governance-body approval |
| **Status** | [ ] Not started |

---

## Phase 7: Future Enhancements (Post-Prototype)

Items from `./policies/` that are relevant for later phases but not required for the prototype.

### 7.1 Payment infrastructure

| Item | Detail |
|------|--------|
| **Task** | Implement the `payment-required` contract policy via a `payment-status` EDC extension |
| **Design** | [`PAYMENT_GATING.md`](PAYMENT_GATING.md) — three-stage rollout: **v0** privateProperties storage + JAX-RS update endpoint + request filter on transfer initiation + email notification to provider's finance contact + audit/obligation read endpoints; **v1** ODRL constraint functions (`payAmount`, `paymentStatus`, `dateTime`) so the policy is machine-evaluated; **v2** scheduled `DutyDeadlineEnforcer` that terminates overdue agreements via DSP `ContractNegotiationTermination`. Sequence: [`policies/diagrams/09-payment-gated-data-exchange.puml`](policies/diagrams/09-payment-gated-data-exchange.puml). |
| **Requires** | External billing/payment system (issues invoices, processes payment, calls back into the connector's payment-update endpoint). SMTP for v0 notifications. No new EDC fork — the extension lives alongside the existing controlplane build. |
| **When** | **After Milestone M1 is signed off** (regenerative-only + internal-use-only end-to-end). The M1 gate validates the auth, claims, policy-function, seeding, and UI infra that Phase 7.1 builds on; starting payment work earlier compounds risk. |
| **Governance handoff** | Refund obligation: connector records (immutable agreement + audit endpoints), Dataspace Authority adjudicates, external billing system executes. See [`PAYMENT_GATING.md` § 3.3](PAYMENT_GATING.md) and the cross-reference proposed in [`AUTHORITY.md` § D](AUTHORITY.md). |
| **Status** | [ ] v0 not started · [ ] v1 not started · [ ] v2 not started |

### 7.2 Verifiable Credentials integration

| Item | Detail |
|------|--------|
| **Task** | Replace Keycloak-based claims with W3C Verifiable Credentials for participant attributes |
| **Why** | VCs are the long-term standard for decentralised identity in dataspaces (aligned with Gaia-X, DSBA). Keycloak claims are a pragmatic prototype shortcut. |
| **Requires** | EDC Identity Hub configuration, VC issuance by the governance authority, updated policy functions to resolve from VCs instead of OIDC tokens |
| **When** | Phase following prototype, aligned with broader GLCDI scaling |
| **Status** | [ ] Not started |

### 7.3 Federated Catalogue policy metadata

| Item | Detail |
|------|--------|
| **Task** | Publish policy summaries as part of self-descriptions in the Federated Catalogue |
| **Why** | Allows participants to discover what terms apply to an asset before initiating contract negotiation — improving UX and reducing failed negotiations |
| **Requires** | Federated Catalogue deployment (currently deferred from governance stack) |
| **Status** | [ ] Not started |

### 7.4 Policy UI in participant dashboard

| Item | Detail |
|------|--------|
| **Task** | Add a policy management interface to the participant UI, allowing producers to select from pre-defined policy templates when publishing assets |
| **Why** | Currently policies are registered via API/scripts. A UI lowers the barrier for non-technical participants (ranchers). |
| **Requires** | `participant-ui` development |
| **Status** | [ ] Not started |

---

## Dependency Graph

```
Phase 1 (Vocabulary)
    │
    └──→ Phase 1.5 (Authority cleanup + identity simplification)
              │
              ├──→ Phase 2 (Keycloak Claims)
              │        │
              │        └──→ Phase 3 (EDC Policy Functions)
              │                    │
              │                    └──→ Phase 4 (Seeding Scripts)
              │                              │
              │                              ├──→ Phase 4.5 E (Bruno test suite) ─┐
              │                              │                                    │
              │                              └──→ Phase 5 (Integration Testing) ──┤
              │                                                                   │
              └──→ Phase 4.5 F (Participant UI)  ─────────────────────────────────┤
                                                                                  │
                                                                  🚦 Milestone M1 ←┘
                                                                                  │
                                                                                  └──→ Phase 7.1 (Payment, per PAYMENT_GATING.md)
                                                                                              │
                                                                                              └──→ Phase 7.2–7.4 (Other future enhancements)

Phase 6 (Governance / Legal) — runs in parallel with all technical phases,
                                aligned with Trust Framework v0→v1
```

**Concurrent agents at peak:** 3 (main implementation track, Bruno track 4.5.E, Participant-UI track 4.5.F).

## Relation to Main Project Phases

| This plan's phase | Maps to main project phase |
|-------------------|----------------------------|
| Phase 1 + 1.5 | Between Phase 1 (done) and Phase 2 (infra) — can start now; 1.5 absorbs the in-flight authority rename |
| Phase 2–3 | During Phase 2–3, before first deployment of the milestone scenario |
| Phase 4 | Replaces the simple policies in Phase 5 (seeding) — narrowed to M1 scope (regenerative-only + internal-use-only) |
| Phase 4.5 (E + F) | Parallel agent tracks; UI & test infra for the M1 demo |
| Phase 5 | Extends Phase 5 (integration testing); anchored on the M1 scenario |
| Milestone M1 | Demo gate; signed off before Phase 7.1 starts |
| Phase 6 | Parallel to all technical phases, aligned with Trust Framework v0→v1 |
| Phase 7.1 | Begins **after M1**; substages v0/v1/v2 per [`PAYMENT_GATING.md`](PAYMENT_GATING.md) |
| Phase 7.2–7.4 | Subsequent post-M1 enhancements (VC, Federated Catalogue, Policy UI) |
