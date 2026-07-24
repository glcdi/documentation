# Phase 1.5: Identity (Tier 1) - Single-tier auth + Authority cleanup

Implements the **Tier 1** identity model defined in [§ Identity Tiering Strategy](../implementation-plan.md#identity-tiering-strategy): one Authority Keycloak holding three connector service-account clients (one per participant org), `client_credentials` flow at startup to mint connector-bound JWTs carrying `glcdi_*` claims, and `X-Api-Key` as the *only* gate at the EDC management API. **No end-user OIDC anywhere - the UI is a per-org tool that authenticates to its local connector with the API key.** The `governance-*` → `authority-*` rename that was bundled with this phase (§ 1.5.1) is complete.

## Why Tier 1 first (read-only spike summary)

A read-only spike across `participant-agent-services/`, `edc-connector/`, and `participant-ui/` confirmed the full two-tier OIDC stack inherited from the Hubl framework is **not load-bearing** for the M1 policy/contract/transfer scenario:

- **Connector ↔ connector trust** is what M1's policy stack actually exercises. It needs a JWT with `glcdi_*` claims; it does not need a per-user identity. A `client_credentials` token from Authority KC (one client per connector) carries exactly the right shape.
- **Management-API auth** is pluggable in EDC: `web.http.management.auth.type=tokenbased` + `X-Api-Key` works without any Bearer token. With the UI co-located with its connector behind a per-participant network boundary, the API key alone is the right gate at this tier.
- **Per-participant Keycloak** existed only to host the second tier of the Hubl two-tier flow. With user OIDC moved to Phase 7.2 (Tier 2), it is no longer needed at all in the participant compose stack.

The two-tier user-OIDC content is preserved verbatim in **[Phase 7.2: Identity (Tier 2)](phase-7-future.md#72-identity-tier-2---add-user-oidc-at-the-ui)** as an optional MVP improvement that layers on top of Tier 1 without disturbing it.

## 1.5.1 Complete the governance → authority rename

**Status:** [x] Done. In-repo renames across the four sibling repos (`edc-connector/`, `governance-services/` → `authority-services/`, `participant-agent-services/`, `participant-ui/`) and the `management/` doc-level sweep have all landed, and staging has been cut over to the new hostnames + `authority-services` repo name. The dedicated operator runbook that guided this cutover has been removed as it no longer applies; the remaining operator-facing content lives in [`ops/vm-deployment.md`](../../ops/vm-deployment.md).

## 1.5.2 Remove per-participant Keycloak (and oauth2-proxy) from the participant compose stack

In `participant-agent-services/docker-compose.yml`: delete the `keycloak`, `postgres-kc`, **and `oauth2-proxy`** services along with the `keycloak-pg-data` volume. Remove `participant/keycloak/realms/edc-realm.json` and the related secrets templates (`participant/keycloak/.env.template`, etc.). Adjust the `nginx` service and any `depends_on` edges that pointed at `keycloak` or `oauth2-proxy`. Routes previously mediated by oauth2-proxy (`/oauth2/*`, `/management/*`) collapse: management traffic goes straight to the connector with `X-Api-Key`; `/oauth2/*` is gone.

> Operators who still want a defence-in-depth layer (basic-auth, IP allow-list, mTLS) in front of the catalogue UI host can add it at the Nginx layer - entirely orthogonal to the connector/policy stack and at the operator's discretion. **Adding user OIDC back is the Tier 2 path (§ 7.2).**

**Status:** [x] `keycloak` + `postgres-kc` services + volume removed · [x] `participant/keycloak/realms/edc-realm.json` deleted · [ ] `oauth2-proxy` service removed (Tier-1 cut) · [ ] Nginx routes collapsed (no `/oauth2/*`; `/management/*` proxied directly to connector) · [ ] Live volumes (`<stack>_keycloak-pg-data`) removed on each VM (per [`ops/vm-deployment.md`](../../ops/vm-deployment.md))

## 1.5.3 `X-Api-Key` as the primary management-API auth

At Tier 1, **`X-Api-Key` is the *only* gate** at the EDC management API. There is no Bearer token in front of it; there is no oauth2-proxy. Programmatic clients (Bruno from § 4.5.E, seeding scripts from § Phase 4) and the catalogue UI all use the same key.

Operator hardening checklist:

- Rotate `web.http.management.auth.key`, `edc.api.auth.key`, `edc.api.control.auth.apikey.value` from the `123456` / `password` example defaults - per the [`CLAUDE.md`](../../../CLAUDE.md) "Things that will bite you" callout. Use `openssl rand -hex 32` per key, propagate via `participant/configuration.properties` on each VM, distribute to UI operators out-of-band.
- The key is **per-participant**, not shared across the dataspace. Each participant rotates independently.
- For "API key in the browser is a bad look in production" - yes, the trust boundary is the per-participant network. Treat the catalogue UI as an internal tool. If that boundary is too weak for a given operator, add basic-auth or VPN at Nginx (see § 1.5.2 callout) or graduate to Tier 2 (§ 7.2).

**Status:** [x] Documented in [`ops/vm-deployment.md`](../../ops/vm-deployment.md) and [`ops/local-stack.md`](../../ops/local-stack.md); Bruno's `99-negative-auth/*.bru` covers the negative cases · [ ] Operator rotates the three API keys from `123456` defaults on each VM · [ ] Live verification: Bruno green run against staging

## 1.5.4 Provision connector service-account clients in the Authority Keycloak

This is the single piece of Authority-KC config that Tier 1 actually requires: **one OAuth2 client per participant connector**, with `client_credentials` enabled and `glcdi_*` claims attached to the client's service-account user. Tokens minted via this flow are what each connector presents at DSP time once `iam-oauth2` replaces `iam-mock` in § 3.5.

In the Authority KC's `glcdi` realm (declarative - already in `authority-services/resources/keycloak/realms/glcdi-realm.json`):

| Client | Service-account user | Realm roles | `glcdi_membership` | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|--------|----------------------|-------------|---------------------|----------------------|------------------------------|-----------------------------|
| `glcdi-connector-caney-fork` | `service-account-glcdi-connector-caney-fork` | `glcdi_member`, `glcdi_producer` | `active` | `caney-fork` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-white-buffalo` | `service-account-glcdi-connector-white-buffalo` | `glcdi_member`, `glcdi_producer` | `active` | `white-buffalo` | `regenerative-verified` | `contributing` (after first asset publish) |
| `glcdi-connector-point-blue` | `service-account-glcdi-connector-point-blue` | `glcdi_member`, `glcdi_researcher` | `active` | `point-blue` | `not-applicable` | `observer` |

- Each client has `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false` - strict client_credentials only.
- Each client carries the `glcdi-claims` client scope (§ 2.3) on its `defaultClientScopes` so all five mappers fire.
- Realm role assignment lives on the SA user record; user attributes (cert / contribution status) likewise. Stock Keycloak doesn't surface client-level attributes via standard mappers, so SA-user attributes are the supported path. (Tier 2 promotes some of these to per-org *groups* with human users - see § 7.2.)

**Casing convention** (referenced by §§ 2, 3.4):

- Attribute *values* (certification statuses, contribution statuses, participant types): lowercase / kebab-case - e.g. `regenerative-verified`, `not-applicable`, `contributing`, `observer`. Matches the policy JSON in `reference/policies/` and the JSON-LD context in [`context.jsonld`](../../context.jsonld).
- Realm role names: snake_case with `glcdi_` prefix (Keycloak / OAuth convention) - e.g. `glcdi_producer`. The participant-type policy function (§ 3.3) maps `kebab-case` → `glcdi_<snake_case>` transparently.
- Purpose taxonomy values: PascalCase per § 1.3 - `InternalAnalysis`, `ScientificResearch`, ….

**Adding a new participant** at Tier 1 = Authority operator creates a new `glcdi-connector-<org>` client + SA in the realm JSON (or via admin console), assigns the right roles + attributes, sends `client_id` / `client_secret` to the new participant out-of-band; the participant operator drops them into `participant/configuration.properties` (`edc.oauth.client.id` / `edc.oauth.client.secret.alias`) per § 3.5.

**Status:** [x] Realm JSON declares the 3 connector clients + 3 SA users with role + attribute assignments - see [`ops/vm-deployment.md` § 3](../../ops/vm-deployment.md) for the breakdown · [ ] Imported into live Authority KC (Path A re-import) · [ ] Per-org connector secrets rotated from `changeme-*` placeholders and propagated to each participant VM's `.env`

## 1.5.5 Sanity-check DSP-level identity is still working

After the cuts above, run a smoke-test contract negotiation between two participant connectors. Pre-§ 3.5 (still on `iam-mock`): expected behaviour is unchanged - fixed claims, negotiation reaches `FINALIZED` regardless. Post-§ 3.5 (`iam-oauth2`): each connector authenticates to Authority KC at startup via its `glcdi-connector-<org>` client_credentials, the JWT carries that org's `glcdi_*` claims, the remote connector validates against Authority KC's JWKS, negotiation reaches `FINALIZED` and access policies are evaluated against the real claims for the first time.

**Status:** [ ] Pre-§ 3.5 smoke (iam-mock) - runs after staging cutover, tracked in [`ops/vm-deployment.md` § 5](../../ops/vm-deployment.md) · [ ] Post-§ 3.5 verification (iam-oauth2 + real claims)

## 1.5.6 Auth flow & credentials reference (Tier 1)

For future contributors and the Track-E/F agents in § 4.5: the Tier-1 credential model is deliberately minimal. **One credential at the management-API edge, one credential at the DSP edge, no users in any KC.**

**UI / operator API calls (Tier 1 - pure API key):**

```
Operator user at <org> (no identity in any Keycloak)
  ↓ opens https://<org>.glcdi.startinblox.com/ in a browser
  ↓ pastes / has stored an X-Api-Key value
Catalogue UI (browser)
  ↓ X-Api-Key on every management-API call
Nginx (reverse proxy at the participant VM)
  ↓ proxies straight to connector - no oauth2-proxy
EDC management API (X-Api-Key gate; tokenbased auth type)
  ↓ admin operations (asset / policy / contract-definition CRUD, transfer initiation)
EDC connector
```

There is no Bearer token, no Authority KC redirect, no IdP brokering, no silent-callback iframe - none of those exist at Tier 1.

**DSP-level (connector ↔ connector) traffic - Tier 1 final shape after § 3.5:**

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

**Pre-§ 3.5 the DSP path runs on `iam-mock`** - tokens accepted without verification; fixed claims returned. § 3.5 (`iam-mock` → `iam-oauth2`) is the **single load-bearing gate to "real auth" between connectors**. Before it, all of M1's policy filtering uses the mock's fixed claims and is therefore not exercising real authentication.

**Role of each credential at Tier 1:**

| Credential | What it gates | Required for |
|------------|---------------|--------------|
| **`X-Api-Key`** (per participant connector) | EDC management-API access | **Every** management-API call (UI, Bruno, seeding scripts). The only gate at this edge at Tier 1. |
| **Authority-KC-issued JWT** (one per connector, minted via `glcdi-connector-<org>` `client_credentials`) | Identity at the DSP layer; carries `glcdi_*` claims into the receiving connector's policy engine | DSP traffic between connectors, post § 3.5. Connectors mint and refresh themselves; operators never handle these tokens. |

**For Bruno (§ 4.5.E):** at Tier 1, `X-Api-Key` only. Identity-driven scenario steps (catalog query as researcher, negotiation as a specific org) are tested by running each step from the connector that already *is* that org - no token gymnastics required. Optional: mint a token via `client_credentials` against `glcdi-connector-<org>` to assert claim shape directly, but this is debugging, not the test path.

**For seeding scripts (§ Phase 4):** `X-Api-Key` only - admin operations on the local connector.

**For DCP/IATP-shaped config** (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.token.url=http://identity-hub:7084/sts/token`): not used at Tier 1 or Tier 2 - that is the Tier-3 long-term direction (§ 7.3). The Identity Hub stays in the compose to keep the migration path open, but is not on the M1 critical path.

**Status:** [x] Design captured (this sub-section is documentation; no implementation work)

## Dependencies & risks

- **Blocks Phase 2** - claims now live on the 3 connector SAs in the Authority KC.
- **§ 3.5 (iam-mock → iam-oauth2) is the load-bearing gate.** Until it ships, Tier 1's claims are wired but not enforced - the receiving connector still trusts mock tokens. Treat § 3.5 as part of the Tier-1 critical path, not an afterthought.
- **Trust boundary at the catalogue UI is the per-participant network.** If a stakeholder pushes back on "API key in the browser," the answer is either (a) add basic-auth/VPN at Nginx - orthogonal to the connector stack - or (b) graduate to Tier 2 (§ 7.2). Do not introduce ad-hoc Bearer-token plumbing at Tier 1.
- **No remaining architectural unknowns** after the spike. Risk is operational: cutover sequencing, API-key rotation, and the § 3.5 swap.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 1: GLCDI Vocabulary & Namespace](phase-1-vocabulary.md) · [next: Phase 1.6: Packaged Organization Onboarding - Current Intermediate Delivery →](phase-1.6-onboarding.md)
