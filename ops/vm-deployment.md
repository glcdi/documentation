# GLCDI VM Deployment

Operator runbook for deploying GLCDI changes to the staging (and, later, production) VMs. Covers the Authority VM and the per-participant VMs (`caney-fork`, `point-blue`, `white-buffalo`, `demo`).

**Most deploys are automated.** Each sibling repo's `.gitlab-ci.yml` has a `deploy-*` job that SSHes into its target VM, runs `git pull` in `/glcdi/<repo>/`, and re-brings the stack up with `docker compose up -d`. The jobs are **manual-trigger** (`when: manual`) so someone clicks the pipeline button, but everything after that is scripted. Manual, hands-on VM work is only needed for:

- Refreshing the Authority Keycloak realm content when `glcdi-realm.json` in the sibling `authority-services` repo changes (realm imports run only on first Keycloak boot).
- Rotating secrets that live in GitLab CI/CD variables + on the VMs' `.env` files.
- First-time VM provisioning (DNS, TLS, `.env`, nginx) — already in place today.
- Recovery / rollback when a deploy goes sideways.

For local development / verification, see [`local-stack.md`](local-stack.md). Local green is the gate before triggering a staging deploy.

---

## 1. The happy path — trigger the CI deploy job

Everyone-uses-this procedure for a standard deploy:

1. **Merge the change** into `main` on the relevant sibling repo (`edc-connector/`, `authority-services/`, `participant-agent-services/`, `participant-ui/`, or `edc-glcdi-extension/`).
2. **Open the pipeline** in GitLab (`https://git.startinblox.com/applications/glcdi/<repo>/-/pipelines`).
3. **Trigger the manual `deploy-*` job** for the target environment (typically `deploy-staging`). CI does the rest — SSH → `git pull` in `/glcdi/<repo>/` → `docker compose pull` → `docker compose up -d`.
4. **Watch the job log** — it prints `docker compose ps` at the end. Failures surface here.
5. **Verify** — run the Bruno collection against staging (see § 5).

That is normally all there is to it. Every subsequent section below is for the cases where the happy path doesn't apply.

---

## 2. Pre-flight (only when adding a new VM, or after infrastructure churn)

The heavy infrastructure pieces are **already in place** on the current staging VMs. Quick confirmation list if you're standing up a new one, or verifying after an outage:

| Item | Status (current GLCDI staging) | Action if not in this state |
|------|-------------------------------|----------------------------|
| DNS for `authority.glcdi.startinblox.com` and per-participant hosts | ✅ resolving | Add A/AAAA records and wait for propagation |
| Nginx config on each VM | Tier-1: `/management/*` proxied **directly** to the connector (no oauth2-proxy hop); `/oauth2/*` removed | Update per `participant-agent-services/nginx/` |
| `.env` on each VM | Tier-1 envvars: `AUTHORITY_KEYCLOAK_URL`, per-org `EDC_OAUTH_CLIENT_ID=glcdi-connector-<org>`, `EDC_OAUTH_CLIENT_SECRET`, `EDC_API_KEY` (rotated). **No `OIDC_CLIENT_ID`, no `GLCDI_UI_CLIENT_SECRET`, no `LOCAL_KEYCLOAK_*`** — those return at Tier 2. | Populate from `.env.example`; distribute secrets via GitLab CI/CD variables |
| Certbot / TLS certs | ✅ issued and renewing | Issue via Certbot (or your CA of choice) and configure auto-renewal |
| Container images built and published to `registry.startinblox.com` | ✅ CI publishes on `main` | If missing, trigger the `build-*` job in the relevant sibling repo |
| Secrets rotated from `changeme-*` / `123456` defaults | ✅ | Rotate secrets on each VM and re-import the realm (§ 3) |
| Bruno collection runs green locally | ✅ prerequisite before any staging deploy | Fix locally first — see [`local-stack.md`](local-stack.md) |

**VM layout.** Each sibling repo lives at `/glcdi/<repo>/` on its target VM. `.env` and `secrets/` are populated out-of-band from GitLab CI/CD variables (`init-secrets.sh` at deploy time, `delete-secrets.sh` after containers start).

---

## 3. Manual intervention — Authority Keycloak realm refresh

Needed **whenever `authority-services/resources/keycloak/realms/glcdi-realm.json` changes** (that file lives in the sibling `authority-services` repo) — new clients, new roles, new protocol mappers, or rotated `changeme-*` placeholders. Keycloak imports realm JSON **only on first boot**, so a plain `docker compose up -d` on the Authority VM ignores realm-JSON edits.

Three options in order of recommendation. Snapshot the Authority Postgres volume before any of them.

### Option 1 — Full re-import (destructive, simplest for a cutover)

Wipe the Authority KC's Postgres volume and let KC re-import the realm JSON on first boot. Recommended for cutovers when there are no console-side edits to preserve.

```bash
# On the Authority VM, with snapshot already taken
cd /glcdi/authority-services
docker compose down

# Identify the Postgres volume (name typically `authority-services_authority-pg-data`)
docker volume ls | grep -i authority
docker volume rm authority-services_authority-pg-data

# Bring the stack back up - KC re-imports glcdi-realm.json on first boot
docker compose up -d

# Wait ~30s, then verify
sleep 30
curl -fsSL https://authority.glcdi.startinblox.com/auth/realms/glcdi/.well-known/openid-configuration \
  | jq -r .issuer
# Expected: https://authority.glcdi.startinblox.com/auth/realms/glcdi
```

Smoke check via admin console (`https://authority.glcdi.startinblox.com/auth/admin`, log in as `admin` with the password from the vault):

- **Clients** list contains the three `glcdi-connector-<org>` entries (Tier-1 load-bearing) plus `glcdi-ui` (Tier-2 carryover, inert at Tier 1).
- **Client Scopes** list contains `glcdi-claims` with 5 protocol mappers.
- **Users** list contains the three `service-account-glcdi-connector-<org>` entries plus three starter human users (Tier-2 carryover).
- **Identity Providers** list is empty.

Any subsequent admin-console edits live only in Postgres until the next re-import — keep the in-repo JSON in sync (or re-export with `kc.sh export …` periodically).

### Option 2 — Partial import via Admin REST API (non-destructive, scriptable)

Use this when the live KC has manual admin-console state to preserve, or when applying incremental changes (e.g. adding a fourth participant later) without a full restart. Not ideal for full-realm cutovers because client-scope and protocol-mapper handling in `partialImport` varies by Keycloak version.

```bash
# 1. Get an admin token
KC_BASE=https://authority.glcdi.startinblox.com/auth
TOKEN=$(curl -fsSL -X POST "$KC_BASE/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
  -d "grant_type=password" \
  | jq -r .access_token)

# 2. Build a partial-import payload
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

The response lists how many of each resource type were `ADDED`, `OVERWRITTEN`, or `SKIPPED`. Caveats:

- Client scopes (the `glcdi-claims` scope) are **not** always covered by `partialImport`. If Option 2 is used and `glcdi-claims` is missing, create it through Option 3 (admin console) before running Option 2.
- Protocol mappers nested inside a client are imported when the client itself is `OVERWRITTEN`, but mappers added at realm-level (in a client scope) need a separate `POST /admin/realms/glcdi/client-scopes/{id}/protocol-mappers/models` per mapper.
- Service-account users (`service-account-glcdi-connector-<org>`) are auto-created when the client has `serviceAccountsEnabled=true`, but per-user attributes + group membership only land if the user records are included in the `partialImport` `users` field.

### Option 3 — Admin console manual edits (last resort)

Walk the admin console step by step. Useful when the KC version doesn't support `partialImport` for some resource type, or for one-off fixes. Option 1 (wipe + re-import) is the clean way to apply everything in one shot. Option 3 is for surgical fixes.

### Rotating client secrets after import

The realm JSON ships placeholder secrets (`changeme-glcdi-connector-caney-fork-secret`, etc.). After import, rotate via the admin console (Clients → `<client>` → Credentials → Regenerate secret) or via the Admin API:

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

Repeat for each of the 3 connector clients. The `glcdi-ui` client is **not used at Tier 1**; rotating its secret can be deferred to the Tier-2 follow-up ([`IMPLEM_PLAN § 7.2.7`](../build/plan/phase-7-future.md#727-cutover-operator-checklist)).

---

## 4. Snapshotting before destructive changes

Announce a maintenance window ≥ 24h ahead for any change that requires Option 1 (realm re-import) or wipes any participant volume.

Before any destructive change:

- **Authority Keycloak Postgres volume** — full snapshot (live admin-console edits live only there).
- **Each participant connector's Postgres volume** — full snapshot.
- **Live `glcdi-realm.json`** — export via Admin API, store next to the in-repo version so you can diff what's on prod against what the in-repo JSON would import.
- **VM filesystem snapshots** if the cloud provider supports them.

---

## 5. Post-deploy verification

Run the [Bruno collection](../build/bruno/) against staging:

```bash
cd management/build/bruno
bru run --env staging
```

Expected: green run. The per-folder assertion contract (`00-auth` / `10-provider-seeding` / `20-catalog-discovery` / `30-negotiation` / `40-transfer` / `99-negative-auth`) lives in [`../build/bruno/README.md`](../build/bruno/README.md).

Also verify in browser dev-tools (one happy-path session):

- **No** calls to any Keycloak host. The catalogue UI authenticates to its local connector with `X-Api-Key` only.
- Management API calls carry **only** `X-Api-Key` (no `Authorization: Bearer`). At Tier 2, both will be present; at Tier 1, just the API key.
- No `silent-callback` requests in flight.

---

## 6. Rollback plan

If verification fails and the issue can't be fixed within the maintenance window:

1. **Roll the compose files back** — `cd /glcdi/<repo> && git reset --hard <previous-sha>` on each affected VM.
2. **Restore Authority KC's Postgres volume** from the § 4 snapshot (only if the realm was refreshed).
3. **Restore each participant's Postgres volume** from the § 4 snapshot (only if a participant volume was wiped).
4. **`docker compose up -d`** on each rolled-back VM.
5. **Verify auth flow** with Bruno on one participant before declaring the rollback complete.
6. **Investigate root cause** offline before re-scheduling the deploy.

---

## 7. Full participant reset (nuclear)

If a participant VM has drift you can't unwind with a normal deploy (renamed assets leaving stale agreements, corrupt Postgres, etc.), use the dedicated reset runbook: [`staging-wipe.md`](staging-wipe.md). It drops the connector's Postgres volume, re-seeds the M1 fixtures with current IDs via `glcdi.sh seed --target <vm>`, and preserves the participant Keycloak realm + identity-hub state by default.

---

## 8. Open items

- **Realm-import determinism.** `glcdi-realm.json` is imported only on first boot. Operators applying changes through Option 3 (live admin console) must keep the in-repo JSON in sync manually. Future work: a CI check that fails if the in-repo JSON drifts from the live realm export.
- **Per-participant deployment-config templates.** Today each participant copies `.env.example` and edits manually. A small generator script (one-shot per onboarding) would reduce config drift between participants.
- **Tier-2 cutover.** When [`IMPLEM_PLAN § 7.2`](../build/plan/phase-7-future.md#72-identity-tier-2---add-user-oidc-at-the-ui) is approved, this doc gets a § covering the additional cutover steps (oauth2-proxy reintroduction, UI OIDC restoration, per-org groups + human-user activation). The operator checklist is already staged in [`IMPLEM_PLAN § 7.2.7`](../build/plan/phase-7-future.md#727-cutover-operator-checklist).
- **Phase 7.1 Payment workflow.** When [`../design/payment-gating.md`](../design/payment-gating.md) v0 ships, this doc gets a sub-section covering the SMTP-recipient env var and the `payment-status-extension` deploy.

---

## Related

- [`local-stack.md`](local-stack.md) — local end-to-end validation via `glcdi.sh`; the gate before any staging deploy.
- [`staging-wipe.md`](staging-wipe.md) — full participant reset (drops connector Postgres + re-seeds).
- [`../build/implementation-plan.md`](../build/implementation-plan.md) — phased plan; the Milestone M1 section defines what "green on staging" means.
- [`../reference/identity.md`](../reference/identity.md) — identity architecture; useful when diagnosing Bruno `00-auth/*` failures.
