# GLCDI Deployment & Validation

Operator runbook for applying [Phase 1.5 (Identity Tier 1)](IMPLEM_PLAN.md#phase-15-identity-tier-1--single-tier-auth--authority-cleanup) changes to staging, plus a local-stack validation procedure that lets developers prove the M1 scenario end-to-end before pushing to staging.

This document complements [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) (which is focused narrowly on the `governance → authority` rename) by covering the Phase 1.5 topology cuts: **removing the per-participant Keycloak and oauth2-proxy** from the participant compose, provisioning the **3 connector service-account clients** in the Authority KC, switching the participant UI to **API-key-only login**, and rotating the API keys + connector secrets out of their `changeme-*` defaults. Everything below is put forward as a proposal for the project team and Dataspace Authority to validate; nothing here is a decided commitment.

> **Tier scope.** This runbook covers the **Tier 1** cutover only - no end-user OIDC, no `oauth2-proxy`, no `glcdi-ui` client validation. Tier 2 ([`IMPLEM_PLAN § 7.2`](IMPLEM_PLAN.md#phase-72-identity-tier-2--add-user-oidc-at-the-ui)) layers user OIDC back on top of the Tier-1 cluster as a separate, post-M1 cutover; the Tier-2 follow-up appendix in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) lists the additional operator steps for that phase.

## TL;DR

- **Staging deployment** in the current GLCDI environment is mostly a **container-restart exercise**. DNS for `authority.glcdi.startinblox.com` and the per-participant hosts is already resolving; nginx, certbot/TLS and the `.env` files on each VM are already valid. The Tier-1 cutover is: snapshot Postgres volumes → refresh the Authority Keycloak realm (Path A: wipe volume + re-import the in-repo `glcdi-realm.json`; or Path B: targeted admin-console edits) → `docker compose down && docker compose up -d` on each participant VM against the post-1.5 compose (no participant KC, no oauth2-proxy). Indicative window: ~20 min for the realm + ~10 min per participant + verification time.
- **Local validation** spins up Authority KC + two participant stacks (one provider, one consumer) on the developer's laptop, seeds the M1 fixtures, and runs the Bruno collection (`management/bruno/`) end-to-end with `X-Api-Key` only. The two acceptance signals are (1) a green Bruno run and (2) the participant UI surfaces the asset / policy / contract / negotiation / transfer-process components correctly under API-key login.
- **The rename runbook in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) only matters if your environment hasn't already migrated DNS/TLS/`.env`/nginx.** Current GLCDI staging is past that point; this doc is the simpler restart-and-verify procedure that follows.

### Fast local bootstrap via `scripts/glcdi.sh`

**Workspace prerequisites.** `scripts/glcdi.sh` orchestrates the whole GLCDI stack, so it needs the sibling repos checked out **next to** the `management/` repo (this documentation lives in its own git repo; the code lives in others). From a clean workspace root:

```sh
git clone git@git.startinblox.com:applications/glcdi/management.git             # this repo
git clone git@git.startinblox.com:applications/glcdi/authority-services.git     # Authority KC + onboarding portal (formerly governance-services/ - see AUTHORITY_MIGRATION.md)
git clone git@git.startinblox.com:applications/glcdi/participant-agent-services.git   # Per-participant Compose stack
git clone git@git.startinblox.com:applications/glcdi/edc-connector.git          # EDC control-plane / data-plane distribution
git clone git@git.startinblox.com:applications/glcdi/edc-glcdi-extension.git    # GLCDI-specific EDC extensions (copy-merged into edc-connector/ at build time)
git clone git@git.startinblox.com:applications/glcdi/participant-ui.git         # Catalogue UI image
```

Resulting layout:

```
<workspace-root>/
├── authority-services/         (or governance-services/ - the script accepts either)
├── edc-connector/
├── edc-glcdi-extension/
├── management/                 ← this repo - runs the script from here
├── participant-agent-services/
└── participant-ui/
```

The script resolves every path relative to its own location (`SCRIPT_DIR/../..`) so it does not care where the workspace root lives, only that the sibling directories are there. `preflight` fails fast with a clear message if any of them is missing.

Everything in § 3 (Authority Keycloak + provider participant + consumer participant + seeding + Bruno) then collapses to one command from the workspace root:

```sh
./management/scripts/glcdi.sh all         # preflight → build → up → seed → test
```

Or, step by step (so you can iterate on any single stage):

```sh
./management/scripts/glcdi.sh preflight   # docker / openssl / curl / jq / bru
./management/scripts/glcdi.sh build       # controlplane + participant-ui + djangoldp-backend images
./management/scripts/glcdi.sh up          # Authority KC on :8090 + 3 participant stacks on :8080/:8081/:8082
./management/scripts/glcdi.sh seed        # Bruno 10-provider-seeding against caney-fork
./management/scripts/glcdi.sh test        # Bruno run (tier1 by default)
./management/scripts/glcdi.sh reset       # docker compose down -v + wipe .glcdi.local/
```

The three participant stacks are one provider, one consumer, and one third-party (see § 3.3 for the role split); any two of the three demonstrate the M1 catalog / negotiation / transfer flow.

**Env files: nothing to edit by hand for the default flow.** The script generates and rotates every secret and config file under `management/scripts/.glcdi.local/` on first `up`:

| Generated file | What's in it |
|---|---|
| `.glcdi.local/secrets.env` (mode 600) | Per-org API keys + `glcdi-connector-<org>` client secrets + KC admin password + DB passwords, all `openssl rand`. Regenerate with `rm .glcdi.local/secrets.env` (then run `reset` before the next `up` - realm JSON only re-imports on a KC first boot). |
| `.glcdi.local/glcdi-realm.json` | Copy of `authority-services/resources/keycloak/realms/glcdi-realm.json` with `changeme-*` client secrets patched to the rotated values, bind-mounted over the in-repo original. |
| `.glcdi.local/authority.env` + `authority.override.yml` | Authority KC + onboarding-backend compose config (KC on `:8090`, onboarding on `:8083`, admin password from secrets). |
| `.glcdi.local/<org>/.env` + `docker-compose.override.yml` + `participant/configuration.properties` | Per-participant compose config for `caney-fork` / `point-blue` / `white-buffalo`, pointed at the Authority KC via `host.docker.internal:8090`, with `edc.dsp.callback.address` matched to each org's external port. |

The only inputs you might override are environment variables on the invocation itself:

- `GLCDI_TIER=tier2` - switches Bruno's auth model (post-§ 7.2 only; the script itself doesn't currently re-shape the compose per tier).
- `GLCDI_FARMOS=1` - additionally brings up the optional caney-fork farmOS site on `:8091`; run `./glcdi.sh farmos-install` once after the first `up`.
- `GLCDI_USE_LOCAL_PACKAGES=true` (+ `GLCDI_SIB_CORE_PATH=…`, `GLCDI_PKG_PATH=…`, etc.) - swap the participant UI's CDN-loaded `@startinblox/glcdi` bundle for a local Vite dev-server URL.

Full subcommand reference, iteration workflows, and capability-vs-gated matrix in [`scripts/README.md`](scripts/README.md).

---

## 1. Pre-flight (before touching any deployed environment)

In the current GLCDI staging environment, the heavy infrastructure pieces are **already in place** - the Tier-1 cutover is mostly container restarts plus the Authority Keycloak realm-import refresh. Quick confirmation list:

| Item | Status (current GLCDI staging) | Action if not in this state |
|------|-------------------------------|----------------------------|
| DNS for `authority.glcdi.startinblox.com` and per-participant hosts | ✅ already resolving | Add records per [`AUTHORITY_MIGRATION.md` § 1](AUTHORITY_MIGRATION.md) |
| Nginx config on each VM | Tier-1 update: `/management/*` proxied **directly** to the connector (no oauth2-proxy hop); `/oauth2/*` route removed | Update per `participant-agent-services/nginx/` |
| `.env` on each VM | Tier-1 envvars: `AUTHORITY_KEYCLOAK_URL`, per-org `EDC_OAUTH_CLIENT_ID=glcdi-connector-<org>`, `EDC_OAUTH_CLIENT_SECRET`, `EDC_API_KEY` (rotated). **No `OIDC_CLIENT_ID`, no `GLCDI_UI_CLIENT_SECRET`, no `LOCAL_KEYCLOAK_*`** - those return at Tier 2. | Apply the Tier-1 changes; re-deploy |
| Certbot / TLS certs | ✅ already issued and renewing | Issue per `AUTHORITY_MIGRATION.md` § 2 |
| In-repo changes merged across the four sibling repos | Verify with `git log` on `main` | Land the per-repo Phase 1.5 commits |
| Container images rebuilt and published | Verify image digests; specifically the `participant-ui` image with **OIDC envvars stripped** (Tier-1 strip-down per [`IMPLEM_PLAN § 4.5.F`](IMPLEM_PLAN.md#45f-participant-ui-configuration-track-f--parallel-agent)) | CI rebuild |
| Secrets rotated and stored | `web.http.management.auth.key` / `edc.api.auth.key` / `edc.api.control.auth.apikey.value` ≠ `123456`; per-org `glcdi-connector-<org>` secrets minted from the realm-JSON `changeme-*` placeholders | Rotate per `AUTHORITY_MIGRATION.md` § 4 |
| Bruno collection runs cleanly against local stack | See § 3 (local validation) | Unblock by fixing the local issue first; staging green requires local green |

**If everything in the "current GLCDI staging" column is ✅, the cutover is the simplified procedure in § 2.** If any row is red, do those rows first (with the runbook in `AUTHORITY_MIGRATION.md`) before § 2.

---

## 2. Staging deployment

The Phase 1.5 cutover for the current GLCDI staging is **mostly a container-restart exercise**: DNS, TLS, nginx, `.env` are already valid; the project just needs the Authority Keycloak realm to be refreshed and every container to come back up against the post-1.5 compose files / images. Indicative duration: ~20 minutes for the realm refresh + 10 minutes per participant restart, plus snapshot and verification time.

### 2.1 Maintenance window & snapshots

Announce ≥ 24 hours ahead. During the window: management API, catalog queries, and contract negotiations are unavailable across the dataspace.

Before any destructive change:
- **Authority Keycloak Postgres volume** - full snapshot (live admin-console edits live only there).
- **Each participant connector's Postgres volume** - full snapshot.
- **Live `glcdi-realm.json`** - export via Admin API, store next to the in-repo version. Lets you compare what's in production vs. what the in-repo JSON will import.
- **VM filesystem snapshots** if the cloud provider supports them.

### 2.2 Authority Keycloak - refresh the realm

The in-repo `authority-services/resources/keycloak/realms/glcdi-realm.json` declares the realm content used by **both Tier 1 (load-bearing for M1)** and **Tier 2 (inert at Tier 1, becomes load-bearing in [`IMPLEM_PLAN § 7.2`](IMPLEM_PLAN.md#phase-72-identity-tier-2--add-user-oidc-at-the-ui))**:

**Tier 1 - load-bearing for M1:**
- 12 realm roles (`user`, `admin`, plus `glcdi_member`, `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, and 6 future participant types).
- 1 client scope `glcdi-claims` carrying the 5 protocol mappers (realm-roles → `glcdi_roles`; user-attribute → `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`).
- **3 `glcdi-connector-<org>` service-account clients** (`caney-fork`, `point-blue`, `white-buffalo`) with `serviceAccountsEnabled: true`, `glcdi-claims` in default scopes.
- **3 service-account users** (one per connector client, auto-created from each client) with `glcdi_*` realm roles + per-user attributes set per [`IMPLEM_PLAN § 1.5.4`](IMPLEM_PLAN.md#154-provision-connector-service-account-clients-in-the-authority-keycloak).
- Empty `identityProviders` (no federation).

**Tier 2 - declared but inert at Tier 1:**
- `glcdi-ui` client (will be activated when Tier-2 oauth2-proxy is reintroduced).
- 3 groups (`caney-fork-team`, `white-buffalo-team`, `point-blue-team`).
- 3 starter human users (`caney-fork`, `white-buffalo`, `point-blue`) - added to their team groups with attributes set.

> **Tier-1 carryover (kept by design):** the Tier-2 content imports alongside the Tier-1 content but does no harm at Tier 1 - there's no oauth2-proxy validating those users' tokens, no UI redirecting to KC. **The chosen approach is to keep them in** the realm JSON throughout: it makes the Tier-2 cutover a flag-flip (turn oauth2-proxy back on, restore UI envvars) rather than a re-import. The handful of inert KC rows at Tier 1 is the right trade-off.

Three options to get this content into the live Authority KC, in order of recommendation:

#### Option 1 - Full re-import (destructive, simplest for the cutover)

Wipe the Authority KC's Postgres volume and let KC re-import the realm JSON on first boot. Recommended for the Phase 1.5 cutover when there are no console-side edits to preserve.

```bash
# On the Authority VM, with snapshot already taken in § 2.1
cd /glcdi/authority-services
docker compose down

# Identify the Postgres volume (name typically `authority-services_authority-pg-data`
# but verify with `docker volume ls`)
docker volume ls | grep -i authority
docker volume rm authority-services_authority-pg-data

# Bring the stack back up - KC re-imports glcdi-realm.json on first boot
docker compose up -d

# Wait ~30s for the import to complete, then verify
sleep 30
curl -fsSL https://authority.glcdi.startinblox.com/auth/realms/glcdi/.well-known/openid-configuration \
  | jq -r .issuer
# Expected: https://authority.glcdi.startinblox.com/auth/realms/glcdi
```

Smoke check via admin console (`https://authority.glcdi.startinblox.com/auth/admin`, log in as `admin/admin`, change the password):
- **Clients** list contains the three `glcdi-connector-<org>` entries (Tier 1 load-bearing) plus `glcdi-ui` (Tier 2 carryover, inert at Tier 1).
- **Client Scopes** list contains `glcdi-claims` with 5 protocol mappers.
- **Users** list contains the three `service-account-glcdi-connector-<org>` entries (Tier 1 load-bearing) plus three starter human users `caney-fork`, `point-blue`, `white-buffalo` (Tier 2 carryover).
- **Groups** list contains `caney-fork-team`, `point-blue-team`, `white-buffalo-team` (Tier 2 carryover).
- **Identity Providers** list is empty.

Any subsequent admin-console edits made before the next re-import will live only in Postgres - keep the in-repo JSON in sync (or re-export with `kc.sh export ...` periodically).

#### Option 2 - Partial import via Admin REST API (non-destructive, scriptable, recommended for incremental updates)

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

#### Option 3 - Admin Console manual edits (last resort, when partial-import support is patchy)

Walk the admin console step by step. Useful when KC version doesn't support partialImport for some resource type, or for one-off fixes. The detailed checklist is in [`AUTHORITY_MIGRATION.md` § 3 Path B](AUTHORITY_MIGRATION.md). Phase 1.5 (Tier 1) specifically adds:

- Confirm or create the `glcdi-claims` client scope with the 5 protocol mappers.
- Create the 3 `glcdi-connector-<org>` clients (`client_credentials` only; `glcdi-claims` in default scopes).
- Create the 13 realm roles (or at least the GLCDI ones not already present).
- For each connector client's auto-created service-account user: assign the org's `glcdi_*` realm roles; set per-user attributes (`glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`).
- Mint and rotate client secrets out-of-band.

Path A in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) (wipe + re-import) is the clean way to apply all of the above in one shot. Option 3 is for surgical fixes. Tier-2 follow-up (groups + human users + `glcdi-ui` activation) is in [`AUTHORITY_MIGRATION.md`'s Tier-2 appendix](AUTHORITY_MIGRATION.md#appendix-tier-2-follow-up-checklist-post-m1-optional).

#### About the per-user attributes

At Tier 1, the realm JSON sets `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status` on each **service-account user** directly. This is the *only* place those attributes need to live for connector ↔ connector policy evaluation. (At Tier 2, the same attributes get set on the per-org *human* users, again on the user record - stock Keycloak's `oidc-usermodel-attribute-mapper` reads user attributes only, there's no built-in mapper for group attributes.) Adding a new participant at Tier 1 = create a new connector client + SA user with the same attribute shape (the `EXTENSIONS=(...)` array pattern in [`IMPLEM_PLAN § 2.7`](IMPLEM_PLAN.md#27-integration-with-the-onboarding-flow-tier-1-out-of-band)).

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
echo "New secret: $NEW_SECRET - store in GLCDI_CONNECTOR_CANEY_FORK_SECRET on the participant VM"
```

Repeat for each of the 3 connector clients (`caney-fork`, `point-blue`, `white-buffalo`). The `glcdi-ui` client is **not used at Tier 1**; rotating its secret can be deferred to the Tier-2 follow-up.

### 2.3 Participant stacks - restart against the post-1.5 images

For each participant VM (`caney-fork`, `point-blue`, `white-buffalo`), in sequence:

1. `cd /glcdi/participant-agent-services && git pull` (lands the Tier-1 compose with `keycloak`, `postgres-kc`, **and `oauth2-proxy`** services removed).
2. `docker compose pull` to get any newly-published `participant-ui` image with the Tier-1 entrypoint defaults (no OIDC envvars, API-key login).
3. `docker compose down` - brings down the existing stack including the now-orphan `keycloak`, `postgres-kc`, and `oauth2-proxy` services from the old compose.
4. (Optional, recoverable from § 2.1 snapshot) `docker volume rm <stack>_keycloak-pg-data` - the per-participant Keycloak data is no longer used.
5. `docker compose up -d`.
6. `docker compose ps` - expected services: `db-connector`, `edc-connector`, `catalogue-ui`, `identity-hub`, `nginx`. **No** `keycloak`, `postgres-kc`, or `oauth2-proxy`.
7. Quick smoke: `curl -fsSL https://<participant-host>/management/v3/assets/request -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $EDC_API_KEY" -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}'` - returns 200 with a JSON list (assets list, possibly empty pre-Phase-4 seeding).

The `.env` on the VM doesn't need editing during the cutover (already done out-of-band). If something is wrong with `.env`, fix it before restarting - `docker compose up -d` will pick it up.

### 2.5 Post-cutover verification

Run the [Bruno collection](bruno/) (`management/bruno/`) against staging:

```bash
cd management/bruno
bru run --env staging
```

Expected: green run. Specifically:
- `00-auth/*` - connector `client_credentials` tokens fetched cleanly from Authority KC; JWTs decoded by Bruno carry the expected `glcdi_*` claims.
- `10-provider-seeding/*` - caney-fork connector accepts the asset/policy/contract-definition POSTs with `X-Api-Key` only.
- `20-catalog-discovery/01-catalog-as-regen-producer.bru` - white-buffalo sees the M1 fixture asset.
- `20-catalog-discovery/02-catalog-as-researcher.bru` - point-blue does NOT see it (filtered).
- `30-negotiation/01` - internal-purpose negotiation reaches FINALIZED.
- `30-negotiation/02` - research-purpose negotiation reaches TERMINATED.
- `40-transfer/01` - transfer initiates and succeeds.
- `99-negative-auth/*` - no-key and wrong-key calls return 401.

> **Pre-§ 3.5 caveat:** until [`IMPLEM_PLAN § 3.5`](IMPLEM_PLAN.md#35-replace-iam-mock-with-iam-oauth2-and-configure-claim-extraction) ships the `iam-mock` → `iam-oauth2` swap, DSP-level identity is the mock's fixed claims - the policy filtering scenarios above (catalog-discovery / negotiation) still pass against the *expected* outcome but the underlying claim chain isn't real yet. The Bruno auth folder (`00-auth/*`) verifies the Authority-KC side of the chain works; the connector-side validation happens once § 3.5 lands.

Also verify in browser dev tools (one happy-path session):
- **No** calls to any Keycloak host. The catalogue UI authenticates to its local connector with `X-Api-Key` only.
- Management API calls carry **only** `X-Api-Key` (no `Authorization: Bearer`). At Tier 2, both will be present; at Tier 1, just the API key.
- No `silent-callback` requests in flight (the Tier-1 strip-down removes that path entirely).

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

Verify (Tier 1):
- Admin console at `http://localhost:8090/auth/admin` (admin/admin from `.env`).
- Realm `glcdi` shows clients `glcdi-connector-caney-fork`, `glcdi-connector-point-blue`, `glcdi-connector-white-buffalo` (Tier 1 load-bearing) plus `glcdi-ui` (Tier 2 carryover, inert at Tier 1).
- Mint a token for `glcdi-connector-caney-fork` via `client_credentials` and decode it (per [`IMPLEM_PLAN § 2.5`](IMPLEM_PLAN.md#25-verify-token-contents)). Expected claims: `glcdi_organisation=caney-fork`, `glcdi_roles=["glcdi_member","glcdi_producer"]`, `glcdi_certification_status=regenerative-verified`.

### 3.3 Spin up two participant stacks (caney-fork as provider, white-buffalo as consumer)

In separate terminals:

```bash
# Terminal A - caney-fork (provider)
cd participant-agent-services
cp .env.example .env.caney-fork
# Edit .env.caney-fork:
#   PARTICIPANT_NAME=caney-fork
#   AUTHORITY_KEYCLOAK_URL=http://host.docker.internal:8090
#   EDC_OAUTH_CLIENT_ID=glcdi-connector-caney-fork
#   EDC_OAUTH_CLIENT_SECRET=<rotated from realm-JSON placeholder>
#   EDC_API_KEY=$(openssl rand -hex 32)   # rotate from default 123456
#   ports: 8080, 19193 (or whatever you've configured)
cp participant/configuration.properties.example participant/configuration.properties
# Edit configuration.properties:
#   web.http.management.auth.key = <same as EDC_API_KEY above>
#   edc.dsp.callback.address = http://host.docker.internal:8080/protocol
#   edc.oauth.client.id = glcdi-connector-caney-fork           # post §3.5
#   edc.oauth.client.secret.alias = edc-oauth-client-secret    # post §3.5
docker compose --env-file .env.caney-fork up -d
```

```bash
# Terminal B - white-buffalo (consumer)
# Same shape, with PARTICIPANT_NAME=white-buffalo,
#   EDC_OAUTH_CLIENT_ID=glcdi-connector-white-buffalo, and different ports (8081, 19194)
docker compose --env-file .env.white-buffalo up -d
```

Verify both stacks:
- `docker compose ps` for each - all services healthy, **no** `keycloak`, `postgres-kc`, or `oauth2-proxy` services.
- `curl -H "X-Api-Key: <EDC_API_KEY>" http://localhost:19193/management/v3/assets/request -X POST -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' -H 'Content-Type: application/json'` returns `[]` (empty list, no assets seeded yet) - proves `X-Api-Key` works, management API is reachable directly (no oauth2-proxy hop).

### 3.4 Seed the M1 fixtures

Until Phase 4's seeding scripts land, seed manually via Bruno's `10-provider-seeding/` folder, or via `curl` directly:

- Asset `urn:glcdi:asset:caney-fork:grazing-soc-2024` with HttpData source.
- Access policy `regenerative-producers-only` referencing `glcdi:certificationStatus eq "regenerative-verified"` (and/or the `glcdi_producer` role check, depending on Phase 4's resolution).
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
| `20-catalog-discovery/01-catalog-as-regen-producer.bru` | white-buffalo sees the M1 asset | ✅ - this is the M1 positive |
| `20-catalog-discovery/02-catalog-as-researcher.bru` | point-blue does NOT see it (filtered) | ✅ - this is the M1 negative |
| `30-negotiation/01-negotiate-internal-purpose.bru` | reaches FINALIZED (after polling - see Bruno notes) | ✅ |
| `30-negotiation/02-negotiate-research-purpose.bru` | reaches TERMINATED | ✅ |
| `40-transfer/01-initiate-transfer.bru` | transfer-process completes | ✅ |
| `99-negative-auth/01,02` | 401 returned | ✅ |

If any row fails, see § 3.7 below.

### 3.6 Smoke-test the participant UI (Tier 1: API-key login)

Open `http://localhost:8080` (caney-fork) in a browser:

- The page loads directly - **no Keycloak redirect**. The UI shows a prompt to enter the operator API key on first load (Tier-1 strip-down per [`IMPLEM_PLAN § 4.5.F`](IMPLEM_PLAN.md#45f-participant-ui-configuration-track-f--parallel-agent)).
- Paste `<EDC_API_KEY>` into the prompt; the UI stores it in `localStorage.glcdi_operator_api_key` and uses it as `X-Api-Key` on every management-API call.
- Browse to assets / policies / contract definitions / contract negotiations / transfer-processes sections - each component renders.
- Browser DevTools network tab: every `/management/*` request carries `X-Api-Key` and **no `Authorization: Bearer`**; no `silent-callback` requests in flight; no calls to any Keycloak host.

### 3.7 Common failure modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Bruno's `00-auth/*` returns 401 from Authority KC | `glcdi-connector-<org>` client secret mismatch, or service account missing the `glcdi-claims` scope on its default scopes (so the token doesn't carry claims) | Verify in admin console: client → Client Scopes → `glcdi-claims` is in defaults; rotate secret if it differs from `.env` |
| Bruno's `00-auth/*` token decodes to an empty claim payload | Service-account user is missing realm-role assignments and per-user attributes | Verify each `service-account-glcdi-connector-<org>` user has the right `glcdi_*` realm roles + attributes (per [`IMPLEM_PLAN § 1.5.4`](IMPLEM_PLAN.md#154-provision-connector-service-account-clients-in-the-authority-keycloak)) |
| `curl -H "X-Api-Key: …" .../management/…` returns 401 | API key on the request doesn't match `web.http.management.auth.key` in the connector's `configuration.properties` | Re-export `EDC_API_KEY=$(grep web.http.management.auth.key participant/configuration.properties | cut -d= -f2 | tr -d ' ')` and retry |
| Bruno's `20-catalog-discovery/01` returns 200 but asset missing from response | Access policy not seeded, or seeded with a constraint that doesn't match the JWT's claim shape | Verify the policy JSON; verify the JWT claims via the `00-auth/*` decode assertions |
| Catalog query returns 200 with the asset visible to *every* consumer (including `point-blue`) | Pre-§ 3.5 expected behaviour: `iam-mock` doesn't actually validate or extract claims, so the access policy receives a fixed mock identity | Expected pre-§ 3.5; the negative-case assertion (`point-blue` filtered out) only becomes load-bearing once `iam-oauth2` is wired |
| Negotiation hangs in REQUESTED forever | `edc.dsp.callback.address` mismatch between the two participants | Check both `participant/configuration.properties` files - must match the external host the *other* connector calls back to |
| Connector logs `Failed to obtain token from oauth2 IdP` after § 3.5 lands | `edc.oauth.token.url` / `edc.oauth.provider.jwks.url` / `edc.oauth.client.id` mismatch with Authority KC config | Verify all three properties resolve correctly; mint a `client_credentials` token manually with the same values to confirm it works end-to-end |
| Participant UI shows "Network error" trying to call `/management` and `localStorage.glcdi_operator_api_key` is set | `EDC_API_KEY` rotation got out of sync between `.env` (consumed by UI build) and `configuration.properties` (consumed by connector) | Rotate the key in both places to the same value; restart connector + rebuild UI image |
| Bruno test for the participant UI's `tems-transfers-list` component fails because the component isn't rendered | Component not configured in `participant-ui/config.json` (Track F finding - deferred) | Add the component to `config.json.template` per [`IMPLEM_PLAN § 4.5.F`](IMPLEM_PLAN.md#45f-participant-ui-configuration-track-f--parallel-agent); rebuild and redeploy the participant UI image |

---

## 4. Workflow recommendations

- **Local validation is the gate before staging.** Don't push to staging if Bruno doesn't run green locally. Catching a misnamed claim or a missing redirect URI on the laptop is cheaper than catching it in a maintenance window.
- **Cycle the local stack frequently** while iterating on policies (Phase 4) and policy functions (Phase 3) - `docker compose down -v` resets state cleanly.
- **Snapshot before destructive changes** even locally (small disk overhead; saves a re-init if a config goes sideways).
- **Use the same `.env` shape locally and in staging.** The only differences should be hostnames, ports, and secrets - not the variable names or which services are present.

---

## 5. Open items / future work

- **Phase 3.5 prerequisite for the Tier-1 claim chain to be load-bearing.** Until `iam-oauth2` is wired in (currently `iam-mock` is the IdentityService), the policy engine doesn't actually evaluate `glcdi_*` claims at the receiving connector. Local validation can prove the auth path (token issuance, `X-Api-Key` gating) but not the policy decisions themselves. Re-run § 2.5 / § 3.5 after Phase 3.5 - that's when M1 sign-off on Tier 1 becomes possible.
- **Realm-import determinism.** The `glcdi-realm.json` is imported only on first boot. Operators applying changes through Path B (live admin console) must keep the in-repo JSON in sync manually. Future work: a CI check that fails if the in-repo JSON drifts from the live realm export.
- **Per-participant deployment-config templates.** Today each participant copies `.env.example` and edits manually. A small generator script (one-shot per onboarding) would reduce config drift between participants.
- **Tier-2 cutover runbook.** When [`IMPLEM_PLAN § 7.2`](IMPLEM_PLAN.md#phase-72-identity-tier-2--add-user-oidc-at-the-ui) is approved, this doc gets a § 4 covering the additional cutover steps (oauth2-proxy reintroduction, UI OIDC restoration, per-org groups + human-user activation). The Tier-2 follow-up appendix in [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md#appendix-tier-2-follow-up-checklist-post-m1-optional) is the placeholder.
- **Phase 7.1 Payment workflow.** When [`PAYMENT_GATING.md`](PAYMENT_GATING.md) v0 ships, this doc gets a sub-section under § 2 / § 3 covering the SMTP-recipient env var and the `payment-status-extension` deploy.

---

## References

- [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) - phased plan, especially § 1.5 (Authority cleanup + identity simplification), § 4.5 (Bruno + UI tracks), § Milestone M1.
- [`AUTHORITY_MIGRATION.md`](AUTHORITY_MIGRATION.md) - operator checklist focused on the rename (DNS, TLS, KC paths A/B, CI/CD vars, VM layout).
- [`IDENTITY.md`](IDENTITY.md) - post-Phase-1.5 identity architecture, claim model, OIDC vs OID4VC rationale.
- [`PAYMENT_GATING.md`](PAYMENT_GATING.md) - payment-required workflow design (post-M1).
- [`bruno/`](bruno/) - Bruno HTTP-test collection for the M1 scenario (track 4.5.E).
- [`policies/`](policies/) - ODRL policy templates (the `regenerative-producers-only` access policy and `internal-use-only` contract policy used in M1 live in `policies/access/` and `policies/contract/`).
