# Authority Rename - Operator Migration Checklist

Live-infrastructure tasks required to complete the rename of the governance deployment from `governance-*` to the new Dataspace Authority name **and** apply the [Phase 1.5 (Identity Tier 1)](../build/plan/phase-1.5-identity-tier1.md) compose-stack cuts (removing the per-participant Keycloak + oauth2-proxy from the participant stack). The local (in-repo) renames and compose changes can be done by the project team (or by an automation agent) ahead of this checklist; the items below are the parts that require hands-on access to DNS, running services, and CI/CD secrets.

> **Scope at Tier 1:** the dataspace ships M1 with **no end-user OIDC anywhere** - the catalogue UI uses `X-Api-Key` only, and the Authority KC holds 3 connector service-account clients (one per participant org) for `client_credentials`-based DSP-level identity. `oauth2-proxy`, the `glcdi-ui` OIDC client, per-org groups, and human user accounts are deliberately deferred to **Tier 2** ([IMPLEM_PLAN § 7.2](../build/plan/phase-7-future.md#72-identity-tier-2---add-user-oidc-at-the-ui)). This checklist covers Tier 1 only; the Tier-2 follow-up appendix at the end lists the additional steps that re-enable user OIDC if/when that phase is approved.

## Status (confirm before executing)

| Item | Proposed | Confirmed? |
|------|----------|:---------:|
| New name (directory / DNS subdomain / client ID prefix) | `authority` | ☐ |
| Migration strategy | **Cutover** (brief downtime, simpler) vs. **Parallel** (dual-run, zero-downtime) | ☐ |
| Cutover date / maintenance window | TBD | ☐ |
| Rollback owner | TBD | ☐ |

The rest of this document assumes `authority` + cutover. If a different name is chosen, do a find-and-replace on this file to update commands and paths. If parallel is chosen, the sections below still apply but each touches *both* names until retirement.

## Prerequisites (done by project team / local before cutover)

- [ ] All in-repo renames merged across the four sibling repos (`edc-connector/`, `governance-services/` → `authority-services/`, `participant-agent-services/`, `participant-ui/`), plus `management/` and workspace `CLAUDE.md` files.
- [ ] Keycloak realm JSON (`authority-services/resources/keycloak/realms/glcdi-realm.json`) carries the **Tier 1** content: 13 realm roles, the `glcdi-claims` client scope, **3 `glcdi-connector-<org>` clients with `serviceAccountsEnabled: true`** and their service-account users with `glcdi_*` realm roles + attributes. (Tier-2 content - `glcdi-ui` client, per-org groups, human user accounts - is *also* declared in the JSON today; at Tier 1 it imports but stays inert. See appendix.)
- [ ] `participant-ui/` `config.json.template` and `docker-entrypoint.sh` carry the Tier-1 strip-down: no `KEYCLOAK_URL` / `OIDC_CLIENT_ID` / `KC_IDP_HINT` / `LINKED_PROVIDER_*` envvars; no `silent-callback.html`; API-key login is the only entry path.
- [ ] `participant-agent-services/docker-compose.yml` has the **`oauth2-proxy` service removed** (Tier 1 sends management traffic straight from nginx to the connector with `X-Api-Key`); per-participant `keycloak` and `postgres-kc` services + `keycloak-pg-data` volume removed.
- [ ] `participant-agent-services/participant/*.properties.example` + `.env.example` templates updated with new URLs, with the Tier-1 connector `client_credentials` shape (`edc.oauth.client.id=glcdi-connector-<org>`).
- [ ] CI pipelines dry-run green on a non-production branch.

---

## 1. DNS

- [ ] Create A or CNAME record for `authority.glcdi.startinblox.com` pointing at the same target as the current `governance.glcdi.startinblox.com`.
- [ ] Decide retention: does the old record cut immediately at cutover, or run dual-resolve for a transition window (recommended: keep the old record live for 7–14 days post-cutover as a soft fallback, then remove).
- [ ] Verify propagation (`dig authority.glcdi.startinblox.com`) before touching TLS or Keycloak.

## 2. TLS certificate

- [ ] Issue a certificate for the new hostname via certbot (or whatever cert manager is in place).
- [ ] Verify the cert covers both names during any dual-resolve window.
- [ ] Confirm the renewal cron / systemd timer picks up the new hostname.

## 3. Keycloak (live instance) - Tier 1 content

**Important context:** per `glcdi/CLAUDE.md` ("Things that will bite you"), realm JSON is only imported on first boot. Post-init changes to `glcdi-realm.json` have no effect unless the Postgres volume is wiped.

The Tier-1 realm content the live KC needs after cutover:

- 13 realm roles (`user`, `admin`, plus 11 `glcdi_*` roles).
- `glcdi-claims` client scope with 5 protocol mappers (realm-role mapper for `glcdi_roles`; user-attribute mappers for `glcdi_membership` / `glcdi_organisation` / `glcdi_certification_status` / `glcdi_contribution_status`).
- **3 `glcdi-connector-<org>` clients** (`caney-fork`, `point-blue`, `white-buffalo`) with `serviceAccountsEnabled: true`, `directAccessGrantsEnabled: false`, `standardFlowEnabled: false`, `glcdi-claims` in default scopes.
- **3 service-account users** (auto-created from the 3 clients) with `glcdi_*` realm roles + per-user attributes set per [`IMPLEM_PLAN § 1.5.4`](../build/plan/phase-1.5-identity-tier1.md#154-provision-connector-service-account-clients-in-the-authority-keycloak).

Two migration paths - pick one:

### Path A: Wipe Postgres volume and re-import

Simplest, recommended for a Tier-1 cutover when there are no console-side edits to preserve.

- [ ] Snapshot the current Postgres volume (rollback safety).
- [ ] Stop the governance Keycloak + Postgres containers.
- [ ] Remove the Postgres volume.
- [ ] Bring up the new stack with the renamed realm JSON.
- [ ] Verify the 3 connector clients exist; mint a test token for each via `client_credentials` (per [`deployment.md § 2.5`](deployment.md)) and decode it to confirm the expected `glcdi_*` claims.
- [ ] Re-assign any user attributes (`glcdi_certification_status`, `glcdi_contribution_status`) that were set out-of-band against existing SA users.

> The realm JSON also declares the Tier-2 `glcdi-ui` client, 3 per-org groups, and 3 starter human users. **By design these stay in throughout** - at Tier 1 they import but are inert (no oauth2-proxy validates their tokens, the UI doesn't redirect to KC), and at Tier-2 cutover they become active simply by turning oauth2-proxy back on (per the [Tier-2 follow-up appendix](#appendix-tier-2-follow-up-checklist-post-m1-optional)). Don't strip them.

### Path B: Live edit via admin console

Non-destructive, but tedious and error-prone. For Tier 1 the targeted edits are:

- [ ] Log into the admin console at the old hostname.
- [ ] Update **every redirect URI and Web Origin** on every client that references `governance.glcdi.startinblox.com` → `authority.glcdi.startinblox.com`. Typical clients affected: any pre-existing `edc-api-client`, `participant-broker`, plus the new `glcdi-connector-<org>` clients if their description URLs reference the old host.
- [ ] Create the 3 `glcdi-connector-<org>` clients if not already present (one per participant: `caney-fork`, `point-blue`, `white-buffalo`).
- [ ] Create / verify the `glcdi-claims` client scope and its 5 protocol mappers; add it to each connector client's default scopes.
- [ ] Create / verify the 13 realm roles; assign the appropriate `glcdi_*` roles to each connector client's auto-created service-account user.
- [ ] Set `glcdi_membership` / `glcdi_organisation` / `glcdi_certification_status` / `glcdi_contribution_status` attributes on each service-account user.
- [ ] Update the realm's display name / display name HTML if it mentions "Governance".
- [ ] Verify a `client_credentials` round-trip works for each connector client before proceeding.

**Recommendation:** Path A if the dataspace is genuinely pre-production. Path B if you must preserve admin-console state. Document which was used and why.

## 4. CI/CD variables (GitLab)

Every sibling repo has a `.gitlab-ci.yml` with `deploy-*` jobs that SSH into target VMs and run `docker compose`. Each pulls secrets from GitLab CI/CD variables. Audit and update:

- [ ] Any `GOVERNANCE_URL` / `KEYCLOAK_URL` CI/CD variable → `AUTHORITY_URL` / new Keycloak URL.
- [ ] **Per-org connector secrets** - one CI/CD variable per participant (`GLCDI_CONNECTOR_CANEY_FORK_SECRET`, `GLCDI_CONNECTOR_POINT_BLUE_SECRET`, `GLCDI_CONNECTOR_WHITE_BUFFALO_SECRET`) - rotated from the realm-JSON `changeme-*` placeholders and propagated to each participant VM's `.env`.
- [ ] Any `GLCDI_UI_CLIENT_SECRET` variable referenced in older deploy jobs - at Tier 1 the `glcdi-ui` client isn't authenticated against, so this can be left dangling or removed; comes back at Tier 2.
- [ ] Any SSH target variable pointing at a path with `governance-services` in it.
- [ ] Rotate any secret that appears in old logs / was baked into the old realm JSON.

Repos to audit: `edc-connector/`, `authority-services/` (formerly `governance-services/`), `participant-agent-services/`, `participant-ui/`.

## 5. VM layout

Per `glcdi/CLAUDE.md`, the VM layout is `/glcdi/<repo>/` on each target VM with `.env` and `secrets/` populated out-of-band.

On each deploy target VM:

- [ ] `cd /glcdi && mv governance-services authority-services` (or: clone the renamed repo fresh and migrate secrets/.env across).
- [ ] Copy or re-create `.env` and `secrets/` in the new directory (from the same out-of-band source that populated the old one).
- [ ] Update any systemd units, cron jobs, or nginx configs on the VM that reference `/glcdi/governance-services/`.
- [ ] Update the deploy job's `cd` path in `.gitlab-ci.yml` (already covered in the local prerequisite step).

## 6. Cutover deploy

Order matters. Recommended sequence during the maintenance window:

- [ ] Announce maintenance window to participants.
- [ ] Disable auto-deploy / freeze merges on the four repos for the window.
- [ ] **Snapshot:** Postgres volumes, VM filesystems, current realm JSON.
- [ ] Bring down the **participant-agent-services** stacks first.
- [ ] Bring down the **governance-services** stack.
- [ ] Execute the Keycloak path (A or B from §3).
- [ ] Bring up the **authority-services** stack at the new hostname.
- [ ] Verify: `curl -k https://authority.glcdi.startinblox.com/auth/realms/glcdi/.well-known/openid-configuration` returns a valid config with the new issuer.
- [ ] **Mint a test token** for one connector client and decode it (per [`IMPLEM_PLAN § 2.5`](../build/plan/phase-2-keycloak-claims.md#25-verify-token-contents)) - confirms the Tier-1 claim chain end-to-end.
- [ ] Bring up each **participant-agent-services** stack one at a time.
- [ ] Verify Tier-1 sanity for one participant: `curl -H "X-Api-Key: $EDC_API_KEY" .../management/v3/assets/request` returns 200; UI loads at `https://<participant>/` and asks for the API key.
- [ ] Re-enable auto-deploy / unfreeze merges.

## 7. Post-cutover verification (within 24h)

- [ ] **Connector `client_credentials` flow** verified for each participant: `client_credentials` mint against `glcdi-connector-<org>` returns a JWT carrying the right `glcdi_*` claims. (Until [`IMPLEM_PLAN § 3.5`](../build/plan/phase-3-edc-policy-extension.md#35-replace-iam-mock-with-a-real-oauth2-identityservice-and-configure-claim-extraction) ships the iam-mock → iam-oauth2 swap, the receiving connector won't yet validate these - that's expected; the verification here is "the token is mintable and the claims are right.")
- [ ] EDC catalog query verified from each participant's connector with `X-Api-Key` only.
- [ ] Confirm scheduled certbot renewal is working against the new hostname.
- [ ] Confirm no references to the old hostname remain in browser dev-console network traces during a normal participant session (stale JS / cached config).
- [ ] Confirm **no calls to any per-participant Keycloak** in browser network traces (the Tier-1 cutover removes them entirely from the participant compose).

## 8. Retirement of old infrastructure

After the soft-fallback window (recommended 7–14 days post-cutover, once you're confident no external integrations still resolve the old name):

- [ ] Remove the old DNS record.
- [ ] Remove the old TLS cert (or let it expire naturally).
- [ ] Remove any leftover Keycloak clients referencing the old name (Path B only).
- [ ] Delete the old `/glcdi/governance-services/` directory on each VM.
- [ ] Archive the snapshots taken in §6 once rollback is no longer needed.

## Rollback plan

If cutover fails during the window:

- [ ] Bring down `authority-services` stack.
- [ ] Restore Postgres volume from snapshot.
- [ ] Bring `governance-services` stack back up at the old hostname.
- [ ] Bring `participant-agent-services` stacks back up against the **pre-Tier-1** compose (the version with the per-participant KC + oauth2-proxy still wired). Keep this compose available in a tagged branch for the duration of the rollback window.
- [ ] Verify auth flow works at the **old** hostname.
- [ ] Investigate what failed before re-scheduling.

---

## Notes / deferred decisions

- **Parallel migration path not documented here.** If cutover is rejected, this doc needs a second variant covering the dual-run period. Ask before drafting.
- **Naming of the `edc` realm inside each participant Keycloak is moot at Tier 1** - there is no per-participant Keycloak. If it returns at Tier 2 (it doesn't, by design - Tier 2 still uses the Authority KC only), it would be the same realm name.
- **Directory inside `management/`** (this file + siblings) is in a separate repo from the infrastructure being renamed and does not need a VM-level move.

---

## Appendix: Tier 2 follow-up checklist (post-M1, optional)

If/when [`IMPLEM_PLAN § 7.2`](../build/plan/phase-7-future.md#72-identity-tier-2---add-user-oidc-at-the-ui) is approved, the additional operator-side steps to re-enable user OIDC are:

- [ ] **Authority KC** - confirm the `glcdi-ui` client is active (not just imported), with redirect URIs covering all participant origins + `silent-callback.html` paths and `glcdi-claims` in its default scopes.
- [ ] **Per-org groups** - confirm `caney-fork-team`, `point-blue-team`, `white-buffalo-team` exist with their realm-role + `glcdi_organisation` attribute assignments.
- [ ] **Starter human users** - confirm `caney-fork`, `point-blue`, `white-buffalo` user accounts exist, each in their team group, with per-user attributes (`glcdi_certification_status`, `glcdi_contribution_status`) set. Set initial credentials and distribute via vault.
- [ ] **GitLab CI/CD variables** - re-add or rotate `GLCDI_UI_CLIENT_SECRET`; populate per VM's `.env`.
- [ ] **Participant compose** - re-add the `oauth2-proxy` service to `participant-agent-services/docker-compose.yml`, configured against Authority KC (`OAUTH2_PROXY_OIDC_ISSUER_URL`, `OAUTH2_PROXY_CLIENT_ID=glcdi-ui`, `OAUTH2_PROXY_CLIENT_SECRET`). Update nginx so `/management/*` routes through it.
- [ ] **Participant UI** - restore `KEYCLOAK_URL` / `OIDC_CLIENT_ID` / `KC_IDP_HINT` / `LINKED_PROVIDER_*` envvars in `participant-ui/docker-entrypoint.sh`; restore `silent-callback.html` and the `sib-auth-linked-provider` widget; rebuild and publish the image.
- [ ] **Per-participant cutover** - bring each participant stack down + up against the Tier-2 compose. Verify a full OIDC round-trip (login → catalog query → contract negotiation → transfer) for one participant before rolling to the rest.
- [ ] **Verification** - browser dev-tools shows `Authorization: Bearer` on every `/management` call (alongside the persisted `X-Api-Key`); oauth2-proxy logs show successful Bearer-token validations against Authority KC JWKS.

Onboarding workflow at Tier 2 - when a new participant is approved, the onboarding app calls Keycloak Admin API to create the human user and add them to the org's group; see [`IMPLEM_PLAN § 7.2.5`](../build/plan/phase-7-future.md#725-tier-2-onboarding-flow).
