# GLCDI Local Stack

How to run the entire GLCDI dataspace on a developer's laptop — Authority Keycloak + three participant connectors + catalogue UIs + Bruno test collection — end-to-end.

**This is almost entirely automated.** The [`build/scripts/glcdi.sh`](../build/scripts/) orchestrator generates every secret and config file, brings the stack up in dependency order, seeds the M1 fixtures, and runs the Bruno collection. Manual editing of `.env` files, `configuration.properties`, or secret rotation is normally unnecessary — override behaviour via environment variables on the invocation instead.

For staging / production VM deployment, see [`vm-deployment.md`](vm-deployment.md). Local green is the gate before triggering a VM deploy.

---

## 1. Prerequisites

**Workspace layout.** `glcdi.sh` needs the sibling repos checked out **next to** the `management/` repo. From a clean workspace root:

```sh
git clone git@git.startinblox.com:applications/glcdi/management.git
git clone git@git.startinblox.com:applications/glcdi/authority-services.git
git clone git@git.startinblox.com:applications/glcdi/participant-agent-services.git
git clone git@git.startinblox.com:applications/glcdi/edc-connector.git
git clone git@git.startinblox.com:applications/glcdi/edc-glcdi-extension.git
git clone git@git.startinblox.com:applications/glcdi/participant-ui.git
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

The script resolves every path relative to its own location (`SCRIPT_DIR/../../..`) — it does not care where the workspace root lives, only that the sibling directories are there. `preflight` fails fast with a clear message if any of them is missing.

**Tools.** Docker + Compose v2, `openssl`, `curl`, `jq`, and the Bruno CLI (`npm install -g @usebruno/cli`). `preflight` verifies all of these.

**Resources.** ≥ 8 GB RAM available to Docker; free host ports `8090` (Authority KC), `8080`/`8081`/`8082` (three participant nginxes).

---

## 2. Fast path — one command

From the workspace root:

```sh
./management/build/scripts/glcdi.sh all
```

This runs `preflight → build → up → seed → test` in sequence:

1. **`preflight`** — verifies docker / openssl / curl / jq / bru and the sibling directories.
2. **`build`** — builds three images locally: `controlplane:latest` (via Gradle `dockerize`), `glcdi-participant-ui:local`, `glcdi-djangoldp-backend:local`.
3. **`up`** — brings the Authority KC up on port `8090`, then three participant stacks on `8080`/`8081`/`8082`. Waits for each to respond `200` on `/management/v3/assets/request` before moving on.
4. **`seed`** — runs the Bruno `10-provider-seeding/` folder against `caney-fork`'s connector.
5. **`test`** — runs the full Bruno collection.

Reset (destructive) with:

```sh
./management/build/scripts/glcdi.sh reset       # docker compose down -v + wipe .glcdi.local/
```

Full subcommand reference lives in [`../build/scripts/README.md`](../build/scripts/README.md).

---

## 3. What the script generates

`glcdi.sh` writes every secret and config file under `management/build/scripts/.glcdi.local/` on first `up`. The layout:

| Generated file | What's in it |
|---|---|
| `.glcdi.local/secrets.env` (mode 600) | Per-org API keys + `glcdi-connector-<org>` client secrets + KC admin password + DB passwords, all `openssl rand`. Regenerate with `rm .glcdi.local/secrets.env` (then run `reset` before the next `up` — the KC realm JSON only re-imports on a fresh Keycloak boot). |
| `.glcdi.local/glcdi-realm.json` | Copy of `authority-services/resources/keycloak/realms/glcdi-realm.json` with `changeme-*` client secrets patched to the rotated values, bind-mounted over the in-repo original. |
| `.glcdi.local/authority.env` + `authority.override.yml` | Authority KC + onboarding-backend compose config (KC on `:8090`, onboarding on `:8083`, admin password from secrets). |
| `.glcdi.local/<org>/.env` + `docker-compose.override.yml` + `participant/configuration.properties` | Per-participant compose config for `caney-fork` / `point-blue` / `white-buffalo`, pointed at the Authority KC via `host.docker.internal:8090`, with `edc.dsp.callback.address` matched to each org's external port. |

**You do not edit these by hand.** If a secret or setting needs to change, delete `secrets.env` and re-run — everything downstream regenerates deterministically.

---

## 4. Environment-variable overrides

The only inputs you might override are environment variables on the `glcdi.sh` invocation itself:

- `GLCDI_TIER=tier2` — switches Bruno's auth model (post-§ 7.2 only; the script itself doesn't currently re-shape the compose per tier).
- `GLCDI_FARMOS=1` — additionally brings up the optional caney-fork farmOS site on `:8091`; run `./glcdi.sh farmos-install` once after the first `up`.
- `GLCDI_USE_LOCAL_PACKAGES=true` (+ `GLCDI_SIB_CORE_PATH=…`, `GLCDI_PKG_PATH=…`, etc.) — swap the participant UI's CDN-loaded `@startinblox/glcdi` bundle for a local Vite dev-server URL.

---

## 5. Expected outcome

After `glcdi.sh all` finishes, two acceptance signals:

**(1) Bruno collection runs green.** The per-folder assertion table lives in [`../build/bruno/README.md`](../build/bruno/README.md) — that's the canonical scenario contract.

**(2) Participant UI smoke-tests clean.** Open `http://localhost:8080` (caney-fork):

- The page loads directly — **no Keycloak redirect**.
- Paste the operator API key when prompted (from `.glcdi.local/secrets.env`; the UI stores it in `localStorage.glcdi_operator_api_key`).
- Browse to assets / policies / contract definitions / contract negotiations / transfer-processes sections — each component renders.
- DevTools network tab: every `/management/*` request carries `X-Api-Key` and no `Authorization: Bearer`; no `silent-callback` requests; no calls to any Keycloak host.

---

## 6. Common failure modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `preflight` fails: `Missing required tools: bru` | Bruno CLI not installed | `npm install -g @usebruno/cli` |
| `preflight` fails: `Expected directory missing: /…/authority-services` | Sibling repo not cloned | Clone per § 1 |
| `up` hangs on "Waiting for Authority KC to import realm" | KC failed to start (usually port conflict or corrupt volume) | `docker compose -f $AUTHORITY_DIR/docker-compose.yml logs keycloak`; if port `8090` is in use, free it or edit `AUTHORITY_KC_PORT` in `glcdi.sh`; if volume is corrupt, `glcdi.sh reset` |
| Bruno `00-auth/*` returns 401 from Authority KC | Client-secret drift between realm JSON and `.glcdi.local/secrets.env` — usually from partial regeneration | `glcdi.sh reset && glcdi.sh up` (regenerates deterministically) |
| Bruno `00-auth/*` token decodes with empty claim payload | Service-account user missing role assignments or per-user attributes | Admin console: check `service-account-glcdi-connector-<org>` users have the right `glcdi_*` realm roles + attributes ([`IMPLEM_PLAN § 1.5.4`](../build/plan/phase-1.5-identity-tier1.md#154-provision-connector-service-account-clients-in-the-authority-keycloak)) |
| Negotiation hangs in REQUESTED forever | `edc.dsp.callback.address` mismatch between the two participants | Regenerated by `glcdi.sh` from `ORG_PORTS` — if hand-edited, `glcdi.sh reset && glcdi.sh up` |
| Participant UI shows "Network error" on `/management` calls | `EDC_API_KEY` drift between `.env` (consumed by UI build) and `configuration.properties` (consumed by connector) | `glcdi.sh reset && glcdi.sh up` |
| Bruno test for the participant UI's `tems-transfers-list` component fails because the component isn't rendered | Component not configured in `participant-ui/config.json` (Track F finding — deferred) | Add the component to `config.json.template` per [`IMPLEM_PLAN § 4.5.F`](../build/plan/phase-4.5-bruno-and-ui.md#45f-participant-ui-configuration-track-f---parallel-agent); rebuild and redeploy the participant UI image |

Most failure modes reduce to `glcdi.sh reset && glcdi.sh up`. That is the recovery move; do not hand-edit files under `.glcdi.local/`.

---

## 7. Iteration workflows

- **Iterating on policy functions (Phase 3).** `glcdi.sh build && glcdi.sh up && glcdi.sh test` — `up` is idempotent and recreates containers with the fresh image.
- **Iterating on Keycloak realm content.** Edit `authority-services/resources/keycloak/realms/glcdi-realm.json`, then `glcdi.sh reset && glcdi.sh up` (KC re-imports the realm only on first boot, so `reset` is required).
- **Iterating on the catalogue UI without rebuilding the image.** Set `GLCDI_USE_LOCAL_PACKAGES=true` + `GLCDI_PKG_PATH=http://localhost:5173/src/index.ts` (with `npm run watch` in the UI package). The UI hot-reloads on save.

---

## 8. When local is green, promote to staging

Local green is the gate before pushing to staging. The staging VM cutover is CI-driven — see [`vm-deployment.md`](vm-deployment.md). Do not push to staging if Bruno doesn't run green locally; catching a misnamed claim or a missing redirect URI on the laptop is cheaper than catching it in a maintenance window.

---

## Related

- [`../build/scripts/README.md`](../build/scripts/README.md) — full `glcdi.sh` subcommand reference, iteration workflows, capability-vs-gated matrix.
- [`../build/bruno/`](../build/bruno/) — Bruno HTTP-test collection.
- [`../reference/identity.md`](../reference/identity.md) — identity architecture the stack implements.
- [`../build/implementation-plan.md`](../build/implementation-plan.md) — phased plan and current status.
