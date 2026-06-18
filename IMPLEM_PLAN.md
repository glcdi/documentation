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
3. **Phase 1.6 — Packaged organization onboarding (current intermediate delivery).** Replace the placeholder onboarding stack in `governance-services` with the `djangoldp_glcdi_onboarding` package — a public registration form at `/registration/` and a Django admin dashboard at `/registration/admin/`. Approval triggers automatic Keycloak provisioning (group, user with temp password, roles); approve/deny links land directly in admin mail. Pairs with the realm-roles cleanup (only `glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_non_profit`, `glcdi_non_regulatory`), the realm-wide spelling normalisation to `glcdi_organization`, and the addition of `realm-management.realm-admin` to the `governance` client's service account. **Connector onboarding stays out-of-band (Tier-1 — see § 2.7); only human-org onboarding is packaged here.**
4. **Phase 2 — Keycloak claims (on connector SAs).** Realm roles, attributes, protocol mappers so each connector's `client_credentials` token carries `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status`, `glcdi_contribution_status`. Claims live on the SA users that back each connector client.
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

**Status (in-repo):** Phase 1 (vocabulary), Phase 1.5 (Tier-1 identity + rename), Phase 1.6 (packaged organization onboarding — **current intermediate delivery, local smoke complete (form → admin mail → approve → KC group `sib` with `glcdi_organization=["sib"]` + `glcdi_member+glcdi_producer` + new user + temp password mail); awaiting staging cutover**), Phase 2 (Keycloak claims on connector SAs), and Phase 4.5 (Bruno + UI tracks) have substantive in-repo work in their working trees, blocked only on the staging cutover (Path-A re-import per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md)). Phase 3 (EDC policy extension), Phase 4 (seeding scripts), Phase 5 (integration testing), and Milestone M1 are still to start. Phase 6 (governance / Trust Framework) runs in parallel and is owned outside this repo. Phase 7 (post-M1) — Tier 2 identity (7.2) and the VC migration (7.3) sit alongside payment (7.1) as candidate next workstreams once M1 is signed off.

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
| `glcdi-connector-caney-fork` | `service-account-glcdi-connector-caney-fork` | `glcdi_member`, `glcdi_producer` | `active` | `caney-fork` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-white-buffalo` | `service-account-glcdi-connector-white-buffalo` | `glcdi_member`, `glcdi_producer` | `active` | `white-buffalo` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-point-blue` | `service-account-glcdi-connector-point-blue` | `glcdi_member`, `glcdi_researcher` | `active` | `point-blue` | `not-applicable` | `observer` |

- Each client has `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false` — strict client_credentials only.
- Each client carries the `glcdi-claims` client scope (§ 2.3) on its `defaultClientScopes` so all five mappers fire.
- Realm role assignment lives on the SA user record; user attributes (cert / contribution status) likewise. Stock Keycloak doesn't surface client-level attributes via standard mappers, so SA-user attributes are the supported path. (Tier 2 promotes some of these to per-org *groups* with human users — see § 7.2.)

**Casing convention** (referenced by §§ 2, 3.4):

- Attribute *values* (certification statuses, contribution statuses, participant types): lowercase / kebab-case — e.g. `regenerative-verified`, `not-applicable`, `contributing`, `observer`. Matches the policy JSON in `policies/` and the JSON-LD context in [`context.jsonld`](context.jsonld).
- Realm role names: snake_case with `glcdi_` prefix (Keycloak / OAuth convention) — e.g. `glcdi_producer`. The participant-type policy function (§ 3.3) maps `kebab-case` → `glcdi_<snake_case>` transparently.
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

## Phase 1.6: Packaged Organization Onboarding — Current Intermediate Delivery

While Phase 1.5 finishes the connector-side cutover, the in-flight intermediate delivery replaces the placeholder onboarding stack in `governance-services/` with the [`djangoldp_glcdi_onboarding`](https://git.startinblox.com/djangoldp-packages/djangoldp-glcdi) package and its sibling `djangoldp_glcdi_common`. The shape is intentionally narrow: **organization-level onboarding is automated; per-user account creation and per-connector enrolment are not in scope here** (the connector case stays out-of-band — see [§ 2.7](#27-integration-with-the-onboarding-flow-tier-1-out-of-band) — and per-user OIDC is the Tier-2 evolution in [§ 7.2](#phase-72-identity-tier-2--add-user-oidc-at-the-ui)).

### Why this lands now

1. **Unblocks a fully self-serve organization signup story** without committing to Tier-2 user OIDC. A new organization can apply via a public form, a reviewer approves from an email link or the admin dashboard, and Keycloak provisioning happens automatically — group, user (with one-time temp password), realm roles.
2. **Cleans up the realm to its M1-essential roles only.** The realm JSON had 7 unused `glcdi_*` participant-type roles from an earlier draft taxonomy. Trimming to the four type roles + `glcdi_member` matches what the packaged onboarding actually drives and what the M1 policies actually read.
3. **Surfaces realm-wide spelling drift.** The `governance` client expects `glcdi_organization` (en-US) on group and user attributes, but the existing realm had `glcdi_organisation` everywhere — protocol mapper included. The fix is one renaming pass; doing it now (while the realm import is still wipe-and-replay) avoids an admin-console migration later.

### 1.6.1 Adopt `djangoldp_glcdi_onboarding` in `governance-services/onboarding`

| Item | Detail |
|------|--------|
| **Task** | Replace `djangoldp_onboarding` in `settings.yml` with `djangoldp_glcdi_common` + `djangoldp_glcdi_onboarding`. Install `Pillow` (required by the registration form's `organization_logo` `ImageField`). Move `djangoldp install` from build-time to container-startup so `runserver.sh` can `envsubst` a templated `settings.yml.template` first (`BASE_URL`, `KEYCLOAK_*`, `DEFAULT_FROM_EMAIL`, `GLCDI_ADMIN_MAILS`). Drop `ONBOARDING_PREFIX` — the package already mounts its routes under `registration/`. |
| **URLs delivered** | `/registration/` (public form), `/registration/admin/` (dashboard, requires `is_superuser && is_staff` — the existing `djangoldp configure --with-dummy-admin` step satisfies this), `/registration/admin/<pk>/{approve,deny}/`, `/registration/admin/logout/`. |
| **Routing** | `nginx-{dev,prod}.conf`: one `location /registration/` block proxying to `onboarding-backend:8083/registration/`, plus `/static/` and `/media/` proxies for Django staticfiles and uploaded org logos. The legacy `/onboarding/` and `/onboarding/validation/` blocks (and the `onboarding-approval` httpd container) drop out. |
| **Status** | [x] Image rewired (Dockerfile, settings.yml.template, runserver.sh) · [x] Compose updated · [x] Nginx routes swapped · [x] Smoke-tested locally (form renders, admin dashboard renders, approve flow exercises `KeycloakService.provision()` end-to-end) · [ ] Smoke-tested on staging |

### 1.6.2 Trim realm roles to the M1-essential set

| Item | Detail |
|------|--------|
| **Task** | In `governance-services/resources/keycloak/realms/glcdi-realm.json`, keep only `glcdi_member`, `glcdi_producer`, `glcdi_researcher`. Add `glcdi_non_profit` and `glcdi_non_regulatory`. Drop the seven unused draft roles (`glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder`). |
| **Why** | `djangoldp_glcdi_onboarding` maps each form-checked `organization_type` to exactly one of these four type roles, plus `glcdi_member` for every approved org. None of the dropped roles are referenced by any user, group, or seed script in the repo, so removal is non-breaking. |
| **Status** | [x] Realm JSON updated · [x] Verified locally (`curl -H "Authorization: Bearer <governance SA token>" /admin/realms/glcdi/roles \| jq` returns exactly `["glcdi_member","glcdi_non_profit","glcdi_non_regulatory","glcdi_producer","glcdi_researcher"]`) · [ ] Verified on staging |

### 1.6.3 Normalise `organisation` → `organization` realm-wide

| Item | Detail |
|------|--------|
| **Task** | One pass over the realm JSON replacing every occurrence of `glcdi_organisation` with `glcdi_organization`: the `glcdi-claims` scope description, the `glcdi-organisation-mapper` protocol mapper (name, `user.attribute`, `claim.name`), the three `*-team` group attributes, and the four operator + three connector-SA user attribute blocks. |
| **Why** | The keycloak admin client in `djangoldp_glcdi_onboarding/keycloak_service.py` sets the group attribute as `glcdi_organization` (en-US). Mismatching that against the in-repo `glcdi_organisation` would silently break the claim mapping for newly-onboarded orgs while leaving the legacy ones working — exactly the kind of drift that is hard to debug later. Aligning on en-US is the smaller delta given the package is upstream. |
| **Status** | [x] Realm JSON updated · [x] Verified locally: an end-to-end approve flow created a KC group whose `attributes.glcdi_organization` carried the slugged org name (en-US). The `glcdi-claims` scope's `glcdi-organization-mapper` is in place but not exercised by a real user-token introspection yet — connector-SA tokens don't carry it (the SA is on a different scope set). · [ ] Verified on staging via a user-token introspection once a real org has logged in |

### 1.6.4 Give the `governance` client `realm-management.realm-admin`

| Item | Detail |
|------|--------|
| **Task** | Add a `service-account-governance` user to the realm JSON (mirroring the existing `service-account-glcdi-connector-*` entries), with `clientRoles: { "realm-management": ["realm-admin"] }`. The `governance` client itself already has `serviceAccountsEnabled: true`; this adds the actual permission. |
| **Why** | `djangoldp_glcdi_onboarding` provisions Keycloak via the Admin REST API on behalf of the `governance` client. Without `realm-admin` on the SA, every `POST /admin/realms/glcdi/users` etc. returns 403 and the approve flow silently leaves the request in `processing` forever. |
| **Decision (proposed to the Dataspace Authority)** | Use `realm-admin` (broadest, simplest) rather than the narrower `manage-users + manage-groups + query-users + query-groups` quartet. Trade-off: a leaked `governance` secret can rotate any account, not just onboarding-created ones — which is why this secret stays in the host `.env` (never committed) and is rotated on every fresh deploy. |
| **Status** | [x] Realm JSON updated · [x] Verified locally — the requester-approve flow successfully called the Admin REST API (group create, role-mapping assign, user create, group-membership assign, temp-password set, send email). Empirically the `governance` SA must have `realm-admin` for these to all return 2xx. · [ ] Verified on staging |

### 1.6.5 Wire a real `governance` client secret, end-to-end

| Item | Detail |
|------|--------|
| **Task** | Replace the literal `"changeme-governance-client-secret"` in the realm JSON with the placeholder `${KC_GOVERNANCE_CLIENT_SECRET}`. Add a small Keycloak entrypoint (`resources/keycloak/entrypoint.sh`) that runs before `kc.sh` and `sed`-substitutes that placeholder from `resources/keycloak/realms/*.json` into `/opt/keycloak/data/import/` on first boot (the keycloak ubi-micro image has no `envsubst`). The same env var feeds the `onboarding-backend` as `KEYCLOAK_CLIENT_SECRET`, so the realm and the django client are guaranteed to match. |
| **Why** | Today the secret is `changeme-governance-client-secret` in the realm and a separate `changeme` in `.env` — they don't match, and even if they did, baking the literal into git is exactly the leakage pattern the per-participant `participant/configuration.properties` review caught. |
| **Reset reminder** | The realm JSON is imported **only on first boot**. A pre-existing Keycloak DB volume holds the *previous* (unrotated, mismatched) secret. To pick up the change, the volume must be wiped (`docker compose down -v`) or the new secret applied via the admin console. The `glcdi.sh reset` path is the supported clean-room form. |
| **Status** | [x] Realm + compose + entrypoint wired · [x] Smoke-tested locally with fresh KC volume: `KC_GOVERNANCE_CLIENT_SECRET` from `secrets.env` → patched into `glcdi-realm.json` by `glcdi.sh patch_realm_json` (jq) → bind-mounted to `data/import-template/` → `entrypoint.sh` `sed`-substitutes into `data/import/` → realm imports cleanly on first boot. The same value reaches `onboarding-backend` as `KEYCLOAK_CLIENT_SECRET` via the compose env block, so the django backend authenticates as `governance` against the live KC without a separate "set this in two places" step. · [ ] Verified on staging |

### 1.6.6 Bootstrap-and-smoke checklist

| Item | Detail |
|------|--------|
| **Task** | Run `./management/scripts/glcdi.sh reset && ./management/scripts/glcdi.sh up` to bring up a clean Authority. Verify in order: (a) `https://.../auth/realms/glcdi/.well-known/openid-configuration` returns 200; (b) `POST .../realms/glcdi/protocol/openid-connect/token` with the `governance` `client_credentials` flow returns an access token whose service-account user holds `realm-management.realm-admin`; (c) `GET /registration/` renders the form; (d) submitting the form lands a "pending approval" mail in `onboarding-backend`'s `./mails`; (e) logging into `/registration/admin/` as the dummy admin and clicking Approve triggers the requester email with temp Keycloak credentials; (f) the new user appears in KC inside a group whose `glcdi_organization` attribute is the slugged org name. |
| **Where** | Local: against `http://localhost/...` per the updated `governance-services/README.md`. Staging: same flow, after Path-A wipe-and-replay of the Authority KC volume per [`DEPLOYMENT.md` § 2.2](DEPLOYMENT.md). |
| **Status** | [x] Local smoke run completed end-to-end — `glcdi.sh reset && up` brought the stack up clean, the form at `http://localhost:8083/registration/` accepted a submission, the admin-notification mail landed in `/ldpserver/mails`, the dummy admin approved via the dashboard, a temporary KC password mail went to the requester, and the new user/group were verified via the Admin REST API (group `sib` with `glcdi_organization=["sib"]` + `glcdi_member` + `glcdi_producer`; user `benoit.aless` in group `sib` with a single password credential). · [ ] Re-run on staging once `1.6.7` ships through CI |

### 1.6.7 Public-facing KC login URL in the requester's approval mail

| Item | Detail |
|------|--------|
| **Task** | Set `KEYCLOAK_LOGIN_URL` explicitly so the approval mail's "Log in at…" link points at a browser-reachable URL. Without it, `djangoldp_glcdi_onboarding` auto-derives the login URL from `KEYCLOAK_BASE_URL`, which is the *internal* docker hostname (`http://keycloak:8080/…`) that 404s outside the container network. |
| **Where** | `onboarding/settings.yml.template` reads `${KEYCLOAK_LOGIN_URL}`; `docker-compose.yml` derives it from `${BASE_URL}`; `management/scripts/glcdi.sh` writes it explicitly into `authority.env` for the symmetric-port dev shape (KC is on `:8090`, BASE_URL is `:8083`, so the auto-derived value would be wrong); `governance-services/.gitlab-ci.yml` writes it from CI's `${BASE_URL}` into `.env`. |
| **Status** | [x] Wired in source · [x] Re-tested locally (re-submission as "Benito Toto" produced an approval mail whose "Log in at:" anchor points at `http://localhost:8090/auth/realms/glcdi/account/` — the browser-reachable KC URL, not the docker-internal `http://keycloak:8080/...`) · [ ] Verified on staging that the approval mail's link opens the KC account console |

### Dependencies & risks

- **Blocks nothing else** — Phase 2 (Keycloak claims), Phase 3 (EDC policy functions), and Phase 4 (seeding) only read from the realm JSON, they don't write through the onboarding API. So Phase 1.6 can land or slip without dragging the M1 critical path.
- **Couples tightly to Phase 1.5's Authority cutover.** Both touch the realm JSON, both prefer a single deploy window per environment. Land 1.6 in the same Path-A re-import as 1.5 to avoid two consecutive wipe-and-replays.
- **Trust boundary on `/registration/` is the public internet.** The form is anonymous-POST by design (anyone can apply). Mitigations to consider before production: nginx `limit_req` on `POST /registration/`, a Cloudflare Turnstile / hCaptcha widget on the form, or an explicit allowlist of organisation email domains. None are required to test, but flag for the Dataspace Authority before opening the staging URL to the public.
- **Realm import is one-shot.** Reset paths (`docker compose down -v`, `glcdi.sh reset`) are the only fully clean ways to re-apply the new realm. Post-bootstrap edits via the admin console diverge from the in-repo source-of-truth — flag any such edits in `IDENTITY.md` so they're not silently lost on the next reset.

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
| **Realm roles** assigned to the SA user | Roles like `glcdi_member`, `glcdi_producer`. Inherited automatically into the token's `realm_access.roles`; surfaced as a clean `glcdi_roles` array via § 2.3 mapper 1. | Participant-type membership: which type buckets does this org belong to? Multi-valued, naturally fits a role list. |
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
| **Roles to create** | `glcdi_member` (active membership), `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder` |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — in the `roles.realm[]` array |
| **Status** | [x] Declared in realm JSON (13 roles total: 2 inherited + 11 GLCDI) · [x] Imported into live Authority KC (verified after each `glcdi.sh reset && up`) |

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
| **Status** | [x] Declared on the 3 connector SA users in the realm JSON · [x] Imported into live Authority KC (verified by decoding a live JWT — § 2.5) |

### 2.3 Create protocol mappers for token serialisation

Realm roles are already included in tokens by default (in `realm_access.roles[]`), but we need
explicit mappers to surface claims in the format the EDC policy functions expect.

| Item | Detail |
|------|--------|
| **Task** | Add protocol mappers to relevant Keycloak clients so that GLCDI claims appear as top-level claims in access tokens |
| **Approach** | Realm-level **client scope** `glcdi-claims` carries all five mappers (one for `glcdi_roles` from realm roles; four `oidc-usermodel-attribute-mapper` entries for `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`). The scope is added to `defaultClientScopes` on each `glcdi-connector-<org>` client at Tier 1 (and on the future `glcdi-ui` client at Tier 2 — see § 7.2). No per-client mapper duplication. |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — `clientScopes[]` array (the `glcdi-claims` scope) plus `defaultClientScopes` on each consuming client. |
| **Status** | [x] `glcdi-claims` client scope declared (5 mappers) · [x] Wired into `defaultClientScopes` on the 3 connector clients · [x] Imported into live Authority KC (decoded JWT shows `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` populated) |

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
| **Status** | [x] Declared in realm JSON: 3 connector clients + 3 SA users with role + attribute assignments · [x] Imported into live Authority KC (caney-fork → `glcdi_producer`; point-blue → `glcdi_researcher`; white-buffalo same as caney-fork) |

The Tier-1 assignment for the M1 prototype cluster (already encoded in `governance-services/resources/keycloak/realms/glcdi-realm.json`):

| SA user | Realm roles | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|---------|-------------|----------------------|------------------------------|-----------------------------|
| `service-account-glcdi-connector-caney-fork` | `glcdi_member`, `glcdi_producer` | `caney-fork` | `regenerative-verified` | `contributing` |
| `service-account-glcdi-connector-white-buffalo` | `glcdi_member`, `glcdi_producer` | `white-buffalo` | `regenerative-verified` | `contributing` |
| `service-account-glcdi-connector-point-blue` | `glcdi_member`, `glcdi_researcher` | `point-blue` | `not-applicable` | `observer` |

The proposed assignment *pattern* by participant type (for new onboardings beyond the M1 trio):

| Participant type | Realm roles | Cert status | Contribution status |
|------------------|-------------|-------------|---------------------|
| Regenerative producer | `glcdi_member`, `glcdi_producer` | `regenerative-verified` | `contributing` (after seeding) |
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
| **Status** | [x] Done — for white-buffalo's SA token the decoded JWT showed `glcdi_membership=active`, `glcdi_roles=[glcdi_producer, glcdi_member]`, `glcdi_certification_status=regenerative-verified`, `glcdi_organisation=white-buffalo`, `glcdi_contribution_status=contributing` |

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
  "glcdi_roles": ["glcdi_member", "glcdi_producer"],
  "glcdi_certification_status": "regenerative-verified",
  "glcdi_contribution_status": "contributing",
  "realm_access": {
    "roles": ["glcdi_member", "glcdi_producer", "user", "default-roles-glcdi"]
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
| **Task** | At Tier 1, **connector** onboarding is **out-of-band**: the Authority operator extends the realm JSON with a new `glcdi-connector-<org>` client + SA user (same shape as § 2.4) and ships the secret to the participant operator via a side channel. Connectors are infrastructure, not human users — there is no need for a self-serve form here. The *human-org* onboarding case (registering the organization itself, creating its first operator user) is covered by the packaged flow in [§ Phase 1.6](#phase-16-packaged-organization-onboarding--current-intermediate-delivery). |
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
| **Status** | [x] Repo created · [x] First extension scaffolded (§ 3.1) — `glcdi-policy-functions/` with build files + SPI entry + package skeleton + the three constraint-function classes + `GlcdiClaims` constants + `GlcdiPolicyFunctionsExtension` registration class + a starter unit-test class · [x] Wired into the controlplane runtime (§ 3.6) · [x] Second extension scaffolded: `glcdi-iam-keycloak/` (custom OAuth2 IdentityService against Authority KC, replaces `iam-mock`) |



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
| **Status** | [x] Repo scaffolded (`edc-glcdi-extension/` root build, settings, gradle.properties, libs.versions.toml, .gitignore, README) · [x] Module scaffolded (`extensions/glcdi-policy-functions/`: build.gradle.kts, README, META-INF SPI entry, package directories) · [x] Gradle wrapper bootstrapped (used by `glcdi.sh build`) · [x] First successful `./gradlew build` (runs as part of `glcdi.sh build`; controlplane image rebuilt + booted cleanly) |

### 3.2 Implement membership policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:membership` |
| **Behaviour** | Extract the `glcdi_membership` claim from the participant's identity (via `ParticipantAgent`), compare it to the constraint's `rightOperand` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/membership"` |
| **Used by** | `access/members-only.json`, `access/regenerative-producers.json`, `access/researchers-only.json`, and all combined policies |
| **Status** | [x] `MembershipConstraintFunction.java` drafted (EQ + NEQ; logs and returns `false` when ParticipantAgent is missing or the claim is absent) · [x] Starter unit-test class `MembershipConstraintFunctionTest.java` covers match / mismatch / no-agent / claim-missing / unsupported-operator paths · [x] Compiled against pinned EDC SPI (EDC 0.15.x: `ParticipantAgentPolicyContext.participantAgent()`, typed `Class<C>` registration). Function is invoked on every catalog request — verified by logging output showing `[glcdi:membership] active EQ active → true`. |

### 3.3 Implement participant type policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:participantType` |
| **Behaviour** | Reads the `glcdi_roles` claim (list); maps the kebab-case `participantType` value to the snake-case role name (`glcdi_<type>`) and tests membership in the participant's role set. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/participantType"` |
| **Used by** | `access/regenerative-producers.json`, `access/researchers-only.json`, `combined/corporate-supply-chain.json` |
| **Status** | [x] `ParticipantTypeConstraintFunction.java` drafted with `toRoleName(...)` kebab→snake helper; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [x] Resilient parsing for claims arriving as a `Collection` or comma-separated `String` · [ ] Unit tests (deferred per § 5.1) · [x] Compiled against pinned EDC SPI; verified by the access matrix in Bruno's `20-catalog-discovery` (regen-producers see regen-only assets, researcher gets filtered out) |

### 3.4 Implement certification status policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:certificationStatus` |
| **Behaviour** | Extract `glcdi_certification_status` claim (string, lowercase / kebab-case per § 1.5.4); compare to the constraint's `rightOperand`. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/certificationStatus"` |
| **Used by** | `access/regenerative-producers.json` |
| **Status** | [x] `CertificationStatusConstraintFunction.java` drafted; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [ ] Unit tests (deferred per § 5.1) · [x] Compiled against pinned EDC SPI |

### 3.5 Replace `iam-mock` with a real OAuth2 IdentityService and configure claim extraction

| Item | Detail |
|------|--------|
| **Task** | Swap the dev-only `iam-mock` IdentityService (was wired in `edc-connector/runtimes/controlplane/build.gradle.kts` as `libs.edc.iam.mock`) for a real OAuth2 IdentityService against the Authority Keycloak. Configure the claim extractor so `glcdi_*` claims land in EDC's `ClaimToken` for the policy engine to read. |
| **Outcome (different from original plan)** | Stock `iam-oauth2` was retired in EDC 0.15.x — the replacement (`controlplane-dcp-bom`) assumes Verifiable Presentations via a DCP-compliant STS, which Keycloak doesn't speak. Implemented as a **custom EDC extension** `edc-glcdi-extension/extensions/glcdi-iam-keycloak/` (~250 LOC Java) that: (i) performs `client_credentials` against KC's `/token`; (ii) validates incoming peer JWTs against KC's JWKS via `nimbus-jose-jwt`; (iii) copies every JWT claim into the `ClaimToken`; (iv) provides a `DefaultParticipantIdExtractionFunction` reading `client_id` then `azp`. |
| **Status** | [x] Custom `glcdi-iam-keycloak` extension built + wired into the controlplane runtime (replaces `iam-mock`). Verified end-to-end: white-buffalo's outgoing token is minted via KC, caney-fork's connector verifies it, `glcdi_*` claims land in `ParticipantAgent`, and the `glcdi-policy-functions` constraints evaluate against them (logs show `[glcdi:membership] active EQ active → true`). |

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

**Claim extraction:** EDC's `iam-oauth2` extension extracts standard claims by default. To surface our custom claims (`glcdi_member`, `glcdi_researcher`, `glcdi_producer`, `glcdi_certification_status`, `glcdi_contribution_status`), configure the claim mapper to copy them from the JWT into the `ClaimToken`. The policy functions in §§ 3.2–3.4 then read from `ClaimToken.getClaim("glcdi_member")` etc.

**To verify during implementation:** the exact claim-mapping config keys for the `iam-oauth2` version pinned in this fork. The principle is consistent across versions; the property names occasionally drift. A small pre-flight read of the EDC source at the pinned version (`./gradlew :runtimes:controlplane:dependencies | grep iam-oauth2`) will confirm.

**Migration note (post-prototype):** the existing DCP-shaped config (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.*`, etc.) is the future direction (decentralised identity via Identity Hub + Verifiable Credentials). For M1 it can be left in place but unused, or removed; either way it does not feed the M1 policy-evaluation path.

### 3.6 Register extension in connector runtime

| Item | Detail |
|------|--------|
| **Task** | Wire `glcdi-policy-functions` (sourced from the `edc-glcdi-extension/` sibling repo) into `edc-connector/`'s build, so every connector image rebuild includes the GLCDI custom extensions automatically — mirrors DS4GO's `edc-dsif-extension` → `edc-connector/extensions/` cp-step pattern |
| **Deliverable** | Rebuilt connector image (published to `registry.startinblox.com/applications/glcdi/edc-connector/controlplane`) carries the GLCDI extensions in its shadowJar; participants pulling the image at `docker compose up -d` time get them automatically |
| **Pattern** | At CI time (or via local helper script): clone `edc-glcdi-extension`, copy its `extensions/<name>/` directories into `edc-connector/extensions/`, run the standard Gradle build. The copies are not tracked in `edc-connector` git (added to `.gitignore` as `extensions/glcdi-*`) so the fork stays clean of GLCDI-specific code that lives upstream. |
| **Status** | [x] `edc-connector/gradle/libs.versions.toml`: added `edc-spi-policy-engine` + `edc-runtime-metamodel` aliases (both required by the extension build) · [x] `edc-connector/settings.gradle.kts`: added `include(":extensions:glcdi-policy-functions")` + `include(":extensions:glcdi-iam-keycloak")` · [x] `edc-connector/runtimes/controlplane/build.gradle.kts`: `runtimeOnly(project(":extensions:glcdi-policy-functions"))` + `runtimeOnly(project(":extensions:glcdi-iam-keycloak"))` · [x] `edc-connector/.gitignore`: ignores `extensions/glcdi-*` (synced from sibling repo, not tracked) · [x] `edc-connector/.gitlab-ci.yml`: `before_script` clones `edc-glcdi-extension` (auth via `CI_JOB_TOKEN`, branch override via `EDC_GLCDI_EXTENSION_BRANCH`) and copies its extensions into `./extensions/` ahead of every Gradle/Kaniko step · [x] `edc-connector/scripts/sync-glcdi-extensions.sh`: local-dev helper (looks for `../edc-glcdi-extension/` by default; override with `EDC_GLCDI_EXTENSION_DIR`); now syncs both `glcdi-policy-functions` + `glcdi-iam-keycloak` · [x] First successful local build with the extensions in place (controlplane image rebuilt + 33/35 Bruno tests passing) · [ ] First successful **CI** build (local-only verification so far) · [ ] Job-token permission granted on `edc-glcdi-extension` repo (Settings → CI/CD → Job token permissions → allow `edc-connector`) |

### 3.7 Known limitation — `odrl:purpose` claim plumbing (refine later)

| Item | Detail |
|------|--------|
| **Symptom** | Transfer attempts against assets whose contract policy carries `odrl:purpose == glcdi:InternalAnalysis` (the M1 `internal-use-only` contract policy) terminate at the provider with `dspace:code:409 / "Cannot process TransferRequestMessage because agreement not found or not valid"`. Provider logs the real cause: `[glcdi-policy] [odrl:purpose] consumer didn't state a purpose claim — denying.` |
| **Root cause** | `PurposeConstraintFunction` (§ 3.x) at `transfer.process` scope reads a `"purpose"` claim from the consumer's `ParticipantAgent`. The consumer's KC client-credentials token uses scope `glcdi-claims`, whose protocol mappers emit `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` — **but not `purpose`**. No mapper produces it, no plumbing propagates the negotiation-time purpose into the transfer-time token. So the constraint denies, EDC surfaces a misleading "agreement not found or not valid" umbrella error, and the M1 transfer never reaches STARTED. The catalog branch returns `true` permissively, which is why catalog browsing isn't affected. |
| **Quick fix (applied)** | In `PurposeConstraintFunction.evaluate()`, short-circuit `true` at `transfer.process` scope — negotiation already validated the purpose, transfer-time re-evaluation is defence-in-depth that breaks without the claim. One-line change, restores end-to-end M1 flow. Tier-1 simplification, matches the class doc's own admission that the negotiation gate is "provisional". |
| **Proper fix (Tier-2, deferred)** | Two parts: (a) add a KC protocol mapper to the `glcdi-claims` client scope that emits a `purpose` claim — initially hardcoded per-participant, eventually driven by the negotiation request body once the consumer-side UI / sib-core can collect the consumer's intended purpose; (b) at the consumer's connector, propagate the negotiation-time purpose into the outbound transfer-request token (or onto the DSP message body and read it server-side from the message rather than the claim). The `PurposeConstraintFunction.evaluate()` transfer-scope branch then reverts to enforcing equality against the agreement's `rightOperand`. |
| **Where to refine** | Lift this section into a proper Phase 3.x rework once Tier-2 lands. Cross-reference from `AUTHENTICATION.md § Tier-2` and from the memory file `reference_glcdi_edc_transfer_diag.md § 7` so the trap is documented in three places. |
| **Status** | [x] Quick fix applied to `PurposeConstraintFunction.evaluate()` (transfer-scope short-circuit) · [ ] KC protocol mapper for `purpose` on the `glcdi-claims` scope · [ ] Consumer-side purpose collection in the negotiation/transfer UI flow · [ ] Restore strict transfer-scope evaluation in `PurposeConstraintFunction` once (a) + (b) are in place · [ ] Unit test that covers the transfer-scope branch (currently bypassed, deserves an explicit test once Tier-2 makes it active again) |

### 3.8 Embed the data plane in the controlplane runtime + register an EndpointGenerator for HttpData

| Item | Detail |
|------|--------|
| **Symptom** | After § 3.7's purpose-policy patch unblocks transfer dispatch, the provider accepts the DSP `TransferRequestMessage` but immediately terminates with `SEVERE … failed to Start DataFlow. Fatal error occurred. Cause: No dataplane found`. Provider state machine: INITIAL → PROVISIONING → PROVISIONED → STARTING → TERMINATED. Consumer receives `TransferTerminationMessage`, lands TERMINATED with `errorDetail: null`, and the UI 404s the EDR endpoint 10× in a row. **After § 3.8's BOM patch:** error advances to `No Endpoint generator function registered for transfer type destination 'HttpData'` — different gap, see §§ 3.8.1–3.8.2. |
| **Root cause** | `edc-connector/runtimes/controlplane/build.gradle.kts` only depended on `edc-bom-controlplane` + `edc-bom-controlplane-sql`. It booted in "remote Data Plane client" mode (visible in startup logs: `Initialized Data Plane Signaling Client / Using remote Data Plane client`) and waited for a separate data plane to register itself via the selector API. None ever did — `participant-agent-services/docker-compose.yml` has no dataplane container, and there's no separate dataplane runtime module in this repo. Aliases for `edc-bom-dataplane` + `edc-bom-dataplane-sql` already existed in `libs.versions.toml` but were never referenced. |
| **Quick fix (applied)** | Add `runtimeOnly(libs.edc.bom.dataplane)` + `runtimeOnly(libs.edc.bom.dataplane.sql)` to `runtimes/controlplane/build.gradle.kts`. The BOM brings in `data-plane-core`, `data-plane-http`, `data-plane-http-oauth2`, `data-plane-iam`, `data-plane-selector-client`, `data-plane-self-registration`, `data-plane-signaling-api`. Verified by inspecting `https://repo.maven.apache.org/maven2/org/eclipse/edc/dataplane-base-bom/0.15.1/dataplane-base-bom-0.15.1.pom`. **Caveat:** the historical `data-plane-public-api-v2` artifact has no 0.15.x build (last is 0.13.0) — do NOT try to add it as a `runtimeOnly`, the build fails to resolve. The public/data-fetch path is bundled inside `data-plane-http` in 0.15.x. |
| **Config note** | The data plane's self-registration reads `edc.dataplane.api.public.baseurl` from `participant/configuration.properties` to register its public endpoint with the controlplane. Default is `http://localhost:<public-port>/public` if unset; for dev this works inside the docker network because controlplane and dataplane share the JVM. For prod (or for cross-container reachability when the dataplane is split out), set it explicitly to the externally-reachable URL — same constraint as `edc.dsp.callback.address`. Also reserve a host port for `/public` on each participant's nginx config and proxy it to the connector — without that the consumer's EDR-token-bearing GET can't reach the source data plane. |
| **Alternative (deferred — Phase 7+ if/when the dataplane needs independent scaling)** | Split the dataplane into a separate runtime module under `edc-connector/runtimes/dataplane/`, package it as its own Docker image, add a `dataplane` service to `participant-agent-services/docker-compose.yml`, and configure it to register against the controlplane's `/management/v3/dataplanes`. More moving parts; only worth it when a participant wants to scale the data path independently of negotiation. |
| **Status** | [x] `runtimes/controlplane/build.gradle.kts` adds `edc.bom.dataplane` + `edc.bom.dataplane.sql` runtimeOnly · [x] Verified `data-plane-public-api-v2` is NOT publishable at 0.15.x (last 0.13.0 — do NOT try to add as dep, build won't resolve) · [x] Verified dataplane self-registration writes a registration with `allowedTransferTypes=["HttpData-PULL-HttpData","HttpData-PUSH-HttpData","HttpData-PULL","HttpData-PUSH"]` and `url=http://localhost:9192/control/v1/dataflows` (the SIGNALING endpoint — not a consumer-facing URL) · [x] Verified that boot has NO `public` web context (only `default / control / management / protocol`) — by design in 0.15.x · [x] M1 PULL transfer now passes the "No dataplane found" gate (provider reaches STARTING) · [ ] Provider now fails at STARTING with `No Endpoint generator function registered for transfer type destination 'HttpData'` — next phase: § 3.8.1 |

### 3.8.1 Register a `PublicEndpointGeneratorService` function for `HttpData` destination

| Item | Detail |
|------|--------|
| **Symptom** | Provider's transfer goes INITIAL → PROVISIONING → PROVISIONED → STARTING → terminates with `WARNING Error obtaining EDR DataAddress: No Endpoint generator function registered for transfer type destination 'HttpData'`. The `PublicEndpointGeneratorService` interface and `PublicEndpointGeneratorServiceImpl` are both in the fat jar (from the BOM); the service is wired but its registration map is empty — no `addGeneratorFunction("HttpData", ...)` call ever fires. |
| **Root cause** | The old `data-plane-public-api-v2` artifact (last published at 0.13.0) was responsible for calling `endpointGenerator.addGeneratorFunction("HttpData", dataAddress -> Endpoint(...))` on boot. EDC 0.15.x's `dataplane-base-bom` does NOT include any extension that does this. None of the bundled extensions (`data-plane-http`, `data-plane-signaling-api`, `data-plane-iam`, `data-plane-self-registration`) wires it. So every HttpData-PULL transfer reaches STARTING and dies because the data plane can't generate the consumer-facing URL for the EDR. |
| **Fix (to implement)** | Add a tiny custom extension to `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/` that injects `PublicEndpointGeneratorService` and registers a generator function for `"HttpData"` destination. The function takes the asset's `HttpDataAddress` and returns an `Endpoint` whose properties include `endpoint = <externally-reachable URL>` + `endpointType = "HttpData"`. Bytecode signatures already verified from the running jar: `addGeneratorFunction(String type, Function<DataAddress, Endpoint>)` is the call to make. |
| **URL strategy decision needed** | The Endpoint URL must be browser-reachable on the consumer side. Two viable approaches: (a) **direct fetch** — Endpoint URL = asset's `baseUrl` rewritten to externally-reachable host (e.g. `http://nginx:8080/ldp/...` → `http://host.docker.internal:8081/ldp/...`); consumer's UI sends the EDR's bearer token + DSP-* headers; `djangoldp_edc` permission class on the LDP backend validates. Simplest, mirrors the existing M1 fixture wiring. (b) **dataplane proxy** — Endpoint URL points to a custom `public` HTTP endpoint we add to the connector, which proxies requests to the asset's source and injects DSP-* headers; consumer UI never sees the source URL. More moving parts but hides backend topology. Recommend (a) for Tier-1 and revisit at Tier-2 when DCP-based identity rotation lands. |
| **Status** | [x] Scaffold `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/` (mirrors policy-functions / iam-keycloak layout) · [x] Implement `GlcdiDataplanePublicApiExtension` — registers EndpointGenerator for `HttpData`, binds the `public` web context via `PortMappingRegistry`, bridges the InMemoryVault gap by loading `edc.vault.secrets.<n>.key/value` pairs from config into the vault · [x] Implement `GlcdiPublicApiController` — JAX-RS `/` resource: validates `Authorization: Bearer <token>` via `DataPlaneAuthorizationService`, resolves AccessTokenData via `DataPlaneAccessTokenService.resolve(token)`, extracts `agreement_id` + `participant_id` from `AccessTokenData.additionalProperties()`, injects them as `DSP-AGREEMENT-ID` / `DSP-PARTICIPANT-ID` headers, proxies GET to the resolved `DataAddress.baseUrl` via OkHttp · [x] Strategy chosen: (b) dataplane proxy · [x] Wired into `runtimes/controlplane/build.gradle.kts` + `scripts/sync-glcdi-extensions.sh` · [x] `glcdi.sh` per-org rewrite of `edc.dataplane.api.public.baseurl` so each participant advertises its own host port · [x] `glcdi.sh` nginx-config heredoc augmented with the `/ldp/` proxy block · [x] `glcdi.sh` `EDC_URL` no longer carries trailing `/management` (djangoldp_edc's `utils.py` appends `/management/v3/…` itself — double-`/management` was causing 404s on agreement lookups) · [x] `glcdi.sh` seed-ldp now writes asset baseUrls pointing at `djangoldp-backend:8083` directly (bypassing nginx) — was `http://nginx:8080/ldp/…`; nginx stripped `/ldp/` before forwarding so django saw `/farms/…` and V3's coverage check couldn't match the asset's stored baseUrl · [x] `glcdi.sh` per-org config now uses `/public/` (trailing slash) so nginx doesn't 301-redirect and the browser doesn't drop `Authorization` on the redirect · [x] `djangoldp-glcdi==3.1.4` published with the `permission_classes = [(AuthenticatedOnly & ReadOnly) \| EdcContractPermissionV3]` wiring on Farm/Plot/Metric · [x] `participant-agent-services/djangoldp/Dockerfile` bumped to `DJANGOLDP_GLCDI_VERSION=3.1.4` · [x] `glcdi.sh` defaults `GLCDI_PATH` to pinned `@startinblox/glcdi@1.0.4` (was empty → fell through to `@latest` → Workbox SW cached indefinitely) — survives across `up` re-templating · [x] **CLI end-to-end verified**: caney-fork → point-blue / `grazing-soc-2024` reaches `STARTED`; EDR returns 200; proxy fetch returns the `Farm` JSON-LD · [x] **UI end-to-end verified in browser**: full chain operates through the modal's Access Data click — `Farm` JSON-LD (name="Point Blue demo farm", plots, metrics, field_levels) renders in the modal · [ ] **`@startinblox/glcdi` follow-up publish**: `dsp-catalog.ts:303` binds `.displayServiceTest=${this.displayServiceTest}` to the modal, but `dsp-catalog` doesn't have its own `@property displayServiceTest` declaration — so it passes `undefined` and overrides the modal's `=true` default. Fix: add `@property displayServiceTest = true;` on `dsp-catalog` (or `… ?? true` on the binding). Today's UI test required `m.displayServiceTest = true` in the console to render the button — but the resulting click worked end-to-end. Publishing the patch + bumping `glcdi.sh`'s pinned version removes the manual step. · [ ] Bruno integration test for the full UI flow · [ ] PR / commit the `glcdi-dataplane-public-api` extension and the `glcdi.sh` per-org fixes |

### 3.8.2 Cleanup: remove stale `public`-context wiring once § 3.8.1 lands

| Item | Detail |
|------|--------|
| **Task** | The current per-org `participant/configuration.properties` carries `web.http.public.port=9291` / `web.http.public.path=/public` / `edc.dataplane.api.public.baseurl=…/public`, and `nginx-dev.conf` + `nginx-prod.conf` carry a `location /public/ → edc-connector:9291` block. These are pre-0.15.x leftovers — EDC 0.15.x doesn't bind a `public` context (verified empirically and via POM inspection of `dataplane-base-bom-0.15.1`). They're inert today (no upstream listening, so any traffic 502s — but no traffic flows there in practice). |
| **Action when § 3.8.1 lands** | If § 3.8.1's chosen URL strategy is (a) direct fetch, drop the `public` lines from both `configuration.properties.example` and the two nginx conf files. If strategy is (b) dataplane proxy, replace the upstream port (9291 → whatever the custom public extension binds) and keep the location block. |
| **Status** | [ ] Strategy chosen in § 3.8.1 · [ ] Stale `public`-context settings removed / updated accordingly · [ ] Note in IMPLEM_PLAN.md release notes that EDC 0.15.x flipped from public-api artifact to caller-registered generator |

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
| **Status** | [x] M1 fixture subset implemented via Bruno (`management/bruno/10-provider-seeding/`): 3 assets per producer org (`grazing-soc-2024` regen-producers-only, `grazing-summary-2024` all-members, `grazing-raw-observations-2024` researchers-only). All 3 access tiers exercised in the test suite. · [ ] Full asset-class taxonomy from this table (paddock boundaries, NDVI, etc.) — out of M1 scope, expand when real producer data lands |

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
| **Status** | [x] M1 fixture subset implemented via Bruno — point-blue (the M1 researcher participant) seeds the same 3-asset shape as producers, with the `researchers-only` and `all-members` tiers serving the negative-test cases for the policy matrix. · [ ] Full research-asset-class taxonomy from this table — post-M1 when real research data lands |

### 4.3 Create seeding helper for policy registration

| Item | Detail |
|------|--------|
| **Task** | Add a section to seeding scripts that registers all needed policy definitions before creating contract definitions, reading from the JSON files in `management/policies/` |
| **Approach** | Loop over the required policy JSON files and POST them to `/management/v3/policydefinitions`. Then create contract definitions that reference the registered policy IDs. |
| **Status** | [x] Implemented as the Bruno `10-provider-seeding/` collection — `glcdi.sh seed` loops over all 3 orgs and runs all 10 requests (assets + 3 policies + 3 contract-defs) per org. Idempotent (re-running accepts 409 conflicts). Re-seed integrated into `glcdi.sh all`. |

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

**Status:** [x] Tiered skeleton in [`bruno/`](bruno/) — 19 files: collection metadata, **collection-level pre-request script** (`collection.bru`) for Tier-2 Bearer injection, 2 environments (local + staging) with `tier` selector, 6 folders covering the M1 scenario plus 2 extra Tier-2-only negative-auth cases · [x] Role-corrected per the M1 resolution (white-buffalo positive, point-blue filtered) · [x] Tier-1 default (X-Api-Key only) and Tier-2 anticipated (Bearer auto-injected) — single source, switch via env var · [x] **Green run against local Tier 1 stack: 33/35 tests passing** — catalog discovery (positive + negative), negotiation accepted (both purposes), all 4 negative-auth scenarios, full seeding (10 requests × 3 orgs). Remaining 2/35 are the contract-agreement polling + transfer init (need § 4.5.E's polling files below). · [ ] Polling files for state-machine assertions (FINALIZED / TERMINATED / STARTED) — TODO inside the relevant `.bru` files · [ ] Pre-request script that fetches the offer from the catalog response and uses it verbatim in the negotiation body — TODO · [ ] Green run against **staging** at Tier 1 (local-only verified so far) · [ ] Green run at Tier 2 (additionally gated on Phase 7.2)

### 4.5.F Participant-UI configuration (Track F — parallel agent)

Adapt `participant-ui/` for the **Tier 1** topology — API-key login only, no OIDC envvars, no `LINKED_PROVIDER_*`, no silent-callback iframe:

- Strip OIDC plumbing from `docker-entrypoint.sh` and `config.json.template`: remove `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OIDC_CLIENT_ID`, `KC_IDP_HINT`, `LINKED_PROVIDER_*`, `LINKED_PROVIDER_SILENT_REDIRECT_URI`. Remove `silent-callback.html` from the served paths. Drop the `sib-auth-linked-provider` widget from the Hubl config.
- Implement **API-key login** as the only entry path — operator pastes an `X-Api-Key` value that the UI uses for every management-API call. Trust boundary is the per-participant network (see § 1.5.3); flag clearly in the UI copy that the key is *not* a per-user credential.
- Keep the existing `config.json`-driven asset / policy / contract / history components — they don't need OIDC.
- Surface the missing **transfer-process management** component (`tems-transfer-processes-management` or equivalent) needed by the M1 scenario.
- Confirm theme/branding still renders correctly per-participant (the runtime-configurable single image continues to work).

> **Tier-2 forward look:** Phase 7.2 reintroduces the OIDC plumbing for federated user login. The work in this track is to land Tier 1 cleanly first; the Tier-2 envvars / silent-callback come back in a controlled way under that phase.

**Owner:** parallel agent. **Read-only audit first** (already complete — see status), then strip-down implementation.

**Status:** [x] Read-only audit complete (Track F findings: 4 components configured, env vars + linked-provider mapped, silent-callback path served by Hubl/nginx, transfer-process component absent) · [x] Strip OIDC envvars from `docker-entrypoint.sh` and `config.json.template` (Tier-1 cut: KEYCLOAK_URL, OIDC_CLIENT_ID, KC_IDP_HINT, LINKED_PROVIDER_* all removed) · [x] Drop `sib-auth-linked-provider` widget + `silent-callback.html` from served paths (autoLogin partial in `orbit/` now routes through `<sib-auth-apikey>`) · [x] API-key-only login implemented — `solid-glcdi/src/components/sib-auth-apikey.ts` (paste-form modal) + `sib-auth-provider-apikey.ts` (input + reveal + retrieval mailto). Storage at `localStorage.glcdi_operator_api_key.<participant-id>` (JSON-wrapped). On activation, propagates the key to every `[participant-api-key]` element so the upstream tems-*-management components actually carry it. · [x] Custom `<glcdi-sidebar>` (replaces `<tems-sidebar-oidc>`) reading menu from `window.orbit.components`, theming via dedicated `--glcdi-*` tokens to avoid TEMS' design-token tug-of-war · [ ] Add `tems-transfer-processes-management` (or equivalent) component to `config.json.template` · [x] README rewritten with single-tier architecture + "PROTOTYPE: API-key-only login" subsection (will need a follow-up update after the strip-down lands)

### Dependencies

- Both tracks **depend on § 1.5** (Tier-1 identity simplification) being landed in at least one staging participant.
- 4.5.E benefits from Phases 2–4 being further along (so the test-suite assertions match real seeded data) but can be drafted in parallel against expected behaviour.
- 4.5.F's strip-down can begin **immediately**; field-tested once § 1.5 is in staging.

---

## Phase 4.6: Decouple participant-ui from `@startinblox/solid-tems`

In-scope for M1. Promoted from the post-prototype backlog because the upstream `tems-modal` only renders rich content for `RDFTYPE_OBJECT` / `RDFTYPE_SERVICE` — for plain `Asset` types (what GLCDI seeds) it shows only the description, no title, no data-address, no Negotiate CTA. The same upstream ownership gap surfaced as the catalog-card `[object Object]` provider badge, the "0 datasets" miscount, and the auth-gating leak (background calls bypassing the paste form). All of them trace to internals we can't change without owning the code.

| Item | Detail |
|------|--------|
| **Task** | Fork or duplicate the catalogue / asset / policy / contract / negotiation components currently sourced from `@startinblox/solid-tems` (+ `solid-tems-ui`) into the GLCDI-owned `solid-glcdi` bundle. |
| **Approach** | Bias to (a) **light fork** — copy only the components GLCDI actually uses (`solid-dsp-catalog`, `tems-modal`, `tems-catalog-data-holder`, `tems-*-management`) into `solid-glcdi`, drop solid-tems from `npm[]`, iterate freely. Alternative (b) is a full fork of `solid-tems-v2` under a GLCDI repo with upstream contribs for dataspace-generic fixes. |
| **Wins this unlocks** | Asset modal showing full props (name, `@id`, data-address, providers, access-policy summary) + a real "Negotiate" CTA that builds the ContractRequest body in the JSON-LD shape EDC 0.15.x accepts; consistent GLCDI branding (no more design-token tug-of-war vs. TEMS' defaults); Cypress test coverage on components GLCDI owns. |
| **Why now (not post-M1)** | M1 explicitly demos catalog → modal → negotiate → transfer. The modal gap blocks the demo. Inheriting upstream bugs while we're stabilising the M1 fixtures consumes more triage time than owning the source would. |
| **Status** | [ ] Not started |

### 4.6.1 Asset detail modal — completion checklist

Specific gaps the fork has to close (acceptance criteria for the modal's M1 cut):

- [ ] Modal title = asset `properties.name`
- [ ] Modal subtitle = `@id` (clickable copy-to-clipboard)
- [ ] Properties section — render `properties.*` excluding internal keys
- [ ] Data address section — `type` + `baseUrl` + `proxyPath` if HttpData
- [ ] Provider badge with `_provider.name` (not `[object Object]`)
- [ ] Access policy summary — fetch the contract-def by id, render constraints in human-readable form (e.g. "Requires: producer + regen-verified")
- [ ] "Negotiate contract" CTA — builds the ContractRequest body in the JSON-LD shape EDC 0.15.x accepts (`odrl:permission` + `{"@id":"..."}` for action/operator/leftOperand, see `management/bruno/30-negotiation/01-negotiate-internal-purpose.bru`), POSTs to `/management/v3/contractnegotiations` with the operator's X-Api-Key
- [ ] Negotiation status drawer — polls `/management/v3/contractnegotiations/{id}` and surfaces state transitions until FINALIZED / TERMINATED
- [ ] "Initiate transfer" CTA once an agreement exists

### 4.6.2 Other follow-ups to fold in during the fork

- [ ] Auth gating — sib-auth-apikey now propagates the operator key to `[participant-api-key]` elements on activation. Once the components live in `solid-glcdi`, replace the attribute-pushing approach with reading the key directly from `sib-auth:activated` events (cleaner: no DOM walk).
- [ ] Provider Statistics counter — use `_provider.participantId` for matching (today it tries `_provider === provider.name`, which is always false because `_provider` is an object).
- [ ] Catalog list — distinct cards per provider rely on per-org asset `properties.name` (already fixed in seeding), but the rendering still leaks the raw `_provider` object as a tag. Drop that tag, or render `_provider.name` + provider color swatch.

### Dependencies

- Builds on § 4.5.F (Tier-1 UI strip-down), which lands the `sib-auth-apikey` + `glcdi-sidebar` baseline. Once those are in, the fork lives entirely inside `solid-glcdi/`.
- Doesn't block § 4.5.E's Bruno green run — Bruno tests the connector layer, independent of the UI.

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
| **Status** | [x] Covered by Bruno `20-catalog-discovery/` (passing locally, 2/2 tests green): 01 = regen-producer querying caney-fork sees the M1 asset; 02 = researcher querying caney-fork is correctly filtered out by the regen-only access policy. Same access matrix verified manually for the all-members + researchers-only tiers. |

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
  - `glcdi-connector-caney-fork` and `glcdi-connector-white-buffalo`: SAs carry `glcdi_member`, `glcdi_producer` realm roles and `glcdi_certification_status = regenerative-verified`.
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
| `caney-fork-team` | `glcdi_member`, `glcdi_producer` | `caney-fork` | `regenerative-verified` | `contributing` |
| `white-buffalo-team` | `glcdi_member`, `glcdi_producer` | `white-buffalo` | `regenerative-verified` | `contributing` |
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

### 7.6 Per-participant DjangoLDP backend, gated by `djangoldp_edc` V3

Each participant runs its own `djangoldp-backend` alongside the connector,
exposing the domain models (Farm / Plot / Metric and the per-org variants
in `djangoldp_glcdi_pointblue` / `djangoldp_glcdi_whitebuffalo`) under
`/ldp/`. Every read goes through `djangoldp_edc.EdcContractPermissionV3`,
which validates the DSP-AGREEMENT-ID / DSP-PARTICIPANT-ID headers against
the local connector's contract agreements — so the same M1 contract that
gates `/management/` now gates the *actual dataset*.

| Item | Detail |
|------|--------|
| **Task** | Wire `djangoldp-backend` + `db-djangoldp` into `participant-agent-services/docker-compose.yml` behind the `dev` profile (local-only at this phase). Domain models in `djangoldp-glcdi/djangoldp_glcdi*` get `EdcContractPermissionV3` on the top-level model (Farm) and `EdcInheritPermission` + `inherit_permissions` on every descendant. |
| **Why** | Phase 1's M1 demo seeded a placeholder `http://provider-data-source/...` URL on each asset; nothing was actually behind it. Phase 7.6 makes contract negotiation resolve to a real, permission-gated dataset, completing the data-exchange story end-to-end. |
| **Requires** | `djangoldp~=5.0.0`, `djangoldp-edc` (this work's prerequisite), local Docker. Staging deployment is out of scope here — both new services are `profiles: ["dev"]`, so the GitLab CI `compose --profile prod` deploy ignores them. |
| **Status** | [x] Models wired with V3 permissions · [x] Compose stack gated to `dev` profile · [x] `glcdi.sh seed-ldp` + Bruno baseUrl plumbing · [ ] Staging rollout |

#### 7.6.1 How it fits together

1. `djangoldp-backend` builds from `participant-agent-services/djangoldp/Dockerfile`,
   installing `djangoldp-glcdi==3.1.3` + `djangoldp-edc`. Its
   `settings.yml.template` enumerates one of the three subpackages
   (`djangoldp_glcdi`, `djangoldp_glcdi_pointblue`, `djangoldp_glcdi_whitebuffalo`)
   under `ldppackages` based on `${LDP_DOMAIN_PACKAGE}`.
2. `EDC_URL` / `EDC_PARTICIPANT_ID` / `EDC_API_KEY` point the V3 permission
   class at the same connector this participant runs, so agreement lookups
   stay on the internal compose network.
3. `glcdi.sh seed-ldp` shells into each participant's `djangoldp-backend`
   via `manage.py shell` and creates one Farm + Plot + Metric. The Farm's
   urlid (e.g. `http://localhost:8080/ldp/farms/abc.../`) is written to
   `.glcdi.local/<org>/ldp-farm-urlid.txt`.
4. `glcdi.sh seed` reads that file and passes the urlid as Bruno's
   `m1_asset_base_url` env-var, so the M1 asset is created with
   `dataAddress.baseUrl = <farm-urlid>` from the start. **Order matters:**
   `cmd_all` runs `seed-ldp` before `seed`; running them in the other order
   would create the asset with a stale baseUrl and break the negotiate-then-
   fetch chain (assets in EDC v3 are not safely PATCH-able for that field
   without losing the contract-definition selector linkage).
5. Local nginx routes `/ldp/` → `djangoldp-backend:8083`, forwarding
   `DSP-*` headers so the V3 permission class can read them.

#### 7.6.2 Local validation walkthrough

Run on a clean host (no GLCDI containers running):

```bash
cd management/scripts
./glcdi.sh reset    # wipe any previous local state
./glcdi.sh all      # preflight → build → up → seed-ldp → seed → test
```

After `glcdi.sh all` returns green, the LDP-protected datasets are reachable
through one of the M1 contract agreements. The minimal manual check:

```bash
# 1. Confirm the LDP backend rejects naked GETs (no DSP headers → 403).
curl -i http://localhost:8080/ldp/farms/

# 2. Read the seeded Farm urlid out of the per-org state file.
FARM_URLID=$(cat management/scripts/.glcdi.local/caney-fork/ldp-farm-urlid.txt)
echo "$FARM_URLID"

# 3. From point-blue's connector, negotiate the M1 caney-fork contract
#    (Bruno collection 30-negotiation/01-negotiate-internal-purpose). After
#    the negotiation finalizes, the connector logs the agreement id. Note it.
AGREEMENT_ID=<paste from Bruno or connector logs>

# 4. Replay the LDP request with the DSP headers the connector would send
#    on consumer-side fetch — same DSP-AGREEMENT-ID, DSP-PARTICIPANT-ID
#    matching point-blue's edc.participant.id. Expect 200.
curl -i "$FARM_URLID" \
  -H "DSP-AGREEMENT-ID: $AGREEMENT_ID" \
  -H "DSP-PARTICIPANT-ID: glcdi-connector-point-blue"

# 5. Same request with a bogus agreement id — expect 403.
curl -i "$FARM_URLID" \
  -H "DSP-AGREEMENT-ID: bogus-agreement-uuid" \
  -H "DSP-PARTICIPANT-ID: glcdi-connector-point-blue"
```

What to look for in logs:

- `docker compose logs djangoldp-backend` — the `EDC V3 ALLOWED` /
  `EDC V3 DENIED` line emitted per request by `djangoldp_edc.permissions.v3`
  tells you which validation step (agreement lookup, participant match,
  asset match) fired.
- `docker compose logs edc-connector` — agreement + negotiation state on the
  provider side. If `_resolve_agreement` denies, the provider's
  `agreementId` field and the consumer's DSP-AGREEMENT-ID don't match —
  check the negotiation's `contractAgreement.@id` vs `agreementId`.

What can go wrong, and where to look:

| Symptom | Likely cause |
|---------|--------------|
| 403 with `Missing DSP headers` in the LDP log | nginx isn't forwarding the `DSP-*` headers — check `Access-Control-Allow-Headers` includes them and the route doesn't strip with default `proxy_set_header`. |
| 403 with `Participant mismatch` | The consumer connector's `edc.participant.id` (used as its DID for agreements) doesn't match the `DSP-PARTICIPANT-ID` header value. |
| 403 with `Asset not covered` | The asset's `dataAddress.baseUrl` doesn't match the LDP urlid you're requesting. Re-run `seed-ldp` then `seed` (in that order). |
| `djangoldp-backend` won't come up | Check `LDP_DOMAIN_PACKAGE` matches one of the three subpackages and that `db-djangoldp` is healthy. |

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
