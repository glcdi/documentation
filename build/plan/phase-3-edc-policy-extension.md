# Phase 3: EDC Policy Extension Development

## 3.0 `edc-glcdi-extension` repository scaffolding

| Item | Detail |
|------|--------|
| **Task** | Set up the GLCDI-owned extension repository as a sibling of `edc-connector/`, following the DS4GO pattern (separate repo, build-time symlinked or path-referenced from the connector's controlplane build). |
| **Why a separate repo (not `edc-connector/extensions/`)** | Keeps GLCDI-owned Java code separate from the EDC fork (which tracks upstream). Independent versioning + git history. Mirrors `ds4go/edc-dsif-extension/` next to `ds4go/edc-connector/`. |
| **Layout (proposed)** | `edc-glcdi-extension/extensions/glcdi-policy-functions/` (the membership / participantType / certificationStatus functions of §§ 3.2–3.4) - first occupant. Future siblings (e.g. `payment-status-extension/` from [`design/payment-gating.md`](../../design/payment-gating.md), if Phase 7.1 lands) live under the same `extensions/` folder. |
| **Wire-up** | `edc-connector/runtimes/controlplane/build.gradle.kts` references the extension via relative path or via a CI symlink step that puts the extension into `edc-connector/extensions/`. Match whichever pattern this team's CI uses for DS4GO. |
| **Status** | [x] Repo created · [x] First extension scaffolded (§ 3.1) - `glcdi-policy-functions/` with build files + SPI entry + package skeleton + the three constraint-function classes + `GlcdiClaims` constants + `GlcdiPolicyFunctionsExtension` registration class + a starter unit-test class · [x] Wired into the controlplane runtime (§ 3.6) · [x] Second extension scaffolded: `glcdi-iam-keycloak/` (custom OAuth2 IdentityService against Authority KC, replaces `iam-mock`) |



The EDC connector needs custom policy functions to evaluate GLCDI-specific constraints.
Without these, constraints referencing `glcdi:membership` or `glcdi:participantType` will be
silently ignored (default: permit) or fail closed, depending on EDC configuration.

## 3.1 Create `glcdi-policy-functions` extension

| Item | Detail |
|------|--------|
| **Task** | Create a new EDC extension in `edc-glcdi-extension/extensions/glcdi-policy-functions/` (sibling repo, mirrors DS4GO's `edc-dsif-extension/` pattern - not inside the `edc-connector/` fork) |
| **Language** | Java 17 |
| **Build** | `settings.gradle.kts` includes the module; `extensions/glcdi-policy-functions/build.gradle.kts` depends on `edc.spi.core`, `edc.spi.policy`, `edc.spi.policy-engine`, `edc.runtime.metamodel`. Tests use JUnit 5 + AssertJ + Mockito |
| **Layout** | `src/main/java/com/startinblox/glcdi/edc/extension/policy/` (package); `src/main/resources/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension` lists `GlcdiPolicyFunctionsExtension` |
| **Status** | [x] Repo scaffolded (`edc-glcdi-extension/` root build, settings, gradle.properties, libs.versions.toml, .gitignore, README) · [x] Module scaffolded (`extensions/glcdi-policy-functions/`: build.gradle.kts, README, META-INF SPI entry, package directories) · [x] Gradle wrapper bootstrapped (used by `glcdi.sh build`) · [x] First successful `./gradlew build` (runs as part of `glcdi.sh build`; controlplane image rebuilt + booted cleanly) |

## 3.2 Implement membership policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:membership` |
| **Behaviour** | Extract the `glcdi_membership` claim from the participant's identity (via `ParticipantAgent`), compare it to the constraint's `rightOperand` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/membership"` |
| **Used by** | `access/members-only.json`, `access/regenerative-producers.json`, `access/researchers-only.json`, and all combined policies |
| **Status** | [x] `MembershipConstraintFunction.java` drafted (EQ + NEQ; logs and returns `false` when ParticipantAgent is missing or the claim is absent) · [x] Starter unit-test class `MembershipConstraintFunctionTest.java` covers match / mismatch / no-agent / claim-missing / unsupported-operator paths · [x] Compiled against pinned EDC SPI (EDC 0.15.x: `ParticipantAgentPolicyContext.participantAgent()`, typed `Class<C>` registration). Function is invoked on every catalog request - verified by logging output showing `[glcdi:membership] active EQ active → true`. |

## 3.3 Implement participant type policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:participantType` |
| **Behaviour** | Reads the `glcdi_roles` claim (list); maps the kebab-case `participantType` value to the snake-case role name (`glcdi_<type>`) and tests membership in the participant's role set. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/participantType"` |
| **Used by** | `access/regenerative-producers.json`, `access/researchers-only.json`, `combined/corporate-supply-chain.json` |
| **Status** | [x] `ParticipantTypeConstraintFunction.java` drafted with `toRoleName(...)` kebab→snake helper; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [x] Resilient parsing for claims arriving as a `Collection` or comma-separated `String` · [ ] Unit tests (deferred per § 5.1) · [x] Compiled against pinned EDC SPI; verified by the access matrix in Bruno's `20-catalog-discovery` (regen-producers see regen-only assets, researcher gets filtered out) |

## 3.4 Implement certification status policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:certificationStatus` |
| **Behaviour** | Extract `glcdi_certification_status` claim (string, lowercase / kebab-case per § 1.5.4); compare to the constraint's `rightOperand`. Supports `eq`, `neq`, `isAnyOf`/`in`, `isNoneOf` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/certificationStatus"` |
| **Used by** | `access/regenerative-producers.json` |
| **Status** | [x] `CertificationStatusConstraintFunction.java` drafted; supports EQ / NEQ / IN / IS_ANY_OF / IS_NONE_OF · [ ] Unit tests (deferred per § 5.1) · [x] Compiled against pinned EDC SPI |

## 3.5 Replace `iam-mock` with a real OAuth2 IdentityService and configure claim extraction

| Item | Detail |
|------|--------|
| **Task** | Swap the dev-only `iam-mock` IdentityService (was wired in `edc-connector/runtimes/controlplane/build.gradle.kts` as `libs.edc.iam.mock`) for a real OAuth2 IdentityService against the Authority Keycloak. Configure the claim extractor so `glcdi_*` claims land in EDC's `ClaimToken` for the policy engine to read. |
| **Outcome (different from original plan)** | Stock `iam-oauth2` was retired in EDC 0.15.x - the replacement (`controlplane-dcp-bom`) assumes Verifiable Presentations via a DCP-compliant STS, which Keycloak doesn't speak. Implemented as a **custom EDC extension** `edc-glcdi-extension/extensions/glcdi-iam-keycloak/` (~250 LOC Java) that: (i) performs `client_credentials` against KC's `/token`; (ii) validates incoming peer JWTs against KC's JWKS via `nimbus-jose-jwt`; (iii) copies every JWT claim into the `ClaimToken`; (iv) provides a `DefaultParticipantIdExtractionFunction` reading `client_id` then `azp`. |
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

# Custom claim mapping - surface glcdi_* claims to the policy engine
# (exact property names depend on the iam-oauth2 version in this fork; verify during the swap)
edc.iam.token.scope=openid profile glcdi_claims
```

**Claim extraction:** EDC's `iam-oauth2` extension extracts standard claims by default. To surface our custom claims (`glcdi_member`, `glcdi_researcher`, `glcdi_producer`, `glcdi_certification_status`, `glcdi_contribution_status`), configure the claim mapper to copy them from the JWT into the `ClaimToken`. The policy functions in §§ 3.2–3.4 then read from `ClaimToken.getClaim("glcdi_member")` etc.

**To verify during implementation:** the exact claim-mapping config keys for the `iam-oauth2` version pinned in this fork. The principle is consistent across versions; the property names occasionally drift. A small pre-flight read of the EDC source at the pinned version (`./gradlew :runtimes:controlplane:dependencies | grep iam-oauth2`) will confirm.

**Migration note (post-prototype):** the existing DCP-shaped config (`edc.iam.issuer.id=did:web:...`, `edc.iam.sts.oauth.*`, etc.) is the future direction (decentralised identity via Identity Hub + Verifiable Credentials). For M1 it can be left in place but unused, or removed; either way it does not feed the M1 policy-evaluation path.

## 3.6 Register extension in connector runtime

| Item | Detail |
|------|--------|
| **Task** | Wire `glcdi-policy-functions` (sourced from the `edc-glcdi-extension/` sibling repo) into `edc-connector/`'s build, so every connector image rebuild includes the GLCDI custom extensions automatically - mirrors DS4GO's `edc-dsif-extension` → `edc-connector/extensions/` cp-step pattern |
| **Deliverable** | Rebuilt connector image (published to `registry.startinblox.com/applications/glcdi/edc-connector/controlplane`) carries the GLCDI extensions in its shadowJar; participants pulling the image at `docker compose up -d` time get them automatically |
| **Pattern** | At CI time (or via local helper script): clone `edc-glcdi-extension`, copy its `extensions/<name>/` directories into `edc-connector/extensions/`, run the standard Gradle build. The copies are not tracked in `edc-connector` git (added to `.gitignore` as `extensions/glcdi-*`) so the fork stays clean of GLCDI-specific code that lives upstream. |
| **Status** | [x] `edc-connector/gradle/libs.versions.toml`: added `edc-spi-policy-engine` + `edc-runtime-metamodel` aliases (both required by the extension build) · [x] `edc-connector/settings.gradle.kts`: added `include(":extensions:glcdi-policy-functions")` + `include(":extensions:glcdi-iam-keycloak")` · [x] `edc-connector/runtimes/controlplane/build.gradle.kts`: `runtimeOnly(project(":extensions:glcdi-policy-functions"))` + `runtimeOnly(project(":extensions:glcdi-iam-keycloak"))` · [x] `edc-connector/.gitignore`: ignores `extensions/glcdi-*` (synced from sibling repo, not tracked) · [x] `edc-connector/.gitlab-ci.yml`: `before_script` clones `edc-glcdi-extension` (auth via `CI_JOB_TOKEN`, branch override via `EDC_GLCDI_EXTENSION_BRANCH`) and copies its extensions into `./extensions/` ahead of every Gradle/Kaniko step · [x] `edc-connector/scripts/sync-glcdi-extensions.sh`: local-dev helper (looks for `../edc-glcdi-extension/` by default; override with `EDC_GLCDI_EXTENSION_DIR`); now syncs both `glcdi-policy-functions` + `glcdi-iam-keycloak` · [x] First successful local build with the extensions in place (controlplane image rebuilt + 33/35 Bruno tests passing) · [ ] First successful **CI** build (local-only verification so far) · [ ] Job-token permission granted on `edc-glcdi-extension` repo (Settings → CI/CD → Job token permissions → allow `edc-connector`) |

## 3.7 Known limitation - `odrl:purpose` claim plumbing (refine later)

| Item | Detail |
|------|--------|
| **Symptom** | Transfer attempts against assets whose contract policy carries `odrl:purpose == glcdi:InternalAnalysis` (the M1 `internal-use-only` contract policy) terminate at the provider with `dspace:code:409 / "Cannot process TransferRequestMessage because agreement not found or not valid"`. Provider logs the real cause: `[glcdi-policy] [odrl:purpose] consumer didn't state a purpose claim - denying.` |
| **Root cause** | `PurposeConstraintFunction` (§ 3.x) at `transfer.process` scope reads a `"purpose"` claim from the consumer's `ParticipantAgent`. The consumer's KC client-credentials token uses scope `glcdi-claims`, whose protocol mappers emit `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` - **but not `purpose`**. No mapper produces it, no plumbing propagates the negotiation-time purpose into the transfer-time token. So the constraint denies, EDC surfaces a misleading "agreement not found or not valid" umbrella error, and the M1 transfer never reaches STARTED. The catalog branch returns `true` permissively, which is why catalog browsing isn't affected. |
| **Quick fix (applied)** | In `PurposeConstraintFunction.evaluate()`, short-circuit `true` at `transfer.process` scope - negotiation already validated the purpose, transfer-time re-evaluation is defence-in-depth that breaks without the claim. One-line change, restores end-to-end M1 flow. Tier-1 simplification, matches the class doc's own admission that the negotiation gate is "provisional". |
| **Proper fix (Tier-2, deferred)** | Two parts: (a) add a KC protocol mapper to the `glcdi-claims` client scope that emits a `purpose` claim - initially hardcoded per-participant, eventually driven by the negotiation request body once the consumer-side UI / sib-core can collect the consumer's intended purpose; (b) at the consumer's connector, propagate the negotiation-time purpose into the outbound transfer-request token (or onto the DSP message body and read it server-side from the message rather than the claim). The `PurposeConstraintFunction.evaluate()` transfer-scope branch then reverts to enforcing equality against the agreement's `rightOperand`. |
| **Where to refine** | Lift this section into a proper Phase 3.x rework once Tier-2 lands. Cross-reference from `reference/authentication.md § Tier-2` and from the memory file `reference_glcdi_edc_transfer_diag.md § 7` so the trap is documented in three places. |
| **Status** | [x] Quick fix applied to `PurposeConstraintFunction.evaluate()` (transfer-scope short-circuit) · [ ] KC protocol mapper for `purpose` on the `glcdi-claims` scope · [ ] Consumer-side purpose collection in the negotiation/transfer UI flow · [ ] Restore strict transfer-scope evaluation in `PurposeConstraintFunction` once (a) + (b) are in place · [ ] Unit test that covers the transfer-scope branch (currently bypassed, deserves an explicit test once Tier-2 makes it active again) |

## 3.8 Embed the data plane in the controlplane runtime + register an EndpointGenerator for HttpData

| Item | Detail |
|------|--------|
| **Symptom** | After § 3.7's purpose-policy patch unblocks transfer dispatch, the provider accepts the DSP `TransferRequestMessage` but immediately terminates with `SEVERE … failed to Start DataFlow. Fatal error occurred. Cause: No dataplane found`. Provider state machine: INITIAL → PROVISIONING → PROVISIONED → STARTING → TERMINATED. Consumer receives `TransferTerminationMessage`, lands TERMINATED with `errorDetail: null`, and the UI 404s the EDR endpoint 10× in a row. **After § 3.8's BOM patch:** error advances to `No Endpoint generator function registered for transfer type destination 'HttpData'` - different gap, see §§ 3.8.1–3.8.2. |
| **Root cause** | `edc-connector/runtimes/controlplane/build.gradle.kts` only depended on `edc-bom-controlplane` + `edc-bom-controlplane-sql`. It booted in "remote Data Plane client" mode (visible in startup logs: `Initialized Data Plane Signaling Client / Using remote Data Plane client`) and waited for a separate data plane to register itself via the selector API. None ever did - `participant-agent-services/docker-compose.yml` has no dataplane container, and there's no separate dataplane runtime module in this repo. Aliases for `edc-bom-dataplane` + `edc-bom-dataplane-sql` already existed in `libs.versions.toml` but were never referenced. |
| **Quick fix (applied)** | Add `runtimeOnly(libs.edc.bom.dataplane)` + `runtimeOnly(libs.edc.bom.dataplane.sql)` to `runtimes/controlplane/build.gradle.kts`. The BOM brings in `data-plane-core`, `data-plane-http`, `data-plane-http-oauth2`, `data-plane-iam`, `data-plane-selector-client`, `data-plane-self-registration`, `data-plane-signaling-api`. Verified by inspecting `https://repo.maven.apache.org/maven2/org/eclipse/edc/dataplane-base-bom/0.15.1/dataplane-base-bom-0.15.1.pom`. **Caveat:** the historical `data-plane-public-api-v2` artifact has no 0.15.x build (last is 0.13.0) - do NOT try to add it as a `runtimeOnly`, the build fails to resolve. The public/data-fetch path is bundled inside `data-plane-http` in 0.15.x. |
| **Config note** | The data plane's self-registration reads `edc.dataplane.api.public.baseurl` from `participant/configuration.properties` to register its public endpoint with the controlplane. Default is `http://localhost:<public-port>/public` if unset; for dev this works inside the docker network because controlplane and dataplane share the JVM. For prod (or for cross-container reachability when the dataplane is split out), set it explicitly to the externally-reachable URL - same constraint as `edc.dsp.callback.address`. Also reserve a host port for `/public` on each participant's nginx config and proxy it to the connector - without that the consumer's EDR-token-bearing GET can't reach the source data plane. |
| **Alternative (deferred - Phase 7+ if/when the dataplane needs independent scaling)** | Split the dataplane into a separate runtime module under `edc-connector/runtimes/dataplane/`, package it as its own Docker image, add a `dataplane` service to `participant-agent-services/docker-compose.yml`, and configure it to register against the controlplane's `/management/v3/dataplanes`. More moving parts; only worth it when a participant wants to scale the data path independently of negotiation. |
| **Status** | [x] `runtimes/controlplane/build.gradle.kts` adds `edc.bom.dataplane` + `edc.bom.dataplane.sql` runtimeOnly · [x] Verified `data-plane-public-api-v2` is NOT publishable at 0.15.x (last 0.13.0 - do NOT try to add as dep, build won't resolve) · [x] Verified dataplane self-registration writes a registration with `allowedTransferTypes=["HttpData-PULL-HttpData","HttpData-PUSH-HttpData","HttpData-PULL","HttpData-PUSH"]` and `url=http://localhost:9192/control/v1/dataflows` (the SIGNALING endpoint - not a consumer-facing URL) · [x] Verified that boot has NO `public` web context (only `default / control / management / protocol`) - by design in 0.15.x · [x] M1 PULL transfer now passes the "No dataplane found" gate (provider reaches STARTING) · [ ] Provider now fails at STARTING with `No Endpoint generator function registered for transfer type destination 'HttpData'` - next phase: § 3.8.1 |

## 3.8.1 Register a `PublicEndpointGeneratorService` function for `HttpData` destination

| Item | Detail |
|------|--------|
| **Symptom** | Provider's transfer goes INITIAL → PROVISIONING → PROVISIONED → STARTING → terminates with `WARNING Error obtaining EDR DataAddress: No Endpoint generator function registered for transfer type destination 'HttpData'`. The `PublicEndpointGeneratorService` interface and `PublicEndpointGeneratorServiceImpl` are both in the fat jar (from the BOM); the service is wired but its registration map is empty - no `addGeneratorFunction("HttpData", ...)` call ever fires. |
| **Root cause** | The old `data-plane-public-api-v2` artifact (last published at 0.13.0) was responsible for calling `endpointGenerator.addGeneratorFunction("HttpData", dataAddress -> Endpoint(...))` on boot. EDC 0.15.x's `dataplane-base-bom` does NOT include any extension that does this. None of the bundled extensions (`data-plane-http`, `data-plane-signaling-api`, `data-plane-iam`, `data-plane-self-registration`) wires it. So every HttpData-PULL transfer reaches STARTING and dies because the data plane can't generate the consumer-facing URL for the EDR. |
| **Fix (to implement)** | Add a tiny custom extension to `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/` that injects `PublicEndpointGeneratorService` and registers a generator function for `"HttpData"` destination. The function takes the asset's `HttpDataAddress` and returns an `Endpoint` whose properties include `endpoint = <externally-reachable URL>` + `endpointType = "HttpData"`. Bytecode signatures already verified from the running jar: `addGeneratorFunction(String type, Function<DataAddress, Endpoint>)` is the call to make. |
| **URL strategy decision needed** | The Endpoint URL must be browser-reachable on the consumer side. Two viable approaches: (a) **direct fetch** - Endpoint URL = asset's `baseUrl` rewritten to externally-reachable host (e.g. `http://nginx:8080/ldp/...` → `http://host.docker.internal:8081/ldp/...`); consumer's UI sends the EDR's bearer token + DSP-* headers; `djangoldp_edc` permission class on the LDP backend validates. Simplest, mirrors the existing M1 fixture wiring. (b) **dataplane proxy** - Endpoint URL points to a custom `public` HTTP endpoint we add to the connector, which proxies requests to the asset's source and injects DSP-* headers; consumer UI never sees the source URL. More moving parts but hides backend topology. Recommend (a) for Tier-1 and revisit at Tier-2 when DCP-based identity rotation lands. |
| **Status** | [x] Scaffold `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/` (mirrors policy-functions / iam-keycloak layout) · [x] Implement `GlcdiDataplanePublicApiExtension` - registers EndpointGenerator for `HttpData`, binds the `public` web context via `PortMappingRegistry`, bridges the InMemoryVault gap by loading `edc.vault.secrets.<n>.key/value` pairs from config into the vault · [x] Implement `GlcdiPublicApiController` - JAX-RS `/` resource: validates `Authorization: Bearer <token>` via `DataPlaneAuthorizationService`, resolves AccessTokenData via `DataPlaneAccessTokenService.resolve(token)`, extracts `agreement_id` + `participant_id` from `AccessTokenData.additionalProperties()`, injects them as `DSP-AGREEMENT-ID` / `DSP-PARTICIPANT-ID` headers, proxies GET to the resolved `DataAddress.baseUrl` via OkHttp · [x] Strategy chosen: (b) dataplane proxy · [x] Wired into `runtimes/controlplane/build.gradle.kts` + `scripts/sync-glcdi-extensions.sh` · [x] `glcdi.sh` per-org rewrite of `edc.dataplane.api.public.baseurl` so each participant advertises its own host port · [x] `glcdi.sh` nginx-config heredoc augmented with the `/ldp/` proxy block · [x] `glcdi.sh` `EDC_URL` no longer carries trailing `/management` (djangoldp_edc's `utils.py` appends `/management/v3/…` itself - double-`/management` was causing 404s on agreement lookups) · [x] `glcdi.sh` seed-ldp now writes asset baseUrls pointing at `djangoldp-backend:8083` directly (bypassing nginx) - was `http://nginx:8080/ldp/…`; nginx stripped `/ldp/` before forwarding so django saw `/farms/…` and V3's coverage check couldn't match the asset's stored baseUrl · [x] `glcdi.sh` per-org config now uses `/public/` (trailing slash) so nginx doesn't 301-redirect and the browser doesn't drop `Authorization` on the redirect · [x] `djangoldp-glcdi==3.1.4` published with the `permission_classes = [(AuthenticatedOnly & ReadOnly) \| EdcContractPermissionV3]` wiring on Farm/Plot/Metric · [x] `participant-agent-services/djangoldp/Dockerfile` bumped to `DJANGOLDP_GLCDI_VERSION=3.1.4` · [x] `glcdi.sh` defaults `GLCDI_PATH` to pinned `@startinblox/glcdi@1.0.4` (was empty → fell through to `@latest` → Workbox SW cached indefinitely) - survives across `up` re-templating · [x] **CLI end-to-end verified**: caney-fork → point-blue / `grazing-soc-2024` reaches `STARTED`; EDR returns 200; proxy fetch returns the `Farm` JSON-LD · [x] **UI end-to-end verified in browser**: full chain operates through the modal's Access Data click - `Farm` JSON-LD (name="Point Blue demo farm", plots, metrics, field_levels) renders in the modal · [ ] **`@startinblox/glcdi` follow-up publish**: `dsp-catalog.ts:303` binds `.displayServiceTest=${this.displayServiceTest}` to the modal, but `dsp-catalog` doesn't have its own `@property displayServiceTest` declaration - so it passes `undefined` and overrides the modal's `=true` default. Fix: add `@property displayServiceTest = true;` on `dsp-catalog` (or `… ?? true` on the binding). Today's UI test required `m.displayServiceTest = true` in the console to render the button - but the resulting click worked end-to-end. Publishing the patch + bumping `glcdi.sh`'s pinned version removes the manual step. · [ ] Bruno integration test for the full UI flow · [ ] PR / commit the `glcdi-dataplane-public-api` extension and the `glcdi.sh` per-org fixes |

## 3.8.2 Cleanup: remove stale `public`-context wiring once § 3.8.1 lands

| Item | Detail |
|------|--------|
| **Task** | The current per-org `participant/configuration.properties` carries `web.http.public.port=9291` / `web.http.public.path=/public` / `edc.dataplane.api.public.baseurl=…/public`, and `nginx-dev.conf` + `nginx-prod.conf` carry a `location /public/ → edc-connector:9291` block. These are pre-0.15.x leftovers - EDC 0.15.x doesn't bind a `public` context (verified empirically and via POM inspection of `dataplane-base-bom-0.15.1`). They're inert today (no upstream listening, so any traffic 502s - but no traffic flows there in practice). |
| **Action when § 3.8.1 lands** | If § 3.8.1's chosen URL strategy is (a) direct fetch, drop the `public` lines from both `configuration.properties.example` and the two nginx conf files. If strategy is (b) dataplane proxy, replace the upstream port (9291 → whatever the custom public extension binds) and keep the location block. |
| **Status** | [ ] Strategy chosen in § 3.8.1 · [ ] Stale `public`-context settings removed / updated accordingly · [ ] Note in IMPLEM_PLAN.md release notes that EDC 0.15.x flipped from public-api artifact to caller-registered generator |

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 2: Keycloak Claims Configuration - Connector Service-Account Tokens](phase-2-keycloak-claims.md) · [next: Phase 4: Update Seeding Scripts & Contract Definitions →](phase-4-seeding.md)
