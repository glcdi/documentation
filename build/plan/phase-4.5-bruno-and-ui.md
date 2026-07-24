# Phase 4.5: Bruno Test Suite + Participant-UI Configuration (Parallel Tracks)

Two independent tracks that can run in parallel with each other and with Phases 3–4. Both feed into the Phase 5 integration tests and the M1 milestone gate.

## 4.5.E Bruno test suite (Track E - parallel agent)

**Location:** [`./bruno/`](../bruno/) (i.e. `management/build/bruno/` in this repo). Single collection; environment variables for staging vs. local; one folder per scenario step or per logical group (auth setup, catalog queries, negotiations, transfers).

A Bruno collection (or equivalent HTTP test harness) executing the M1 scenario end-to-end against the management API:

- Catalog query as a researcher (`glcdi_researcher` claim) → expect the regenerative-only asset to be **visible**.
- Catalog query as a non-regenerative producer (only `glcdi_member`) → expect the same asset to be **filtered out** (access policy hides it).
- Contract negotiation with `purpose = InternalAnalysis` → expect **AGREED → FINALIZED**.
- Contract negotiation with `purpose = ResearchAnalysis` → expect **TERMINATED** (purpose mismatch on the `internal-use-only` contract policy).
- Transfer-process initiation against the agreed contract → expect data payload returned.
- Negative auth: management-API call without `X-Api-Key` → expect `401`. With wrong `X-Api-Key` → expect `401`.
- **Tier-2-only negative auth** (skipped at Tier 1): no Bearer / wrong Bearer → expect `401` from oauth2-proxy.

**Auth context - tiered:**

- **Tier 1 (M1 default, `tier=tier1`):** `X-Api-Key` only on every `/management` call - the only gate at this edge (see § 1.5.3 and § 1.5.6). Identity-driven scenarios (catalog query as researcher, negotiation as a specific org) are tested by **running each step from the connector that already is that org** - point-blue's connector queries caney-fork's catalog as point-blue, no Bearer-token gymnastics. The connector's own `client_credentials` token (per § 1.5.4) carries the right `glcdi_*` claims into the receiving connector via `iam-oauth2` (post-§ 3.5).
- **Tier 2 (post-§ 7.2, `tier=tier2`):** the same `/management` calls additionally carry `Authorization: Bearer <connector-SA token>`. The Bearer header is injected by the **collection-level pre-request script** in `bruno/collection.bru` - individual `.bru` files don't change between tiers. Bruno automation uses connector-SA tokens (from 00-auth/) rather than per-user OIDC; oauth2-proxy validates "any token signed by Authority KC", which is sufficient for test traffic.
- **00-auth/** is the **diagnostic claim-shape check** at both tiers: mint a connector-SA token via `client_credentials`, decode the JWT, assert the `glcdi_*` claim shape (per § 2.5). At Tier 1 the captured tokens are not used downstream; at Tier 2 the collection-level script reuses them as Bearer values.

Bruno runs against either a single participant's connector locally, or against the staging URLs (`caney-fork.glcdi.startinblox.com`, `point-blue.glcdi.startinblox.com`, `white-buffalo.glcdi.startinblox.com`).

**Owner:** parallel agent. Can begin drafting once §§ 1.5.3–1.5.4 fix the API-key contract and the per-org client_credentials shape; doesn't strictly need Phases 2–4 to run, only to be runnable green.

**Status:** [x] Tiered skeleton in [`bruno/`](../bruno/) - 19 files: collection metadata, **collection-level pre-request script** (`collection.bru`) for Tier-2 Bearer injection, 2 environments (local + staging) with `tier` selector, 6 folders covering the M1 scenario plus 2 extra Tier-2-only negative-auth cases · [x] Role-corrected per the M1 resolution (white-buffalo positive, point-blue filtered) · [x] Tier-1 default (X-Api-Key only) and Tier-2 anticipated (Bearer auto-injected) - single source, switch via env var · [x] **Green run against local Tier 1 stack: 33/35 tests passing** - catalog discovery (positive + negative), negotiation accepted (both purposes), all 4 negative-auth scenarios, full seeding (10 requests × 3 orgs). Remaining 2/35 are the contract-agreement polling + transfer init (need § 4.5.E's polling files below). · [ ] Polling files for state-machine assertions (FINALIZED / TERMINATED / STARTED) - TODO inside the relevant `.bru` files · [ ] Pre-request script that fetches the offer from the catalog response and uses it verbatim in the negotiation body - TODO · [ ] Green run against **staging** at Tier 1 (local-only verified so far) · [ ] Green run at Tier 2 (additionally gated on Phase 7.2)

## 4.5.F Participant-UI configuration (Track F - parallel agent)

Adapt `participant-ui/` for the **Tier 1** auth flow - API-key login only, no OIDC envvars, no `LINKED_PROVIDER_*`, no silent-callback iframe:

- Strip OIDC plumbing from `docker-entrypoint.sh` and `config.json.template`: remove `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OIDC_CLIENT_ID`, `KC_IDP_HINT`, `LINKED_PROVIDER_*`, `LINKED_PROVIDER_SILENT_REDIRECT_URI`. Remove `silent-callback.html` from the served paths. Drop the `sib-auth-linked-provider` widget from the Hubl config.
- Implement **API-key login** as the only entry path - operator pastes an `X-Api-Key` value that the UI uses for every management-API call. Trust boundary is the per-participant network (see § 1.5.3); flag clearly in the UI copy that the key is *not* a per-user credential.
- Keep the existing `config.json`-driven asset / policy / contract / history components - they don't need OIDC.
- Surface the missing **transfer-process management** component (`tems-transfer-processes-management` or equivalent) needed by the M1 scenario.
- Confirm theme/branding still renders correctly per-participant (the runtime-configurable single image continues to work).

> **Tier-2 forward look:** Phase 7.2 reintroduces the OIDC plumbing for federated user login. The work in this track is to land Tier 1 cleanly first; the Tier-2 envvars / silent-callback come back in a controlled way under that phase.

**Owner:** parallel agent. **Read-only audit first** (already complete - see status), then strip-down implementation.

**Status:** [x] Read-only audit complete (Track F findings: 4 components configured, env vars + linked-provider mapped, silent-callback path served by Hubl/nginx, transfer-process component absent) · [x] Strip OIDC envvars from `docker-entrypoint.sh` and `config.json.template` (Tier-1 cut: KEYCLOAK_URL, OIDC_CLIENT_ID, KC_IDP_HINT, LINKED_PROVIDER_* all removed) · [x] Drop `sib-auth-linked-provider` widget + `silent-callback.html` from served paths (autoLogin partial in `orbit/` now routes through `<sib-auth-apikey>`) · [x] API-key-only login implemented - `solid-glcdi/src/components/sib-auth-apikey.ts` (paste-form modal) + `sib-auth-provider-apikey.ts` (input + reveal + retrieval mailto). Storage at `localStorage.glcdi_operator_api_key.<participant-id>` (JSON-wrapped). On activation, propagates the key to every `[participant-api-key]` element so the upstream tems-*-management components actually carry it. · [x] Custom `<glcdi-sidebar>` (replaces `<tems-sidebar-oidc>`) reading menu from `window.orbit.components`, theming via dedicated `--glcdi-*` tokens to avoid TEMS' design-token tug-of-war · [ ] Add `tems-transfer-processes-management` (or equivalent) component to `config.json.template` · [x] README rewritten with single-tier architecture + "PROTOTYPE: API-key-only login" subsection (will need a follow-up update after the strip-down lands)

## Dependencies

- Both tracks **depend on § 1.5** (Tier-1 identity simplification) being landed in at least one staging participant.
- 4.5.E benefits from Phases 2–4 being further along (so the test-suite assertions match real seeded data) but can be drafted in parallel against expected behaviour.
- 4.5.F's strip-down can begin **immediately**; field-tested once § 1.5 is in staging.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 4: Update Seeding Scripts & Contract Definitions](phase-4-seeding.md) · [next: Phase 4.6: Decouple participant-ui from `@startinblox/solid-tems` →](phase-4.6-decouple-ui.md)
