# GLCDI Policy Support — Implementation Plan

Implementation steps to make the ODRL policies defined in `./policies/` operational in the
GLCDI dataspace. This covers vocabulary registration, Keycloak configuration, EDC extension
development, integration into seeding scripts, and testing.

Phases are ordered by dependency. Steps within a phase can largely be parallelised.

## TL;DR

GLCDI's path from today's single open-research policy to a fully enforced ODRL policy stack runs through eight phases plus a milestone gate, **with identity rolled out in tiers**: ship M1 on Tier 1 (the simplest viable shape), add Tier 2 if the MVP needs per-user accountability, and migrate to Tier 3 when decentralised identity becomes a priority.

**Identity tiering** (see [§ Identity Tiering Strategy](#identity-tiering-strategy) for the full picture):

- **Tier 1 (M1, this plan's default):** Authority Keycloak + 3 connector service accounts (one per org, `client_credentials` flow). UI authenticates to the local connector with `X-Api-Key` only — **no end-user OIDC anywhere**. Trust boundary is per-org; auditing is at org granularity.
- **Tier 2 (optional MVP improvement, post-M1):** add per-user OIDC at the UI layer, federated through the Authority Keycloak. Per-user audit and role-gated UI views. No change to connector ↔ connector trust.
- **Tier 3 (long-term):** decentralised identity — connectors present Verifiable Presentations (DCP/IATP); claims come from issued VCs rather than a central Keycloak. Removes the central-IdP dependency.

**Delivery order:**

1. **Phase 1 — Vocabulary & Namespace.** Register `glcdi:` JSON-LD context; agree on participant-type, certification-status, purpose taxonomies. Foundational; blocks Phase 3.
2. **Phase 1.5 — Identity (Tier 1) + Authority cleanup.** Complete the governance→authority rename (per [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md)); remove per-participant Keycloak from the participant compose stack; provision 3 connector service-account clients in the Authority Keycloak (`glcdi-connector-<org>`) with `glcdi_*` claims; UI runs on `X-Api-Key` only. **No end-user OIDC at this tier.**
3. **Phase 2 — Keycloak claims (on connector SAs).** Realm roles, attributes, protocol mappers so each connector's `client_credentials` token carries `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`, `glcdi_contribution_status`. Claims live on the SA users that back each connector client.
4. **Phase 3 — EDC policy functions.** Custom `AtomicConstraintFunction`s reading the claims above. ~200 LOC. § 3.5 swaps `iam-mock` for `iam-oauth2` against the Authority KC — **the gate to "real auth" between connectors**.
5. **Phase 4 — Seeding scripts.** Replace the current single `glcdi:policy:open-research` with per-asset access + contract policies — scoped initially to the M1 scenario.
6. **Phase 4.5 — Bruno test suite + Participant-UI configuration (parallel tracks).** (E) Bruno collection executing the M1 scenario non-interactively against the management API; (F) ship `participant-ui` in API-key-only mode for the asset/policy/contract/history components. Both run in parallel agents and feed Phase 5.
7. **Phase 5 — Integration testing.** Anchored on the M1 scenario: regenerative-producers-only access policy + internal-use-only contract policy, full positive and negative paths.
8. 🚦 **Milestone M1 — Regenerative-only access + internal-use-only contract, end-to-end demonstrable on Tier 1.** Gate before payment work starts.
9. **Phase 6 — Governance-level enforcement (proposal).** DSA clause wording, audit mechanism, consent-revocation procedure. Runs in parallel with the technical phases; ratification by the Dataspace Authority (see [`AUTHORITY.md`](AUTHORITY.md)).
10. **Phase 7.1 — Payment-required workflow.** v0/v1/v2 substages per [`PAYMENT_GATING.md`](PAYMENT_GATING.md). **Starts after M1 is signed off** — not before.
11. **Phase 7.2 — Identity (Tier 2): add user OIDC at the UI.** Optional MVP improvement: federated SSO via Authority KC, per-user audit, role-gated UI views. Schedulable in parallel with 7.1 once M1 ships.
12. **Phase 7.3 — Identity (Tier 3): decentralised claims via VC/DCP.** Long-term migration to Verifiable Credentials and the Decentralised Claims Protocol. Aligns GLCDI with Gaia-X / DSBA direction.
13. **Phase 7.4–7.5 — Other future enhancements.** Federated Catalogue policy metadata, participant-facing policy UI.

**Status (in-repo):** Phase 1 (vocabulary), Phase 1.5 (Tier-1 identity + rename), Phase 2 (Keycloak claims on connector SAs), and Phase 4.5 (Bruno + UI tracks) have substantive in-repo work in their working trees, blocked only on the staging cutover (Path-A re-import per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)). Phase 3 (EDC policy extension), Phase 4 (seeding scripts), Phase 5 (integration testing), and Milestone M1 are still to start. Phase 6 (governance / Trust Framework) runs in parallel and is owned outside this repo. Phase 7 (post-M1) — Tier 2 identity (7.2) and the VC migration (7.3) sit alongside payment (7.1) as candidate next workstreams once M1 is signed off.

**Parallelisation:** up to **3 concurrent agents** at peak — main implementation track (1.5 → 2 → 3 → 4 → 5 → M1 → 7.1), Bruno track (4.5 E), Participant-UI track (4.5 F). Phase 6 also runs in parallel with the technical phases.

**Dependency highlights:** Phase 1.5 (Tier-1 identity) blocks Phase 2 (claims now live on connector SAs in the Authority KC). Phase 3 depends on Phase 1's vocabulary. Phase 4 depends on Phases 2–3. Phase 4.5's two parallel tracks feed Phase 5. M1 gates payment. **Tier 2 (Phase 7.2) does not block M1** — it sits as an optional enhancement after the Tier-1 path ships. For cohort-by-cohort sequencing of *which* policies land *when*, see [`policies/plan.md`](policies/plan.md).

---

## Identity Tiering Strategy

The GLCDI prototype is sequenced so that the **simplest credible identity model ships first** — letting the policy/contract/transfer machinery prove itself end-to-end on Tier 1 — and richer identity is layered on only as the dataspace's governance and audit needs justify it. The three tiers are mutually compatible: each adds capability on top of the previous one without invalidating the work already shipped.

| Tier | Phase | What it covers | What it doesn't cover |
|------|-------|----------------|-----------------------|
| **Tier 1** — single-tier, connector-only | **Phase 1.5** (M1 default) | One Authority Keycloak. One `client_credentials` client + service account per participant connector (`glcdi-connector-<org>`), carrying `glcdi_*` claims. Connector ↔ connector trust via Authority-KC-signed JWTs (`iam-oauth2` post-§ 3.5). UI authenticates to the *local* connector with `X-Api-Key` only — **no end-user OIDC anywhere**. | Per-user identity in the UI; per-user audit ("which operator at caney-fork pressed negotiate?"); decentralised credential issuance. |
| **Tier 2** — add user OIDC at the UI | **Phase 7.2** (optional, post-M1) | Adds per-user OIDC at the UI layer, federated through the Authority KC (single realm, single `glcdi-ui` client). Per-user roles + audit; oauth2-proxy in front of `/management` validates user JWTs in addition to `X-Api-Key`. Connector ↔ connector trust unchanged from Tier 1. | Decentralised credential issuance; cross-dataspace identity portability. |
| **Tier 3** — decentralised claims via VC/DCP | **Phase 7.3** (long-term) | Connectors present Verifiable Presentations (W3C VCs, signed by issuers) instead of Authority-KC-issued JWTs. Identity Hub holds VCs; the Decentralised Claims Protocol (DCP / IATP) handles issuance and verification. Aligns GLCDI with Gaia-X / DSBA. | — |

### Why Tier 1 first

1. **Smallest surface to validate by M1.** The M1 scenario tests policy/contract/transfer behaviour, not authentication. Shipping Tier 1 means M1's pass/fail signal is about the policy stack, not about whether OIDC iframe redirects worked.
2. **Org-level claims are sufficient for the policies in scope.** Every M1-relevant claim (`glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`) is an organisation property, not a per-user one. Putting them on per-org SAs is the natural shape.
3. **Tier 2 is a clean addition.** Adding user OIDC later doesn't reshape the policy stack — it adds a layer in front of `/management` and a session story for the UI. The connector trust path doesn't change.
4. **Avoids duplicating work that will be replaced anyway.** Tier 3 (VC/DCP) eventually replaces the Authority KC as the *issuer* of connector credentials. Investing heavily in Tier-2 user OIDC scaffolding (per-participant brokering, IdP federation mappers) before M1 is investing in something Tier 3 will obsolete.

### When to graduate

- **From Tier 1 to Tier 2:** when an MVP stakeholder asks "who at caney-fork did this?" and the audit log answer ("someone with the API key") is no longer acceptable; or when role-gated UI views (different views for `data-steward` vs. `researcher` inside one org) become a product requirement.
- **From Tier 2 to Tier 3:** when GLCDI joins a multi-dataspace federation, when the Authority KC becomes a single point of trust failure that the governance body wants to dilute, or when alignment with Gaia-X / DSBA federation requirements becomes mandatory.

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
| **Status** | [x] Documented as proposal (this section) · [x] Encoded in [`context.jsonld`](context.jsonld) value aliases · [x] Realm roles + group/user attributes for the M1 subset (`producer`, `researcher`, `data-steward`, `regenerative-verified`, `not-applicable`) declared in `governance-services/resources/keycloak/realms/glcdi-realm.json` · [ ] Ratified by the Dataspace Authority |

### 1.3 Define ODRL purpose taxonomy

| Item | Detail |
|------|--------|
| **Task** | Formalise the set of purpose values that consumers can declare in contract offers |
| **Proposed values** | `InternalAnalysis`, `ScientificResearch`, `AgronomicModelTraining`, `EcosystemModelCalibration`, `RegionalBenchmarking`, `EducationalUse`, `ConservationPlanning`, `Scope3Reporting`, `ESGCompliance`, `CertificationVerification`, `ModelOutput` |
| **Why** | Purpose constraints in policies (e.g., `purpose-model-training.json`) rely on consumers declaring a purpose from this controlled vocabulary. Without agreement on the terms, policies cannot be consistently evaluated. |
| **Status** | [x] Documented as proposal (this section) · [x] Encoded in [`context.jsonld`](context.jsonld) value aliases (PascalCase per JSON-LD value-class convention) · [ ] Ratified by the Dataspace Authority |

---

## Phase 1.5: Identity (Tier 1) — Single-tier auth + Authority cleanup

Implements the **Tier 1** identity model defined in [§ Identity Tiering Strategy](#identity-tiering-strategy): one Authority Keycloak holding three connector service-account clients (one per participant org), `client_credentials` flow at startup to mint connector-bound JWTs carrying `glcdi_*` claims, and `X-Api-Key` as the *only* gate at the EDC management API. **No end-user OIDC anywhere — the UI is a per-org tool that authenticates to its local connector with the API key.** Bundled with the in-flight governance→authority rename whose operator checklist lives in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md).

### Why Tier 1 first (read-only spike summary)

A read-only spike across `participant-agent-services/`, `edc-connector/`, and `participant-ui/` confirmed the full two-tier OIDC stack inherited from the Hubl framework is **not load-bearing** for the M1 policy/contract/transfer scenario:

- **Connector ↔ connector trust** is what M1's policy stack actually exercises. It needs a JWT with `glcdi_*` claims; it does not need a per-user identity. A `client_credentials` token from Authority KC (one client per connector) carries exactly the right shape.
- **Management-API auth** is pluggable in EDC: `web.http.management.auth.type=tokenbased` + `X-Api-Key` works without any Bearer token. With the UI co-located with its connector behind a per-participant network boundary, the API key alone is the right gate at this tier.
- **Per-participant Keycloak** existed only to host the second tier of the Hubl two-tier flow. With user OIDC moved to Phase 7.2 (Tier 2), it is no longer needed at all in the participant compose stack.

The two-tier user-OIDC content is preserved verbatim in **[Phase 7.2: Identity (Tier 2)](#phase-72-identity-tier-2--add-user-oidc-at-the-ui)** as an optional MVP improvement that layers on top of Tier 1 without disturbing it.

### 1.5.1 Complete the governance → authority rename

Per [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md): finish the in-repo renames across `edc-connector/`, `governance-services/` (→ `authority-services/`), `participant-agent-services/`, `participant-ui/`, and the `management/` docs themselves. Operator checklist (DNS, TLS, live Keycloak path A vs. B, CI/CD variables, VM layout, cutover, post-cutover verification) is in that document.

**Status:** [x] In-repo edits across the 4 sibling repos done (edc-connector clean; participant-ui, participant-agent-services, governance-services swept); top-level `governance-services/` → `authority-services/` directory rename is a separate workspace-level `mv` · [x] `management/` doc-level sweep done (IDENTITY.md, IMPLEM_PLAN.md, README.md, AUTHORITY.md, etc.) · [ ] Operator-side cutover in staging (per [`DEPLOYMENT.md` § 2](DEPLOYMENT.md))

### 1.5.2 Remove per-participant Keycloak (and oauth2-proxy) from the participant compose stack

In `participant-agent-services/docker-compose.yml`: delete the `keycloak`, `postgres-kc`, **and `oauth2-proxy`** services along with the `keycloak-pg-data` volume. Remove `participant/keycloak/realms/edc-realm.json` and the related secrets templates (`participant/keycloak/.env.template`, etc.). Adjust the `nginx` service and any `depends_on` edges that pointed at `keycloak` or `oauth2-proxy`. Routes previously mediated by oauth2-proxy (`/oauth2/*`, `/management/*`) collapse: management traffic goes straight to the connector with `X-Api-Key`; `/oauth2/*` is gone.

> Operators who still want a defence-in-depth layer (basic-auth, IP allow-list, mTLS) in front of the catalogue UI host can add it at the Nginx layer — entirely orthogonal to the connector/policy stack and at the operator's discretion. **Adding user OIDC back is the Tier 2 path (§ 7.2).**

**Status:** [x] `keycloak` + `postgres-kc` services + volume removed · [x] `participant/keycloak/realms/edc-realm.json` deleted · [ ] `oauth2-proxy` service removed (Tier-1 cut) · [ ] Nginx routes collapsed (no `/oauth2/*`; `/management/*` proxied directly to connector) · [ ] Live volumes (`<stack>_keycloak-pg-data`) removed on each VM (per [`DEPLOYMENT.md` § 2.3](DEPLOYMENT.md))

### 1.5.3 `X-Api-Key` as the primary management-API auth

At Tier 1, **`X-Api-Key` is the *only* gate** at the EDC management API. There is no Bearer token in front of it; there is no oauth2-proxy. Programmatic clients (Bruno from § 4.5.E, seeding scripts from § Phase 4) and the catalogue UI all use the same key.

Operator hardening checklist:

- Rotate `web.http.management.auth.key`, `edc.api.auth.key`, `edc.api.control.auth.apikey.value` from the `123456` / `password` example defaults — per the [`CLAUDE.md`](../../CLAUDE.md) "Things that will bite you" callout. Use `openssl rand -hex 32` per key, propagate via `participant/configuration.properties` on each VM, distribute to UI operators out-of-band.
- The key is **per-participant**, not shared across the dataspace. Each participant rotates independently.
- For "API key in the browser is a bad look in production" — yes, the trust boundary is the per-participant network. Treat the catalogue UI as an internal tool. If that boundary is too weak for a given operator, add basic-auth or VPN at Nginx (see § 1.5.2 callout) or graduate to Tier 2 (§ 7.2).

**Status:** [x] Documented in [`DEPLOYMENT.md` § 1, § 2.5, § 3.7](DEPLOYMENT.md); Bruno's `99-negative-auth/*.bru` covers the negative cases · [ ] Operator rotates the three API keys from `123456` defaults on each VM · [ ] Live verification: Bruno green run against staging

### 1.5.4 Provision connector service-account clients in the Authority Keycloak

This is the single piece of Authority-KC config that Tier 1 actually requires: **one OAuth2 client per participant connector**, with `client_credentials` enabled and `glcdi_*` claims attached to the client's service-account user. Tokens minted via this flow are what each connector presents at DSP time once `iam-oauth2` replaces `iam-mock` in § 3.5.

In the Authority KC's `glcdi` realm (declarative — already in `governance-services/resources/keycloak/realms/glcdi-realm.json`):

| Client | Service-account user | Realm roles | `glcdi_membership` | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|--------|----------------------|-------------|---------------------|----------------------|------------------------------|-----------------------------|
| `glcdi-connector-caney-fork` | `service-account-glcdi-connector-caney-fork` | `glcdi_member`, `glcdi_regenerative_producer` | `active` | `caney-fork` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-white-buffalo` | `service-account-glcdi-connector-white-buffalo` | `glcdi_member`, `glcdi_regenerative_producer` | `active` | `white-buffalo` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-point-blue` | `service-account-glcdi-connector-point-blue` | `glcdi_member`, `glcdi_researcher` | `active` | `point-blue` | `not-applicable` | `observer` |

- Each client has `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false` — strict client_credentials only.
- Each client carries the `glcdi-claims` client scope (§ 2.3) on its `defaultClientScopes` so all five mappers fire.
- Realm role assignment lives on the SA user record; user attributes (cert / contribution status) likewise. Stock Keycloak doesn't surface client-level attributes via standard mappers, so SA-user attributes are the supported path. (Tier 2 promotes some of these to per-org *groups* with human users — see § 7.2.)

**Casing convention** (referenced by §§ 2, 3.4):

- Attribute *values* (certification statuses, contribution statuses, participant types): lowercase / kebab-case — e.g. `regenerative-verified`, `not-applicable`, `contributing`, `observer`. Matches the policy JSON in `policies/` and the JSON-LD context in [`context.jsonld`](context.jsonld).
- Realm role names: snake_case with `glcdi_` prefix (Keycloak / OAuth convention) — e.g. `glcdi_regenerative_producer`. The participant-type policy function (§ 3.3) maps `kebab-case` → `glcdi_<snake_case>` transparently.
- Purpose taxonomy values: PascalCase per § 1.3 — `InternalAnalysis`, `ScientificResearch`, ….

**Adding a new participant** at Tier 1 = Authority operator creates a new `glcdi-connector-<org>` client + SA in the realm JSON (or via admin console), assigns the right roles + attributes, sends `client_id` / `client_secret` to the new participant out-of-band; the participant operator drops them into `participant/configuration.properties` (`edc.oauth.client.id` / `edc.oauth.client.secret.alias`) per § 3.5.

**Status:** [x] Realm JSON declares the 3 connector clients + 3 SA users with role + attribute assignments — see [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md) for the breakdown · [ ] Imported into live Authority KC (Path A re-import) · [ ] Per-org connector secrets rotated from `changeme-*` placeholders and propagated to each participant VM's `.env`

### 1.5.5 Sanity-check DSP-level identity is still working

After the cuts above, run a smoke-test contract negotiation between two participant connectors. Pre-§ 3.5 (still on `iam-mock`): expected behaviour is unchanged — fixed claims, negotiation reaches `FINALIZED` regardless. Post-§ 3.5 (`iam-oauth2`): each connector authenticates to Authority KC at startup via its `glcdi-connector-<org>` client_credentials, the JWT carries that org's `glcdi_*` claims, the remote connector validates against Authority KC's JWKS, negotiation reaches `FINALIZED` and access policies are evaluated against the real claims for the first time.

**Status:** [ ] Pre-§ 3.5 smoke (iam-mock) — runs after staging cutover, tracked in [`DEPLOYMENT.md` § 2.5](DEPLOYMENT.md) · [ ] Post-§ 3.5 verification (iam-oauth2 + real claims)

### 1.5.6 Auth flow & credentials reference (Tier 1)

For future contributors and the Track-E/F agents in § 4.5: the Tier-1 credential model is deliberately minimal. **One credential at the management-API edge, one credential at the DSP edge, no users in any KC.**

**UI / operator API calls (Tier 1 — pure API key):**

```
Operator user at <org> (no identity in any Keycloak)
  ↓ opens https://<org>.glcdi.startinblox.com/ in a browser
  ↓ pastes / has stored an X-Api-Key value
Catalogue UI (browser)
  ↓ X-Api-Key on every management-API call
Nginx (reverse proxy at the participant VM)
  ↓ proxies straight to connector — no oauth2-proxy
EDC management API (X-Api-Key gate; tokenbased auth type)
  ↓ admin operations (asset / policy / contract-definition CRUD, transfer initiation)
EDC connector
```

There is no Bearer token, no Authority KC redirect, no IdP brokering, no silent-callback iframe — none of those exist at Tier 1.

**DSP-level (connector ↔ connector) traffic — Tier 1 final shape after § 3.5:**

```
Connector A startup (e.g. point-blue's connector)
  ↓ client_credentials grant against Authority KC
  ↓   client_id     = glcdi-connector-point-blue
  ↓   client_secret = (vault-stored)
Authority KC issues an OIDC token carrying the SA's claims
  ↓   glcdi_membership = active
  ↓   glcdi_roles      = [glcdi_member, glcdi_researcher]
  ↓   glcdi_organisation = point-blue
  ↓   glcdi_certification_status = not-applicable
Connector A caches the token; refreshes before expiry
  ↓ initiates a DSP request to Connector B (e.g. catalog query)
Connector B receives DSP request with Authorization: Bearer <token>
  ↓ iam-oauth2 validates signature against Authority KC JWKS
  ↓ extracts glcdi_* claims into ClaimToken / ParticipantAgent
EDC policy engine on Connector B evaluates the access policy against those claims
  ↓ regenerative-producers-only filter applied → asset visible / hidden accordingly
```

**Pre-§ 3.5 the DSP path runs on `iam-mock`** — tokens accepted without verification; fixed claims returned. § 3.5 (`iam-mock` → `iam-oauth2`) is the **single load-bearing gate to "real auth" between connectors**. Before it, all of M1's policy filtering uses the mock's fixed claims and is therefore not exercising real authentication.

**Role of each credential at Tier 1:**

| Credential | What it gates | Required for |
|------------|---------------|--------------|
| **`X-Api-Key`** (per participant connector) | EDC management-API access | **Every** management-API call (UI, Bruno, seeding scripts). The only gate at this edge at Tier 1. |
| **Authority-KC-issued JWT** (one per connector, minted via `glcdi-connector-<org>` `client_credentials`) | Identity at the DSP layer; carries `glcdi_*` claims into the receiving connector's policy engine | DSP traffic between connectors, post § 3.5. Connectors mint and refresh themselves; operators never handle these tokens. |

**For Bruno (§ 4.5.E):** at Tier 1, `X-Api-Key` only. Identity-driven scenario steps (catalog query as researcher, negotiation as a specific org) are tested by running each step from the connector that already *is* that org — no token gymnastics required. Optional: mint a token via `client_credentials` against `glcdi-connector-<org>` to assert claim shape directly, but this is debugging, not the test path.

**For seeding scripts (§ Phase 4):** `X-Api-Key` only — admin operations on the local connector.

**For DCP/IATP-shaped config** (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.token.url=http://identity-hub:7084/sts/token`): not used at Tier 1 or Tier 2 — that is the Tier-3 long-term direction (§ 7.3). The Identity Hub stays in the compose to keep the migration path open, but is not on the M1 critical path.

**Status:** [x] Design captured (this sub-section is documentation; no implementation work)

### Dependencies & risks

- **Blocks Phase 2** — claims now live on the 3 connector SAs in the Authority KC.
- **Coordinates with [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md)** — the operator-side rename and the topology simplification benefit from a single deploy window per participant.
- **§ 3.5 (iam-mock → iam-oauth2) is the load-bearing gate.** Until it ships, Tier 1's claims are wired but not enforced — the receiving connector still trusts mock tokens. Treat § 3.5 as part of the Tier-1 critical path, not an afterthought.
- **Trust boundary at the catalogue UI is the per-participant network.** If a stakeholder pushes back on "API key in the browser," the answer is either (a) add basic-auth/VPN at Nginx — orthogonal to the connector stack — or (b) graduate to Tier 2 (§ 7.2). Do not introduce ad-hoc Bearer-token plumbing at Tier 1.
- **No remaining architectural unknowns** after the spike. Risk is operational: cutover sequencing, API-key rotation, and the § 3.5 swap.

---

## Phase 2: Keycloak Claims Configuration — Connector Service-Account Tokens

Policies like `members-only`, `regenerative-producers`, and `researchers-only` evaluate claims from
the consumer's identity token. **At Tier 1 the consumer is a connector** — claims live on the
Keycloak service-account user that backs each `glcdi-connector-<org>` client (§ 1.5.4), and reach
the receiving connector's policy engine via the Authority-KC-issued JWT minted at startup. Verifiable
Credentials (the long-term replacement) are out of scope at this tier — see [§ Phase 7.3](#phase-73-identity-tier-3--decentralised-claims-via-vc--dcp).

### Architecture decision: where the claims live

Two Keycloak surfaces can carry participant attributes into a token. At Tier 1 each connector's
*service-account user* is the carrier:

| Surface | How it works at Tier 1 | When to use |
|---------|------------------------|-------------|
| **Realm roles** assigned to the SA user | Roles like `glcdi_member`, `glcdi_regenerative_producer`. Inherited automatically into the token's `realm_access.roles`; surfaced as a clean `glcdi_roles` array via § 2.3 mapper 1. | Participant-type membership: which type buckets does this org belong to? Multi-valued, naturally fits a role list. |
| **User attributes** on the SA user | Key/value pairs on the SA user record (`glcdi_certification_status=regenerative-verified`). Surfaced via `oidc-usermodel-attribute-mapper` entries — § 2.3 mappers 2–2b. | Structured single-valued state: certification status, contribution status, organisation slug. |

**Why SA users, not client attributes:** stock Keycloak's standard mappers read user-level fields
only — there is no built-in `oidc-client-attribute-mapper`. Each client's SA *is* a user record,
so attribute-based mappers Just Work without custom mappers or admin extensions.

**Tier 2 / Tier 3 forward look:** Tier 2 (§ 7.2) introduces *human* users who join per-org groups
that carry the same role/attribute shape — the mappers in § 2.3 are unchanged. Tier 3 (§ 7.3)
moves the issuance off Keycloak entirely; § 2.7's claim → constraint table survives because the
policy functions only see claim *names*, not the issuer.

### 2.1 Create GLCDI realm roles

| Item | Detail |
|------|--------|
| **Task** | Add realm roles to the `glcdi` realm in Authority Keycloak |
| **Roles to create** | `glcdi_member` (active membership), `glcdi_regenerative_producer`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder` |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — in the `roles.realm[]` array |
| **Status** | [x] Declared in realm JSON (13 roles total: 2 inherited + 11 GLCDI) · [ ] Imported into live Authority KC (per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)) |

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
| **Task** | Define `glcdi_certification_status` and `glcdi_contribution_status` as custom user attributes on each connector service-account user |
| **Certification values** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Contribution values** | `contributing` (has published data), `observer` (onboarded but no data published yet), `pending` (awaiting verification) |
| **Where** | Set on each `service-account-glcdi-connector-<org>` user in the realm JSON (`users[].attributes`). Adding a fourth participant = new connector client + SA user with the same attribute shape. |
| **Proposed owner for contribution status** | For the prototype (small participant set): it is proposed that the Dataspace Authority sets this manually after verifying that a participant's connector has published assets. For scaling: a periodic automated service could query each participant's catalog and update the attribute. |
| **Status** | [x] Declared on the 3 connector SA users in the realm JSON · [ ] Imported into live Authority KC (per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)) |

### 2.3 Create protocol mappers for token serialisation

Realm roles are already included in tokens by default (in `realm_access.roles[]`), but we need
explicit mappers to surface claims in the format the EDC policy functions expect.

| Item | Detail |
|------|--------|
| **Task** | Add protocol mappers to relevant Keycloak clients so that GLCDI claims appear as top-level claims in access tokens |
| **Approach** | Realm-level **client scope** `glcdi-claims` carries all five mappers (one for `glcdi_roles` from realm roles; four `oidc-usermodel-attribute-mapper` entries for `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`). The scope is added to `defaultClientScopes` on each `glcdi-connector-<org>` client at Tier 1 (and on the future `glcdi-ui` client at Tier 2 — see § 7.2). No per-client mapper duplication. |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — `clientScopes[]` array (the `glcdi-claims` scope) plus `defaultClientScopes` on each consuming client. |
| **Status** | [x] `glcdi-claims` client scope declared (5 mappers) · [x] Wired into `defaultClientScopes` on the 3 connector clients · [ ] Imported into live Authority KC (per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)) |

**Five mappers in the `glcdi-claims` client scope (declarative, in the realm JSON):**

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

### 2.4 Assign roles + attributes to the connector service-account users

| Item | Detail |
|------|--------|
| **Task** | Each `service-account-glcdi-connector-<org>` user in the realm JSON carries that org's realm roles directly and the `glcdi_membership` / `glcdi_organisation` / `glcdi_certification_status` / `glcdi_contribution_status` attributes. The realm JSON is the source of truth; live edits go through the admin console. |
| **Status** | [x] Declared in realm JSON: 3 connector clients + 3 SA users with role + attribute assignments · [ ] Imported into live Authority KC (per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)) |

The Tier-1 assignment for the M1 prototype cluster (already encoded in `governance-services/resources/keycloak/realms/glcdi-realm.json`):

| SA user | Realm roles | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|---------|-------------|----------------------|------------------------------|-----------------------------|
| `service-account-glcdi-connector-caney-fork` | `glcdi_member`, `glcdi_regenerative_producer` | `caney-fork` | `regenerative-verified` | `contributing` |
| `service-account-glcdi-connector-white-buffalo` | `glcdi_member`, `glcdi_regenerative_producer` | `white-buffalo` | `regenerative-verified` | `contributing` |
| `service-account-glcdi-connector-point-blue` | `glcdi_member`, `glcdi_researcher` | `point-blue` | `not-applicable` | `observer` |

The proposed assignment *pattern* by participant type (for new onboardings beyond the M1 trio):

| Participant type | Realm roles | Cert status | Contribution status |
|------------------|-------------|-------------|---------------------|
| Regenerative producer | `glcdi_member`, `glcdi_regenerative_producer` | `regenerative-verified` | `contributing` (after seeding) |
| Producer (non-regen) | `glcdi_member`, `glcdi_producer` | per declared status | `contributing` (after seeding) |
| Research institution | `glcdi_member`, `glcdi_researcher` | `not-applicable` | `contributing` (after seeding) |
| Data steward / monitoring alliance | `glcdi_member`, `glcdi_data_steward` | `not-applicable` | `observer` (until data published) |
| Newly onboarded (any type, no data yet) | `glcdi_member` + type role | per declared type | `observer` (until data published) |

**Live edit recipe** (post-import attribute tweaks via admin console — keep the realm JSON in sync afterwards):

```bash
KEYCLOAK_URL="https://authority.glcdi.startinblox.com"
REALM="glcdi"

# Get admin token
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq -r '.access_token')

# Resolve the SA user ID (example: caney-fork's connector)
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users?username=service-account-glcdi-connector-caney-fork" \
  | jq -r '.[0].id')

# Update the certification status attribute (e.g. promotion to regenerative-verified)
curl -s -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID" \
  -d "{\"attributes\": {\"glcdi_certification_status\": [\"regenerative-verified\"]}}"
```

### 2.5 Verify token contents

| Item | Detail |
|------|--------|
| **Task** | Confirm that tokens issued by Authority Keycloak contain the expected GLCDI claims |
| **Status** | [ ] Not started |

**Manual verification** (mint a token for a connector SA via `client_credentials` and decode):

```bash
# Request a token for a connector service account
TOKEN=$(curl -s -X POST \
  "https://authority.glcdi.startinblox.com/auth/realms/glcdi/protocol/openid-connect/token" \
  -d "client_id=glcdi-connector-caney-fork" \
  -d "client_secret=<rotated-from-changeme-glcdi-connector-caney-fork-secret>" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Decode and inspect (JWT is base64-encoded, middle segment is the payload)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**Expected output (relevant claims):**

```json
{
  "iss": "https://authority.glcdi.startinblox.com/auth/realms/glcdi",
  "sub": "<sa-user-uuid>",
  "azp": "glcdi-connector-caney-fork",
  "glcdi_membership": "active",
  "glcdi_organisation": "caney-fork",
  "glcdi_roles": ["glcdi_member", "glcdi_regenerative_producer"],
  "glcdi_certification_status": "regenerative-verified",
  "glcdi_contribution_status": "contributing",
  "realm_access": {
    "roles": ["glcdi_member", "glcdi_regenerative_producer", "user", "default-roles-glcdi"]
  }
}
```

### 2.6 Mapping from token claims to policy constraints

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

### 2.7 Integration with the onboarding flow (Tier 1: out-of-band)

| Item | Detail |
|------|--------|
| **Task** | At Tier 1, onboarding a new participant is **out-of-band**: the Authority operator extends the realm JSON with a new `glcdi-connector-<org>` client + SA user (same shape as § 2.4) and ships the secret to the participant operator via a side channel. No automated user-creation API is needed at this tier — there are no human users to provision. |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — append to `clients[]` and `users[]`. After import, also distribute the rotated `client_secret` via a vault / out-of-band channel for the participant's `participant/configuration.properties`. |
| **Status** | [ ] Not started — first new onboarding post-M1 will exercise this |

**Tier-1 onboarding sequence** (to be ratified by the Dataspace Authority):

1. Participant submits onboarding request (name, organisation, type, certification evidence).
2. The Dataspace Authority reviews and approves.
3. On approval, the Authority operator:
   - Adds a `glcdi-connector-<new-org>` client (with `serviceAccountsEnabled: true`, `glcdi-claims` default scope) and its SA user (with the right `glcdi_*` realm roles + attributes) to the realm JSON.
   - Imports / patches the live realm (admin console for a single client; Path B re-import for a batch — see [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)).
   - Rotates the placeholder secret and ships `client_id` / `client_secret` to the participant operator via vault / out-of-band channel.
4. The participant operator drops `client_id` / `client_secret` into `participant/configuration.properties` (`edc.oauth.client.id` / `edc.oauth.client.secret.alias` per § 3.5) and restarts the connector.

> **Tier-2 evolution:** when human-user onboarding becomes a requirement (per-user audit, role-gated UI views), the onboarding-app workflow described in § 7.2 takes over: the DjangoLDP approval UI calls the Keycloak Admin API to create human users in the org's group. The connector-SA flow above continues unchanged underneath.

---

## Phase 3: EDC Policy Extension Development

### 3.0 `edc-glcdi-extension` repository scaffolding

| Item | Detail |
|------|--------|
| **Task** | Set up the GLCDI-owned extension repository as a sibling of `edc-connector/`, following the DS4GO pattern (separate repo, build-time symlinked or path-referenced from the connector's controlplane build). |
| **Why a separate repo (not `edc-connector/extensions/`)** | Keeps GLCDI-owned Java code separate from the EDC fork (which tracks upstream). Independent versioning + git history. Mirrors `ds4go/edc-dsif-extension/` next to `ds4go/edc-connector/`. |
| **Layout (proposed)** | `edc-glcdi-extension/extensions/glcdi-policy-functions/` (the membership / participantType / certificationStatus functions of §§ 3.2–3.4) — first occupant. Future siblings (e.g. `payment-status-extension/` from [`PAYMENT_GATING.md`](PAYMENT_GATING.md), if Phase 7.1 lands) live under the same `extensions/` folder. |
| **Wire-up** | `edc-connector/runtimes/controlplane/build.gradle.kts` references the extension via relative path or via a CI symlink step that puts the extension into `edc-connector/extensions/`. Match whichever pattern this team's CI uses for DS4GO. |
| **Status** | [x] Repo created · [x] First extension scaffolded (§ 3.1) — `glcdi-policy-functions/` with build files + SPI entry + package skeleton + the three constraint-function classes + `GlcdiClaims` constants + `GlcdiPolicyFunctionsExtension` registration class + a starter unit-test class · [ ] Wired into the controlplane runtime (§ 3.6) |



The EDC connector needs custom policy functions to evaluate GLCDI-specific constraints.
Without these, constraints referencing `glcdi:membership` or `glcdi:participantType` will be
silently ignored (default: permit) or fail closed, depending on EDC configuration.

### 3.1 Create `glcdi-policy-functions` extension

| Item | Detail |
|------|--------|
| **Task** | Create a new EDC extension in `edc-glcdi-extension/extensions/glcdi-policy-functions/` (sibling repo, mirrors DS4GO's `edc-dsif-extension/` pattern — not inside the `edc-connector/` fork) |
| **Language** | Java 17 |
| **Build** | `settings.gradle.kts` includes the module; `extensions/glcdi-policy-functions/build.gradle.kts` depends on `edc.spi.core`, `edc.spi.policy`, `edc.spi.policy-engine`, `edc.runtime.metamodel`. Tests use JUnit 5 + AssertJ + Mockito |
| **Layout** | `src/main/java/com/startinblox/glcdi/edc/extension/policy/` (package); `src/main/resources/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension` lists `GlcdiPolicyFunctionsExtension` |
| **Status** | [x] Repo scaffolded (`edc-glcdi-extension/` root build, settings, gradle.properties, libs.versions.toml, .gitignore, README) · [x] Module scaffolded (`extensions/glcdi-policy-functions/`: build.gradle.kts, README, META-INF SPI entry, package directories) · [ ] Gradle wrapper bootstrapped (`gradle wrapper` once Gradle is installed locally) · [ ] First successful `./gradlew build` |

### 3.2 Implement membership policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:membership` |
| **Behaviour** | Extract the `glcdi_membership` claim from the participant's identity (via `ParticipantAgent`), compare it to the constraint's `rightOperand` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/membership"` |
| **Used by** | `access/members-only.json`, `access/regenerative-producers.json`, `access/researchers-only.json`, and all combined policies |
| **Status** | [x] `MembershipConstraintFunction.java` drafted (EQ + NEQ; logs and returns `false` when ParticipantAgent is missing or the claim is absent) · [x] Starter unit-test class `MembershipConstraintFunctionTest.java` covers match / mismatch / no-agent / claim-missing / unsupported-operator paths · [ ] Compiled against pinned EDC SPI (verifies API: `org.eclipse.edc.spi.iam.ParticipantAgent`, `AtomicConstraintRuleFunction`, `PolicyContext.getContextData(...)`) |

### 3.3 Implement participant type policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:participantType` |
| **Behaviour** | Reads the `glcdi_roles` claim (list); maps the kebab-case `participantType` value to the snake-case role name (`glcdi_<type>`) and tests membership in the participant's role set. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/participantType"` |
| **Used by** | `access/regenerative-producers.json`, `access/researchers-only.json`, `combined/corporate-supply-chain.json` |
| **Status** | [x] `ParticipantTypeConstraintFunction.java` drafted with `toRoleName(...)` kebab→snake helper; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [x] Resilient parsing for claims arriving as a `Collection` or comma-separated `String` · [ ] Unit tests (deferred per § 5.1) · [ ] Compiled against pinned EDC SPI |

### 3.4 Implement certification status policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:certificationStatus` |
| **Behaviour** | Extract `glcdi_certification_status` claim (string, lowercase / kebab-case per § 1.5.4); compare to the constraint's `rightOperand`. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/certificationStatus"` |
| **Used by** | `access/regenerative-producers.json` |
| **Status** | [x] `CertificationStatusConstraintFunction.java` drafted; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [ ] Unit tests (deferred per § 5.1) · [ ] Compiled against pinned EDC SPI |

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
edc.oauth.client.id=glcdi-connector-<this-org>          # e.g. glcdi-connector-caney-fork (per § 1.5.4)
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
| **Task** | Wire `glcdi-policy-functions` (sourced from the `edc-glcdi-extension/` sibling repo) into `edc-connector/`'s build, so every connector image rebuild includes the GLCDI custom extensions automatically — mirrors DS4GO's `edc-dsif-extension` → `edc-connector/extensions/` cp-step pattern |
| **Deliverable** | Rebuilt connector image (published to `registry.startinblox.com/applications/glcdi/edc-connector/controlplane`) carries the GLCDI extensions in its shadowJar; participants pulling the image at `docker compose up -d` time get them automatically |
| **Pattern** | At CI time (or via local helper script): clone `edc-glcdi-extension`, copy its `extensions/<name>/` directories into `edc-connector/extensions/`, run the standard Gradle build. The copies are not tracked in `edc-connector` git (added to `.gitignore` as `extensions/glcdi-*`) so the fork stays clean of GLCDI-specific code that lives upstream. |
| **Status** | [x] `edc-connector/gradle/libs.versions.toml`: added `edc-spi-policy-engine` + `edc-runtime-metamodel` aliases (both required by the extension build) · [x] `edc-connector/settings.gradle.kts`: added `include(":extensions:glcdi-policy-functions")` · [x] `edc-connector/runtimes/controlplane/build.gradle.kts`: added `runtimeOnly(project(":extensions:glcdi-policy-functions"))` · [x] `edc-connector/.gitignore`: ignores `extensions/glcdi-*` (synced from sibling repo, not tracked) · [x] `edc-connector/.gitlab-ci.yml`: `before_script` clones `edc-glcdi-extension` (auth via `CI_JOB_TOKEN`, branch override via `EDC_GLCDI_EXTENSION_BRANCH`) and copies its extensions into `./extensions/` ahead of every Gradle/Kaniko step · [x] `edc-connector/scripts/sync-glcdi-extensions.sh`: local-dev helper (looks for `../edc-glcdi-extension/` by default; override with `EDC_GLCDI_EXTENSION_DIR`) · [ ] First successful CI build with the extension in place · [ ] Job-token permission granted on `edc-glcdi-extension` repo (Settings → CI/CD → Job token permissions → allow `edc-connector`) |

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
- **Tier-2-only negative auth** (skipped at Tier 1): no Bearer / wrong Bearer → expect `401` from oauth2-proxy.

**Auth context — tiered:**

- **Tier 1 (M1 default, `tier=tier1`):** `X-Api-Key` only on every `/management` call — the only gate at this edge (see § 1.5.3 and § 1.5.6). Identity-driven scenarios (catalog query as researcher, negotiation as a specific org) are tested by **running each step from the connector that already is that org** — point-blue's connector queries caney-fork's catalog as point-blue, no Bearer-token gymnastics. The connector's own `client_credentials` token (per § 1.5.4) carries the right `glcdi_*` claims into the receiving connector via `iam-oauth2` (post-§ 3.5).
- **Tier 2 (post-§ 7.2, `tier=tier2`):** the same `/management` calls additionally carry `Authorization: Bearer <connector-SA token>`. The Bearer header is injected by the **collection-level pre-request script** in `bruno/collection.bru` — individual `.bru` files don't change between tiers. Bruno automation uses connector-SA tokens (from 00-auth/) rather than per-user OIDC; oauth2-proxy validates "any token signed by Authority KC", which is sufficient for test traffic.
- **00-auth/** is the **diagnostic claim-shape check** at both tiers: mint a connector-SA token via `client_credentials`, decode the JWT, assert the `glcdi_*` claim shape (per § 2.5). At Tier 1 the captured tokens are not used downstream; at Tier 2 the collection-level script reuses them as Bearer values.

Bruno runs against either a single participant's connector locally, or against the staging URLs (`caney-fork.glcdi.startinblox.com`, `point-blue.glcdi.startinblox.com`, `white-buffalo.glcdi.startinblox.com`).

**Owner:** parallel agent. Can begin drafting once §§ 1.5.3–1.5.4 fix the API-key contract and the per-org client_credentials shape; doesn't strictly need Phases 2–4 to run, only to be runnable green.

**Status:** [x] Tiered skeleton in [`bruno/`](bruno/) — 19 files: collection metadata, **collection-level pre-request script** (`collection.bru`) for Tier-2 Bearer injection, 2 environments (local + staging) with `tier` selector, 6 folders covering the M1 scenario plus 2 extra Tier-2-only negative-auth cases · [x] Role-corrected per the M1 resolution (white-buffalo positive, point-blue filtered) · [x] Tier-1 default (X-Api-Key only) and Tier-2 anticipated (Bearer auto-injected) — single source, switch via env var · [ ] Polling files for state-machine assertions (FINALIZED / TERMINATED / STARTED) — TODO inside the relevant `.bru` files · [ ] Pre-request script that fetches the offer from the catalog response and uses it verbatim in the negotiation body — TODO · [ ] Green run against staging at Tier 1 (gated on Phase 1.5 cutover + Phases 2–4) · [ ] Green run at Tier 2 (additionally gated on Phase 7.2)

### 4.5.F Participant-UI configuration (Track F — parallel agent)

Adapt `participant-ui/` for the **Tier 1** topology — API-key login only, no OIDC envvars, no `LINKED_PROVIDER_*`, no silent-callback iframe:

- Strip OIDC plumbing from `docker-entrypoint.sh` and `config.json.template`: remove `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OIDC_CLIENT_ID`, `KC_IDP_HINT`, `LINKED_PROVIDER_*`, `LINKED_PROVIDER_SILENT_REDIRECT_URI`. Remove `silent-callback.html` from the served paths. Drop the `sib-auth-linked-provider` widget from the Hubl config.
- Implement **API-key login** as the only entry path — operator pastes an `X-Api-Key` value that the UI uses for every management-API call. Trust boundary is the per-participant network (see § 1.5.3); flag clearly in the UI copy that the key is *not* a per-user credential.
- Keep the existing `config.json`-driven asset / policy / contract / history components — they don't need OIDC.
- Surface the missing **transfer-process management** component (`tems-transfer-processes-management` or equivalent) needed by the M1 scenario.
- Confirm theme/branding still renders correctly per-participant (the runtime-configurable single image continues to work).

> **Tier-2 forward look:** Phase 7.2 reintroduces the OIDC plumbing for federated user login. The work in this track is to land Tier 1 cleanly first; the Tier-2 envvars / silent-callback come back in a controlled way under that phase.

**Owner:** parallel agent. **Read-only audit first** (already complete — see status), then strip-down implementation.

**Status:** [x] Read-only audit complete (Track F findings: 4 components configured, env vars + linked-provider mapped, silent-callback path served by Hubl/nginx, transfer-process component absent) · [ ] Strip OIDC envvars from `docker-entrypoint.sh` and `config.json.template` (Tier-1 cut) · [ ] Drop `sib-auth-linked-provider` widget + `silent-callback.html` from served paths · [ ] API-key-only login implemented — operator pastes the value at first load; UI stores it (`localStorage.glcdi_operator_api_key`) and attaches it as `X-Api-Key` on every management-API call · [ ] Add `tems-transfer-processes-management` (or equivalent) component to `config.json.template` · [x] README rewritten with single-tier architecture + "PROTOTYPE: API-key-only login" subsection (will need a follow-up update after the strip-down lands)

### Dependencies

- Both tracks **depend on § 1.5** (Tier-1 identity simplification) being landed in at least one staging participant.
- 4.5.E benefits from Phases 2–4 being further along (so the test-suite assertions match real seeded data) but can be drafted in parallel against expected behaviour.
- 4.5.F's strip-down can begin **immediately**; field-tested once § 1.5 is in staging.

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

## 🚦 Milestone M1: Regenerative-Only Access + Internal-Use-Only Contract — End-to-End on Tier 1

**Gate before Phase 7.1 (Payment-required workflow) starts.** M1 ships on **Tier 1 identity** (§ Identity Tiering Strategy) — `iam-oauth2` between connectors, `X-Api-Key` on the UI, no end-user OIDC. Tier 2 (§ 7.2) and Tier 3 (§ 7.3) sit as post-M1 candidate workstreams; neither is required for M1 sign-off.

M1 is demonstrable when, against a deployed three-participant cluster — **`caney-fork`** (regenerative producer, provider), **`white-buffalo`** (regenerative producer, positive consumer), **`point-blue`** (researcher, negative-test consumer) — the following all pass:

- [ ] Authority Keycloak has 3 connector clients + service-account users (per § 1.5.4):
  - `glcdi-connector-caney-fork` and `glcdi-connector-white-buffalo`: SAs carry `glcdi_member`, `glcdi_regenerative_producer` realm roles and `glcdi_certification_status = regenerative-verified`.
  - `glcdi-connector-point-blue`: SA carries `glcdi_member`, `glcdi_researcher` realm roles and `glcdi_certification_status = not-applicable`.
  - All 3 clients have `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false` and the `glcdi-claims` default scope.
- [ ] `iam-oauth2` is wired in each participant's connector (§ 3.5) against Authority KC. A `client_credentials` token mint at startup decodes to a JWT carrying the org's `glcdi_*` claims (verified per § 2.5).
- [ ] `caney-fork` connector publishes an asset whose **access policy** is `regenerative-producers-only` (Phase 4) and whose **contract policy** is `internal-use-only` (Phase 4).
- [ ] `white-buffalo` (regen producer) sees the asset in the catalog query against `caney-fork`. **Positive case.**
- [ ] `point-blue` (researcher) does **not** see the asset in the catalog query — filtered out by the access policy. **Negative case (the policy is doing its job).**
- [ ] `white-buffalo` negotiates with `caney-fork` declaring `purpose = InternalAnalysis` → reaches `FINALIZED`. With a different purpose → reaches `TERMINATED`.
- [ ] Transfer succeeds against the agreed contract (`white-buffalo` ← `caney-fork`).
- [ ] The Bruno collection (§ 4.5.E) executes all of the above non-interactively against the management API with `X-Api-Key` only — green run.
- [ ] The participant UI (§ 4.5.F) surfaces asset / policy / contract / history / transfer-process components correctly under API-key login. **No OIDC envvars set anywhere.**
- [ ] Per-participant Keycloak and oauth2-proxy are gone from the deployed compose stack (§ 1.5.2). The participant compose is `connector + identity-hub + UI + nginx + 2× postgres` only.

Once M1 is signed off, three workstreams become candidates: **Phase 7.1** (payment-required workflow per [`PAYMENT_GATING.md`](PAYMENT_GATING.md)), **Phase 7.2** (Tier 2: add user OIDC to the UI), and **Phase 7.3** (Tier 3: VC/DCP migration). Sequencing among them is a stakeholder decision, not a technical one — they don't block each other. Phase 6 (governance-level enforcement) continues in parallel throughout.

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

### 7.2 Identity (Tier 2) — Add User OIDC at the UI

Optional MVP improvement that layers per-user authentication on top of the Tier-1 Authority KC. Connector ↔ connector trust (the work of § 3.5 + § 1.5.4) is **unchanged** — Tier 2 only adds a user-session layer in front of the catalogue UI's `/management` calls. Skippable if M1's org-level audit and shared API key remain acceptable.

| Item | Detail |
|------|--------|
| **Task** | Add a single-tier user-OIDC flow against the Authority Keycloak: per-org groups + human users + a `glcdi-ui` OIDC client + `oauth2-proxy` in front of the connector's `/management` endpoint. |
| **Why** | Per-user audit ("which operator at caney-fork pressed negotiate?"); role-gated UI views (e.g. distinct views for `glcdi_data_steward` vs. `glcdi_researcher` inside one org); federated SSO across the dataspace ("log in via the dataspace, choose your org"). |
| **When** | Sequencing among 7.1 / 7.2 / 7.3 is a stakeholder decision. 7.2 is an additive change — it doesn't break Tier 1, doesn't interfere with 7.1 (payment), and doesn't pre-empt 7.3 (VC/DCP) since both Tier 1 and Tier 2 still rely on Authority KC as the issuer. |
| **Status** | [ ] Not started |

#### 7.2.1 Reintroduce the `glcdi-ui` OIDC client in the Authority Keycloak

Add a `glcdi-ui` client in the `glcdi` realm's `clients[]` (the Authority KC realm JSON):
- `standardFlowEnabled: true`, `directAccessGrantsEnabled: false`, `serviceAccountsEnabled: false`.
- Redirect URIs covering all participant origins (`https://caney-fork.glcdi.startinblox.com/*`, `https://point-blue.glcdi.startinblox.com/*`, `https://white-buffalo.glcdi.startinblox.com/*`) and the `silent-callback.html` paths.
- `defaultClientScopes: [..., "glcdi-claims"]` so user JWTs carry the same `glcdi_*` claim shape as connector SA tokens (mappers from § 2.3 work unchanged).
- Audience configured so oauth2-proxy accepts the token as a valid Bearer for the management API.

#### 7.2.2 Reintroduce per-org groups + starter human users

Add the per-org groups + starter users (the content originally drafted as part of Tier 1, deferred to here):

| Group | Realm roles | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|-------|-------------|----------------------|------------------------------|-----------------------------|
| `caney-fork-team` | `glcdi_member`, `glcdi_regenerative_producer` | `caney-fork` | `regenerative-verified` | `contributing` |
| `white-buffalo-team` | `glcdi_member`, `glcdi_regenerative_producer` | `white-buffalo` | `regenerative-verified` | `contributing` |
| `point-blue-team` | `glcdi_member`, `glcdi_researcher` | `point-blue` | `not-applicable` | `observer` |

- Realm roles inherit from the group. User attributes are set on the user record (stock Keycloak's `oidc-usermodel-attribute-mapper` reads user-level fields, not group attributes).
- One starter human user per group: `caney-fork`, `point-blue`, `white-buffalo`. Adding more operators later = "create user, add to existing group."
- The 3 connector SA users from § 1.5.4 stay as-is — their claims are already on the SA user record directly. Don't dual-source them.

#### 7.2.3 Reintroduce oauth2-proxy in front of `/management`

Re-add the `oauth2-proxy` service to `participant-agent-services/docker-compose.yml`, configured against Authority KC:

- `OAUTH2_PROXY_OIDC_ISSUER_URL=https://<authority-host>/auth/realms/glcdi`
- `OAUTH2_PROXY_OIDC_JWKS_URL=https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/certs`
- `OAUTH2_PROXY_CLIENT_ID=glcdi-ui` (single-client mode)
- `OAUTH2_PROXY_CLIENT_SECRET` from each VM's `.env` (rotated, distributed out-of-band).

Adjust nginx so that `/management/*` traffic routes through oauth2-proxy. The `X-Api-Key` floor from § 1.5.3 stays in place — at Tier 2, *both* the Bearer token *and* the API key are required for management traffic, exactly the layered model the original two-tier design described.

#### 7.2.4 Reintroduce UI OIDC plumbing

Reverse the strip-down from § 4.5.F:

- Restore `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OIDC_CLIENT_ID`, `KC_IDP_HINT`, `LINKED_PROVIDER_*`, `LINKED_PROVIDER_SILENT_REDIRECT_URI` envvars in `participant-ui/docker-entrypoint.sh` and `config.json.template`.
- Restore `silent-callback.html` and the `sib-auth-linked-provider` widget.
- The UI now obtains a user JWT via the standard OIDC redirect flow against `glcdi-ui`, sends it as `Authorization: Bearer <token>` alongside the `X-Api-Key`, and uses claim-driven role gating to show/hide views.

#### 7.2.5 Tier-2 onboarding flow

The realm-JSON onboarding from § 2.7 extends with human-user creation. Proposal (to be validated with the Dataspace Authority):
1. Participant submits onboarding request via the onboarding app.
2. Authority approves; backend calls Keycloak Admin API to: create the org's group (if not already there), create the human user, add to the group, set per-user attributes that aren't group-derivable.
3. Participant operator receives credentials and can now log in.

This automates what Tier 1 does manually via realm-JSON edits.

#### 7.2.6 Auth flow at Tier 2

```
Operator user (member of <org>-team in Authority KC)
  ↓ logs in via UI → Authority KC issues OIDC token (client: glcdi-ui)
  ↓ token carries glcdi_membership, glcdi_roles, glcdi_organisation,
  ↓               glcdi_certification_status, glcdi_contribution_status
Browser / UI
  ↓ X-Api-Key + Authorization: Bearer <token> on every management-API call
oauth2-proxy validates Bearer token against Authority KC JWKS
  ↓ passes through if valid
EDC management API (X-Api-Key gate, unchanged from Tier 1)
  ↓ EDC IdentityService extracts user claims for any UI-driven policy work
EDC connector
```

Connector ↔ connector traffic is **unchanged** from Tier 1 — `iam-oauth2` against Authority KC, connector SAs still mint their own JWTs at startup.

**Deliverable:** the Tier-1 staging cluster keeps running; Tier-2-ready realm JSON, compose changes, and UI build are validated against staging in a controlled rollout per participant.

### 7.3 Identity (Tier 3) — Decentralised claims via VC / DCP

Long-term migration replacing the Authority Keycloak as the *issuer* of connector credentials with W3C Verifiable Credentials presented through the Decentralised Claims Protocol (DCP / IATP). Aligns GLCDI with Gaia-X / DSBA federation requirements.

| Item | Detail |
|------|--------|
| **Task** | Replace Authority-KC-issued JWTs with VC-based proof of org claims. Connectors hold credentials in their Identity Hub (already present in the compose stack); contract negotiation exchanges Verifiable Presentations rather than OAuth2 access tokens. |
| **Why** | Removes the single-IdP trust dependency; aligns with Gaia-X / DSBA; supports cross-dataspace identity portability; matches where EDC's upstream is heading (DCP / IATP is the EDC IdentityService direction that has progressively replaced `iam-oauth2` in the project's roadmap). |
| **What's preserved** | The `glcdi_*` claim *names* and the policy functions (§§ 3.2–3.4) are unchanged — they read claims from `ParticipantAgent`, indifferent to whether the issuer is a Keycloak-signed JWT or a VC. § 2.6's claim → constraint mapping table survives verbatim. |
| **What changes** | (a) Identity Hub config switches on; `iam-oauth2` is replaced with `iam-identity-trust` (the DCP/IATP module). (b) Authority becomes a **VC issuer** (issues `MembershipCredential`, `RoleCredential`, `CertificationStatusCredential`, `ContributionStatusCredential` per participant). (c) Trust anchor management — DIDs, issuer trust list — replaces the JWKS endpoint. (d) Connectors present Verifiable Presentations during DSP handshake. |
| **Requires** | EDC Identity Hub configuration unblocked; VC issuance pipeline at the Dataspace Authority; alignment with Gaia-X / DSBA technical specs current at migration time. |
| **When** | After GLCDI scales beyond the M1 trio, when multi-dataspace federation becomes a priority, or when Authority KC is identified as an unacceptable single point of failure. Not before — at smaller scale the centralised-IdP simplicity is the right choice. |
| **Migration path** | Tier 2 → Tier 3 is the larger leap (Tier 1 → Tier 3 skips the human-user surface and is also possible). The DCP-shaped config (`edc.iam.issuer.id=did:web:…`, `edc.iam.sts.oauth.token.url=…`) already noted in the codebase is the placeholder for this future direction; § 3.5 leaves it in place but unused. |
| **Status** | [ ] Not started |

### 7.4 Federated Catalogue policy metadata

| Item | Detail |
|------|--------|
| **Task** | Publish policy summaries as part of self-descriptions in the Federated Catalogue |
| **Why** | Allows participants to discover what terms apply to an asset before initiating contract negotiation — improving UX and reducing failed negotiations |
| **Requires** | Federated Catalogue deployment (currently deferred from governance stack) |
| **Status** | [ ] Not started |

### 7.5 Policy UI in participant dashboard

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
    └──→ Phase 1.5 (Identity Tier 1 + Authority cleanup)
              │
              ├──→ Phase 2 (KC claims on connector SAs)
              │        │
              │        └──→ Phase 3 (EDC Policy Functions; § 3.5 = iam-oauth2 swap, the Tier-1 auth gate)
              │                    │
              │                    └──→ Phase 4 (Seeding Scripts)
              │                              │
              │                              ├──→ Phase 4.5 E (Bruno test suite) ─┐
              │                              │                                    │
              │                              └──→ Phase 5 (Integration Testing) ──┤
              │                                                                   │
              └──→ Phase 4.5 F (Participant UI — Tier-1 strip-down) ──────────────┤
                                                                                  │
                                                                  🚦 Milestone M1 ←┘  (ships on Tier 1)
                                                                                  │
                                            ┌─────────────────────────────────────┤
                                            │                                     │
                          Phase 7.1 (Payment, per PAYMENT_GATING.md)               │
                                            │                                     │
                          Phase 7.2 (Identity Tier 2: add user OIDC at the UI) ────┤  (additive; no block)
                                            │                                     │
                          Phase 7.3 (Identity Tier 3: VC / DCP migration) ────────┤  (long-term)
                                            │                                     │
                          Phase 7.4–7.5 (Federated Catalogue, Policy UI) ─────────┘

Phase 6 (Governance / Legal) — runs in parallel with all technical phases,
                                aligned with Trust Framework v0→v1
```

**Concurrent agents at peak:** 3 (main implementation track, Bruno track 4.5.E, Participant-UI track 4.5.F).

**Tier sequencing:** Phases 7.1 / 7.2 / 7.3 are **independent** post-M1 candidates — they don't block each other. Stakeholders pick the order based on priority (revenue model? per-user audit? federation alignment?).

## Relation to Main Project Phases

| This plan's phase | Maps to main project phase |
|-------------------|----------------------------|
| Phase 1 + 1.5 | Between Phase 1 (done) and Phase 2 (infra) — can start now; 1.5 absorbs the in-flight authority rename and ships **Identity Tier 1** |
| Phase 2–3 | During Phase 2–3, before first deployment of the milestone scenario; § 3.5 is the Tier-1 auth gate |
| Phase 4 | Replaces the simple policies in Phase 5 (seeding) — narrowed to M1 scope (regenerative-only + internal-use-only) |
| Phase 4.5 (E + F) | Parallel agent tracks; UI & test infra for the M1 demo (UI ships in API-key-only mode at Tier 1) |
| Phase 5 | Extends Phase 5 (integration testing); anchored on the M1 scenario |
| Milestone M1 | Demo gate; ships on Tier 1; signed off before any Phase 7 workstream starts |
| Phase 6 | Parallel to all technical phases, aligned with Trust Framework v0→v1 |
| Phase 7.1 | Begins **after M1**; substages v0/v1/v2 per [`PAYMENT_GATING.md`](PAYMENT_GATING.md) |
| Phase 7.2 | **Identity Tier 2** — user OIDC at the UI; optional MVP improvement; non-blocking |
| Phase 7.3 | **Identity Tier 3** — VC / DCP migration; long-term, federation-aligned |
| Phase 7.4–7.5 | Federated Catalogue policy metadata; participant-facing Policy UI |
