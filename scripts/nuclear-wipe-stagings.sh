#!/usr/bin/env bash
# nuclear-wipe-stagings.sh
#
# Drops the connector Postgres volume on one or more staging participant
# VMs (assets / policies / contract definitions / agreements / transfers
# all gone), then re-seeds the M1 fixtures with current IDs via
# ./glcdi.sh seed.
#
# Run from a laptop with SSH access to the VMs. SSH login defaults to
# root@<slug>.glcdi.startinblox.com per VM.
#
# By default this script DRY-RUNS — it prints every destructive command
# without executing. Pass --no-dry-run to actually do it.
#
# Usage:
#   ./nuclear-wipe-stagings.sh [--target T] [--no-dry-run] [--total-wipe]
#
#   --target T      one of caney-fork | point-blue | white-buffalo | demo | all-staging
#                   (default: all-staging)
#   --no-dry-run    actually execute the wipe + reseed (default: dry-run)
#   --total-wipe    use `docker compose down -v` instead of dropping only
#                   the connector pg volume. Drops ALL volumes for the
#                   participant stack — INCLUDING participant Keycloak
#                   (you lose realm config + brokered IdP setup) and the
#                   identity hub state. Default action preserves both.
#   -h | --help     show this help
#
# SSH overrides (matches glcdi.sh's fetch_staging_api_key convention):
#   SSH_USER_CANEY      / SSH_HOST_CANEY
#   SSH_USER_POINTBLUE  / SSH_HOST_POINTBLUE
#   SSH_USER_WB         / SSH_HOST_WB
#
# Path on each VM defaults to ~/participant-agent-services (matches
# glcdi.sh:919). Override with VM_REPO_PATH=/glcdi/participant-agent-services.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLCDI_SH="$SCRIPT_DIR/glcdi.sh"
VM_REPO_PATH="${VM_REPO_PATH:-~/participant-agent-services}"

declare -A SSH_USER_VAR=(
  [caney-fork]=SSH_USER_CANEY
  [point-blue]=SSH_USER_POINTBLUE
  [white-buffalo]=SSH_USER_WB
  [demo]=SSH_USER_DEMO
)
declare -A SSH_HOST_VAR=(
  [caney-fork]=SSH_HOST_CANEY
  [point-blue]=SSH_HOST_POINTBLUE
  [white-buffalo]=SSH_HOST_WB
  [demo]=SSH_HOST_DEMO
)

# Expected post-seed state per org (kebab-case ids minted by glcdi.sh seed).
# M1 trio (caney-fork / point-blue / white-buffalo): 4 policies + 3 CDs from
# bruno/10-provider-seeding/. Caney-fork additionally gets the farmos-animals
# CD from bruno/13-provider-seeding-caney-fork-farmos/ when GLCDI_FARMOS=1.
# Demo: 1 access policy (anonymous) + 6 contract policies (baseline + 5 atomic
# obligations) + 4 contributor-specific CDs from bruno/12-provider-seeding-demo/.
expected_policies_for() {
  case "$1" in
    caney-fork|point-blue|white-buffalo)
      printf '%s\n' \
        producer-only-policy \
        members-policy \
        researcher-only-policy \
        internal-use-only-policy
      ;;
    demo)
      printf '%s\n' \
        public-policy \
        members-policy \
        internal-use-only-policy
      ;;
    *) die "expected_policies_for: unknown org $1" ;;
  esac
}
expected_cds_for() {
  case "$1" in
    caney-fork)
      printf '%s\n' \
        "caney-fork-grazing-soc-2024-cd" \
        "caney-fork-grazing-summary-2024-cd" \
        "caney-fork-grazing-raw-observations-2024-cd"
      # farmOS-backed asset CD lands only when caney-fork is being seeded
      # via `GLCDI_FARMOS=1 glcdi.sh seed`; expecting it otherwise would
      # red-flag an entirely-correct seed run.
      if [[ "${GLCDI_FARMOS:-0}" == "1" ]]; then
        printf '%s\n' "caney-fork-farmos-animals-cd"
      fi
      ;;
    point-blue|white-buffalo)
      printf '%s\n' \
        "${1}-grazing-soc-2024-cd" \
        "${1}-grazing-summary-2024-cd" \
        "${1}-grazing-raw-observations-2024-cd"
      ;;
    demo)
      printf '%s\n' \
        stone-barns-soil-health-cd \
        sonoma-mountain-pasture-map-cd \
        florida-grazing-soc-cd \
        pasa-soil-health-cd
      ;;
    *) die "expected_cds_for: unknown org $1" ;;
  esac
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RED='\033[31m'; C_GREEN='\033[32m'
  C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_RESET='\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

log()  { printf '%b==>%b %s\n' "$C_BLUE"  "$C_RESET" "$*"; }
ok()   { printf '%b✓%b %s\n'   "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b⚠%b %s\n'   "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%b✗%b %s\n'   "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%b%s%b\n' "$C_DIM" "----------------------------------------------------------------" "$C_RESET"; }

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------

TARGET=all-staging
DRY_RUN=true
TOTAL_WIPE=false

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)      TARGET="${2:-}"; shift 2 || die "--target needs a value" ;;
    --target=*)    TARGET="${1#--target=}"; shift ;;
    --no-dry-run)  DRY_RUN=false; shift ;;
    --total-wipe)  TOTAL_WIPE=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown argument: $1 — see --help" ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

expand_target() {
  case "$1" in
    caney-fork|point-blue|white-buffalo|demo) printf '%s\n' "$1" ;;
    all-staging) printf 'caney-fork\npoint-blue\nwhite-buffalo\ndemo\n' ;;
    *) die "Unknown --target: $1 (expected caney-fork|point-blue|white-buffalo|demo|all-staging)" ;;
  esac
}

ssh_user_for() {
  local v="${SSH_USER_VAR[$1]:-}"
  [[ -n "$v" ]] || die "no SSH_USER var mapping for $1"
  printf '%s' "${!v:-root}"
}
ssh_host_for() {
  local v="${SSH_HOST_VAR[$1]:-}"
  [[ -n "$v" ]] || die "no SSH_HOST var mapping for $1"
  printf '%s' "${!v:-${1}.glcdi.startinblox.com}"
}
host_url_for() { printf 'https://%s.glcdi.startinblox.com' "$1"; }

# Run a shell command on a target VM. Quoted as one string to ssh — caller
# is responsible for shell-escaping the inner command if it contains
# subshells, pipes, etc.
ssh_run() {
  local target="$1"; shift
  local cmd="$*"
  local user host
  user="$(ssh_user_for "$target")"
  host="$(ssh_host_for "$target")"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" "$cmd"
}

# Dry-run-aware SSH: prints the command in dry-run mode, otherwise runs it.
ssh_do() {
  local target="$1"; shift
  local cmd="$*"
  local user host
  user="$(ssh_user_for "$target")"
  host="$(ssh_host_for "$target")"
  if $DRY_RUN; then
    printf '  %b[dry-run]%b ssh %s@%s %q\n' "$C_DIM" "$C_RESET" "$user" "$host" "$cmd"
    return 0
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" "$cmd"
}

preflight_ssh() {
  local target="$1"
  local user host
  user="$(ssh_user_for "$target")"
  host="$(ssh_host_for "$target")"
  log "[$target] SSH preflight to ${user}@${host}"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" \
      'docker version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo ok' \
      >/dev/null 2>&1 \
    || die "[$target] SSH preflight failed — cannot reach ${user}@${host} or docker/docker-compose missing"
  ok "[$target] SSH + docker reachable"
}

fetch_api_key() {
  local target="$1"
  local user host
  user="$(ssh_user_for "$target")"
  host="$(ssh_host_for "$target")"
  local key
  key=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" \
          "grep '^EDC_API_KEY=' ${VM_REPO_PATH}/.env | cut -d= -f2-" \
        2>/dev/null) \
    || die "[$target] could not fetch EDC_API_KEY from ${VM_REPO_PATH}/.env on ${user}@${host}"
  key="${key//$'\r'/}"
  key="${key%$'\n'}"
  [[ -n "$key" ]] || die "[$target] empty EDC_API_KEY (path may be wrong — try VM_REPO_PATH=/glcdi/participant-agent-services)"
  printf '%s' "$key"
}

# Identify the connector pg volume name on the VM. Compose v2 prefixes
# the project name, which can differ — match by suffix. Empty on absent
# (idempotent re-runs after a prior wipe that already removed it).
identify_connector_volume() {
  local target="$1"
  local vol
  vol=$(ssh_run "$target" "docker volume ls --format '{{.Name}}' | grep -E 'connector-pg-data|connector_pg' | head -1" 2>/dev/null) \
    || die "[$target] failed to query docker volumes"
  vol="${vol//$'\r'/}"
  vol="${vol%$'\n'}"
  printf '%s' "$vol"
}

# Wait for the management API to return 200 on /assets/request. Used after
# bringing the stack back up.
wait_for_mgmt_api() {
  local target="$1" key="$2"
  local host status i
  host="$(host_url_for "$target")"
  log "[$target] waiting for mgmt API at $host/management/v3/assets/request"
  for i in $(seq 1 90); do
    status=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 \
                  -X POST "$host/management/v3/assets/request" \
                  -H 'Content-Type: application/json' \
                  -H "X-Api-Key: $key" \
                  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":1}' \
              || echo "000")
    if [[ "$status" == "200" ]]; then
      ok "[$target] mgmt API ready after $((i*2))s"
      return 0
    fi
    if (( i % 5 == 0 )); then
      printf '  ... waiting (%ds, last=%s)\n' "$((i*2))" "$status"
    fi
    sleep 2
  done
  die "[$target] mgmt API never returned 200 (last=$status) — connector did not come back up cleanly"
}

# Count items in each mgmt-api collection. Echoes 'assets=N policies=N cds=N'.
count_mgmt_state() {
  local target="$1" key="$2"
  local host count_assets count_policies count_cds
  host="$(host_url_for "$target")"
  for triple in "assets:assets" "policydefinitions:policies" "contractdefinitions:cds"; do
    local ep="${triple%:*}"
    local body
    body=$(curl -sk -X POST --max-time 15 \
              -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
              -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
              "$host/management/v3/${ep}/request") \
      || die "[$target] failed to list $ep"
    printf '%s\n' "$body" | jq -e 'type == "array"' >/dev/null \
      || die "[$target] unexpected mgmt API response for $ep: $body"
    case "$ep" in
      assets) count_assets=$(printf '%s' "$body" | jq 'length') ;;
      policydefinitions) count_policies=$(printf '%s' "$body" | jq 'length') ;;
      contractdefinitions) count_cds=$(printf '%s' "$body" | jq 'length') ;;
    esac
  done
  printf 'assets=%s policies=%s cds=%s' "$count_assets" "$count_policies" "$count_cds"
}

verify_empty() {
  local target="$1" key="$2"
  log "[$target] verifying mgmt API is empty"
  local state
  state="$(count_mgmt_state "$target" "$key")"
  log "[$target] state: $state"
  if [[ "$state" != "assets=0 policies=0 cds=0" ]]; then
    die "[$target] wipe incomplete — expected all zero, got: $state"
  fi
  ok "[$target] all collections empty"
}

verify_seeded() {
  local target="$1" key="$2"
  local host
  host="$(host_url_for "$target")"
  log "[$target] verifying seeded state"

  local policies cds
  policies=$(curl -sk -X POST --max-time 15 \
             -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
             -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
             "$host/management/v3/policydefinitions/request" \
             | jq -r '.[]["@id"]')
  cds=$(curl -sk -X POST --max-time 15 \
        -H 'Content-Type: application/json' -H "X-Api-Key: $key" \
        -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":200}' \
        "$host/management/v3/contractdefinitions/request" \
        | jq -r '.[]["@id"]')

  local missing=()
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if grep -qx "$p" <<<"$policies"; then
      ok "[$target] policy: $p"
    else
      err "[$target] missing policy: $p"
      missing+=("policy:$p")
    fi
  done < <(expected_policies_for "$target")
  local cd
  while IFS= read -r cd; do
    [[ -z "$cd" ]] && continue
    if grep -qx "$cd" <<<"$cds"; then
      ok "[$target] CD: $cd"
    else
      err "[$target] missing CD: $cd"
      missing+=("cd:$cd")
    fi
  done < <(expected_cds_for "$target")

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "[$target] actual policies:"
    printf '    %s\n' $policies >&2
    err "[$target] actual CDs:"
    printf '    %s\n' $cds >&2
    die "[$target] verification failed — missing: ${missing[*]}"
  fi
  ok "[$target] seed verification passed"
}

# -----------------------------------------------------------------------------
# Wipe + reseed per target
# -----------------------------------------------------------------------------

wipe_target() {
  local target="$1"
  hr
  log "[$target] starting wipe"

  preflight_ssh "$target"

  # caney-fork stacks the farmos override so the recreated nginx-prod
  # keeps the farmos.<domain> vhost template mount; other targets stay
  # on the base compose only.
  local compose_args="--profile prod"
  if [[ "$target" == "caney-fork" ]]; then
    compose_args="-f docker-compose.yml -f docker-compose.farmos.yml --profile prod --profile farmos"
  fi

  local vol
  if $DRY_RUN; then
    log "[$target] [dry-run] would identify connector pg volume:"
    log "    ssh ... 'docker volume ls --format \"{{.Name}}\" | grep connector-pg-data | head -1'"
    vol="<connector-pg-volume>"
  else
    vol="$(identify_connector_volume "$target")"
    if [[ -n "$vol" ]]; then
      log "[$target] connector pg volume: $vol"
    else
      log "[$target] connector pg volume already absent — skipping volume rm"
    fi
  fi

  if $TOTAL_WIPE; then
    warn "[$target] --total-wipe: will drop ALL volumes (KC + identity-hub + connector)"
    ssh_do "$target" "cd ${VM_REPO_PATH} && docker compose ${compose_args} down -v --remove-orphans"
  else
    ssh_do "$target" "cd ${VM_REPO_PATH} && docker compose ${compose_args} down --remove-orphans"
    if $DRY_RUN; then
      log "[$target] [dry-run] would: ssh ... docker volume rm <connector-pg-volume>"
    elif [[ -n "$vol" ]]; then
      log "[$target] removing connector pg volume: $vol"
      ssh_run "$target" "docker volume rm '$vol'" \
        || die "[$target] docker volume rm failed — likely still in use; investigate before retrying"
    fi
  fi

  ssh_do "$target" "cd ${VM_REPO_PATH} && docker compose ${compose_args} up -d"

  if $DRY_RUN; then
    log "[$target] [dry-run] would wait for mgmt API + verify empty + reseed + verify seeded"
    return 0
  fi

  log "[$target] fetching EDC_API_KEY"
  local key
  key="$(fetch_api_key "$target")"

  wait_for_mgmt_api "$target" "$key"
  verify_empty "$target" "$key"

  log "[$target] reseeding via glcdi.sh seed --target $target"
  "$GLCDI_SH" seed --target "$target" \
    || die "[$target] glcdi.sh seed failed"

  verify_seeded "$target" "$key"
  ok "[$target] DONE"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

preflight_local() {
  for tool in ssh curl jq; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
  done
  [[ -x "$GLCDI_SH" ]] || die "glcdi.sh not executable at $GLCDI_SH"
}

main() {
  preflight_local

  local targets
  mapfile -t targets < <(expand_target "$TARGET")

  hr
  log "Targets:     ${targets[*]}"
  log "VM repo path: $VM_REPO_PATH"
  if $TOTAL_WIPE; then
    warn "Mode: TOTAL WIPE (down -v) — will drop KC + identity-hub volumes too"
  else
    log "Mode:        connector-pg only (KC + identity-hub preserved)"
  fi
  if $DRY_RUN; then
    warn "DRY-RUN — no destructive action will execute. Add --no-dry-run to commit."
  else
    warn "LIVE RUN — about to wipe ${#targets[@]} VM(s). Ctrl-C within 5s to abort."
    local i
    for i in 5 4 3 2 1; do
      printf '  %d...\n' "$i"
      sleep 1
    done
  fi

  local t
  for t in "${targets[@]}"; do
    wipe_target "$t"
  done

  hr
  ok "All targets processed: ${targets[*]}"
  if $DRY_RUN; then
    warn "Was dry-run. Re-run with --no-dry-run to actually wipe + reseed."
  fi
}

main "$@"
