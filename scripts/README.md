# GLCDI local-stack orchestrator

`glcdi.sh` brings up the entire GLCDI workspace locally - Authority Keycloak
plus the three M1 participant connectors (`caney-fork`, `point-blue`,
`white-buffalo`) - in the right order with secrets rotated from their
`changeme-*` placeholders.

It is the scripted form of [`../DEPLOYMENT.md` § 3 (local validation)](../DEPLOYMENT.md).

## Quick start

```sh
# From the workspace root (or anywhere - paths are absolute):
./management/scripts/glcdi.sh preflight   # verify tools
./management/scripts/glcdi.sh build       # edc-connector + participant-ui images
./management/scripts/glcdi.sh up          # authority KC + 3 participants
./management/scripts/glcdi.sh seed        # M1 fixtures via Bruno
./management/scripts/glcdi.sh test        # Bruno run (tier1 default)
./management/scripts/glcdi.sh status      # health check

# Or all at once:
./management/scripts/glcdi.sh all
```

To reset (destructive):

```sh
./management/scripts/glcdi.sh reset       # down + remove volumes + nuke local state
```

## Subcommand reference

| Subcommand | What it does | Idempotent? |
|---|---|---|
| `preflight` | Verifies docker, openssl, curl, jq, docker-compose-v2; warns if `bru` missing or ports occupied | yes |
| `secrets` | Generates `.glcdi.local/secrets.env` on first run; prints contents thereafter | yes |
| `build` | `sync-glcdi-extensions.sh` + `gradlew :runtimes:controlplane:dockerize` for edc-connector; `docker build` for participant-ui | yes |
| `up` | Authority KC (port 8090) → 3 participant stacks (ports 8080/8081/8082); waits for each to respond | yes |
| `seed` | `bru run 10-provider-seeding --env local` against caney-fork's connector | yes (re-seeds; EDC accepts) |
| `test [tier]` | `bru run --env local --env-var tier=<tier>` against the local stack. Tier defaults to `$GLCDI_TIER` or `tier1` | yes |
| `status` | Hits Authority KC discovery + each participant's `/management/v3/assets/request` | yes |
| `logs <svc>` | `docker compose logs -f --tail=200` for `authority` or one of the 3 participant names | yes |
| `down` | `docker compose down` for every stack - **preserves volumes** | yes |
| `reset` | `docker compose down -v` + `rm -rf .glcdi.local/` - **destroys all local state** | yes (terminal) |
| `all` | `preflight` → `build` → `up` → `seed` → `test` | yes |

## Tier toggle

Tier 1 (default) and Tier 2 of the [identity tiering strategy](../IMPLEM_PLAN.md#identity-tiering-strategy):

```sh
./glcdi.sh test          # tier1: X-Api-Key only
./glcdi.sh test tier2    # tier2: X-Api-Key + Bearer (post-§ 7.2)
GLCDI_TIER=tier2 ./glcdi.sh all     # equivalent
```

The script itself doesn't bring up oauth2-proxy differently between tiers
(the participant compose has `oauth2-proxy` as a long-running service
either way today). The tier flag drives Bruno's auth model only - see
`../bruno/README.md`. **Until [`IMPLEM_PLAN § 7.2`](../IMPLEM_PLAN.md#phase-72-identity-tier-2--add-user-oidc-at-the-ui)
lands the actual Tier-2 UI changes**, `test tier2` exercises the
oauth2-proxy validation path but the catalogue UI itself is still in
its pre-§ 4.5.F state.

## Working directory: `.glcdi.local/`

Generated state lives here, gitignored:

```
.glcdi.local/
├── secrets.env                  # Rotated secrets (mode 600). Keep out of VCS.
├── glcdi-realm.json             # Realm JSON patched with rotated client secrets
├── authority.env                # Authority KC compose envvars
├── authority.override.yml       # Re-binds realm JSON + admin password + port
├── caney-fork/
│   ├── .env                     # Per-participant compose envvars
│   ├── docker-compose.override.yml   # Re-binds participant/ volume to this dir
│   └── participant/
│       ├── configuration.properties        # Patched ports + URLs + API key
│       └── idh-configuration.properties    # Identity Hub config (if present)
├── point-blue/                  # Same shape
└── white-buffalo/               # Same shape
```

`reset` removes this whole tree. `down` leaves it intact.

## Port allocation

| Service | Host port |
|---|---|
| Authority Keycloak | `8090` (admin console: `http://localhost:8090/auth/admin`) |
| caney-fork | `8080` (UI + nginx → connector mgmt) |
| point-blue | `8081` |
| white-buffalo | `8082` |

The script remaps via `NGINX_PORT` and per-participant `configuration.properties`
(`edc.dsp.callback.address`, `edc.participant.id`).

## What's currently functional vs. gated

| Capability | Status | Gated by |
|---|---|---|
| Authority KC up + realm imported with rotated client secrets | ✅ | - |
| 3 participant connectors up with separate ports | ✅ | - |
| `/management` reachable with rotated `X-Api-Key` | ✅ | - |
| Bruno's `00-auth/` succeeds - connector SAs mint tokens with the right claims | ✅ post-realm-import | - |
| Bruno's `10-provider-seeding/` (asset / policy / contract def CRUD) | ✅ | - |
| Bruno's `20-catalog-discovery/` filtering correctly admits white-buffalo + filters point-blue | ⚠ partial | [`IMPLEM_PLAN § 3`](../IMPLEM_PLAN.md#phase-3-edc-policy-extension-development) (custom constraint functions) + [`§ 3.5`](../IMPLEM_PLAN.md#35-replace-iam-mock-with-iam-oauth2-and-configure-claim-extraction) (iam-oauth2 swap) - until both land, `iam-mock` accepts everything and the access policy doesn't filter |
| Bruno's `30-negotiation/` reaching FINALIZED / TERMINATED | ⚠ partial | Same as above + EDC async-state-machine polling files |
| Bruno's `40-transfer/` reaching a terminal success state | ⚠ partial | Phase 3+4 + transfer state-machine polling |
| `99-negative-auth/03-tier2-no-bearer.bru` and `/04-tier2-wrong-bearer.bru` | ⚠ Tier-2 only | [`IMPLEM_PLAN § 7.2`](../IMPLEM_PLAN.md#phase-72-identity-tier-2--add-user-oidc-at-the-ui) (oauth2-proxy actually validating Bearer) |

The script doesn't pretend more works than does. Run it, observe what's
green vs. red, and use the red rows as a checklist for the next phase.

## Common workflows

### Fresh setup, just want to see it run

```sh
./glcdi.sh all
```

### Iterating on policy functions (Phase 3)

```sh
./glcdi.sh build && ./glcdi.sh down && ./glcdi.sh up && ./glcdi.sh test
# or:
./glcdi.sh build && ./glcdi.sh up    # `up` is idempotent - re-creates containers
./glcdi.sh test
```

### Iterating on Keycloak realm content

```sh
# Edit governance-services/resources/keycloak/realms/glcdi-realm.json, then:
./glcdi.sh reset       # full wipe - KC re-imports the realm only on first boot
./glcdi.sh up
```

### Tail logs while something fails

```sh
./glcdi.sh logs caney-fork    # in one terminal
./glcdi.sh test               # in another
```

### Switching to Tier 2 to validate the oauth2-proxy path

```sh
# Once IMPLEM_PLAN § 7.2 has landed the actual Tier-2 changes:
./glcdi.sh test tier2
```

## Limitations / caveats

- **Per-participant Postgres volumes** are shared across participants by
  Docker volume name (`glcdi-<participant>_connector-pg-data`). The
  per-participant project name (`name: glcdi-${PARTICIPANT_NAME}` in
  `docker-compose.yml`) keeps them isolated, but `docker volume ls` will
  show 3 separate volumes - by design.
- **The realm JSON is patched at script time, not at compose time.** If
  the script has already brought up Authority KC and you regenerate
  secrets (`rm .glcdi.local/secrets.env`), you must `reset` rather than
  `down` to get the new secrets imported (KC imports realm JSON on first
  boot only).
- **`bru` (Bruno CLI) is required for `seed` and `test`.** Install with
  `npm install -g @usebruno/cli`. The `seed` step has a curl fallback
  but it's a stub - Phase 4's seeding scripts will land separately.
- **`participant/` volume mount via override.** The script uses a
  `docker-compose.override.yml` per participant to rebind the
  `./participant:/app/conf:ro` mount to the per-org directory in
  `.glcdi.local/`. If `participant-agent-services/docker-compose.yml`
  changes how `./participant` is mounted, the override needs updating.
- **`oauth2-proxy` stays in compose at Tier 1.** The Tier-1 strip-down
  per [`IMPLEM_PLAN § 1.5.2`](../IMPLEM_PLAN.md#152-remove-per-participant-keycloak-and-oauth2-proxy-from-the-participant-compose-stack)
  removes `oauth2-proxy` from the participant compose. Until that lands
  in `participant-agent-services/docker-compose.yml`, the script brings
  it up - it just doesn't gate any Bruno path at Tier 1 because the
  Bruno tests don't send a Bearer header at that tier (oauth2-proxy
  passes through to the connector, where `X-Api-Key` decides).

## Pointers

- Identity tiering: [`../IMPLEM_PLAN.md` § Identity Tiering Strategy](../IMPLEM_PLAN.md#identity-tiering-strategy)
- Tier-1 cutover (manual, runbook): [`../DEPLOYMENT.md`](../DEPLOYMENT.md)
- Authority rename runbook: [`../AUTHORITY_MIGRATION.md`](../AUTHORITY_MIGRATION.md)
- Bruno collection: [`../bruno/`](../bruno/)
