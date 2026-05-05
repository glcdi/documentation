# Authority Rename — Operator Migration Checklist

Live-infrastructure tasks required to complete the rename of the governance deployment from `governance-*` to the new Dataspace Authority name. The local (in-repo) rename of code, documentation, and configuration templates can be done by the project team (or by an automation agent) ahead of this checklist; the items below are the parts that require hands-on access to DNS, running services, and CI/CD secrets.

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
- [ ] Keycloak realm JSON updated (`governance-services/resources/keycloak/realms/glcdi-realm.json` → now at its renamed path) with updated client IDs (`catalog-ui-governance` → `catalog-ui-authority`) and redirect URIs pointing at the new hostname.
- [ ] `participant-ui/` `config.json.template` and `docker-entrypoint.sh` token substitutions updated (`GOVERNANCE_URL` env var → `AUTHORITY_URL`, or equivalent) and the image rebuilt.
- [ ] `participant-agent-services/participant/*.properties.example` + `.env.example` templates updated with new URLs and client IDs.
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

## 3. Keycloak (live instance)

**Important context:** per `glcdi/CLAUDE.md` ("Things that will bite you"), realm JSON is only imported on first boot. Post-init changes to `glcdi-realm.json` have no effect unless the Postgres volume is wiped.

Two migration paths — pick one:

### Path A: Wipe Postgres volume and re-import

Simplest, but **destructive** — loses every manually-set user attribute, role assignment, and identity-provider broker configuration made through the admin console since the last fresh import.

- [ ] Snapshot the current Postgres volume (rollback safety).
- [ ] Stop the governance Keycloak + Postgres containers.
- [ ] Remove the Postgres volume.
- [ ] Bring up the new stack with the renamed realm JSON.
- [ ] Re-create any manually-configured per-participant identity-provider aliases in the admin console (one per participant).
- [ ] Re-assign any user attributes (`glcdi_certification_status`, `glcdi_contribution_status`) that were set out-of-band.

### Path B: Live edit via admin console

Non-destructive, but tedious and error-prone.

- [ ] Log into the admin console at the old hostname.
- [ ] For each participant identity-provider alias: update any redirect URIs or display names that mention `governance`.
- [ ] Rename the client ID `catalog-ui-governance` → `catalog-ui-authority` (or create new, migrate users' session assignments, retire old).
- [ ] Update **every redirect URI and Web Origin** on every client that references `governance.glcdi.startinblox.com` → `authority.glcdi.startinblox.com`. Typical clients affected: `catalog-ui-governance`, `edc-api-client`, `participant-broker`.
- [ ] Update the realm's display name / display name HTML if it mentions "Governance".
- [ ] Verify a full OIDC round-trip still works before proceeding.

**Recommendation:** Path A if the dataspace is genuinely pre-production and user attributes are few. Path B if participant data has been built up. Document which was used and why.

## 4. CI/CD variables (GitLab)

Every sibling repo has a `.gitlab-ci.yml` with `deploy-*` jobs that SSH into target VMs and run `docker compose`. Each pulls secrets from GitLab CI/CD variables. Audit and update:

- [ ] Any `GOVERNANCE_URL` / `KEYCLOAK_URL` CI/CD variable → `AUTHORITY_URL` / new Keycloak URL.
- [ ] Any service-account client secret tied to `catalog-ui-governance` → the renamed client.
- [ ] Any SSH target variable pointing at a path with `governance-services` in it.
- [ ] Rotate any secret that appears in old logs / was baked into the old realm JSON (defence in depth — rename is a good moment to rotate).

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
- [ ] Bring down the **participant-agent-services** stacks first (they depend on the governance Keycloak).
- [ ] Bring down the **governance-services** stack.
- [ ] Execute the Keycloak path (A or B from §3).
- [ ] Bring up the **authority-services** stack at the new hostname.
- [ ] Verify: `curl -k https://authority.glcdi.startinblox.com/auth/realms/glcdi/.well-known/openid-configuration` returns a valid config with the new issuer.
- [ ] Bring up each **participant-agent-services** stack one at a time.
- [ ] Verify end-to-end auth flow for one participant: login → catalog query → contract negotiation → transfer.
- [ ] Re-enable auto-deploy / unfreeze merges.

## 7. Post-cutover verification (within 24h)

- [ ] Full OIDC flow tested for each participant (not just one).
- [ ] EDC catalog query verified from each participant's connector.
- [ ] Contract negotiation end-to-end verified for at least one asset.
- [ ] Check oauth2-proxy logs for auth failures / unexpected redirects.
- [ ] Confirm scheduled certbot renewal is working against the new hostname.
- [ ] Confirm no references to the old hostname remain in browser dev-console network traces during a normal participant session (stale JS / cached config).

## 8. Retirement of old infrastructure

After the soft-fallback window (recommended 7–14 days post-cutover, once you're confident no external integrations still resolve the old name):

- [ ] Remove the old DNS record.
- [ ] Remove the old TLS cert (or let it expire naturally).
- [ ] Remove any leftover Keycloak clients / IdP aliases referencing the old name (Path B only).
- [ ] Delete the old `/glcdi/governance-services/` directory on each VM.
- [ ] Archive the snapshots taken in §6 once rollback is no longer needed.

## Rollback plan

If cutover fails during the window:

- [ ] Bring down `authority-services` stack.
- [ ] Restore Postgres volume from snapshot.
- [ ] Bring `governance-services` stack back up at the old hostname.
- [ ] Bring `participant-agent-services` stacks back up.
- [ ] Verify auth flow works at the **old** hostname.
- [ ] Investigate what failed before re-scheduling.

---

## Notes / deferred decisions

- **Parallel migration path not documented here.** If cutover is rejected, this doc needs a second variant covering the dual-run period (both hostnames resolving, both realms importable or one realm with dual client IDs, overlapping oauth2-proxy configs). Ask before drafting.
- **Naming of the `edc` realm inside each participant Keycloak is unchanged** by this migration — that realm is `edc`, not `governance`. No participant-Keycloak-side rename is required.
- **Directory inside `management/`** (this file + siblings) is in a separate repo from the infrastructure being renamed and does not need a VM-level move.
