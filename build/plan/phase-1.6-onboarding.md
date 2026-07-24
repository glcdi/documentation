# Phase 1.6: Packaged Organization Onboarding - Current Intermediate Delivery

While Phase 1.5 finishes the connector-side cutover, the in-flight intermediate delivery replaces the placeholder onboarding stack in `governance-services/` with the [`djangoldp_glcdi_onboarding`](https://git.startinblox.com/djangoldp-packages/djangoldp-glcdi) package and its sibling `djangoldp_glcdi_common`. The shape is intentionally narrow: **organization-level onboarding is automated; per-user account creation and per-connector enrolment are not in scope here** (the connector case stays out-of-band - see [§ 2.7](phase-2-keycloak-claims.md#27-integration-with-the-onboarding-flow-tier-1-out-of-band) - and per-user OIDC is the Tier-2 evolution in [§ 7.2](phase-7-future.md#72-identity-tier-2---add-user-oidc-at-the-ui)).

## Why this lands now

1. **Unblocks a fully self-serve organization signup story** without committing to Tier-2 user OIDC. A new organization can apply via a public form, a reviewer approves from an email link or the admin dashboard, and Keycloak provisioning happens automatically - group, user (with one-time temp password), realm roles.
2. **Cleans up the realm to its M1-essential roles only.** The realm JSON had 7 unused `glcdi_*` participant-type roles from an earlier draft taxonomy. Trimming to the four type roles + `glcdi_member` matches what the packaged onboarding actually drives and what the M1 policies actually read.
3. **Surfaces realm-wide spelling drift.** The `governance` client expects `glcdi_organization` (en-US) on group and user attributes, but the existing realm had `glcdi_organisation` everywhere - protocol mapper included. The fix is one renaming pass; doing it now (while the realm import is still wipe-and-replay) avoids an admin-console migration later.

## 1.6.1 Adopt `djangoldp_glcdi_onboarding` in `authority-services/onboarding`

| Item | Detail |
|------|--------|
| **Task** | Replace `djangoldp_onboarding` in `settings.yml` with `djangoldp_glcdi_common` + `djangoldp_glcdi_onboarding`. Install `Pillow` (required by the registration form's `organization_logo` `ImageField`). Move `djangoldp install` from build-time to container-startup so `runserver.sh` can `envsubst` a templated `settings.yml.template` first (`BASE_URL`, `KEYCLOAK_*`, `DEFAULT_FROM_EMAIL`, `GLCDI_ADMIN_MAILS`). Drop `ONBOARDING_PREFIX` - the package already mounts its routes under `registration/`. |
| **URLs delivered** | `/registration/` (public form), `/registration/admin/` (dashboard, requires `is_superuser && is_staff` - the existing `djangoldp configure --with-dummy-admin` step satisfies this), `/registration/admin/<pk>/{approve,deny}/`, `/registration/admin/logout/`. |
| **Routing** | `nginx-{dev,prod}.conf`: one `location /registration/` block proxying to `onboarding-backend:8083/registration/`, plus `/static/` and `/media/` proxies for Django staticfiles and uploaded org logos. The legacy `/onboarding/` and `/onboarding/validation/` blocks (and the `onboarding-approval` httpd container) drop out. |
| **Status** | [x] Image rewired (Dockerfile, settings.yml.template, runserver.sh) · [x] Compose updated · [x] Nginx routes swapped · [x] Smoke-tested locally (form renders, admin dashboard renders, approve flow exercises `KeycloakService.provision()` end-to-end) · [ ] Smoke-tested on staging |

## 1.6.2 Trim realm roles to the M1-essential set

| Item | Detail |
|------|--------|
| **Task** | In `authority-services/resources/keycloak/realms/glcdi-realm.json`, keep only `glcdi_member`, `glcdi_producer`, `glcdi_researcher`. Add `glcdi_non_profit` and `glcdi_non_regulatory`. Drop the seven unused draft roles (`glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder`). |
| **Why** | `djangoldp_glcdi_onboarding` maps each form-checked `organization_type` to exactly one of these four type roles, plus `glcdi_member` for every approved org. None of the dropped roles are referenced by any user, group, or seed script in the repo, so removal is non-breaking. |
| **Status** | [x] Realm JSON updated · [x] Verified locally (`curl -H "Authorization: Bearer <governance SA token>" /admin/realms/glcdi/roles \| jq` returns exactly `["glcdi_member","glcdi_non_profit","glcdi_non_regulatory","glcdi_producer","glcdi_researcher"]`) · [ ] Verified on staging |

## 1.6.3 Normalise `organisation` → `organization` realm-wide

| Item | Detail |
|------|--------|
| **Task** | One pass over the realm JSON replacing every occurrence of `glcdi_organisation` with `glcdi_organization`: the `glcdi-claims` scope description, the `glcdi-organisation-mapper` protocol mapper (name, `user.attribute`, `claim.name`), the three `*-team` group attributes, and the four operator + three connector-SA user attribute blocks. |
| **Why** | The keycloak admin client in `djangoldp_glcdi_onboarding/keycloak_service.py` sets the group attribute as `glcdi_organization` (en-US). Mismatching that against the in-repo `glcdi_organisation` would silently break the claim mapping for newly-onboarded orgs while leaving the legacy ones working - exactly the kind of drift that is hard to debug later. Aligning on en-US is the smaller delta given the package is upstream. |
| **Status** | [x] Realm JSON updated · [x] Verified locally: an end-to-end approve flow created a KC group whose `attributes.glcdi_organization` carried the slugged org name (en-US). The `glcdi-claims` scope's `glcdi-organization-mapper` is in place but not exercised by a real user-token introspection yet - connector-SA tokens don't carry it (the SA is on a different scope set). · [ ] Verified on staging via a user-token introspection once a real org has logged in |

## 1.6.4 Give the `governance` client `realm-management.realm-admin`

| Item | Detail |
|------|--------|
| **Task** | Add a `service-account-governance` user to the realm JSON (mirroring the existing `service-account-glcdi-connector-*` entries), with `clientRoles: { "realm-management": ["realm-admin"] }`. The `governance` client itself already has `serviceAccountsEnabled: true`; this adds the actual permission. |
| **Why** | `djangoldp_glcdi_onboarding` provisions Keycloak via the Admin REST API on behalf of the `governance` client. Without `realm-admin` on the SA, every `POST /admin/realms/glcdi/users` etc. returns 403 and the approve flow silently leaves the request in `processing` forever. |
| **Decision (proposed to the Dataspace Authority)** | Use `realm-admin` (broadest, simplest) rather than the narrower `manage-users + manage-groups + query-users + query-groups` quartet. Trade-off: a leaked `governance` secret can rotate any account, not just onboarding-created ones - which is why this secret stays in the host `.env` (never committed) and is rotated on every fresh deploy. |
| **Status** | [x] Realm JSON updated · [x] Verified locally - the requester-approve flow successfully called the Admin REST API (group create, role-mapping assign, user create, group-membership assign, temp-password set, send email). Empirically the `governance` SA must have `realm-admin` for these to all return 2xx. · [ ] Verified on staging |

## 1.6.5 Wire a real `governance` client secret, end-to-end

| Item | Detail |
|------|--------|
| **Task** | Replace the literal `"changeme-governance-client-secret"` in the realm JSON with the placeholder `${KC_GOVERNANCE_CLIENT_SECRET}`. Add a small Keycloak entrypoint (`resources/keycloak/entrypoint.sh`) that runs before `kc.sh` and `sed`-substitutes that placeholder from `resources/keycloak/realms/*.json` into `/opt/keycloak/data/import/` on first boot (the keycloak ubi-micro image has no `envsubst`). The same env var feeds the `onboarding-backend` as `KEYCLOAK_CLIENT_SECRET`, so the realm and the django client are guaranteed to match. |
| **Why** | Today the secret is `changeme-governance-client-secret` in the realm and a separate `changeme` in `.env` - they don't match, and even if they did, baking the literal into git is exactly the leakage pattern the per-participant `participant/configuration.properties` review caught. |
| **Reset reminder** | The realm JSON is imported **only on first boot**. A pre-existing Keycloak DB volume holds the *previous* (unrotated, mismatched) secret. To pick up the change, the volume must be wiped (`docker compose down -v`) or the new secret applied via the admin console. The `glcdi.sh reset` path is the supported clean-room form. |
| **Status** | [x] Realm + compose + entrypoint wired · [x] Smoke-tested locally with fresh KC volume: `KC_GOVERNANCE_CLIENT_SECRET` from `secrets.env` → patched into `glcdi-realm.json` by `glcdi.sh patch_realm_json` (jq) → bind-mounted to `data/import-template/` → `entrypoint.sh` `sed`-substitutes into `data/import/` → realm imports cleanly on first boot. The same value reaches `onboarding-backend` as `KEYCLOAK_CLIENT_SECRET` via the compose env block, so the django backend authenticates as `governance` against the live KC without a separate "set this in two places" step. · [ ] Verified on staging |

## 1.6.6 Bootstrap-and-smoke checklist

| Item | Detail |
|------|--------|
| **Task** | Run `./management/build/scripts/glcdi.sh reset && ./management/build/scripts/glcdi.sh up` to bring up a clean Authority. Verify in order: (a) `https://.../auth/realms/glcdi/.well-known/openid-configuration` returns 200; (b) `POST .../realms/glcdi/protocol/openid-connect/token` with the `governance` `client_credentials` flow returns an access token whose service-account user holds `realm-management.realm-admin`; (c) `GET /registration/` renders the form; (d) submitting the form lands a "pending approval" mail in `onboarding-backend`'s `./mails`; (e) logging into `/registration/admin/` as the dummy admin and clicking Approve triggers the requester email with temp Keycloak credentials; (f) the new user appears in KC inside a group whose `glcdi_organization` attribute is the slugged org name. |
| **Where** | Local: against `http://localhost/...` per the updated `authority-services/README.md`. Staging: same flow, after Option 1 wipe-and-replay of the Authority KC volume per [`ops/vm-deployment.md` § 3](../../ops/vm-deployment.md). |
| **Status** | [x] Local smoke run completed end-to-end - `glcdi.sh reset && up` brought the stack up clean, the form at `http://localhost:8083/registration/` accepted a submission, the admin-notification mail landed in `/ldpserver/mails`, the dummy admin approved via the dashboard, a temporary KC password mail went to the requester, and the new user/group were verified via the Admin REST API (group `sib` with `glcdi_organization=["sib"]` + `glcdi_member` + `glcdi_producer`; user `benoit.aless` in group `sib` with a single password credential). · [ ] Re-run on staging once `1.6.7` ships through CI |

## 1.6.7 Public-facing KC login URL in the requester's approval mail

| Item | Detail |
|------|--------|
| **Task** | Set `KEYCLOAK_LOGIN_URL` explicitly so the approval mail's "Log in at…" link points at a browser-reachable URL. Without it, `djangoldp_glcdi_onboarding` auto-derives the login URL from `KEYCLOAK_BASE_URL`, which is the *internal* docker hostname (`http://keycloak:8080/…`) that 404s outside the container network. |
| **Where** | `onboarding/settings.yml.template` reads `${KEYCLOAK_LOGIN_URL}`; `docker-compose.yml` derives it from `${BASE_URL}`; `management/build/scripts/glcdi.sh` writes it explicitly into `authority.env` for the symmetric-port dev shape (KC is on `:8090`, BASE_URL is `:8083`, so the auto-derived value would be wrong); `authority-services/.gitlab-ci.yml` writes it from CI's `${BASE_URL}` into `.env`. |
| **Status** | [x] Wired in source · [x] Re-tested locally (re-submission as "Benito Toto" produced an approval mail whose "Log in at:" anchor points at `http://localhost:8090/auth/realms/glcdi/account/` - the browser-reachable KC URL, not the docker-internal `http://keycloak:8080/...`) · [ ] Verified on staging that the approval mail's link opens the KC account console |

## Dependencies & risks

- **Blocks nothing else** - Phase 2 (Keycloak claims), Phase 3 (EDC policy functions), and Phase 4 (seeding) only read from the realm JSON, they don't write through the onboarding API. So Phase 1.6 can land or slip without dragging the M1 critical path.
- **Couples tightly to Phase 1.5's Authority cutover.** Both touch the realm JSON, both prefer a single deploy window per environment. Land 1.6 in the same Path-A re-import as 1.5 to avoid two consecutive wipe-and-replays.
- **Trust boundary on `/registration/` is the public internet.** The form is anonymous-POST by design (anyone can apply). Mitigations to consider before production: nginx `limit_req` on `POST /registration/`, a Cloudflare Turnstile / hCaptcha widget on the form, or an explicit allowlist of organisation email domains. None are required to test, but flag for the Dataspace Authority before opening the staging URL to the public.
- **Realm import is one-shot.** Reset paths (`docker compose down -v`, `glcdi.sh reset`) are the only fully clean ways to re-apply the new realm. Post-bootstrap edits via the admin console diverge from the in-repo source-of-truth - flag any such edits in `reference/identity.md` so they're not silently lost on the next reset.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 1.5: Identity (Tier 1) - Single-tier auth + Authority cleanup](phase-1.5-identity-tier1.md) · [next: Phase 2: Keycloak Claims Configuration - Connector Service-Account Tokens →](phase-2-keycloak-claims.md)
