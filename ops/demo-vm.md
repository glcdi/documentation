# Demo Staging VM - Plan

**Status:** Decisions locked 2026-06-11. Repo scaffold landed; VM-side
conversion + governance-KC steps pending.

**Companion docs:**
- `management/ASSETS_EXAMPLES.md` - workshop-phase contributor inputs
  (Stone Barns / Sonoma Mountain / UFL / Pasa / White Buffalo)
- `management/IMPLEM_PLAN.md` - M1 trio + roadmap
- `management/ops/staging-wipe.md` - wipe + reseed flow,
  extended to cover the demo VM

## 1. Scope

Workshop participants 1–4 in `ASSETS_EXAMPLES.md` co-locate on a single
new staging VM. Participant 5 (White Buffalo) keeps its existing
`white-buffalo` VM and is out of scope here.

| # | Contributor | Org | Dataset | Target VM |
|---|---|---|---|---|
| 1 | Elijah Goodwin | Stone Barns Center | SBC Grazing Soil Health 2020-2025 | **demo** |
| 2 | Byron Palmer | Sonoma Mountain Institute | Pasture Map Export | **demo** |
| 3 | Chang Zhao | University of Florida | FL Grazing-land SOC 2022-2024 | **demo** |
| 4 | Laura Kaminsky | Pasa Sustainable Agriculture | Pasa Soil Health Benchmark 2016-2024 | **demo** |
| 5 | Aarushi Jhatro | White Buffalo Land Trust | Jalama Canyon Rangeland SOC 2021-2025 | white-buffalo (existing) |

## 2. Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| Q1 | VM slug | `demo` | user-supplied; matches `demo.glcdi.startinblox.com` |
| Q2 | Contract policy shape | **Shape B** - atomic obligation policies + per-asset composite | obligation taxonomy queryable in the catalog; CDs reference a derived composite per asset |
| Q3 | Data backing | **Option A** - static JSON stubs behind nginx | fastest path for catalog/discovery demo; no per-asset LDP enforcement (not needed at this tier) |
| Q4 | Identity | **single demo user in `demo-team` group with realm role `glcdi_member`** | no per-contributor end-users; tokens issued for the group, contributors distinguished by asset prefix |
| Q5 | `public-policy` semantics | **truly anonymous** | unauth viewers see the catalog directly - closest to workshop intent (corporates / supply-chain / public) |

## 3. VM topology

| Slot | Value |
|---|---|
| VM slug | `demo` |
| Public host | `demo.glcdi.startinblox.com` (DNS → 91.107.215.221) |
| Connector ID | `glcdi-connector-demo` |
| Realm (participant tier) | n/a - tier-1 IAM uses governance KC's `glcdi` realm |
| Local dev port | `8083` (would only be used if `demo` is ever run locally - currently staging-only) |
| Type tag | `other` |
| LDP package | `djangoldp_glcdi` (baseline - reused; LDP container boots but isn't authoritative) |
| Static data root | `https://demo.glcdi.startinblox.com/data/` |

The 4 workshop contributors are modelled as **asset prefixes**, not as
separate connectors or realms. Their distinguishing metadata lives on
the asset (`glcdi:contributor`, `glcdi:contact`, ID prefix
`urn:glcdi:asset:<contributor-slug>:...`).

## 4. Policy taxonomy

### 4.1 Access policies (catalog visibility)

| Policy ID | Constraints | Status |
|---|---|---|
| `producer-only-policy` | `membership=active` + `participantType=producer` | exists (M1) |
| `researcher-only-policy` | `membership=active` + `participantType=researcher` | exists (M1) |
| `members-policy` | `membership=active` | exists (M1) - used by Stone Barns asset |
| `public-policy` | **none** (anonymous: `odrl:permission` without constraint) | **NEW** - `12-provider-seeding-demo/01-create-access-policy-public.bru` |

### 4.2 Contract policies (terms attached at negotiation)

Shape B: atomic atoms (03–07) seeded once; each asset has its own
composite (11/21/31/41) that merges the relevant atoms inline. CDs
reference the per-asset composite.

| Policy ID | Mechanism | Enforced in M1? | Status |
|---|---|---|---|
| `internal-use-only-policy` | baseline; no clause | yes | exists (M1) + re-seeded for demo (02, idempotent) |
| `attribution-required-policy` | `odrl:duty` - `attribute` | yes (recorded on agreement) | **NEW** (03) |
| `share-back-required-policy` | `odrl:duty` - `inform` w/ `glcdi:shareBackArtifact` | yes (recorded) | **NEW** (04) |
| `no-commercial-use-policy` | `odrl:prohibition` - `commercialise` + `distribute` | yes (rejection at agreement time) | **NEW** (05) |
| `pre-publication-review-policy` | `odrl:duty` - `reviewBefore` | **no** - recorded only | **NEW** (06) |
| `payment-required-policy` | `odrl:duty` - `compensate` w/ amount + currency | **no** in M1 - system enforcement is M2 (`PAYMENT_GATING.md`) | **NEW** (07) |

Per-asset composites (11/21/31/41) inline the merged ODRL set
referencing the relevant atoms' duties / prohibitions.

## 5. Per-asset matrix

| Asset ID | Contributor | Access policy | Contract policy (composite) |
|---|---|---|---|
| `urn:glcdi:asset:stone-barns:soil-health-2020-2025` | Stone Barns | `members-policy` | `stone-barns-soil-health-cp` = internal + attribution + share-back + no-commercial |
| `urn:glcdi:asset:sonoma-mountain:pasture-map-export` | Sonoma Mountain | `public-policy` | `sonoma-mountain-pasture-map-cp` = internal + share-back (extended scope) + payment ($500 USD) |
| `urn:glcdi:asset:florida:grazing-soc-2022-2024` | University of Florida | `public-policy` | `florida-grazing-soc-cp` = internal + attribution + pre-publication-review |
| `urn:glcdi:asset:pasa:soil-health-benchmark-2016-2024` | Pasa | `public-policy` | `pasa-soil-health-cp` = internal + pre-publication-review |

CDs: `<asset-prefix>-cd` for each (e.g. `stone-barns-soil-health-cd`).

## 6. Data backing - Option A (static stubs)

Each asset's `dataAddress.baseUrl` points at a JSON file served by
nginx on the demo VM under `/data/<slug>.json`:

| Asset | baseUrl |
|---|---|
| Stone Barns | `https://demo.glcdi.startinblox.com/data/stone-barns-soil-health.json` |
| Sonoma Mountain | `https://demo.glcdi.startinblox.com/data/sonoma-mountain-pasture-map.json` |
| University of Florida | `https://demo.glcdi.startinblox.com/data/florida-grazing-soc.json` |
| Pasa | `https://demo.glcdi.startinblox.com/data/pasa-soil-health.json` |

Wiring:
- Stub JSON files: `participant-agent-services/data/demo/*.json` - sample
  records only, real datasets withheld pending dataspace launch.
- nginx volume mount: `participant-agent-services/docker-compose.yml`
  mounts `${PARTICIPANT_DATA_DIR:-./data/empty}` to
  `/usr/share/nginx/html/data` in the `nginx-prod` service.
- nginx route: `participant-agent-services/participant/nginx-prod.conf`
  has a `location /data/` block serving from the alias.
- The M1 trio's `.env` leaves `PARTICIPANT_DATA_DIR` unset → defaults to
  `./data/empty/` → `/data/` returns 404 cleanly on those VMs.
- The demo `.env` (from `.env.demo.example`) sets
  `PARTICIPANT_DATA_DIR=./data/demo` → stubs reachable.

## 7. Repo scaffold (landed)

| File | Status |
|---|---|
| `management/scripts/glcdi.sh` | extended: `demo` in ORGS/ORG_PORTS/ORG_COLORS/ORG_TYPES/ORG_LDP_PACKAGES, expand_target, target_host, target_bruno_env, SSH_USER_VAR/SSH_HOST_VAR; `LOCAL_ORGS` introduced (= M1 trio) for local-iteration spots; `seed_one` dispatches `demo` → `seed_demo` → `12-provider-seeding-demo` Bruno folder |
| `management/scripts/nuclear-wipe-stagings.sh` | extended: `demo` in SSH var maps + `expand_target`; `expected_policies_for` / `expected_cds_for` per-org dispatchers cover M1 trio + demo |
| `management/scripts/setup-demo-from-snapshot.sh` | **NEW** - VM-side conversion from a white-buffalo snapshot. Dry-run by default. See §9 |
| `management/bruno/12-provider-seeding-demo/` | **NEW** folder - 7 policy files (01 public + 02 internal + 03–07 atomic obligations) + 4 contributor trios (asset / composite / CD), see §4–5 |
| `management/bruno/environments/staging.bru` | added `demo_host` / `demo_dsp` / `demo_participant_id` / `demo_data_root` + `demo_api_key` / `demo_client_secret` / `demo_token` in `vars:secret` |
| `participant-agent-services/.env.demo.example` | **NEW** - env template (purple branding, glcdi-connector-demo, DSP_PROVIDERS = 3 M1 peers, PARTICIPANT_DATA_DIR=./data/demo) |
| `participant-agent-services/.gitlab-ci.yml` | **NEW** `deploy-demo` job mirroring `deploy-white-buffalo`, gated on `SSH_USER_DEMO` / `SSH_HOST_DEMO` CI vars |
| `participant-agent-services/docker-compose.yml` | `nginx-prod` gains `${PARTICIPANT_DATA_DIR:-./data/empty}:/usr/share/nginx/html/data:ro` mount |
| `participant-agent-services/participant/nginx-prod.conf` | new `location /data/` block aliasing `/usr/share/nginx/html/data/` (CORS open, application/json default) |
| `participant-agent-services/data/demo/*.json` | **NEW** 4 stub datasets (Stone Barns / Sonoma / Florida / Pasa) |
| `participant-agent-services/data/empty/.gitkeep` | placeholder so M1 trio mount succeeds |

## 8. CI / DNS / VM provisioning

| Step | Owner | Notes |
|---|---|---|
| DNS A record `demo.glcdi.startinblox.com` → 91.107.215.221 | ops | done per user |
| VM provisioned by snapshotting white-buffalo | ops | done per user |
| Out-of-band: live `.env` on VM | **`setup-demo-from-snapshot.sh`** | see §9 |
| Out-of-band: governance KC client + realm role + group + user | governance admin | via Keycloak admin console; see §10 |
| GitLab CI vars `SSH_USER_DEMO` + `SSH_HOST_DEMO` | ops | required for the `deploy-demo` manual job |
| Certbot first-run for `demo.glcdi.startinblox.com` | nginx-prod profile | should happen on first `up -d` provided DNS resolves |

## 9. VM-side conversion (from white-buffalo snapshot)

The white-buffalo snapshot still carries white-buffalo's `.env`,
`participant/configuration.properties`, its rotated EDC API key, its
Keycloak client identity (white-buffalo), and white-buffalo's connector
Postgres + DjangoLDP volumes. `setup-demo-from-snapshot.sh` is the
conversion runbook:

```bash
ssh root@demo.glcdi.startinblox.com
cd ~/participant-agent-services
git pull       # to get the new script + templates from this branch
bash management/scripts/setup-demo-from-snapshot.sh                            # dry-run first
bash management/scripts/setup-demo-from-snapshot.sh --no-dry-run --kc-secret <SECRET-FROM-KC>
```

The script:

1. **Stops the snapshotted stack** (`docker compose --profile prod down --remove-orphans`).
2. **Drops the project's named volumes** (`glcdi-white-buffalo_connector-pg-data` etc.) so the new demo connector starts with empty pg.
3. **Backs up the old `.env`** to `.env.snapshot-backup-<TIMESTAMP>`.
4. **Mints fresh secrets** via `openssl rand`: `EDC_API_KEY`, `CONNECTOR_DB_PASSWORD`, `LDP_DB_PASSWORD`, `LDP_DB_BOOTSTRAP_PASSWORD`, `DJANGO_SECRET_KEY`.
5. **Writes the new `.env`** with demo slug + `demo.glcdi.startinblox.com` + purple branding + `DSP_PROVIDERS` listing CF/PB/WB + `PARTICIPANT_DATA_DIR=./data/demo`.
6. **Rewrites `participant/configuration.properties`** in place: `glcdi-connector-PARTICIPANT_NAME` / `glcdi-connector-white-buffalo` → `glcdi-connector-demo`, `host.docker.internal` → `demo.glcdi.startinblox.com`, all three API-key entries → newly minted key, `edc.datasource.default.password` → newly minted db password, `glcdi.iam.kc.client.id` → `glcdi-connector-demo`, `glcdi.iam.kc.client.secret` → value from `--kc-secret`.
7. **Rewrites `participant/idh-configuration.properties`** similarly (`host.docker.internal*` → `demo.glcdi.startinblox.com`).
8. **Brings the stack up** (`docker compose --profile prod up -d`).
9. **Polls `/check/health`** on the connector for up to ~150s.
10. **Prints the new `EDC_API_KEY`** + a checklist of governance-KC steps (§10) + the seed command (§11).

Caveats:

- The `--kc-secret` value MUST come from the governance Keycloak admin
  console BEFORE running `--no-dry-run` - the connector won't get
  client-credentials tokens otherwise. See §10.
- Certbot needs DNS to be live (it is). On first up, the nginx-prod
  container will request a new cert for `demo.glcdi.startinblox.com`
  via the Let's Encrypt ACME challenge. Watch
  `docker compose logs certbot` if `/check/health` over HTTPS doesn't
  come up.
- `--keep-volumes` skips the volume drop - useful if you've already
  wiped manually.

## 10. Governance Keycloak - manual steps

These can't be automated without governance-admin credentials. Do them
in the `glcdi` realm on `governance.glcdi.startinblox.com/auth/admin/`:

1. **Client `glcdi-connector-demo`:**
   - Client-credentials flow enabled.
   - Service-accounts enabled.
   - Scope `glcdi-claims`.
   - Generate a client secret → pass to
     `setup-demo-from-snapshot.sh --kc-secret`.
2. **Realm role `glcdi_member`** (create if missing).
3. **Group `demo-team`** → role-mapping → `glcdi_member`.
4. **User `demo@demo.glcdi.startinblox.com`** (or any handle) →
   member of `demo-team`. Set a password so the catalogue UI can log in.
5. **Protocol mapper** on either the realm-default scope or the
   `glcdi-claims` scope so `glcdi_member` role membership emits the
   `glcdi:membership=active` claim. Mirror what the M1 trio already has.
6. **Brokered IdP** - if the demo VM uses governance KC directly (no
   participant KC sub-realm), nothing to do.

## 11. Seed + validate (from laptop)

```bash
distrobox enter dev
cd ~/Workspaces/Dataspaces/glcdi

./management/scripts/glcdi.sh seed --target demo
```

`glcdi.sh seed --target demo` dispatches to `seed_demo`, which runs the
`12-provider-seeding-demo` Bruno folder and seeds:

- `public-policy` (anonymous access)
- `internal-use-only-policy` (idempotent - 409 if M1 also seeded here)
- 5 atomic obligation policies
- 4 composite contract policies (one per contributor)
- 4 assets
- 4 contract definitions

Validate:

```bash
./management/scripts/nuclear-wipe-stagings.sh --target demo                  # dry-run preview (does NOT wipe)
./management/scripts/nuclear-wipe-stagings.sh --target demo --no-dry-run     # if you need to re-seed clean
```

The wipe script's `verify_seeded` step now expects, for demo: 7 policies
(public + internal + 5 atomic) + 4 CDs. (Per-asset composite policies
are NOT in `expected_policies_for("demo")` - they're an internal
composition detail and would add noise. The CDs are what the script
verifies.)

Manual catalog visibility checks:

- `curl -sk https://demo.glcdi.startinblox.com/ui/`  → 200, demo
  branding.
- Hit catalogue UI **unauthenticated** → 3 anonymous (public-policy)
  assets visible.
- Hit catalogue UI as `demo@demo.glcdi.startinblox.com` →
  additionally the Stone Barns asset (members-policy).
- Trigger a contract negotiation for each asset; confirm the agreement
  carries the §5 composite policy ID.

## 12. Open / next

- **Onboarding** - the existing onboarding flow (governance-services
  onboarding app) hasn't been wired to issue `glcdi_member` roles
  to demo-tier users. For the demo VM the user is provisioned by hand
  (§10). No work until/unless a self-serve flow is needed.
- **Real datasets** - current stubs are sample records only. Replace
  via the Option B path (new `djangoldp_glcdi_demo` package) when /
  if contributors are ready to release.
- **Onboarding the demo VM as a peer of the M1 trio** - the M1
  trio's `DSP_PROVIDERS` does NOT currently list `demo` as a peer.
  Adding it would make demo appear in their catalog views too;
  decide whether that's desirable or whether demo stays one-way
  (sees the trio, isn't seen by them).
- **Pre-publication-review / payment** - recorded only in M1.
  System-enforcement is in `PAYMENT_GATING.md` scope (M2).

## 13. References

- `management/ASSETS_EXAMPLES.md` - workshop dataset inputs
- `management/IMPLEM_PLAN.md` - M1 trio + roadmap
- `management/ops/staging-wipe.md` - wipe + reseed flow
- `management/scripts/setup-demo-from-snapshot.sh` - VM-side conversion
- `management/scripts/glcdi.sh:76-104` - `ORGS` + `LOCAL_ORGS` + per-org maps
- `management/scripts/glcdi.sh:1062-1080` - `seed_demo`
- `management/bruno/12-provider-seeding-demo/` - full seed contract
- `participant-agent-services/.env.demo.example` - env template
- `participant-agent-services/data/demo/*.json` - stub datasets
- `participant-agent-services/participant/nginx-prod.conf` - `/data/` location block
