# Phase 7: Future Enhancements (Post-Prototype)

Items from `./policies/` that are relevant for later phases but not required for the prototype.

## 7.1 Payment infrastructure

| Item | Detail |
|------|--------|
| **Task** | Implement the `payment-required` contract policy via a `payment-status` EDC extension |
| **Design** | [`design/payment-gating.md`](../../design/payment-gating.md) - three-stage rollout: **v0** privateProperties storage + JAX-RS update endpoint + request filter on transfer initiation + email notification to provider's finance contact + audit/obligation read endpoints; **v1** ODRL constraint functions (`payAmount`, `paymentStatus`, `dateTime`) so the policy is machine-evaluated; **v2** scheduled `DutyDeadlineEnforcer` that terminates overdue agreements via DSP `ContractNegotiationTermination`. Sequence: [`reference/policies/diagrams/09-payment-gated-data-exchange.puml`](../../reference/policies/diagrams/09-payment-gated-data-exchange.puml). |
| **Requires** | External billing/payment system (issues invoices, processes payment, calls back into the connector's payment-update endpoint). SMTP for v0 notifications. No new EDC fork - the extension lives alongside the existing controlplane build. |
| **When** | **After Milestone M1 is signed off** (regenerative-only + internal-use-only end-to-end). The M1 gate validates the auth, claims, policy-function, seeding, and UI infra that Phase 7.1 builds on; starting payment work earlier compounds risk. |
| **Governance handoff** | Refund obligation: connector records (immutable agreement + audit endpoints), Dataspace Authority adjudicates, external billing system executes. See [`design/payment-gating.md` § 3.3](../../design/payment-gating.md) and the cross-reference proposed in [`strategy/authority.md` § D](../../strategy/authority.md). |
| **Status** | [ ] v0 not started · [ ] v1 not started · [ ] v2 not started |

## 7.2 Identity (Tier 2) - Add User OIDC at the UI

Optional MVP improvement that layers per-user authentication on top of the Tier-1 Authority KC. Connector ↔ connector trust (the work of § 3.5 + § 1.5.4) is **unchanged** - Tier 2 only adds a user-session layer in front of the catalogue UI's `/management` calls. Skippable if M1's org-level audit and shared API key remain acceptable.

| Item | Detail |
|------|--------|
| **Task** | Add a single-tier user-OIDC flow against the Authority Keycloak: per-org groups + human users + a `glcdi-ui` OIDC client + `oauth2-proxy` in front of the connector's `/management` endpoint. |
| **Why** | Per-user audit ("which operator at caney-fork pressed negotiate?"); role-gated UI views (e.g. distinct views for `glcdi_data_steward` vs. `glcdi_researcher` inside one org); federated SSO across the dataspace ("log in via the dataspace, choose your org"). |
| **When** | Sequencing among 7.1 / 7.2 / 7.3 is a stakeholder decision. 7.2 is an additive change - it doesn't break Tier 1, doesn't interfere with 7.1 (payment), and doesn't pre-empt 7.3 (VC/DCP) since both Tier 1 and Tier 2 still rely on Authority KC as the issuer. |
| **Status** | [ ] Not started |

### 7.2.1 Reintroduce the `glcdi-ui` OIDC client in the Authority Keycloak

Add a `glcdi-ui` client in the `glcdi` realm's `clients[]` (the Authority KC realm JSON):
- `standardFlowEnabled: true`, `directAccessGrantsEnabled: false`, `serviceAccountsEnabled: false`.
- Redirect URIs covering all participant origins (`https://caney-fork.glcdi.startinblox.com/*`, `https://point-blue.glcdi.startinblox.com/*`, `https://white-buffalo.glcdi.startinblox.com/*`) and the `silent-callback.html` paths.
- `defaultClientScopes: [..., "glcdi-claims"]` so user JWTs carry the same `glcdi_*` claim shape as connector SA tokens (mappers from § 2.3 work unchanged).
- Audience configured so oauth2-proxy accepts the token as a valid Bearer for the management API.

### 7.2.2 Reintroduce per-org groups + starter human users

Add the per-org groups + starter users (the content originally drafted as part of Tier 1, deferred to here):

| Group | Realm roles | `glcdi_organisation` | `glcdi_certification_status` | `glcdi_contribution_status` |
|-------|-------------|----------------------|------------------------------|-----------------------------|
| `caney-fork-team` | `glcdi_member`, `glcdi_producer` | `caney-fork` | `regenerative-verified` | `contributing` |
| `white-buffalo-team` | `glcdi_member`, `glcdi_producer` | `white-buffalo` | `regenerative-verified` | `contributing` |
| `point-blue-team` | `glcdi_member`, `glcdi_researcher` | `point-blue` | `not-applicable` | `observer` |

- Realm roles inherit from the group. User attributes are set on the user record (stock Keycloak's `oidc-usermodel-attribute-mapper` reads user-level fields, not group attributes).
- One starter human user per group: `caney-fork`, `point-blue`, `white-buffalo`. Adding more operators later = "create user, add to existing group."
- The 3 connector SA users from § 1.5.4 stay as-is - their claims are already on the SA user record directly. Don't dual-source them.

### 7.2.3 Reintroduce oauth2-proxy in front of `/management`

Re-add the `oauth2-proxy` service to `participant-agent-services/docker-compose.yml`, configured against Authority KC:

- `OAUTH2_PROXY_OIDC_ISSUER_URL=https://<authority-host>/auth/realms/glcdi`
- `OAUTH2_PROXY_OIDC_JWKS_URL=https://<authority-host>/auth/realms/glcdi/protocol/openid-connect/certs`
- `OAUTH2_PROXY_CLIENT_ID=glcdi-ui` (single-client mode)
- `OAUTH2_PROXY_CLIENT_SECRET` from each VM's `.env` (rotated, distributed out-of-band).

Adjust nginx so that `/management/*` traffic routes through oauth2-proxy. The `X-Api-Key` floor from § 1.5.3 stays in place - at Tier 2, *both* the Bearer token *and* the API key are required for management traffic, exactly the layered model the original two-tier design described.

### 7.2.4 Reintroduce UI OIDC plumbing

Reverse the strip-down from § 4.5.F:

- Restore `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OIDC_CLIENT_ID`, `KC_IDP_HINT`, `LINKED_PROVIDER_*`, `LINKED_PROVIDER_SILENT_REDIRECT_URI` envvars in `participant-ui/docker-entrypoint.sh` and `config.json.template`.
- Restore `silent-callback.html` and the `sib-auth-linked-provider` widget.
- The UI now obtains a user JWT via the standard OIDC redirect flow against `glcdi-ui`, sends it as `Authorization: Bearer <token>` alongside the `X-Api-Key`, and uses claim-driven role gating to show/hide views.

### 7.2.5 Tier-2 onboarding flow

The realm-JSON onboarding from § 2.7 extends with human-user creation. Proposal (to be validated with the Dataspace Authority):
1. Participant submits onboarding request via the onboarding app.
2. Authority approves; backend calls Keycloak Admin API to: create the org's group (if not already there), create the human user, add to the group, set per-user attributes that aren't group-derivable.
3. Participant operator receives credentials and can now log in.

This automates what Tier 1 does manually via realm-JSON edits.

### 7.2.6 Auth flow at Tier 2

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

Connector ↔ connector traffic is **unchanged** from Tier 1 - `iam-oauth2` against Authority KC, connector SAs still mint their own JWTs at startup.

**Deliverable:** the Tier-1 staging cluster keeps running; Tier-2-ready realm JSON, compose changes, and UI build are validated against staging in a controlled rollout per participant.

### 7.2.7 Cutover operator checklist

When Tier 2 is approved and the changes above have shipped to `main`, the per-VM cutover is:

- [ ] **Authority KC** - confirm the `glcdi-ui` client is active (not just imported), with redirect URIs covering all participant origins + `silent-callback.html` paths and `glcdi-claims` in its default scopes.
- [ ] **Per-org groups** - confirm `caney-fork-team`, `point-blue-team`, `white-buffalo-team` exist with their realm-role + `glcdi_organisation` attribute assignments.
- [ ] **Starter human users** - confirm one starter user per team group exists, with per-user attributes (`glcdi_certification_status`, `glcdi_contribution_status`) set. Set initial credentials and distribute via vault.
- [ ] **GitLab CI/CD variables** - re-add or rotate `GLCDI_UI_CLIENT_SECRET`; populate per VM's `.env`.
- [ ] **Per-participant rollout** - bring each participant stack down + up against the Tier-2 compose. **Verify a full OIDC round-trip** (login → catalog query → contract negotiation → transfer) for one participant before rolling to the rest.
- [ ] **Verification** - browser dev-tools shows `Authorization: Bearer` on every `/management` call (alongside the persisted `X-Api-Key`); oauth2-proxy logs show successful Bearer-token validations against Authority KC JWKS.

## 7.3 Identity (Tier 3) - Decentralised claims via VC / DCP

Long-term migration replacing the Authority Keycloak as the *issuer* of connector credentials with W3C Verifiable Credentials presented through the Decentralised Claims Protocol (DCP / IATP). Aligns GLCDI with Gaia-X / DSBA federation requirements.

| Item | Detail |
|------|--------|
| **Task** | Replace Authority-KC-issued JWTs with VC-based proof of org claims. Connectors hold credentials in their Identity Hub (already present in the compose stack); contract negotiation exchanges Verifiable Presentations rather than OAuth2 access tokens. |
| **Why** | Removes the single-IdP trust dependency; aligns with Gaia-X / DSBA; supports cross-dataspace identity portability; matches where EDC's upstream is heading (DCP / IATP is the EDC IdentityService direction that has progressively replaced `iam-oauth2` in the project's roadmap). |
| **What's preserved** | The `glcdi_*` claim *names* and the policy functions (§§ 3.2–3.4) are unchanged - they read claims from `ParticipantAgent`, indifferent to whether the issuer is a Keycloak-signed JWT or a VC. § 2.6's claim → constraint mapping table survives verbatim. |
| **What changes** | (a) Identity Hub config switches on; `iam-oauth2` is replaced with `iam-identity-trust` (the DCP/IATP module). (b) Authority becomes a **VC issuer** (issues `MembershipCredential`, `RoleCredential`, `CertificationStatusCredential`, `ContributionStatusCredential` per participant). (c) Trust anchor management - DIDs, issuer trust list - replaces the JWKS endpoint. (d) Connectors present Verifiable Presentations during DSP handshake. |
| **Requires** | EDC Identity Hub configuration unblocked; VC issuance pipeline at the Dataspace Authority; alignment with Gaia-X / DSBA technical specs current at migration time. |
| **When** | After GLCDI scales beyond the M1 trio, when multi-dataspace federation becomes a priority, or when Authority KC is identified as an unacceptable single point of failure. Not before - at smaller scale the centralised-IdP simplicity is the right choice. |
| **Migration path** | Tier 2 → Tier 3 is the larger leap (Tier 1 → Tier 3 skips the human-user surface and is also possible). The DCP-shaped config (`edc.iam.issuer.id=did:web:…`, `edc.iam.sts.oauth.token.url=…`) already noted in the codebase is the placeholder for this future direction; § 3.5 leaves it in place but unused. |
| **Status** | [ ] Not started |

## 7.4 Federated Catalogue policy metadata

| Item | Detail |
|------|--------|
| **Task** | Publish policy summaries as part of self-descriptions in the Federated Catalogue |
| **Why** | Allows participants to discover what terms apply to an asset before initiating contract negotiation - improving UX and reducing failed negotiations |
| **Requires** | Federated Catalogue deployment (currently deferred from governance stack) |
| **Status** | [ ] Not started |

## 7.5 Policy UI in participant dashboard

| Item | Detail |
|------|--------|
| **Task** | Add a policy management interface to the participant UI, allowing producers to select from pre-defined policy templates when publishing assets |
| **Why** | Currently policies are registered via API/scripts. A UI lowers the barrier for non-technical participants (ranchers). |
| **Requires** | `participant-ui` development |
| **Status** | [ ] Not started |

## 7.6 Per-participant DjangoLDP backend, gated by `djangoldp_edc` V3

Each participant runs its own `djangoldp-backend` alongside the connector,
exposing the domain models (Farm / Plot / Metric and the per-org variants
in `djangoldp_glcdi_pointblue` / `djangoldp_glcdi_whitebuffalo`) under
`/ldp/`. Every read goes through `djangoldp_edc.EdcContractPermissionV3`,
which validates the DSP-AGREEMENT-ID / DSP-PARTICIPANT-ID headers against
the local connector's contract agreements - so the same M1 contract that
gates `/management/` now gates the *actual dataset*.

| Item | Detail |
|------|--------|
| **Task** | Wire `djangoldp-backend` + `db-djangoldp` into `participant-agent-services/docker-compose.yml` behind the `dev` profile (local-only at this phase). Domain models in `djangoldp-glcdi/djangoldp_glcdi*` get `EdcContractPermissionV3` on the top-level model (Farm) and `EdcInheritPermission` + `inherit_permissions` on every descendant. |
| **Why** | Phase 1's M1 demo seeded a placeholder `http://provider-data-source/...` URL on each asset; nothing was actually behind it. Phase 7.6 makes contract negotiation resolve to a real, permission-gated dataset, completing the data-exchange story end-to-end. |
| **Requires** | `djangoldp~=5.0.0`, `djangoldp-edc` (this work's prerequisite), local Docker. Staging deployment is out of scope here - both new services are `profiles: ["dev"]`, so the GitLab CI `compose --profile prod` deploy ignores them. |
| **Status** | [x] Models wired with V3 permissions · [x] Compose stack gated to `dev` profile · [x] `glcdi.sh seed-ldp` + Bruno baseUrl plumbing · [ ] Staging rollout |

### 7.6.1 How it fits together

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

### 7.6.2 Local validation walkthrough

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
FARM_URLID=$(cat management/build/scripts/.glcdi.local/caney-fork/ldp-farm-urlid.txt)
echo "$FARM_URLID"

# 3. From point-blue's connector, negotiate the M1 caney-fork contract
#    (Bruno collection 30-negotiation/01-negotiate-internal-purpose). After
#    the negotiation finalizes, the connector logs the agreement id. Note it.
AGREEMENT_ID=<paste from Bruno or connector logs>

# 4. Replay the LDP request with the DSP headers the connector would send
#    on consumer-side fetch - same DSP-AGREEMENT-ID, DSP-PARTICIPANT-ID
#    matching point-blue's edc.participant.id. Expect 200.
curl -i "$FARM_URLID" \
  -H "DSP-AGREEMENT-ID: $AGREEMENT_ID" \
  -H "DSP-PARTICIPANT-ID: glcdi-connector-point-blue"

# 5. Same request with a bogus agreement id - expect 403.
curl -i "$FARM_URLID" \
  -H "DSP-AGREEMENT-ID: bogus-agreement-uuid" \
  -H "DSP-PARTICIPANT-ID: glcdi-connector-point-blue"
```

What to look for in logs:

- `docker compose logs djangoldp-backend` - the `EDC V3 ALLOWED` /
  `EDC V3 DENIED` line emitted per request by `djangoldp_edc.permissions.v3`
  tells you which validation step (agreement lookup, participant match,
  asset match) fired.
- `docker compose logs edc-connector` - agreement + negotiation state on the
  provider side. If `_resolve_agreement` denies, the provider's
  `agreementId` field and the consumer's DSP-AGREEMENT-ID don't match -
  check the negotiation's `contractAgreement.@id` vs `agreementId`.

What can go wrong, and where to look:

| Symptom | Likely cause |
|---------|--------------|
| 403 with `Missing DSP headers` in the LDP log | nginx isn't forwarding the `DSP-*` headers - check `Access-Control-Allow-Headers` includes them and the route doesn't strip with default `proxy_set_header`. |
| 403 with `Participant mismatch` | The consumer connector's `edc.participant.id` (used as its DID for agreements) doesn't match the `DSP-PARTICIPANT-ID` header value. |
| 403 with `Asset not covered` | The asset's `dataAddress.baseUrl` doesn't match the LDP urlid you're requesting. Re-run `seed-ldp` then `seed` (in that order). |
| `djangoldp-backend` won't come up | Check `LDP_DOMAIN_PACKAGE` matches one of the three subpackages and that `db-djangoldp` is healthy. |

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 6: Governance-Level Enforcement (Non-Technical) - Proposal](phase-6-governance.md)
