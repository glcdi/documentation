# Nuclear Wipe — Staging Participants

**Audience:** ops / dev triggering a full reset on a staging GLCDI participant VM.

**What it does:** drops the EDC connector Postgres volume on a staging
participant VM, then re-seeds the M1 fixtures with current IDs via
`./management/scripts/glcdi.sh seed`. Preserves the participant
Keycloak realm and the identity-hub state by default; `--total-wipe`
extends to those too.

**Use when:** the seeded asset / policy / contract-definition names have
drifted (e.g. you renamed `regenerative-producers-policy` →
`producer-only-policy`) and surgical `glcdi.sh wipe --no-dry-run` would
leave stale agreements / transfer-process records dangling against the
new IDs.

**Use `glcdi.sh wipe` instead when:** you only need to drop assets /
policies / contract-definitions and don't care about leftover negotiation /
agreement / transfer-process rows. That path is non-destructive to volumes
and runs entirely over the mgmt API. See [§7](#7-when-not-to-use-this-script).

## 1. The orchestrator script

`management/scripts/nuclear-wipe-stagings.sh` automates the whole flow
from your laptop. SSH login defaults to `root@<slug>.glcdi.startinblox.com`.

```bash
distrobox enter dev
cd ~/Workspaces/Dataspaces/glcdi

# Always preview first — default is dry-run.
./management/scripts/nuclear-wipe-stagings.sh --target all-staging

# Commit when the dry-run looks right.
./management/scripts/nuclear-wipe-stagings.sh --target all-staging --no-dry-run
```

What it does per VM, in order:

1. SSH preflight — verifies `docker` + `docker compose` are reachable.
2. Identifies the connector pg volume by suffix (`connector-pg-data` or
   `connector_pg`) so it doesn't matter what Compose project prefix the
   VM uses.
3. `docker compose --profile prod down --remove-orphans` — stops the stack
   (volumes survive).
4. `docker volume rm <connector-pg-volume>` — drops only the connector
   data. (KC + identity-hub stay.)
5. `docker compose --profile prod up -d` — brings it back; empty
   connector means no assets / policies / CDs.
6. Polls the mgmt API on `<vm>/management/v3/assets/request` for up to
   ~3 minutes, requires HTTP 200 to proceed.
7. Verifies all three collections (`assets`, `policydefinitions`,
   `contractdefinitions`) return `count=0`.
8. Runs `./management/scripts/glcdi.sh seed --target <vm>` to re-seed
   the M1 fixtures.
9. Verifies the expected policies + contract definitions are now present.

`all-staging` fans out to the three M1 participants in order:
`caney-fork`, `point-blue`, `white-buffalo`.

### 1.1 Flags

| Flag | Effect |
|---|---|
| `--target T` | `caney-fork` \| `point-blue` \| `white-buffalo` \| `all-staging` (default `all-staging`) |
| `--no-dry-run` | actually execute (default is dry-run preview) |
| `--total-wipe` | uses `docker compose down -v` instead — drops **every** volume including participant Keycloak + identity-hub. Lose KC realm config + brokered IdP setup. |

### 1.2 SSH overrides

The script defaults to `root@<slug>.glcdi.startinblox.com` per VM. Override
via env vars (matches `glcdi.sh`'s convention from
`fetch_staging_api_key`):

| Var | Default |
|---|---|
| `SSH_USER_CANEY`     | `root` |
| `SSH_HOST_CANEY`     | `caney-fork.glcdi.startinblox.com` |
| `SSH_USER_POINTBLUE` | `root` |
| `SSH_HOST_POINTBLUE` | `point-blue.glcdi.startinblox.com` |
| `SSH_USER_WB`        | `root` |
| `SSH_HOST_WB`        | `white-buffalo.glcdi.startinblox.com` |

### 1.3 VM path override

The script assumes `~/participant-agent-services` on each VM (matches
`fetch_staging_api_key` in `glcdi.sh:919`). If your VMs use the
`/glcdi/<repo>/` layout from the workspace's CLAUDE.md, override:

```bash
VM_REPO_PATH=/glcdi/participant-agent-services \
  ./management/scripts/nuclear-wipe-stagings.sh --target all-staging
```

## 2. What the script preserves vs drops

| | default (connector-pg only) | `--total-wipe` |
|---|---|---|
| EDC assets / policies / contract definitions | dropped | dropped |
| Past contract negotiations / agreements / transfers | dropped | dropped |
| EDR token cache (in connector pg) | dropped | dropped |
| Participant Keycloak realm + users + brokered IdP | **kept** | dropped |
| Identity-hub DIDs + credentials | **kept** | dropped |
| Vault entries (signing keys) | kept (separate volume) | kept |

`--total-wipe` re-imports the participant KC realm from the JSON on
next boot (only on first boot — i.e. after a fresh volume). Don't run
it unless you've also bumped `glcdi-realm.json` or `edc-realm.json`
and actually want them re-imported.

## 3. Manual fallback (per-VM, if the script can't run)

If you can't run the script (no laptop SSH access, want to do it by hand,
etc.), here's the manual recipe per VM. Repeat for each of `caney-fork`,
`point-blue`, `white-buffalo`.

```bash
# 1) SSH in
ssh root@caney-fork.glcdi.startinblox.com

# 2) Find the connector pg volume (Compose v2 prefixes by project name)
cd ~/participant-agent-services      # or /glcdi/participant-agent-services
docker volume ls | grep -E 'connector-pg-data|connector_pg' || true
# Example matches:
#   local  glcdi-caney-fork_connector-pg-data
#   local  participant-agent-services_connector-pg-data
VOL=$(docker volume ls --format '{{.Name}}' | grep -E 'connector-pg-data|connector_pg' | head -1)
echo "Will wipe: $VOL"

# 3) Stop the stack (volumes survive)
docker compose --profile prod down --remove-orphans

# 4) Drop the connector pg volume (KC + identity-hub stay)
docker volume rm "$VOL"

# 5) Bring it back
docker compose --profile prod up -d

# 6) Watch until 'started in ...ms' (or no errors), Ctrl-C
docker compose --profile prod ps
docker compose --profile prod logs -f --tail=80 edc-connector
```

For the **`--total-wipe`** equivalent, swap step 3–4 for:

```bash
docker compose --profile prod down -v --remove-orphans
# Skip step 4 — `down -v` already dropped every named volume.
docker compose --profile prod up -d
```

## 4. Verify empty state (after a manual wipe)

Run this from your laptop. The script does it automatically.

```bash
CF_HOST=https://caney-fork.glcdi.startinblox.com
PB_HOST=https://point-blue.glcdi.startinblox.com
WB_HOST=https://white-buffalo.glcdi.startinblox.com
CF_KEY=...   # grep '^EDC_API_KEY=' ~/participant-agent-services/.env on each VM
PB_KEY=...
WB_KEY=...

empty_check() {
  local host="$1" key="$2"
  for ep in assets policydefinitions contractdefinitions; do
    printf '  %-22s ' "$ep"
    curl -sk -X POST --max-time 15 \
      -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
      -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
      "$host/management/v3/${ep}/request" \
      | jq 'length'
  done
}

echo "=== caney-fork ===";    empty_check "$CF_HOST" "$CF_KEY"
echo "=== point-blue ===";    empty_check "$PB_HOST" "$PB_KEY"
echo "=== white-buffalo ==="; empty_check "$WB_HOST" "$WB_KEY"
# Every line must read 0.
```

## 5. Reseed (after a manual wipe)

From the dev distrobox:

```bash
distrobox enter dev
cd ~/Workspaces/Dataspaces/glcdi

./management/scripts/glcdi.sh seed --target all-staging
# Or per-VM:
./management/scripts/glcdi.sh seed --target caney-fork
./management/scripts/glcdi.sh seed --target point-blue
./management/scripts/glcdi.sh seed --target white-buffalo
```

## 6. Verify the new IDs landed (after a manual reseed)

```bash
verify_org() {
  local org="$1" host="$2" key="$3"
  echo "=== ${org} policies ==="
  curl -sk -X POST --max-time 15 \
    -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
    -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
    "$host/management/v3/policydefinitions/request" \
    | jq -r '.[]["@id"]' | sed 's/^/  /'
  echo "=== ${org} contract definitions ==="
  curl -sk -X POST --max-time 15 \
    -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
    -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
    "$host/management/v3/contractdefinitions/request" \
    | jq -r '.[] | "  \(.["@id"]) -> \(.accessPolicyId)"'
}

verify_org caney-fork    "$CF_HOST" "$CF_KEY"
verify_org point-blue    "$PB_HOST" "$PB_KEY"
verify_org white-buffalo "$WB_HOST" "$WB_KEY"
```

Expected per VM:

- **4 policies:** `producer-only-policy`, `members-policy`,
  `researcher-only-policy`, `internal-use-only-policy`.
- **3 contract definitions:**
  - `<org>-grazing-soc-2024-cd` → `producer-only-policy`
  - `<org>-grazing-summary-2024-cd` → `members-policy`
  - `<org>-grazing-raw-observations-2024-cd` → `researcher-only-policy`

The script does this automatically and fails loudly if anything is missing,
listing what it actually found.

## 7. When not to use this script

| Goal | Use instead |
|---|---|
| "I just want to drop stale assets/policies/CDs" | `./management/scripts/glcdi.sh wipe --target T --no-dry-run` — pure mgmt-API, no SSH, no volumes touched. |
| "I want a clean Keycloak too" | `--total-wipe`. Only do this if you've actually changed the realm JSON; otherwise you'll have to manually re-apply admin-console-only changes. |
| "Local development reset" | `./management/scripts/glcdi.sh reset` — wipes the local stack only, not staging. |

## 8. Known traps

- **`docker volume rm` fails "volume in use".** A container didn't fully
  stop. Re-run `docker compose --profile prod down --remove-orphans` and
  retry. If a container is stuck in `Removing`, `docker rm -f` it by name.
- **VM repo path.** The script assumes `~/participant-agent-services`
  (matching `glcdi.sh:919`). If your VM has the repo under
  `/glcdi/participant-agent-services` instead, set
  `VM_REPO_PATH=/glcdi/participant-agent-services` — see [§1.3](#13-vm-path-override).
- **`--total-wipe` against `governance-services`**. The script targets
  participant VMs only — it derives hosts from
  `<slug>.glcdi.startinblox.com`. There is no governance target. Don't
  manually adapt and aim it at `governance.glcdi.startinblox.com`; the
  governance KC realm + onboarding DB are not what you want gone.
- **Realm JSON re-import**. `--total-wipe` triggers it via fresh KC pg.
  If `glcdi-realm.json` / `edc-realm.json` have post-init changes you
  made via admin console, those are lost. See `glcdi/CLAUDE.md` →
  "Things that will bite you".
- **Don't `source` the VM `.env`** when working manually on a VM —
  Compose `.env` allows unquoted spaces (`APP_TITLE=Caney Fork - GLCDI`)
  and `source` chokes on the dash. Use `grep '^VAR=' .env | cut -d= -f2-`
  or an `IFS='=' read` loop. See
  [memory: `feedback_dont_source_compose_env`].

## 9. References

- `management/scripts/nuclear-wipe-stagings.sh` — orchestrator
- `management/scripts/glcdi.sh` — `cmd_seed`, `cmd_wipe`,
  `fetch_staging_api_key`, `expand_target`
- `glcdi/CLAUDE.md` — VM layout, Keycloak realm import semantics
- `participant-agent-services/.env.example` — Compose env vars
- `MEMORY.md` → `reference_glcdi_edc_transfer_diag` —
  diagnose post-reseed transfer failures
