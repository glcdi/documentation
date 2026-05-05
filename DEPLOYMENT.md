# GLCDI Deployment & Validation

Operator runbook for applying [Phase 1.5](IMPLEM_PLAN.md#phase-15-authority-cleanup--identity-simplification) changes to staging, plus a local-stack validation procedure that lets developers prove the M1 scenario end-to-end before pushing to staging.

This document complements [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) (which is focused narrowly on the `governance → authority` rename) by covering the Phase 1.5 topology cuts: removing the per-participant Keycloak, repointing oauth2-proxy, configuring `glcdi-ui` as the single OIDC client, and the operator-users / connector-service-accounts setup in the Authority KC. Everything below is put forward as a proposal for the project team and Dataspace Authority to validate; nothing here is a decided commitment.

## TL;DR

- **Staging deployment** in the current GLCDI environment is mostly a **container-restart exercise**. DNS for `authority.glcdi.startinblox.com` and the per-participant hosts is already resolving; nginx, certbot/TLS and the `.env` files on each VM are already valid. The cutover is: snapshot Postgres volumes → refresh the Authority Keycloak realm (Path A: wipe volume + re-import the in-repo `glcdi-realm.json`; or Path B: targeted admin-console edits) → `docker compose down && docker compose up -d` on each participant VM against the post-1.5 compose. Indicative window: ~20 min for the realm + ~10 min per participant + verification time.
- **Local validation** spins up Authority KC + two participant stacks (one provider, one consumer) on the developer's laptop, seeds the M1 fixtures, and runs the Bruno collection (`management/bruno/`) end-to-end. The two acceptance signals are (1) a green Bruno run and (2) the participant UI surfaces the asset / policy / contract / negotiation / transfer-process components correctly under API-key login.
- **The rename runbook in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) only matters if your environment hasn't already migrated DNS/TLS/`.env`/nginx.** Current GLCDI staging is past that point; this doc is the simpler restart-and-verify procedure that follows.

---

## 1. Pre-flight (before touching any deployed environment)

In the current GLCDI staging environment, the heavy infrastructure pieces are **already in place** — the cutover is mostly container restarts plus the Authority Keycloak realm-import refresh. Quick confirmation list:

| Item | Status (current GLCDI staging) | Action if not in this state |
|------|-------------------------------|----------------------------|
| DNS for `authority.glcdi.startinblox.com` and per-participant hosts | ✅ already resolving | Add records per [`AUTHORITY_MIGRATION.md` § 1](AUTHORITY_MIGRATION.md) |
| Nginx config on each VM | ✅ already valid (routes `/management/`, `/protocol/`, etc. correctly) | Update per `participant-agent-services/nginx/` |
| `.env` on each VM | ✅ already populated with the Phase 1.5 variables (`AUTHORITY_KEYCLOAK_URL`, `OIDC_CLIENT_ID=glcdi-ui`, `GLCDI_UI_CLIENT_SECRET`, etc.) and the obsolete `LOCAL_KEYCLOAK_*` removed | Apply the changes in this doc's § 2.4, then re-deploy |
| Certbot / TLS certs | ✅ already issued and renewing | Issue per `AUTHORITY_MIGRATION.md` § 2 |
| In-repo changes merged across the four sibling repos | Verify with `git log` on `main` | Land the per-repo Phase 1.5 commits |
| Container images rebuilt and published | Verify image digests; specifically the `participant-ui` image with `OIDC_CLIENT_ID=glcdi-ui` defaults | CI rebuild |
| Secrets rotated and stored | `web.http.management.auth.key` / `edc.api.auth.key` / `edc.api.control.auth.apikey.value` ≠ `123456`; `GLCDI_UI_CLIENT_SECRET` and per-org `glcdi-connector-<org>` secrets minted | Rotate per `AUTHORITY_MIGRATION.md` § 4 |
| Bruno collection runs cleanly against local stack | See § 3 (local validation) | Unblock by fixing the local issue first; staging green requires local green |

**If everything in the "current GLCDI staging" column is ✅, the cutover is the simplified procedure in § 2.** If any row is red, do those rows first (with the runbook in `AUTHORITY_MIGRATION.md`) before § 2.

---

## 2. Staging deployment

The Phase 1.5 cutover for the current GLCDI staging is **mostly a container-restart exercise**: DNS, TLS, nginx, `.env` are already valid; the project just needs the Authority Keycloak realm to be refreshed and every container to come back up against the post-1.5 compose files / images. Indicative duration: ~20 minutes for the realm refresh + 10 minutes per participant restart, plus snapshot and verification time.

### 2.1 Maintenance window & snapshots

Announce ≥ 24 hours ahead. During the window: management API, catalog queries, and contract negotiations are unavailable across the dataspace.

Before any destructive change:
- **Authority Keycloak Postgres volume** — full snapshot (live admin-console edits live only there).
- **Each participant connector's Postgres volume** — full snapshot.
- **Live `glcdi-realm.json`** — export via Admin API, store next to the in-repo version. Lets you compare what's in production vs. what the in-repo JSON will import.
- **VM filesystem snapshots** if the cloud provider supports them.

### 2.2 Authority Keycloak — refresh the realm

The in-repo `authority-services/resources/keycloak/realms/glcdi-realm.json` already has the full post-Phase-1.5 state:

- 13 realm roles (`user`, `admin`, plus `glcdi_member`, `glcdi_regenerative_producer`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, and 6 future participant types).
- 1 client scope `glcdi-claims` carrying the 5 protocol mappers (realm-roles → `glcdi_roles`; user-attribute → `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`).
- 8 clients: existing `governance`, `onboarding`, `glcdi-ui`, `edc-api-client`, `participant-broker` (last two flagged as legacy in their `description`), plus 3 new `glcdi-connector-<org>` service-account clients.
- Empty `identityProviders` (federation removed).
- 3 groups (`caney-fork-team`, `white-buffalo-team`, `point-blue-team`) with their realm-role + organisation-attribute assignments.
- 7 users: `admin` plus 3 starter operators (`caney-fork`, `point-blue`, `white-buffalo`) with their per-user attributes set, plus 3 service-account users (one per connector client) — also in their org's group with the same attributes.

Three options to get this content into the live Authority KC, in order of recommendation:

#### Option 1 — Full re-import (destructive, simplest for the cutover)

Wipe the Authority KC's Postgres volume and let KC re-import the realm JSON on first boot. Recommended for the Phase 1.5 cutover when there are no console-side edits to preserve.

```bash
# On the Authority VM, with snapshot already taken in § 2.1
cd /glcdi/authority-services
docker compose down

# Identify the Postgres volume (name typically `authority-services_authority-pg-data`
# but verify with `docker volume ls`)
docker volume ls | grep -i authority
docker volume rm authority-services_authority-pg-data

# Bring the stack back up — KC re-imports glcdi-realm.json on first boot
docker compose up -d

# Wait ~30s for the import to complete, then verify
sleep 30
curl -fsSL https://authority.glcdi.startinblox.com/auth/realms/glcdi/.well-known/openid-configuration \
  | jq -r .issuer
# Expected: https://authority.glcdi.startinblox.com/auth/realms/glcdi
```

Smoke check via admin console (`https://authority.glcdi.startinblox.com/auth/admin`, log in as `admin/admin`, change the password):
- **Clients** list contains `glcdi-ui` + the three `glcdi-connector-<org>` entries.
- **Client Scopes** list contains `glcdi-claims` with 5 protocol mappers.
- **Groups** list contains `caney-fork-team`, `point-blue-team`, `white-buffalo-team`.
- **Users** list contains `caney-fork`, `point-blue`, `white-buffalo` plus the three `service-account-glcdi-connector-<org>` entries (auto-created from the realm JSON).
- **Identity Providers** list is empty.

Any subsequent admin-console edits made before the next re-import will live only in Postgres — keep the in-repo JSON in sync (or re-export with `kc.sh export ...` periodically).

#### Option 2 — Partial import via Admin REST API (non-destructive, scriptable, recommended for incremental updates)

Use this when the live KC has manual admin-console state to preserve, or when applying incremental changes (e.g. adding a fourth participant later) without a full restart. Not ideal for the Phase 1.5 cutover itself because client-scope and protocol-mapper handling in `partialImport` varies by KC version.

```bash
# 1. Get an admin token
KC_BASE=https://authority.glcdi.startinblox.com/auth
TOKEN=$(curl -fsSL -X POST "$KC_BASE/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
  -d "grant_type=password" \
  | jq -r .access_token)

# 2. Build a partial-import payload (jq is in the host distrobox or distrobox `dev`)
jq '{
  ifResourceExists: "OVERWRITE",
  realm: .realm,
  roles: .roles,
  clients: .clients,
  groups: .groups,
  users: .users,
  identityProviders: .identityProviders
}' /glcdi/authority-services/resources/keycloak/realms/glcdi-realm.json \
  > /tmp/partial-import.json

# 3. Push it
curl -fsSL -X POST "$KC_BASE/admin/realms/glcdi/partialImport" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/partial-import.json
```

The response lists how many of each resource type were `ADDED`, `OVERWRITTEN`, or `SKIPPED`.

**Caveats with `partialImport`:**

- Client scopes (the `glcdi-claims` scope) are **not** covered by the partial-import endpoint in older KC versions. If Option 2 is used and `glcdi-claims` is missing, create it through Option 3 (admin console) before running Option 2.
- Protocol mappers nested inside a client are imported when the client itself is `OVERWRITTEN`, but mappers added at realm-level (in the client scope) need a separate `POST /admin/realms/glcdi/client-scopes/{id}/protocol-mappers/models` for each mapper.
- Service-account users (`service-account-glcdi-connector-<org>`) are auto-created when their client has `serviceAccountsEnabled=true`, but the per-user attributes + group membership in the realm JSON only land if the user records are imported via partialImport's `users` field.

#### Option 3 — Admin Console manual edits (last resort, when partial-import support is patchy)

Walk the admin console step by step. Useful when KC version doesn't support partialImport for some resource type, or for one-off fixes. The detailed checklist is in [`AUTHORITY_MIGRATION.md` § 3 Path B](AUTHORITY_MIGRATION.md). Phase 1.5 specifically adds:

- Confirm or create the `glcdi-claims` client scope with the 5 protocol mappers.
- Confirm `glcdi-ui` has the silent-callback redirect URIs and `glcdi-claims` in its default scopes.
- Create the 3 `glcdi-connector-<org>` clients (`client_credentials` only; `glcdi-claims` in default scopes).
- Create the 13 realm roles (or at least the GLCDI ones not already present).
- Create the 3 `<org>-team` groups with realm-role assignments.
- Create the 3 starter users; set their per-user attributes (`glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`); add them to their team group.
- For each connector client's auto-created service-account user: add to the org's team group; set the same per-user attributes.
- Mint and rotate client secrets out-of-band.

Path A in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) (wipe + re-import) is the clean way to apply all of the above in one shot. Option 3 is for surgical fixes.

#### About the per-user attributes

The realm JSON sets `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status` on each **user** directly (not on the group). Reason: stock Keycloak's `oidc-usermodel-attribute-mapper` reads user attributes only — there's no built-in mapper for group attributes. Realm roles inherit from the group; user attributes are explicitly set per user. When adding a fourth user to an existing team, copy the team's attribute values to the new user record (small handoff cost, manageable for a prototype).

#### Rotating client secrets after import

The realm JSON ships placeholder secrets (`changeme-glcdi-connector-caney-fork-secret`, etc.). After import, rotate via admin console (Clients → `<client>` → Credentials → Regenerate secret) or via Admin API:

```bash
NEW_SECRET=$(openssl rand -hex 32)
CLIENT_INTERNAL_ID=$(curl -fsSL "$KC_BASE/admin/realms/glcdi/clients?clientId=glcdi-connector-caney-fork" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')
curl -fsSL -X PUT "$KC_BASE/admin/realms/glcdi/clients/$CLIENT_INTERNAL_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"secret\": \"$NEW_SECRET\"}"
echo "New secret: $NEW_SECRET — store in $GLCDI_UI_CLIENT_SECRET / GLCDI_CONNECTOR_CANEY_FORK_SECRET on the participant VM"
```

Repeat for each connector client. Same procedure for `glcdi-ui` if the public-client form is replaced with a confidential client (currently `glcdi-ui` is `publicClient: true`, so it has no secret — operator can flip to confidential post-import if oauth2-proxy needs it for client_credentials).

### 2.3 Participant stacks — restart against the post-1.5 images

For each participant VM (`caney-fork`, `point-blue`, `white-buffalo`), in sequence:

1. `cd /glcdi/participant-agent-services && git pull` (lands the post-1.5 compose with `keycloak` + `postgres-kc` services removed).
2. `docker compose pull` to get any newly-published `participant-ui` image with the post-1.5 entrypoint defaults.
3. `docker compose down` — brings down the existing stack including the now-orphan `keycloak` + `postgres-kc` services from the old compose.
4. (Optional, recoverable from § 2.1 snapshot) `docker volume rm <stack>_keycloak-pg-data` — the per-participant Keycloak data is no longer used.
5. `docker compose up -d`.
6. `docker compose ps` — expected services: `db-connector`, `edc-connector`, `catalogue-ui`, `identity-hub`, `oauth2-proxy`, `nginx`. **No** `keycloak` or `postgres-kc`.
7. Quick smoke: `curl -fsSL https://<participant-host>/management/v3/assets/request -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $EDC_API_KEY" -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}'` — returns 200 with a JSON list (assets list, possibly empty pre-Phase-4 seeding).

The `.env` on the VM doesn't need editing during the cutover (already done out-of-band). If something is wrong with `.env`, fix it before restarting — `docker compose up -d` will pick it up.

### 2.5 Post-cutover verification

Run the [Bruno collection](bruno/) (`management/bruno/`) against staging:

```bash
cd management/bruno
bru run --env staging
```

Expected: green run. Specifically:
- `00-auth/*` — three tokens fetched cleanly from Authority KC; JWTs decoded by Bruno carry the expected `glcdi_*` claims.
- `10-provider-seeding/*` — caney-fork connector accepts the asset/policy/contract-definition POSTs (after `iam-oauth2` swap from § 3.5; for now this requires the `iam-mock` to still be in place — note that policies aren't actually evaluated until § 3.5 lands).
- `20-catalog-discovery/01-catalog-as-regen-producer.bru` — white-buffalo sees the M1 fixture asset.
- `20-catalog-discovery/02-catalog-as-researcher.bru` — point-blue does NOT see it (filtered).
- `30-negotiation/01` — internal-purpose negotiation reaches FINALIZED.
- `30-negotiation/02` — research-purpose negotiation reaches TERMINATED.
- `40-transfer/01` — transfer initiates and succeeds.
- `99-negative-auth/*` — no-key and wrong-key calls return 401.

Also verify in browser dev tools (one happy-path session):
- Network tab shows OIDC tokens issued by `authority.glcdi.startinblox.com/realms/glcdi`, no calls to any per-participant KC.
- Management API calls carry both `X-Api-Key` and `Authorization: Bearer`.
- No `silent-callback` errors (Track F's Authority-KC redirect-URI requirement satisfied).

### 2.6 Rollback plan

If verification fails and the issue can't be fixed within the maintenance window:

1. Bring down all participant stacks.
2. Restore Authority KC's Postgres volume from § 2.2 snapshot.
3. Restore each participant's Postgres volume from § 2.2 snapshot.
4. Roll the participant compose files back to the pre-Phase-1.5 version (which still has the per-participant KC).
5. Bring stacks back up at the **old** hostnames + old client IDs.
6. Verify auth flow at the old hostname for one participant.
7. Investigate root cause before re-scheduling.

---

## 3. Local validation

A reproducible procedure to spin up the simplified stack on a developer's laptop and prove the M1 scenario end-to-end before pushing to staging.

### 3.1 Prerequisites

- Docker + docker compose (Compose v2 syntax used throughout).
- ≥ 8 GB RAM available to Docker (Authority KC + 2 participant stacks + Postgres ×3 + Identity Hub ×2 + nginx ×2).
- Free ports: `8090` (Authority KC), `8080` and `8081` (two participant stack nginxes), `19193` and `19194` (two EDC management APIs).
- Bruno installed (or the CLI: `npm install -g @usebruno/cli`).

### 3.2 Spin up Authority Keycloak (single instance)

```bash
cd authority-services
cp .env.example .env  # adjust ports if 8090 is taken
./init-secrets.sh     # creates working secrets from *.template
docker compose up -d
# Wait ~30 seconds for KC to import the realm
curl -fsSL http://localhost:8090/auth/realms/glcdi/.well-known/openid-configuration | jq -r .issuer
# expected: http://localhost:8090/auth/realms/glcdi
```

Verify:
- Admin console at `http://localhost:8090/auth/admin` (admin/admin from `.env`).
- Realm `glcdi` shows clients `glcdi-ui`, `glcdi-connector-caney-fork`, `glcdi-connector-point-blue`, `glcdi-connector-white-buffalo`.
- Groups `caney-fork-team`, `point-blue-team`, `white-buffalo-team` with the role / attribute assignments from § 2.3.
- Users `caney-fork`, `point-blue`, `white-buffalo` exist; each is in its team group.

### 3.3 Spin up two participant stacks (caney-fork as provider, white-buffalo as consumer)

In separate terminals:

```bash
# Terminal A — caney-fork (provider)
cd participant-agent-services
cp .env.example .env.caney-fork
# Edit .env.caney-fork:
#   PARTICIPANT_NAME=caney-fork
#   AUTHORITY_KEYCLOAK_URL=http://host.docker.internal:8090
#   OIDC_CLIENT_ID=glcdi-ui
#   GLCDI_UI_CLIENT_SECRET=<from authority-services init-secrets>
#   EDC_API_KEY=$(openssl rand -hex 32)   # rotate from default 123456
#   ports: 8080, 19193 (or whatever you've configured)
cp participant/configuration.properties.example participant/configuration.properties
# Edit configuration.properties:
#   web.http.management.auth.key = <same as EDC_API_KEY above>
#   edc.dsp.callback.address = http://host.docker.internal:8080/protocol
docker compose --env-file .env.caney-fork up -d
```

```bash
# Terminal B — white-buffalo (consumer)
# Same shape, with PARTICIPANT_NAME=white-buffalo and different ports (8081, 19194)
docker compose --env-file .env.white-buffalo up -d
```

Verify both stacks:
- `docker compose ps` for each — all services healthy, no `keycloak` or `postgres-kc` services.
- `curl -H "X-Api-Key: <EDC_API_KEY>" http://localhost:19193/management/v3/assets/request -X POST -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' -H 'Content-Type: application/json'` returns `[]` (empty list, no assets seeded yet) — proves `X-Api-Key` works, management API is reachable.

### 3.4 Seed the M1 fixtures

Until Phase 4's seeding scripts land, seed manually via Bruno's `10-provider-seeding/` folder, or via `curl` directly:

- Asset `urn:glcdi:asset:caney-fork:grazing-soc-2024` with HttpData source.
- Access policy `regenerative-producers-only` referencing `glcdi:certificationStatus eq "regenerative-verified"` (and/or the `glcdi_regenerative_producer` role check, depending on Phase 4's resolution).
- Contract policy `internal-use-only` with `odrl:purpose eq glcdi:InternalAnalysis`.
- Contract definition binding the asset to both policies.

### 3.5 Run the Bruno collection

```bash
cd management/bruno
# Edit environments/local.bru to set the secrets / api keys you generated above
bru run --env local
```

Expected outcomes:

| Folder | Assertion | Status |
|--------|-----------|--------|
| `00-auth/01–03` | tokens fetched; expected `glcdi_*` claims present | ✅ |
| `20-catalog-discovery/01-catalog-as-regen-producer.bru` | white-buffalo sees the M1 asset | ✅ — this is the M1 positive |
| `20-catalog-discovery/02-catalog-as-researcher.bru` | point-blue does NOT see it (filtered) | ✅ — this is the M1 negative |
| `30-negotiation/01-negotiate-internal-purpose.bru` | reaches FINALIZED (after polling — see Bruno notes) | ✅ |
| `30-negotiation/02-negotiate-research-purpose.bru` | reaches TERMINATED | ✅ |
| `40-transfer/01-initiate-transfer.bru` | transfer-process completes | ✅ |
| `99-negative-auth/01,02` | 401 returned | ✅ |

If any row fails, see § 3.7 below.

### 3.6 Smoke-test the participant UI

Open `http://localhost:8080` (caney-fork) in a browser:

- Login redirects to Authority KC at `localhost:8090`. Log in as `caney-fork`. After auth, lands on the catalog page.
- Browse to assets / policies / contract definitions / contract negotiations sections — each component renders.
- Open browser DevTools, set `localStorage.setItem('glcdi_operator_api_key', '<EDC_API_KEY>')`, refresh — verify API-key login flow works as documented in `participant-ui/README.md`.

### 3.7 Common failure modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Bruno's `00-auth/*` returns 401 from Authority KC | `glcdi-connector-<org>` client secret mismatch, or service account not in the org's group (so the token doesn't carry claims) | Verify in admin console; rotate secret; ensure SA → Service Accounts → Groups membership |
| Bruno's `20-catalog-discovery/01` returns 200 but asset missing from response | Access policy not seeded, or seeded with a constraint that doesn't match the JWT's claim shape | Verify the policy JSON; verify the JWT claims via `00-auth/02-fetch-token-as-white-buffalo.bru`'s decode assertions |
| Catalog query returns DSP error | EDC connector not configured for OIDC token validation (Phase 3.5 not in place yet — `iam-mock` accepts everything but doesn't validate) | If the test is flaky here, the M1 acceptance criteria assume Phase 3.5 has landed; if you're pre-3.5, this row of the Bruno is informational only |
| UI silent-iframe errors in console | `glcdi-ui` client missing `silent-callback.html` redirect URI | Add `https://localhost:8080/silent-callback.html` (and the participant-host variants) to `glcdi-ui` Valid Redirect URIs in admin console |
| Negotiation hangs in REQUESTED forever | `edc.dsp.callback.address` mismatch between the two participants | Check both `participant/configuration.properties` files — must match the external host the *other* connector calls back to |
| oauth2-proxy returns 502 on `/management/*` | OIDC issuer URL or JWKS URL pointing somewhere unreachable | Verify `OAUTH2_PROXY_OIDC_ISSUER_URL` and `OAUTH2_PROXY_OIDC_JWKS_URL` in compose env; test with `curl` from inside the oauth2-proxy container |
| Bruno test for the participant UI's `tems-transfers-list` component fails because the component isn't rendered | Component not configured in `participant-ui/config.json` (Track F finding — deferred) | Add the component to `config.json.template` per § 4.5.F; rebuild and redeploy the participant UI image |

---

## 4. Workflow recommendations

- **Local validation is the gate before staging.** Don't push to staging if Bruno doesn't run green locally. Catching a misnamed claim or a missing redirect URI on the laptop is cheaper than catching it in a maintenance window.
- **Cycle the local stack frequently** while iterating on policies (Phase 4) and policy functions (Phase 3) — `docker compose down -v` resets state cleanly.
- **Snapshot before destructive changes** even locally (small disk overhead; saves a re-init if a config goes sideways).
- **Use the same `.env` shape locally and in staging.** The only differences should be hostnames, ports, and secrets — not the variable names or which services are present.

---

## 5. Open items / future work

- **Phase 3.5 prerequisite for full Bruno green.** Until `iam-oauth2` is wired in (currently `iam-mock` is the IdentityService), the policy engine doesn't actually evaluate `glcdi_*` claims. Local validation can prove the auth path (token issuance, X-Api-Key gating, oauth2-proxy validation) but not the policy decisions themselves. Re-run § 2.5 / § 3.5 after Phase 3.5.
- **Realm-import determinism.** The `glcdi-realm.json` is imported only on first boot. Operators applying changes through Path B (live admin console) must keep the in-repo JSON in sync manually. Future work: a CI check that fails if the in-repo JSON drifts from the live realm export.
- **Per-participant deployment-config templates.** Today each participant copies `.env.example` and edits manually. A small generator script (one-shot per onboarding) would reduce config drift between participants.
- **Phase 7.1 Payment workflow.** When [`PAYMENT_GATING.md`](PAYMENT_GATING.md) v0 ships, this doc gets a sub-section under § 2 / § 3 covering the SMTP-recipient env var and the `payment-status-extension` deploy.

---

## References

- [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) — phased plan, especially § 1.5 (Authority cleanup + identity simplification), § 4.5 (Bruno + UI tracks), § Milestone M1.
- [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) — operator checklist focused on the rename (DNS, TLS, KC paths A/B, CI/CD vars, VM layout).
- [`IDENTITY.md`](IDENTITY.md) — post-Phase-1.5 identity architecture, claim model, OIDC vs OID4VC rationale.
- [`PAYMENT_GATING.md`](PAYMENT_GATING.md) — payment-required workflow design (post-M1).
- [`bruno/`](bruno/) — Bruno HTTP-test collection for the M1 scenario (track 4.5.E).
- [`policies/`](policies/) — ODRL policy templates (the `regenerative-producers-only` access policy and `internal-use-only` contract policy used in M1 live in `policies/access/` and `policies/contract/`).
