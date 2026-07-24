#!/usr/bin/env bash
#
# glcdi.sh - local-stack orchestrator for the GLCDI workspace.
#
# Brings up the Authority Keycloak + 3 participant connectors (caney-fork,
# point-blue, white-buffalo) in the right order with the right config, seeds
# the M1 fixtures, and runs the Bruno collection. Idempotent: re-running
# `up` is safe; `reset` is the destructive nuclear option.
#
# Run from anywhere - paths are resolved relative to the workspace root
# (the directory holding governance-services/, participant-agent-services/,
# edc-connector/, edc-glcdi-extension/, participant-ui/, management/).
#
# Subcommands:
#   preflight                       - verify required tools are installed
#   secrets                         - generate (once) and print local secrets
#   build                           - build edc-connector + participant-ui images
#   up                              - bring up authority + 3 participants
#   seed [--target T]               - seed M1 fixtures via Bruno (default T=local)
#   seed-ldp                        - Phase-2: seed Farm/Plot/Metric in each
#                                     participant's djangoldp-backend (local
#                                     only). Must run BEFORE `seed`, because
#                                     it writes the Farm urlid that `seed`
#                                     bakes into the M1 asset's baseUrl.
#   wipe [--target T] [--no-dry-run] - delete contract-defs + policies + assets
#                                     (dry-run by default; --no-dry-run actually deletes)
#   test [tier]                     - run the Bruno collection (tier1 default; tier2 anticipated)
#   status                          - quick health check on every service
#   logs <svc>                      - tail logs for a service (svc = authority|onboarding|caney-fork|point-blue|white-buffalo)
#   down                            - bring down stacks (preserves volumes)
#   reset                           - bring down + remove volumes + delete .glcdi.local/
#   all                             - preflight + build + up + seed + test (the happy path)
#   bruno-cmd                       - print the `bru run` command line (with secrets baked in)
#   farmos-install                  - one-shot composer+drush install inside caney-fork's
#                                     farmos container (requires GLCDI_FARMOS=1)
#   test-farmos [--target T]        - end-to-end OAuth2 transfer test: drives point-blue
#                                     through catalog → negotiate → transfer → EDR fetch
#                                     against caney-fork's farmOS asset. Proves that
#                                     glcdi-dataplane-oauth2-inline performs the token
#                                     exchange at transfer-time.
#   help                            - show this list
#
# --target values: local | caney-fork | point-blue | white-buffalo | all-staging
#   For staging targets, EDC_API_KEY is fetched at runtime via SSH against the
#   participant VM. Defaults: root@<target>.glcdi.startinblox.com. Override
#   per-target via env vars when needed:
#     caney-fork    → SSH_USER_CANEY     / SSH_HOST_CANEY
#     point-blue    → SSH_USER_POINTBLUE / SSH_HOST_POINTBLUE
#     white-buffalo → SSH_USER_WB        / SSH_HOST_WB
#
# Config:
#   GLCDI_TIER   (default tier1) - switches Bruno test mode.
#   GLCDI_FARMOS (default 0)     - when =1, caney-fork additionally brings up
#                                  the optional farmOS site (port 8091).
#                                  Run `glcdi.sh farmos-install` once after the
#                                  first `up` to seed the Drupal site.
# Working dir: ./.glcdi.local/ (gitignored) holds rotated secrets + per-org configs.

set -euo pipefail

# -----------------------------------------------------------------------------
# Resolve paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The script lives in management/build/scripts/. The workspace root is three levels up.
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOCAL_DIR="$SCRIPT_DIR/.glcdi.local"
SECRETS_FILE="$LOCAL_DIR/secrets.env"

# The governance-services dir is renamed to authority-services in the in-flight
# ops/authority-migration.md cutover. Support both - the local script picks whichever
# exists.
if [[ -d "$WORKSPACE_ROOT/authority-services" ]]; then
  AUTHORITY_DIR="$WORKSPACE_ROOT/authority-services"
elif [[ -d "$WORKSPACE_ROOT/governance-services" ]]; then
  AUTHORITY_DIR="$WORKSPACE_ROOT/governance-services"
else
  AUTHORITY_DIR=""
fi

PARTICIPANT_DIR="$WORKSPACE_ROOT/participant-agent-services"
EDC_CONNECTOR_DIR="$WORKSPACE_ROOT/edc-connector"
EDC_EXTENSION_DIR="$WORKSPACE_ROOT/edc-glcdi-extension"
PARTICIPANT_UI_DIR="$WORKSPACE_ROOT/participant-ui"
BRUNO_DIR="$WORKSPACE_ROOT/management/build/bruno"

# Participants. M1 trio runs locally + staging; demo is staging-only
# (a workshop showcase VM colocating Stone Barns / Sonoma / UFL / Pasa
# fixtures - see ops/demo-vm.md).
ORGS=(caney-fork point-blue white-buffalo demo)
LOCAL_ORGS=(caney-fork point-blue white-buffalo)
declare -A ORG_PORTS=(
  [caney-fork]=8080
  [point-blue]=8081
  [white-buffalo]=8082
  [demo]=8083
)
declare -A ORG_COLORS=(
  [caney-fork]="#2E7D32"
  [point-blue]="#1565C0"
  [white-buffalo]="#C0392B"
  [demo]="#7B1FA2"
)
# Secondary/accent shades - mirror configurations/<org>.env so local dev matches staging.
declare -A ORG_SECONDARY_COLORS=(
  [caney-fork]="#1B5E20"
  [point-blue]="#0D47A1"
  [white-buffalo]="#8E2A1F"
  [demo]="#4A148C"
)
declare -A ORG_ACCENT_COLORS=(
  [caney-fork]="#66BB6A"
  [point-blue]="#42A5F5"
  [white-buffalo]="#E67E22"
  [demo]="#BA68C8"
)
declare -A ORG_TYPES=(
  [caney-fork]=regenerative-producer
  [point-blue]=researcher
  [white-buffalo]=regenerative-producer
  [demo]=other
)

# Each participant exposes one djangoldp-glcdi subpackage under its /ldp/
# prefix. Caney-fork is the generic baseline; the other two carry their
# own domain models (BiomassPlot / FieldLevel for Point Blue, CattleRotation
# for White Buffalo). Demo reuses the baseline (its M1 assets are static
# JSON stubs, no LDP). Used by write_participant_configs + seed_ldp_one.
declare -A ORG_LDP_PACKAGES=(
  [caney-fork]=djangoldp_glcdi
  [point-blue]=djangoldp_glcdi_pointblue
  [white-buffalo]=djangoldp_glcdi_whitebuffalo
  [demo]=djangoldp_glcdi
)

AUTHORITY_KC_PORT=8090
AUTHORITY_ONBOARDING_PORT=8083
TIER="${GLCDI_TIER:-tier1}"
FARMOS_ENABLED="${GLCDI_FARMOS:-0}"

# Returns extra `docker compose` args (a flat space-separated string -
# eval-safe and array-friendly) for the org's farmOS profile, when
# applicable. Empty for non-caney-fork orgs or when GLCDI_FARMOS isn't 1.
# Locally we don't stack docker-compose.farmos.yml - that override only
# matters for nginx-prod, which the dev profile doesn't use.
farmos_profile_args() {
  local org="$1"
  if [[ "$FARMOS_ENABLED" == "1" && "$org" == "caney-fork" ]]; then
    printf -- '--profile farmos'
  fi
}

# Build the glcdi.dataplane.host.rewrite map for $org. Adds farmOS-specific
# host:port→host:port entries (localhost:8091→farmos:80) on caney-fork so the
# connector reaches farmOS via docker DNS instead of the unreachable host
# loopback. Other orgs get the bare hostname swap (no current callers, but
# kept as a no-op default so future backends behind localhost can be added
# without breaking existing assets).
host_rewrite_for() {
  local org="$1" port="${FARMOS_PORT:-8091}"
  if [[ "$FARMOS_ENABLED" == "1" && "$org" == "caney-fork" ]]; then
    printf 'localhost:%s=farmos:80,127.0.0.1:%s=farmos:80,localhost=host.docker.internal,127.0.0.1=host.docker.internal' "$port" "$port"
  else
    printf 'localhost=host.docker.internal,127.0.0.1=host.docker.internal'
  fi
}

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RED='\033[31m'; C_GREEN='\033[32m'
  C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_RESET='\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

log()  { printf '%b==>%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%b✓%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%b✗%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%b%s%b\n' "$C_DIM" "----------------------------------------------------------------" "$C_RESET"; }

# -----------------------------------------------------------------------------
# Preflight: verify tooling
# -----------------------------------------------------------------------------

cmd_preflight() {
  log "Preflight checks"
  local missing=()
  for tool in docker openssl curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ! docker compose version >/dev/null 2>&1; then
    missing+=("docker-compose-v2")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}. Install them and re-run."
  fi

  if ! docker info >/dev/null 2>&1; then
    die "Docker daemon is not running or current user lacks access."
  fi

  # Bruno CLI is optional - only needed for `test`.
  if command -v bru >/dev/null 2>&1; then
    ok "bru (Bruno CLI) found - $(bru --version 2>/dev/null | head -1 || echo 'unknown version')"
  else
    warn "bru (Bruno CLI) not installed - \`test\` subcommand will be unavailable. Install with: npm install -g @usebruno/cli"
  fi

  if [[ -z "$AUTHORITY_DIR" ]]; then
    die "Neither $WORKSPACE_ROOT/authority-services nor governance-services exists. Are you in the right workspace?"
  fi

  for d in "$PARTICIPANT_DIR" "$EDC_CONNECTOR_DIR" "$EDC_EXTENSION_DIR" "$PARTICIPANT_UI_DIR" "$BRUNO_DIR"; do
    if [[ ! -d "$d" ]]; then
      die "Expected directory missing: $d"
    fi
  done

  # Port availability - warn only (some users intentionally remap).
  for port in "$AUTHORITY_KC_PORT" "${ORG_PORTS[@]}"; do
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"; then
      warn "Port $port appears already in use - local stack will fail to bind."
    fi
  done

  ok "Preflight OK"
  log "Workspace root: $WORKSPACE_ROOT"
  log "Authority dir:  $AUTHORITY_DIR"
  log "Local dir:      $LOCAL_DIR"
  log "Tier:           $TIER"
}

# -----------------------------------------------------------------------------
# Secrets - generate once, reuse on subsequent runs
# -----------------------------------------------------------------------------

cmd_secrets() {
  mkdir -p "$LOCAL_DIR"

  if [[ -f "$SECRETS_FILE" ]]; then
    log "Reusing existing secrets at $SECRETS_FILE"
  else
    log "Generating local secrets at $SECRETS_FILE"
    {
      echo "# GLCDI local-stack secrets - generated $(date -Iseconds)"
      echo "# Regenerate with: rm $SECRETS_FILE && $0 secrets"
      echo
      echo "KC_ADMIN_PASSWORD=$(openssl rand -hex 16)"
      echo "KC_DB_PASSWORD=$(openssl rand -hex 16)"
      echo "DJANGO_SECRET_KEY=$(openssl rand -hex 32)"
      echo "GOVERNANCE_CLIENT_SECRET=$(openssl rand -hex 32)"
      echo "GLCDI_UI_CLIENT_SECRET=$(openssl rand -hex 32)"
      echo
      for org in "${LOCAL_ORGS[@]}"; do
        local upper
        upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
        echo "${upper}_API_KEY=$(openssl rand -hex 32)"
        echo "${upper}_CONNECTOR_SECRET=$(openssl rand -hex 32)"
        echo "${upper}_DB_PASSWORD=$(openssl rand -hex 16)"
      done
      echo
      # farmOS M2M consumer creds - provisioned by install.sh, read by bruno_env_flags + test-farmos-transfer.sh.
      echo "FARMOS_ANIMAL_CLIENT_ID=farm_m2m_$(openssl rand -hex 8)"
      echo "FARMOS_ANIMAL_CLIENT_SECRET=$(openssl rand -hex 32)"
    } > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
    ok "Generated $SECRETS_FILE (mode 600)"
  fi

  # Source for use by callers; export so child processes can see them.
  set -a
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
  set +a
}

cmd_secrets_show() {
  cmd_secrets
  hr
  cat "$SECRETS_FILE"
  hr
}

# -----------------------------------------------------------------------------
# Realm JSON patching - replace `changeme-*` secrets with rotated values
# -----------------------------------------------------------------------------

# Generates .glcdi.local/glcdi-realm.json with the live secrets, then
# bind-mounts it over the in-repo realm JSON when bringing Authority KC up.
patch_realm_json() {
  cmd_secrets
  local source_realm
  source_realm="$AUTHORITY_DIR/resources/keycloak/realms/glcdi-realm.json"
  if [[ ! -f "$source_realm" ]]; then
    die "Realm JSON not found at $source_realm"
  fi

  local target="$LOCAL_DIR/glcdi-realm.json"
  log "Patching realm JSON → $target"

  jq --arg cf "$CANEY_FORK_CONNECTOR_SECRET" \
     --arg pb "$POINT_BLUE_CONNECTOR_SECRET" \
     --arg wb "$WHITE_BUFFALO_CONNECTOR_SECRET" \
     --arg ui "$GLCDI_UI_CLIENT_SECRET" \
     --arg gov "$GOVERNANCE_CLIENT_SECRET" \
     '
     .clients |= map(
       if .clientId == "glcdi-connector-caney-fork" then .secret = $cf
       elif .clientId == "glcdi-connector-point-blue" then .secret = $pb
       elif .clientId == "glcdi-connector-white-buffalo" then .secret = $wb
       elif .clientId == "glcdi-ui" and (.publicClient // false) == false then .secret = $ui
       elif .clientId == "governance" then .secret = $gov
       else . end
     )
     ' "$source_realm" > "$target"
  ok "Realm JSON patched (incl. governance client secret)"
}

# -----------------------------------------------------------------------------
# Authority Keycloak - bring up
# -----------------------------------------------------------------------------

up_authority() {
  log "Bringing up Authority Keycloak"
  cmd_secrets
  patch_realm_json

  # init-secrets.sh skips files that already exist - so on re-runs the
  # populated files would keep their first-run substituted values while
  # secrets.env carries the rotated current values. We bypass it entirely
  # and re-copy from the .template files ourselves on every up.
  substitute_authority_secrets

  # Stage a per-run .env with our rotated values. KC_GOVERNANCE_CLIENT_SECRET
  # is the single source of truth - the realm JSON patcher above already
  # substituted it into the bind-mounted realm, and the onboarding-backend
  # reads it as KEYCLOAK_CLIENT_SECRET via the compose env block. The compose
  # file also `:?`-requires it, so leaving it unset would fail fast.
  #
  # We write to BOTH the script-private location (passed via --env-file in
  # the up/down/reset paths) AND $AUTHORITY_DIR/.env (compose's auto-loaded
  # default). The second copy means bare `docker compose ...` invocations
  # from the governance-services dir also pick up the secret - no more
  # cryptic ":? must be set" parse errors when you're poking at the stack
  # by hand.
  # Dev URLs follow the symmetric "each service on its own host port" model:
  # KC on AUTHORITY_KC_PORT (8090), onboarding on AUTHORITY_ONBOARDING_PORT
  # (8083). BASE_URL points at the onboarding host port so approve/deny links
  # in admin mail land on the django backend directly without nginx in the
  # mix. Prod uses nginx-prod with a single hostname (path-based routing).
  local authority_env="$LOCAL_DIR/authority.env"
  cat > "$authority_env" <<EOF
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
DEBUG=true
BASE_URL=http://localhost:${AUTHORITY_ONBOARDING_PORT}
DEFAULT_FROM_EMAIL=noreply@glcdi.local
GLCDI_ADMIN_MAILS=["admin@glcdi.local"]
KEYCLOAK_BASE_URL=http://keycloak:8080
KEYCLOAK_REALM=glcdi
KEYCLOAK_CLIENT_ID=governance
KC_GOVERNANCE_CLIENT_SECRET=${GOVERNANCE_CLIENT_SECRET}
# Public-facing KC URL embedded in approval mails. Internal KEYCLOAK_BASE_URL
# would yield "http://keycloak:8080/auth/..." which 404s in a browser.
KEYCLOAK_LOGIN_URL=http://localhost:${AUTHORITY_KC_PORT}/auth/realms/glcdi/account/
KC_START_MODE=start-dev
KC_HOSTNAME=http://localhost:${AUTHORITY_KC_PORT}/auth
KC_BACKCHANNEL_DYNAMIC=false
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD}
EOF
  cp "$authority_env" "$AUTHORITY_DIR/.env"
  chmod 600 "$AUTHORITY_DIR/.env"

  # Override file: bind-mounts the patched realm JSON over the in-repo one,
  # remaps the KC port, and pins the admin password from .env.
  #
  # `ports: !override` REPLACES the in-repo `ports` list instead of merging
  # with it. Without this, the in-repo `8080:8080` mapping stays AND our
  # `8090:8080` is appended - KC ends up on both ports and we hog the
  # caney-fork nginx port.
  # The override bind-mounts our pre-patched realm over the template that
  # gets fed to resources/keycloak/entrypoint.sh. The entrypoint will run
  # its sed pass on it, but jq already substituted ${KC_GOVERNANCE_CLIENT_SECRET}
  # with the live value - so the sed is a no-op. This keeps dev and prod on
  # the same code path.
  # Override yaml: remaps KC to AUTHORITY_KC_PORT, publishes onboarding on
  # AUTHORITY_ONBOARDING_PORT, bind-mounts the patched realm. Neither port
  # mapping leaks into prod - prod runs the base compose only (with
  # --profile prod for nginx-prod + certbot).
  local override="$LOCAL_DIR/authority.override.yml"
  cat > "$override" <<EOF
# Auto-generated by glcdi.sh - do not edit by hand.
services:
  keycloak:
    ports: !override
      - "${AUTHORITY_KC_PORT}:8080"
    volumes:
      - ${LOCAL_DIR}/glcdi-realm.json:/opt/keycloak/data/import-template/glcdi-realm.json:ro
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: \${KEYCLOAK_ADMIN_PASSWORD}
      # Cap JVM heap. JAVA_TOOL_OPTIONS is read by every JVM regardless of
      # how the image's entrypoint is written. KC needs ~512MB headroom for
      # realm import + admin console; bump to 1024m if tight.
      JAVA_TOOL_OPTIONS: "-Xmx768m -Xms128m -XX:MaxMetaspaceSize=256m"
  onboarding-backend:
    ports:
      - "${AUTHORITY_ONBOARDING_PORT}:8083"
EOF

  # No profile flag: nginx (profile dev) and nginx-prod (profile prod) both
  # stay down. Onboarding + KC are reached directly on their host ports.
  ( cd "$AUTHORITY_DIR" \
    && docker compose --env-file "$authority_env" \
         -f docker-compose.yml -f "$override" up -d --build \
  ) || die "docker compose up failed for Authority Keycloak"

  wait_for_authority
  wait_for_onboarding
  ok "Authority Keycloak:        http://localhost:${AUTHORITY_KC_PORT}/auth"
  ok "  Admin: admin / ${KC_ADMIN_PASSWORD}"
  ok "Onboarding registration:   http://localhost:${AUTHORITY_ONBOARDING_PORT}/registration/"
  ok "Onboarding admin dashboard: http://localhost:${AUTHORITY_ONBOARDING_PORT}/registration/admin/  (login admin/admin)"
}

# Substitutes {{POSTGRES_USER}}, {{POSTGRES_PASSWORD}}, {{KC_DB_USERNAME}},
# {{KC_DB_PASSWORD}}, {{KC_ADMIN_USERNAME}}, {{KC_BOOTSTRAP_ADMIN_PASSWORD}}
# in the secret files written by init-secrets.sh. Idempotent - re-running on
# already-substituted files is a no-op.
substitute_authority_secrets() {
  local kc_db_user="keycloak"
  local kc_admin_user="admin"

  local files=(
    "$AUTHORITY_DIR/secrets/postgres-governance/postgres_user"
    "$AUTHORITY_DIR/secrets/postgres-governance/postgres_pwd"
    "$AUTHORITY_DIR/secrets/keycloak/keycloak.conf"
  )

  log "Re-generating Authority secret files from templates with current rotated values"
  for f in "${files[@]}"; do
    local template="${f}.template"
    if [[ ! -f "$template" ]]; then
      warn "Template missing - skipping: $template"
      continue
    fi
    # Always re-copy from .template, then substitute. This is what fixes the
    # "first-run password sticks across resets" bug - the populated file
    # gets whatever values are CURRENTLY in secrets.env, not the first-ever
    # generated ones.
    sed \
      -e "s|{{POSTGRES_USER}}|$kc_db_user|g" \
      -e "s|{{POSTGRES_PASSWORD}}|$KC_DB_PASSWORD|g" \
      -e "s|{{KC_DB_USERNAME}}|$kc_db_user|g" \
      -e "s|{{KC_DB_PASSWORD}}|$KC_DB_PASSWORD|g" \
      -e "s|{{KC_ADMIN_USERNAME}}|$kc_admin_user|g" \
      -e "s|{{KC_BOOTSTRAP_ADMIN_PASSWORD}}|$KC_ADMIN_PASSWORD|g" \
      "$template" > "$f"
  done

  # Sanity-check leftovers - only the populated files matter; .template
  # originals are expected to keep their {{...}} markers.
  local leftover
  leftover=$(grep -rE '\{\{[A-Z_]+\}\}' "$AUTHORITY_DIR/secrets" \
               --exclude='*.template' 2>/dev/null || true)
  if [[ -n "$leftover" ]]; then
    warn "Unsubstituted placeholders remain in populated secrets - KC may fail to start:"
    printf '%s\n' "$leftover" >&2
  fi
}

wait_for_authority() {
  local url="http://localhost:${AUTHORITY_KC_PORT}/auth/realms/glcdi/.well-known/openid-configuration"
  log "Waiting for Authority KC to import realm and serve OIDC discovery"
  local i
  for i in {1..180}; do
    if curl -fsSL --max-time 2 "$url" >/dev/null 2>&1; then
      ok "Authority KC ready (after ~${i}s)"
      return 0
    fi
    sleep 1
  done
  die "Authority KC did not become ready within 180s. Check: docker compose -f $AUTHORITY_DIR/docker-compose.yml logs keycloak"
}

# Onboarding-backend is published directly on AUTHORITY_ONBOARDING_PORT in
# dev (no nginx in front). First-boot work - djangoldp install + migrate +
# collectstatic - can take a minute. Subsequent boots are quick.
wait_for_onboarding() {
  local url="http://localhost:${AUTHORITY_ONBOARDING_PORT}/registration/"
  log "Waiting for onboarding backend to serve $url"
  local i
  for i in {1..240}; do
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$url" || echo "000")
    # 200 = form rendered. 301/302 = django redirect (also fine).
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
      ok "Onboarding backend ready (after ~${i}s, HTTP $code)"
      return 0
    fi
    sleep 1
  done
  warn "Onboarding backend did not serve /registration/ within 240s."
  warn "Check: docker compose -f $AUTHORITY_DIR/docker-compose.yml logs onboarding-backend"
}

# -----------------------------------------------------------------------------
# Per-participant config generation
# -----------------------------------------------------------------------------

# Ports inside container stay constant; nginx publishes 8080 inside, mapped
# to NGINX_PORT on the host. edc.dsp.callback.address must match the
# external host:port so other connectors can reach back.
write_participant_configs() {
  cmd_secrets
  local org
  for org in "${LOCAL_ORGS[@]}"; do
    local org_upper
    org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
    local nginx_port="${ORG_PORTS[$org]}"
    local org_dir="$LOCAL_DIR/$org"
    mkdir -p "$org_dir/participant"

    local api_key_var="${org_upper}_API_KEY"
    local secret_var="${org_upper}_CONNECTOR_SECRET"
    local db_var="${org_upper}_DB_PASSWORD"

    local api_key="${!api_key_var}"
    local connector_secret="${!secret_var}"
    local db_pass="${!db_var}"

    log "Writing config for $org (port $nginx_port)"

    # .env - consumed by docker compose and the catalogue-ui image entrypoint.
    # Tier 1 (IMPLEM_PLAN.md § 1.5): X-Api-Key only on the UI, connector
    # client_credentials against Authority KC for DSP. No OIDC envvars at
    # this tier - they (KEYCLOAK_URL / OIDC_CLIENT_ID / KC_IDP_HINT /
    # LINKED_PROVIDER_* / oauth2-proxy/GLCDI_UI_CLIENT_SECRET) come back
    # under § 7.2 along with the user-OIDC layer.
    cat > "$org_dir/.env" <<EOF
PARTICIPANT_NAME=$org
PARTICIPANT_ID=$org
EDC_API_KEY=$api_key
CONNECTOR_DB_PASSWORD=$db_pass

# Connector self-auth: client_credentials against Authority KC (post §3.5).
EDC_OAUTH_CLIENT_ID=glcdi-connector-$org
EDC_OAUTH_CLIENT_SECRET=$connector_secret

PARTICIPANT_CONNECTOR_URI=http://localhost:${nginx_port}
PARTICIPANT_DOMAIN=localhost
NGINX_PORT=$nginx_port
IDH_LOG_LEVEL=INFO

# --- Participant DjangoLDP backend (djangoldp_edc V3 permissions) ---
# The domain package gates which models are exposed under /ldp/. Each
# participant picks its own (see ORG_LDP_PACKAGES at the top of glcdi.sh).
LDP_DOMAIN_PACKAGE=${ORG_LDP_PACKAGES[$org]}
LDP_BASE_URL=http://localhost:${nginx_port}/ldp
DJANGO_SECRET_KEY=$DJANGO_SECRET_KEY
LDP_DB_PASSWORD=ldp-${org}
LDP_DB_BOOTSTRAP_PASSWORD=postgres

# EDC base URL - no trailing /management; djangoldp_edc appends it itself.
EDC_URL=http://edc-connector:9193
EDC_PARTICIPANT_ID=glcdi-connector-$org
EDC_ASSET_ID_STRATEGY=full_url
EDC_AGREEMENT_VALIDATION_ENABLED=True
EDC_AUTO_NEGOTIATION_ENABLED=False
EDC_POLICY_DISCOVERY_ENABLED=False

# Local-package iteration (mirrors TEMS catalogue-ui pattern):
# Set GLCDI_USE_LOCAL_PACKAGES=true on the glcdi.sh invocation to toggle
# the catalogue-ui's npm[] paths from jsdelivr to localhost Vite dev-server
# URLs. Defaults to false - production-style CDN loading.
USE_LOCAL_PACKAGES=${GLCDI_USE_LOCAL_PACKAGES:-false}
SIB_CORE_PATH=${GLCDI_SIB_CORE_PATH:-}
SOLID_TEMS_UI_PATH=${GLCDI_SOLID_TEMS_UI_PATH:-}
SOLID_TEMS_PATH=${GLCDI_SOLID_TEMS_PATH:-}
# Pin the version - @latest is cached forever by the participant-ui SW. Bump when a release is verified.
GLCDI_PATH=${GLCDI_PKG_PATH:-https://cdn.jsdelivr.net/npm/@startinblox/glcdi@1.0.5/+esm}

APP_TITLE=$(echo "$org" | sed 's/.*/\u&/' | tr - ' ') - GLCDI
PRIMARY_COLOR=${ORG_COLORS[$org]:-#2E7D32}
SECONDARY_COLOR=${ORG_SECONDARY_COLORS[$org]:-#1B5E20}
ACCENT_COLOR=${ORG_ACCENT_COLORS[$org]:-#66BB6A}

DSP_PROVIDERS=$(other_dsp_providers_json "$org")

# OAuth2 token endpoint for the participant's bound farmOS instance
# (caney-fork + GLCDI_FARMOS=1 only). Empty otherwise - the asset-create
# form just shows a placeholder.
FARMOS_TOKEN_URL=$([[ "$FARMOS_ENABLED" == "1" && "$org" == "caney-fork" ]] && echo "http://localhost:${FARMOS_PORT:-8091}/oauth/token" || echo "")
EOF

    # Per-org configuration.properties - patched from the example.
    # The DB triple (url/user/password) must match what the compose's
    # `db-connector` postgres is created with. Compose sets POSTGRES_DB and
    # POSTGRES_USER to ${PARTICIPANT_NAME} and POSTGRES_PASSWORD to
    # ${CONNECTOR_DB_PASSWORD}. The example properties hardcode `participant`
    # for all three - that mismatch is the root cause of "password
    # authentication failed for user participant" on first boot.
    sed -e "s|web.http.management.auth.key=.*|web.http.management.auth.key=$api_key|" \
        -e "s|edc.api.auth.key=.*|edc.api.auth.key=$api_key|" \
        -e "s|edc.api.control.auth.apikey.value=.*|edc.api.control.auth.apikey.value=$api_key|" \
        -e "s|edc.dsp.callback.address=.*|edc.dsp.callback.address=http://host.docker.internal:${nginx_port}/protocol|" \
        -e "s|edc.dataplane.api.public.baseurl=.*|edc.dataplane.api.public.baseurl=http://host.docker.internal:${nginx_port}/public/|" \
        -e "s|glcdi.dataplane.host.rewrite=.*|glcdi.dataplane.host.rewrite=$(host_rewrite_for "$org")|" \
        -e "s|edc.participant.id=.*|edc.participant.id=glcdi-connector-${org}|" \
        -e "s|glcdi.iam.kc.client.id=.*|glcdi.iam.kc.client.id=glcdi-connector-${org}|" \
        -e "s|glcdi.iam.kc.client.secret=.*|glcdi.iam.kc.client.secret=${connector_secret}|" \
        -e "s|edc.datasource.default.url=.*|edc.datasource.default.url=jdbc:postgresql://db-connector:5432/$org|" \
        -e "s|edc.datasource.default.user=.*|edc.datasource.default.user=$org|" \
        -e "s|edc.datasource.default.password=.*|edc.datasource.default.password=$db_pass|" \
        "$PARTICIPANT_DIR/participant/configuration.properties.example" \
        > "$org_dir/participant/configuration.properties"

    # idh-configuration.properties - copy if example exists.
    if [[ -f "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" ]]; then
      cp "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" \
         "$org_dir/participant/idh-configuration.properties"
    fi

    # Tier-1 nginx config - drops every route that depends on services we
    # disable at this tier (per-participant Keycloak, oauth2-proxy, identity-hub).
    # Adds an /auth/ proxy to the Authority KC on the host (via host.docker.internal,
    # which the nginx container CAN resolve via its extra_hosts entry) so the
    # browser-side UI hits same-origin (localhost:NGINX_PORT/auth/*) instead
    # of cross-origin to the KC's port.
    # Open CORS (Access-Control-Allow-Origin *) on every route - local dev
    # only; production deployments narrow this to specific origins.
    # Mounted into the nginx container via the override below in place of the
    # in-repo nginx-dev.conf.
    cat > "$org_dir/participant/nginx-dev.conf" <<EOF
# Auto-generated by glcdi.sh (Tier 1) - do not edit by hand.

# Reusable CORS handler. Responds to OPTIONS preflight + sets ACAO on every
# response. * is fine for local dev; tighten in prod.
map \$request_method \$cors_method {
    OPTIONS 1;
    default 0;
}

server {
    listen 8080;
    server_name _;

    # Keep Location headers relative - the container listens on 8080 but the host
    # maps each org to its own port (8080/8081/8082), so absolute redirects would
    # collapse every participant onto caney-fork's port.
    absolute_redirect off;

    # Apply CORS on every response from this server.
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Api-Key, X-Requested-With' always;
    add_header 'Access-Control-Expose-Headers' 'Authorization, Content-Type' always;
    add_header 'Access-Control-Max-Age' '600' always;

    # Short-circuit OPTIONS preflight without touching the upstream.
    if (\$cors_method) {
        return 204;
    }

    location = / {
        return 302 /ui/;
    }

    # Proxy /auth/ to the Authority Keycloak on the host. Same-origin from
    # the browser's perspective (localhost:NGINX_PORT/auth/*).
    location /auth/ {
        proxy_pass http://host.docker.internal:${AUTHORITY_KC_PORT}/auth/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /management/ {
        proxy_pass http://edc-connector:9193/management/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /protocol/ {
        proxy_pass http://edc-connector:9194/protocol/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /public/ {
        proxy_pass http://edc-connector:9291/public/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Participant DjangoLDP backend - strip /ldp prefix; permission class is djangoldp_edc V3.
    location /ldp/ {
        proxy_pass http://djangoldp-backend:8083/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
    }

    location /ui/ {
        proxy_pass http://catalogue-ui:80/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Override file - Tier-1 stack:
    #   - edc-connector: locally-built image (fastest iteration when changing
    #                    extension code) + re-bound config dir + JVM heap cap
    #   - nginx:         dev nginx config from the local org dir
    #   - catalogue-ui:  locally-built image (fastest iteration when changing
    #                    orbit/solid-glcdi/config). Since the new self-contained
    #                    Dockerfile clones the same hubl branch as CI, the
    #                    :local image is functionally identical to the
    #                    published :latest - this override is purely a build-
    #                    speed optimisation; you can omit it without breaking
    #                    Tier-1 behaviour, at the cost of pulling on every up.
    #
    # NOTE: identity-hub and oauth2-proxy used to be stubbed here because
    # they appeared in the upstream compose; they were removed from
    # docker-compose.yml at Tier 1, so no stub is needed anymore.
    cat > "$org_dir/docker-compose.override.yml" <<EOF
# Auto-generated by glcdi.sh - do not edit by hand.
services:
  edc-connector:
    # Use the locally-built controlplane image (produced by
    # gradlew :runtimes:controlplane:dockerize in glcdi.sh build).
    # Equivalent to registry :latest when CI is healthy, but a local
    # build is faster than waiting for CI to publish.
    image: controlplane:latest
    pull_policy: never
    volumes:
      - ${org_dir}/participant:/app/conf:ro
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx512m -Xms128m -XX:MaxMetaspaceSize=192m"
  nginx:
    volumes: !override
      - ${org_dir}/participant/nginx-dev.conf:/etc/nginx/conf.d/default.conf:ro
  catalogue-ui:
    image: glcdi-participant-ui:local
    pull_policy: never
  djangoldp-backend:
    # Pin to the locally-built image (produced by glcdi.sh build).
    # pull_policy: never keeps compose from trying to pull a non-existent
    # registry tag and from silently using a stale cached image.
    image: glcdi-djangoldp-backend:local
    pull_policy: never
EOF
  done
}

# Build the JSON array of OTHER orgs as DSP providers, for the catalogue UI's
# "discover other dataspaces" view. Caney-fork's array lists point-blue +
# white-buffalo, etc.
other_dsp_providers_json() {
  local me="$1"
  local out="["
  local first=1
  for org in "${LOCAL_ORGS[@]}"; do
    [[ "$org" == "$me" ]] && continue
    [[ $first -eq 1 ]] || out+=","
    first=0
    local port="${ORG_PORTS[$org]}"
    local nice
    nice=$(echo "$org" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')
    # participantId must match the connector's edc.participant.id (set to
    # glcdi-connector-<org> after the Tier-1 IAM swap). Without this, the
    # catalogue UI matches incoming dataset._provider.participantId
    # against the wrong value and counts 0 datasets per provider.
    local color="${ORG_COLORS[$org]:-#1565C0}"
    out+="{\"name\":\"$nice\",\"address\":\"http://host.docker.internal:${port}/protocol\",\"color\":\"${color}\",\"participantId\":\"glcdi-connector-${org}\"}"
  done
  out+="]"
  printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# Per-participant compose up
# -----------------------------------------------------------------------------

up_participants() {
  write_participant_configs

  for org in "${LOCAL_ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    log "Bringing up participant: $org"
    ( cd "$PARTICIPANT_DIR" \
      && docker compose \
           --env-file "$org_dir/.env" \
           --profile dev \
           $(farmos_profile_args "$org") \
           -f docker-compose.yml \
           -f "$org_dir/docker-compose.override.yml" \
           up -d \
    ) || die "docker compose up failed for $org"
  done

  for org in "${LOCAL_ORGS[@]}"; do
    wait_for_participant "$org"
  done
}

wait_for_participant() {
  local org="$1"
  local port="${ORG_PORTS[$org]}"
  local org_upper
  org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
  local api_key_var="${org_upper}_API_KEY"
  local api_key="${!api_key_var}"

  local url="http://localhost:${port}/management/v3/assets/request"
  log "Waiting for $org connector at $url"
  local i
  for i in {1..180}; do
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
      -X POST "$url" \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: $api_key" \
      -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}' \
      || true)
    if [[ "$status" == "200" ]]; then
      ok "$org ready"
      return 0
    fi
    sleep 1
  done
  warn "$org did not respond 200 within 180s (last status: ${status:-unknown}). Check: $0 logs $org"
}

cmd_up() {
  cmd_preflight
  up_authority
  up_participants
  hr
  ok "Stack up. Endpoints:"
  printf '  Authority KC: http://localhost:%s/auth/admin (admin / from secrets)\n' "$AUTHORITY_KC_PORT"
  for org in "${LOCAL_ORGS[@]}"; do
    printf '  %-15s http://localhost:%s/  (UI)  +  /management/* with X-Api-Key\n' "$org" "${ORG_PORTS[$org]}"
  done
  if [[ "$FARMOS_ENABLED" == "1" ]]; then
    printf '  %-15s http://localhost:8091/  (Drupal - run \`%s farmos-install\` first time)\n' "farmos" "$0"
  fi
  hr
  if [[ "$FARMOS_ENABLED" == "1" ]]; then
    log "Next: $0 farmos-install   then   $0 seed   then   $0 test"
  else
    log "Next: $0 seed   then   $0 test"
  fi
}

# -----------------------------------------------------------------------------
# Build edc-connector + participant-ui images
# -----------------------------------------------------------------------------

cmd_build() {
  log "Building edc-connector image (with glcdi extensions synced)"
  if [[ -x "$EDC_CONNECTOR_DIR/scripts/sync-glcdi-extensions.sh" ]]; then
    ( cd "$EDC_CONNECTOR_DIR" && ./scripts/sync-glcdi-extensions.sh ) \
      || die "sync-glcdi-extensions.sh failed"
  else
    warn "scripts/sync-glcdi-extensions.sh not found - skipping extension sync"
  fi

  if [[ -x "$EDC_CONNECTOR_DIR/gradlew" ]]; then
    ( cd "$EDC_CONNECTOR_DIR" && ./gradlew :runtimes:controlplane:dockerize ) \
      || die "Gradle build failed"
    ok "edc-connector image built"
  else
    warn "$EDC_CONNECTOR_DIR/gradlew not found - bootstrap with: gradle wrapper, then re-run"
  fi

  log "Building participant-ui image (clones hubl branch at build time)"
  if [[ -f "$PARTICIPANT_UI_DIR/Dockerfile" ]]; then
    # Build context is participant-ui/ itself - the Dockerfile clones
    # the hubl/orbit source at build time, so it no longer needs the
    # workspace-root layout. Local image is byte-equivalent to what CI
    # publishes to registry.startinblox.com.
    ( cd "$PARTICIPANT_UI_DIR" \
      && docker build \
           -t glcdi-participant-ui:local \
           . \
    ) || die "participant-ui build failed"
    ok "participant-ui image built (glcdi-participant-ui:local)"
  else
    warn "$PARTICIPANT_UI_DIR/Dockerfile not found - UI image not built"
  fi

  # djangoldp-backend (participant LDP server, Tier-2 / Phase-7.6).
  # Built explicitly to a known tag so the per-org override.yml can pin it
  # with pull_policy: never - same pattern as controlplane:latest and
  # glcdi-participant-ui:local above. Without this step, `docker compose
  # up` would do an implicit build on first run and silently reuse a stale
  # image on subsequent runs after Dockerfile / runserver.sh / template
  # edits - exactly the iteration trap we want to avoid.
  log "Building djangoldp-backend image (participant LDP server)"
  if [[ -f "$PARTICIPANT_DIR/djangoldp/Dockerfile" ]]; then
    ( cd "$PARTICIPANT_DIR/djangoldp" \
      && docker build \
           -t glcdi-djangoldp-backend:local \
           . \
    ) || die "djangoldp-backend build failed"
    ok "djangoldp-backend image built (glcdi-djangoldp-backend:local)"
  else
    warn "$PARTICIPANT_DIR/djangoldp/Dockerfile not found - djangoldp-backend image not built"
  fi
}

# -----------------------------------------------------------------------------
# Target resolution (local + staging)
# -----------------------------------------------------------------------------

# SSH env var pairs per staging participant. Kept in one place so the error
# message and the resolver can't drift.
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

# Expand a --target value to one or more concrete targets. all-staging fans
# out to the three named staging participants.
expand_target() {
  local target="$1"
  case "$target" in
    local|caney-fork|point-blue|white-buffalo|demo) printf '%s\n' "$target" ;;
    all-staging)
      printf 'caney-fork\n'
      printf 'point-blue\n'
      printf 'white-buffalo\n'
      printf 'demo\n'
      ;;
    *) die "Unknown --target: $target (expected local|caney-fork|point-blue|white-buffalo|demo|all-staging)" ;;
  esac
}

# Resolve a single target to its host URL. Echoes the host.
target_host() {
  local target="$1"
  case "$target" in
    local) die "target_host called with 'local' - caller should iterate ORGS" ;;
    caney-fork|point-blue|white-buffalo)
      printf 'https://%s.glcdi.startinblox.com' "$target"
      ;;
    demo)
      printf 'https://demo.glcdi.startinblox.com'
      ;;
    *) die "target_host: unknown target $target" ;;
  esac
}

# Bruno environment name for a target (local|staging).
target_bruno_env() {
  case "$1" in
    local) printf 'local' ;;
    caney-fork|point-blue|white-buffalo|demo) printf 'staging' ;;
    *) die "target_bruno_env: unknown target $1" ;;
  esac
}

# Fetch the EDC_API_KEY for a staging target by SSH-ing to its VM.
# Defaults to root@<target>.glcdi.startinblox.com; override via SSH_USER_* / SSH_HOST_* env vars.
fetch_staging_api_key() {
  fetch_staging_env_value "$1" EDC_API_KEY
}

# Fetch any .env variable from a staging target's ~/participant-agent-services/.env over SSH.
# Returns empty string (not fatal) if the var isn't set - callers decide whether absence is OK.
fetch_staging_env_value() {
  local target="$1" key="$2"
  local user_var="${SSH_USER_VAR[$target]:-}"
  local host_var="${SSH_HOST_VAR[$target]:-}"
  if [[ -z "$user_var" || -z "$host_var" ]]; then
    die "fetch_staging_env_value: no SSH var mapping for $target"
  fi
  local user="${!user_var:-root}"
  local host="${!host_var:-${target}.glcdi.startinblox.com}"
  local val
  val=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" \
          "grep '^${key}=' ~/participant-agent-services/.env | cut -d= -f2-" \
        2>/dev/null) || die "SSH to ${user}@${host} failed for $target - check connectivity and ~/participant-agent-services/.env on the VM."
  val="${val//$'\r'/}"
  val="${val%$'\n'}"
  # Critical-var sentinel - EDC_API_KEY's absence is fatal; everything else returns "".
  if [[ -z "$val" && "$key" == "EDC_API_KEY" ]]; then
    die "Empty $key fetched from ${user}@${host} for $target - does ~/participant-agent-services/.env exist on the VM?"
  fi
  printf '%s' "$val"
}

# -----------------------------------------------------------------------------
# Seed M1 fixtures via Bruno
# -----------------------------------------------------------------------------

# Friendly display name for the asset titles (Title Case from kebab).
org_display_name() {
  echo "$1" | sed 's/-/ /g' \
    | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1'
}

# Run the bruno 10-provider-seeding folder against one org-host pair. The
# bruno files use {{caney_fork_host}} / {{caney_fork_api_key}} placeholders
# regardless of which org is being seeded - overrides rebind them per call.
#
# Demo dispatches to 12-provider-seeding-demo instead: 4 contributor-specific
# assets + atomic obligation policies, not the M1 3-asset triple.
seed_one() {
  local org="$1"
  local host="$2"
  local api_key="$3"
  local bruno_env="$4"

  if [[ "$org" == "demo" ]]; then
    seed_demo "$host" "$api_key" "$bruno_env"
    return $?
  fi

  local org_display
  org_display=$(org_display_name "$org")

  # If seed-ldp produced LDP urlids for this org, pass them so each M1
  # asset's dataAddress.baseUrl resolves to a real LDP-protected resource:
  #   01-create-asset            (grazing-soc-2024)           → Farm urlid
  #   06-create-asset-research-summary (grazing-summary-2024) → Plot urlid
  #   09-create-asset-research-only (grazing-raw-observations) → Metric urlid
  # If urlids are missing (staging today, or local pre-seed-ldp), Bruno
  # falls back to the legacy http://provider-data-source/... defaults in
  # environments/<env>.bru - the asset still gets created, contract negotiation
  # still works, but the data path doesn't end at a real protected resource.
  local farm_file="$LOCAL_DIR/$org/ldp-farm-urlid.txt"
  local plot_file="$LOCAL_DIR/$org/ldp-plot-urlid.txt"
  local metric_file="$LOCAL_DIR/$org/ldp-metric-urlid.txt"
  local base_url_flags=""
  local description_flags=""

  # Staging: each participant owns an external djangoldp instance at
  # api.stg.<org>.glcdi.startinblox.com. Asset baseUrls point at the LDP
  # containers exposed by that org's djangoldp package - caney-fork uses the
  # baseline (farms/plots/metrics); point-blue adds biomass + soil-sample;
  # white-buffalo adds cattle-rotation.
  if [[ "$bruno_env" == "staging" || "$bruno_env" == "caney-fork" || "$bruno_env" == "point-blue" || "$bruno_env" == "white-buffalo" ]]; then
    local m1_url m1_research_url m1_researcher_url m1_desc m1_research_desc m1_researcher_desc
    case "$org" in
      caney-fork)
        m1_url="https://api.stg.caneyfork.glcdi.startinblox.com/metrics/"
        m1_research_url="https://api.stg.caneyfork.glcdi.startinblox.com/plots/"
        m1_researcher_url="https://api.stg.caneyfork.glcdi.startinblox.com/farms/"
        m1_desc="Soil organic carbon Metric records from Caney Fork's /metrics/ container (djangoldp_glcdi baseline), 2024 season - restricted to producers (M1 fixture)."
        m1_research_desc="Plot-level grazing summary from Caney Fork's /plots/ container (djangoldp_glcdi baseline), aggregated 2024 - open to any active dataspace member (M1 fixture)."
        m1_researcher_desc="Farm-level raw observations from Caney Fork's /farms/ container (djangoldp_glcdi baseline), 2024 - restricted to researcher participants (M1 fixture)."
        ;;
      point-blue)
        m1_url="https://api.stg.pointblue.glcdi.startinblox.com/soil-samples/"
        m1_research_url="https://api.stg.pointblue.glcdi.startinblox.com/biomass-plots/"
        m1_researcher_url="https://api.stg.pointblue.glcdi.startinblox.com/biomass-points/"
        m1_desc="SoilSample records from Point Blue's /soil-samples/ container (djangoldp_glcdi_pointblue), 2024 season - restricted to producers (M1 fixture)."
        m1_research_desc="BiomassPlot aggregates from Point Blue's /biomass-plots/ container (djangoldp_glcdi_pointblue), 2024 - open to any active dataspace member (M1 fixture)."
        m1_researcher_desc="Raw BiomassPoint observations from Point Blue's /biomass-points/ container (djangoldp_glcdi_pointblue), 2024 - restricted to researcher participants (M1 fixture)."
        ;;
      white-buffalo)
        m1_url="https://api.stg.whitebuffalo.glcdi.startinblox.com/metrics/"
        m1_research_url="https://api.stg.whitebuffalo.glcdi.startinblox.com/plots/"
        m1_researcher_url="https://api.stg.whitebuffalo.glcdi.startinblox.com/cattle-rotations/"
        m1_desc="Soil organic carbon Metric records from White Buffalo's /metrics/ container (djangoldp_glcdi_whitebuffalo), 2024 season - restricted to producers (M1 fixture)."
        m1_research_desc="Plot-level grazing summary from White Buffalo's /plots/ container (djangoldp_glcdi_whitebuffalo), aggregated 2024 - open to any active dataspace member (M1 fixture)."
        m1_researcher_desc="CattleRotation rotation log from White Buffalo's /cattle-rotations/ container (djangoldp_glcdi_whitebuffalo), 2024 - restricted to researcher participants (M1 fixture)."
        ;;
      *)
        die "seed_one: unknown org '$org' for staging URL mapping"
        ;;
    esac
    base_url_flags="--env-var m1_asset_base_url=${m1_url} --env-var m1_research_asset_base_url=${m1_research_url} --env-var m1_researcher_only_asset_base_url=${m1_researcher_url}"
    description_flags=(--env-var "m1_asset_description=${m1_desc}" --env-var "m1_research_asset_description=${m1_research_desc}" --env-var "m1_researcher_only_asset_description=${m1_researcher_desc}")
    log "  Using external LDP baseUrls for $org:"
    log "    M1 (producers):     $m1_url"
    log "    research-summary:   $m1_research_url"
    log "    researcher-only:    $m1_researcher_url"
  elif [[ -f "$farm_file" && -f "$plot_file" && -f "$metric_file" ]]; then
    # Local: seed-ldp produced LDP urlids from the dev djangoldp sibling.
    local farm_urlid plot_urlid metric_urlid
    farm_urlid=$(<"$farm_file")
    plot_urlid=$(<"$plot_file")
    metric_urlid=$(<"$metric_file")
    base_url_flags="--env-var m1_asset_base_url=${farm_urlid} --env-var m1_research_asset_base_url=${plot_urlid} --env-var m1_researcher_only_asset_base_url=${metric_urlid}"
    log "  Using LDP-backed baseUrls:"
    log "    M1:                 $farm_urlid"
    log "    research-summary:   $plot_urlid"
    log "    researcher-only:    $metric_urlid"
  else
    log "  No complete set of LDP urlids in $LOCAL_DIR/$org/ - keeping Bruno defaults. Run \`$0 seed-ldp\` first for end-to-end LDP gating."
  fi

  log "Seeding M1 fixtures on $org ($host) via Bruno [env=$bruno_env]"
  # shellcheck disable=SC2046
  ( cd "$BRUNO_DIR" && bru run 10-provider-seeding --env "$bruno_env" $(bruno_env_flags) $base_url_flags "${description_flags[@]}" \
      --env-var "caney_fork_host=${host}" \
      --env-var "caney_fork_api_key=${api_key}" \
      --env-var "org_display_name=${org_display}" \
      --env-var "m1_asset_id=urn:glcdi:asset:${org}:grazing-soc-2024" \
      --env-var "m1_contract_definition_id=${org}-grazing-soc-2024-cd" \
      --env-var "m1_research_asset_id=urn:glcdi:asset:${org}:grazing-summary-2024" \
      --env-var "m1_research_contract_definition_id=${org}-grazing-summary-2024-cd" \
      --env-var "m1_researcher_only_asset_id=urn:glcdi:asset:${org}:grazing-raw-observations-2024" \
      --env-var "m1_researcher_only_contract_definition_id=${org}-grazing-raw-observations-2024-cd" \
  ) || die "Bruno seeding folder failed for $org - see output above"
}

# Caney-fork-only extension: drops the farmOS-backed asset + its CD onto the
# connector and runs the consumer-side catalog leak check. Pre-req: 10-... must
# have run first (members-policy + internal-use-only-policy already exist).
#
# Gated on FARMOS_ENABLED - without GLCDI_FARMOS=1 the locally-running
# connector has no farmOS service to fetch from, and on staging this implies
# the operator hasn't set up the farmOS consumer either, so seeding the asset
# would be a half-broken contract definition. cmd_seed calls this only when
# the flag is set AND $org == caney-fork.
#
# Args: org host api_key bruno_env [cli_cid cli_secret].
# cli_cid/cli_secret are the --farmos-client-id/--farmos-client-secret overrides
# from cmd_seed; when set, they replace both the local secrets.env value and the
# staging VM .env fetch.
seed_farmos_one() {
  local org="$1"
  local host="$2"
  local api_key="$3"
  local cli_farmos_cid="${5:-}"
  local cli_farmos_secret="${6:-}"

  # Enable farmOS asset bundles + populate dummy animals/lands/plants.
  # Idempotent; only runs on local (the farmOS container is local-only).
  if [[ "${4:-}" == "local" ]] && [[ "$org" == "caney-fork" ]]; then
    local container
    container=$(compose_for caney-fork ps -q farmos 2>/dev/null || true)
    if [[ -n "$container" ]]; then
      log "Seeding farmOS dummy data (animals/lands/plants) on $org"
      compose_for caney-fork exec -T --user root \
        -e FARMOS_OAUTH_CLIENT_ID="${FARMOS_ANIMAL_CLIENT_ID:-}" \
        farmos bash /opt/drupal/seed-dummy-data.sh >/dev/null \
        || warn "seed-dummy-data.sh exited non-zero (consumer-repair errors are non-fatal - install.sh already provisions)"
    else
      warn "farmos container not running - skipping dummy-data seed"
    fi
  fi

  local bruno_env="$4"
  # Peer host used by 13-.../03-verify-secret-not-in-catalog.bru to query
  # caney-fork's catalog from outside. Local always uses point-blue;
  # staging uses point-blue's public URL.
  local peer_host peer_api_key peer_dsp peer_id
  case "$bruno_env" in
    local)
      peer_host="http://localhost:${ORG_PORTS[point-blue]}"
      peer_api_key="${POINT_BLUE_API_KEY:-}"
      peer_dsp="http://host.docker.internal:${ORG_PORTS[caney-fork]}/protocol"
      peer_id="glcdi-connector-caney-fork"
      ;;
    *)
      peer_host="https://point-blue.glcdi.startinblox.com"
      peer_api_key="$(fetch_staging_api_key point-blue 2>/dev/null || true)"
      peer_dsp="https://caney-fork.glcdi.startinblox.com/protocol"
      peer_id="glcdi-connector-caney-fork"
      ;;
  esac

  # Cred resolution priority: CLI override > local secrets.env > staging VM .env.
  local farmos_cid="${FARMOS_ANIMAL_CLIENT_ID:-}"
  local farmos_secret="${FARMOS_ANIMAL_CLIENT_SECRET:-}"
  if [[ -n "$cli_farmos_cid" && -n "$cli_farmos_secret" ]]; then
    farmos_cid="$cli_farmos_cid"
    farmos_secret="$cli_farmos_secret"
    log "  using --farmos-client-id/--farmos-client-secret overrides"
  elif [[ "$bruno_env" != "local" ]]; then
    farmos_cid=$(fetch_staging_env_value "$org" FARMOS_ANIMAL_CLIENT_ID)
    farmos_secret=$(fetch_staging_env_value "$org" FARMOS_ANIMAL_CLIENT_SECRET)
    if [[ -z "$farmos_cid" || -z "$farmos_secret" ]]; then
      die "FARMOS_ANIMAL_CLIENT_ID/SECRET missing from ${org}'s VM .env - set them, pass --farmos-client-id/--farmos-client-secret, or see README §farmOS staging step 4."
    fi
  fi

  # URLs the PUT-update step needs; mirrors environments/<bruno_env>.bru.
  local farmos_base_url farmos_token_url
  case "$bruno_env" in
    local)
      farmos_base_url="http://farmos:80/api/asset/animal"
      farmos_token_url="http://farmos:80/oauth/token"
      ;;
    *)
      farmos_base_url="https://farmos.caney-fork.glcdi.startinblox.com/api/asset/animal"
      farmos_token_url="https://farmos.caney-fork.glcdi.startinblox.com/oauth/token"
      ;;
  esac

  log "Seeding farmOS asset + CD on $org ($host) via Bruno [env=$bruno_env]"
  # shellcheck disable=SC2046
  ( cd "$BRUNO_DIR" && bru run 13-provider-seeding-caney-fork-farmos --env "$bruno_env" $(bruno_env_flags) \
      --env-var "caney_fork_host=${host}" \
      --env-var "caney_fork_api_key=${api_key}" \
      --env-var "caney_fork_dsp=${peer_dsp}" \
      --env-var "caney_fork_participant_id=${peer_id}" \
      --env-var "point_blue_host=${peer_host}" \
      --env-var "point_blue_api_key=${peer_api_key}" \
      --env-var "org_display_name=$(org_display_name "$org")" \
      --env-var "farmos_animal_client_id=${farmos_cid}" \
      --env-var "farmos_animal_client_secret=${farmos_secret}" \
  ) || die "Bruno farmOS seeding folder failed for $org - see output above"

  # Bruno step 01 uses POST, which 409s if the asset already exists - so re-seeding
  # an existing asset is otherwise a no-op for the dataAddress + privateProperties.
  # PUT here ensures the on-disk creds (+ URLs + scope) always converge to the
  # values resolved above. Safe wrt existing contract agreements: they reference
  # the asset URN, not its content, so updates flow into in-flight + future transfers.
  local org_display
  org_display=$(org_display_name "$org")
  local put_body
  put_body=$(jq -nc \
    --arg id "urn:glcdi:asset:caney-fork:farmos-animals-2024" \
    --arg name "${org_display} - live animal census (farmOS)" \
    --arg base "$farmos_base_url" \
    --arg tok  "$farmos_token_url" \
    --arg cid  "$farmos_cid" \
    --arg sec  "$farmos_secret" \
'{
  "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/","glcdi":"https://w3id.org/glcdi/v0.1.0/ns/"},
  "@id": $id, "@type": "Asset",
  "properties": {
    "name": $name,
    "description": "JSON:API feed of farmOS asset/animal records, fetched at transfer time via OAuth2 client_credentials.",
    "contenttype": "application/vnd.api+json",
    "glcdi:assetClass": "livestock-census",
    "glcdi:source": "farmos"
  },
  "privateProperties": {"oauth2:clientSecret": $sec},
  "dataAddress": {
    "type": "HttpData",
    "name": "farmos-animals",
    "baseUrl": $base,
    "proxyPath": "false",
    "proxyQueryParams": "true",
    "oauth2:tokenUrl": $tok,
    "oauth2:clientId": $cid,
    "oauth2:scope": "farm_viewer"
  }
}')
  local put_code
  put_code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H 'Content-Type: application/json' -H "X-Api-Key: $api_key" \
    "$host/management/v3/assets" -d "$put_body" 2>/dev/null || echo "000")
  case "$put_code" in
    2*) ok "PUT-updated $org's farmos-animals asset (HTTP $put_code)" ;;
    404) warn "PUT returned 404 - Bruno step 01 should have created the asset; check that output." ;;
    *)  die "PUT-update of farmos-animals asset on $org failed (HTTP $put_code)" ;;
  esac
}

# Seed the demo VM via the 12-provider-seeding-demo bruno folder. 4
# contributor-specific assets backed by static JSON stubs at /data/<slug>.json
# on the demo VM. Atomic obligation policies + per-asset CD policies that
# merge the relevant atoms (Shape B per ops/demo-vm.md §4.1).
seed_demo() {
  local host="$1"
  local api_key="$2"
  local bruno_env="$3"

  local data_root="${host}/data"
  log "Seeding demo fixtures on $host via Bruno [env=$bruno_env]"
  log "  Asset baseUrls under: $data_root"

  ( cd "$BRUNO_DIR" && bru run 12-provider-seeding-demo --env "$bruno_env" $(bruno_env_flags) \
      --env-var "demo_host=${host}" \
      --env-var "demo_api_key=${api_key}" \
      --env-var "demo_data_root=${data_root}" \
  ) || die "Bruno seeding folder failed for demo - see output above"
}

###############################################################################
# Phase-2 LDP seeding
#
# Each participant's djangoldp-backend exposes Farm / Plot / Metric models
# behind djangoldp_edc.EdcContractPermissionV3. The LDP fixture must exist
# BEFORE the EDC asset is created, because the asset's dataAddress.baseUrl
# must point at the Farm's urlid - and Bruno's `seed` then bakes that URL
# into the asset + the downstream contract definition references it.
#
# Therefore `seed-ldp` runs strictly before `seed`:
#   - up        → bring up the stack (including djangoldp-backend)
#   - seed-ldp  → create Farm/Plot/Metric in each participant's LDP backend
#                 and record the Farm urlid at .glcdi.local/<org>/ldp-farm-urlid.txt
#   - seed      → Bruno reads each urlid and POSTs the M1 asset with that
#                 baseUrl, so contract negotiation maps consumer → that URL
#                 → djangoldp_edc V3 perm validates the agreement → 200.
#
# `cmd_all` enforces this order. Idempotent - Farm.get_or_create is keyed by
# name. Use `glcdi.sh reset` to wipe everything.
###############################################################################

# Run docker compose against the per-org stack with the given subcommand
# args. e.g. `compose_for caney-fork ps`, `compose_for caney-fork logs --tail 80 djangoldp-backend`.
#
# Earlier this helper echoed the command as a string and callers ran it
# through `eval`; that re-parsed every subsequent arg as shell, which
# wrecked multi-line `manage.py shell -c "$python"` calls (newlines became
# statement separators, parens became subshells, etc.). Calling docker
# compose directly keeps argv intact end-to-end.
compose_for() {
  local org="$1"
  shift
  local org_dir="$LOCAL_DIR/$org"
  ( cd "$PARTICIPANT_DIR" \
    && docker compose \
         --env-file "$org_dir/.env" \
         --profile dev \
         $(farmos_profile_args "$org") \
         -f docker-compose.yml \
         -f "$org_dir/docker-compose.override.yml" \
         "$@"
  )
}

# Run a snippet through djangoldp-backend's manage.py shell with the right
# org's compose stack. Stdout from the snippet goes to fd 1; stderr is left
# on fd 2 so callers can see Django tracebacks.
ldp_shell() {
  local org="$1"
  local snippet="$2"
  compose_for "$org" exec -T djangoldp-backend ./manage.py shell -c "$snippet"
}

# Poll djangoldp-backend over HTTP until it answers anything (200, 302, 403
# - all mean Django is serving). Earlier versions cold-started `manage.py
# shell` per iteration, which takes 2-5s each, made the loop drift, and
# failed silently when Django emitted a banner that pushed our sentinel
# off `tail -n1`. HTTP polling via the participant nginx is fast and
# definitive, and matches how `wait_for_participant` checks the connector.
wait_for_ldp_backend() {
  local org="$1"
  local port="${ORG_PORTS[$org]}"
  local url="http://localhost:${port}/ldp/"
  local i status
  log "Waiting for djangoldp-backend ($org) at $url"
  for i in {1..180}; do
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$url" || echo "000")
    # Any non-zero HTTP code from nginx → upstream is responding. 502 / 504
    # means nginx is up but Django isn't yet - keep waiting.
    case "$status" in
      000|502|503|504)
        # not ready yet
        ;;
      *)
        printf '\n'
        ok "  djangoldp-backend ($org) ready after ${i}s (HTTP ${status} from $url)"
        return 0
        ;;
    esac
    if (( i % 10 == 0 )); then
      printf ' (%ds, last=%s)\n' "$i" "$status"
    else
      printf '.'
    fi
    sleep 1
  done
  printf '\n'
  warn "djangoldp-backend ($org) did not respond on $url in 180s (last status: ${status}). Recent logs:"
  compose_for "$org" logs --tail 80 djangoldp-backend >&2 || true
  die "djangoldp-backend ($org) never reached a usable state"
}

# Create one Farm + Plot + Metric in the participant's LDP backend, then
# write the Farm urlid to .glcdi.local/<org>/ldp-farm-urlid.txt for the
# downstream Bruno seed to pick up. No stdout return value - earlier
# versions used `farm_urlid=$(seed_ldp_one "$org")` which swallowed every
# log line into the captured subshell and made the script look frozen.
seed_ldp_one() {
  local org="$1"
  local pkg="${ORG_LDP_PACKAGES[$org]}"
  local org_display
  org_display=$(org_display_name "$org")

  wait_for_ldp_backend "$org"

  log "Seeding LDP fixtures on $org (package: $pkg)"

  # Idempotent get_or_create so re-running doesn't pile up rows. Three
  # FARM_URLID / PLOT_URLID / METRIC_URLID prefixes keep Django banners
  # out of the captured values and let each asset target a distinct
  # protected resource - Farm (V3 directly), Plot (inherits from Farm),
  # Metric (inherits from Plot).
  local py
  py=$(cat <<PY
from ${pkg}.models import Farm, Plot, Metric
farm, _ = Farm.objects.get_or_create(name="${org_display} demo farm")
plot, _ = Plot.objects.get_or_create(name="${org_display} demo plot", farm=farm, defaults={"latitude": 0.0, "longitude": 0.0})
metric, _ = Metric.objects.get_or_create(plot=plot, metric_type="soc-stock", year=2024, defaults={"value": 42.0})
print("FARM_URLID:" + farm.urlid)
print("PLOT_URLID:" + plot.urlid)
print("METRIC_URLID:" + metric.urlid)
PY
)
  local out
  out=$(ldp_shell "$org" "$py" 2>&1) || {
    err "  shell -c failed for $org. Container output:"
    printf '%s\n' "$out" >&2
    die "seed-ldp: could not exec into djangoldp-backend ($org)"
  }

  local farm_urlid plot_urlid metric_urlid
  farm_urlid=$(printf '%s\n' "$out" | grep '^FARM_URLID:'   | tail -n1 | sed 's/^FARM_URLID://'   | tr -d '\r')
  plot_urlid=$(printf '%s\n' "$out" | grep '^PLOT_URLID:'   | tail -n1 | sed 's/^PLOT_URLID://'   | tr -d '\r')
  metric_urlid=$(printf '%s\n' "$out" | grep '^METRIC_URLID:' | tail -n1 | sed 's/^METRIC_URLID://' | tr -d '\r')
  if [[ -z "$farm_urlid" || -z "$plot_urlid" || -z "$metric_urlid" ]]; then
    err "  Missing one or more URLID lines in container output for $org. Full output:"
    printf '%s\n' "$out" >&2
    die "seed-ldp: could not read Farm/Plot/Metric urlids back from $org"
  fi

  # The LDP server mints urlids from BASE_URL=http://localhost:<host-port>/ldp,
  # which is the URL a browser on the host uses. The EDC connector container
  # cannot reach that URL - inside the container "localhost" is the connector
  # itself, not the participant nginx. Rewrite the host-facing prefix to a
  # container-internal one that ALSO matches what django sees via
  # request.build_absolute_uri(). Going via nginx (http://nginx:8080/ldp/...)
  # makes the asset baseUrl carry the /ldp prefix; nginx then strips that prefix
  # before forwarding to djangoldp, so django sees /farms/... and the V3
  # permission's coverage check (requested_url vs asset.baseUrl) never matches.
  # Bypass nginx entirely and target djangoldp-backend directly: the EDC
  # public-api proxy and django then see the SAME URL.
  local host_port="${ORG_PORTS[$org]}"
  local host_prefix="http://localhost:${host_port}/ldp"
  local container_prefix="http://djangoldp-backend:8083"
  farm_urlid="${farm_urlid//${host_prefix}/${container_prefix}}"
  plot_urlid="${plot_urlid//${host_prefix}/${container_prefix}}"
  metric_urlid="${metric_urlid//${host_prefix}/${container_prefix}}"

  ok "  $org Farm:   $farm_urlid"
  ok "  $org Plot:   $plot_urlid"
  ok "  $org Metric: $metric_urlid"

  mkdir -p "$LOCAL_DIR/$org"
  printf '%s\n' "$farm_urlid"   > "$LOCAL_DIR/$org/ldp-farm-urlid.txt"
  printf '%s\n' "$plot_urlid"   > "$LOCAL_DIR/$org/ldp-plot-urlid.txt"
  printf '%s\n' "$metric_urlid" > "$LOCAL_DIR/$org/ldp-metric-urlid.txt"
}

cmd_seed_ldp() {
  cmd_secrets
  for org in "${LOCAL_ORGS[@]}"; do
    seed_ldp_one "$org"
  done
  ok "LDP seeded on all orgs (${LOCAL_ORGS[*]}). Per-org Farm urlid in .glcdi.local/<org>/ldp-farm-urlid.txt"
  log "Next: $0 seed   (Bruno will pick up the urlid via m1_asset_base_url)"
}

cmd_seed() {
  local target="local"
  # Optional CLI overrides - when set, bypass both secrets.env (local) and
  # the staging VM .env fetch in seed_farmos_one. Useful when the operator
  # has provisioned the farmOS consumer out-of-band and wants the seeded
  # asset to carry those exact creds without touching either env file.
  local cli_farmos_cid=""
  local cli_farmos_secret=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) target="${2:-}"; shift 2 || die "--target requires a value" ;;
      --target=*) target="${1#--target=}"; shift ;;
      --farmos-client-id) cli_farmos_cid="${2:-}"; shift 2 || die "--farmos-client-id requires a value" ;;
      --farmos-client-id=*) cli_farmos_cid="${1#--farmos-client-id=}"; shift ;;
      --farmos-client-secret) cli_farmos_secret="${2:-}"; shift 2 || die "--farmos-client-secret requires a value" ;;
      --farmos-client-secret=*) cli_farmos_secret="${1#--farmos-client-secret=}"; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: glcdi.sh seed [--target T] [--farmos-client-id ID] [--farmos-client-secret SECRET]

  --target T              One of: local (default) | caney-fork | point-blue | white-buffalo | all-staging
                          Staging defaults to root@<target>.glcdi.startinblox.com; override via SSH_USER_*/SSH_HOST_* env vars.
  --farmos-client-id ID   Override the farmOS M2M consumer client_id (default: secrets.env locally, VM .env on staging).
  --farmos-client-secret  Override the matching client_secret. Both must be passed together for the override to take effect.
EOF
        return 0 ;;
      *) die "seed: unknown argument: $1" ;;
    esac
  done

  if ! command -v bru >/dev/null 2>&1; then
    die "bru (Bruno CLI) is not installed. Install with: npm install -g @usebruno/cli"
  fi

  if [[ -n "$cli_farmos_cid" && -z "$cli_farmos_secret" ]] || [[ -z "$cli_farmos_cid" && -n "$cli_farmos_secret" ]]; then
    die "--farmos-client-id and --farmos-client-secret must be passed together (got only one)."
  fi

  if [[ "$target" == "local" ]]; then
    cmd_secrets
    for org in "${LOCAL_ORGS[@]}"; do
      local port="${ORG_PORTS[$org]}"
      local org_upper
      org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
      local api_key_var="${org_upper}_API_KEY"
      seed_one "$org" "http://localhost:${port}" "${!api_key_var}" "local"
      # farmOS extension only attaches to caney-fork, only when explicitly
      # enabled. Skipping for the other orgs keeps the seed unchanged for
      # operators who never opt into farmOS.
      if [[ "$FARMOS_ENABLED" == "1" && "$org" == "caney-fork" ]]; then
        seed_farmos_one "$org" "http://localhost:${port}" "${!api_key_var}" "local" "$cli_farmos_cid" "$cli_farmos_secret"
      fi
    done
    ok "M1 fixtures seeded on all local orgs (${LOCAL_ORGS[*]})"
    return 0
  fi

  local targets=()
  mapfile -t targets < <(expand_target "$target")
  for t in "${targets[@]}"; do
    local host
    host=$(target_host "$t")
    local key
    key=$(fetch_staging_api_key "$t")
    seed_one "$t" "$host" "$key" "$(target_bruno_env "$t")"
    if [[ "$FARMOS_ENABLED" == "1" && "$t" == "caney-fork" ]]; then
      seed_farmos_one "$t" "$host" "$key" "$(target_bruno_env "$t")" "$cli_farmos_cid" "$cli_farmos_secret"
    fi
  done
  ok "M1 fixtures seeded on staging targets: ${targets[*]}"
}

# Build the --env-var flags `bru run` needs to populate secret env vars
# (Bruno's vars:secret declarations are empty by default; the CLI reads
# values from --env-var flags or the Bruno UI's secret store).
#
# Echoes the flags as one line - caller does:
#   bru run --env local $(bruno_env_flags) ...
bruno_env_flags() {
  printf -- '--env-var caney_fork_api_key=%s ' "${CANEY_FORK_API_KEY:-}"
  printf -- '--env-var point_blue_api_key=%s ' "${POINT_BLUE_API_KEY:-}"
  printf -- '--env-var white_buffalo_api_key=%s ' "${WHITE_BUFFALO_API_KEY:-}"
  printf -- '--env-var caney_fork_client_secret=%s ' "${CANEY_FORK_CONNECTOR_SECRET:-}"
  printf -- '--env-var point_blue_client_secret=%s ' "${POINT_BLUE_CONNECTOR_SECRET:-}"
  printf -- '--env-var white_buffalo_client_secret=%s ' "${WHITE_BUFFALO_CONNECTOR_SECRET:-}"
  # farmOS OAuth2 client used by 13-provider-seeding-caney-fork-farmos/.
  # Values come from .glcdi.local/secrets.env (see cmd_secrets). Empty unless
  # the operator filled them in; the seed step that needs them will simply
  # post an asset whose oauth2:clientSecret is blank, and the decorator's
  # null-guard turns it into a no-op rather than a hard failure.
  printf -- '--env-var farmos_animal_client_id=%s ' "${FARMOS_ANIMAL_CLIENT_ID:-}"
  printf -- '--env-var farmos_animal_client_secret=%s ' "${FARMOS_ANIMAL_CLIENT_SECRET:-}"
}

# -----------------------------------------------------------------------------
# Wipe seeded fixtures from a connector
# -----------------------------------------------------------------------------
#
# Deletion order is load-bearing: contract-definitions reference policies +
# assets, so they go first; policies are referenced by contract-defs only, so
# they go next; assets go last.
#
# Defaults to dry-run - prints the curl commands + IDs that would be deleted.
# Pass --no-dry-run to actually issue DELETEs.

wipe_one() {
  local org="$1"
  local host="$2"
  local api_key="$3"
  local dry_run="$4"

  log "Wiping $org ($host)  dry-run=${dry_run}"

  local resource
  for resource in contractdefinitions policydefinitions assets; do
    local list_url="${host}/management/v3/${resource}/request"
    local body='{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}'

    local ids_json
    ids_json=$(curl -fsSL --max-time 15 \
                 -X POST "$list_url" \
                 -H 'Content-Type: application/json' \
                 -H "X-Api-Key: ${api_key}" \
                 -d "$body") || die "List $resource failed against $host"

    local ids=()
    mapfile -t ids < <(printf '%s' "$ids_json" | jq -r '.[]["@id"]')

    if [[ ${#ids[@]} -eq 0 ]]; then
      log "  $resource: nothing to delete"
      continue
    fi

    log "  $resource: ${#ids[@]} item(s)"
    local id
    for id in "${ids[@]}"; do
      local del_url="${host}/management/v3/${resource}/${id}"
      if [[ "$dry_run" == "true" ]]; then
        printf '    [dry-run] curl -X DELETE -H "X-Api-Key: ***" %q\n' "$del_url"
      else
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
                 -X DELETE "$del_url" \
                 -H "X-Api-Key: ${api_key}" || echo "000")
        if [[ "$code" =~ ^2 ]]; then
          ok "    deleted $resource/$id"
        else
          warn "    DELETE $resource/$id → $code"
        fi
      fi
    done
  done
}

cmd_wipe() {
  local target="local"
  local dry_run="true"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) target="${2:-}"; shift 2 || die "--target requires a value" ;;
      --target=*) target="${1#--target=}"; shift ;;
      --no-dry-run) dry_run="false"; shift ;;
      --dry-run) dry_run="true"; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: glcdi.sh wipe [--target T] [--no-dry-run]

  --target T     One of: local (default) | caney-fork | point-blue | white-buffalo | all-staging
                 Staging defaults to root@<target>.glcdi.startinblox.com; override via SSH_USER_*/SSH_HOST_* env vars.
  --no-dry-run   Actually issue DELETEs. Default is dry-run (print the commands + IDs only).

Deletes in order: contract-definitions → policy-definitions → assets.
EOF
        return 0 ;;
      *) die "wipe: unknown argument: $1" ;;
    esac
  done

  if [[ "$target" == "local" ]]; then
    cmd_secrets
    for org in "${LOCAL_ORGS[@]}"; do
      local port="${ORG_PORTS[$org]}"
      local org_upper
      org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
      local api_key_var="${org_upper}_API_KEY"
      wipe_one "$org" "http://localhost:${port}" "${!api_key_var}" "$dry_run"
    done
    if [[ "$dry_run" == "true" ]]; then
      warn "Dry-run only - re-run with --no-dry-run to actually delete."
    else
      ok "Wipe complete on local orgs (${LOCAL_ORGS[*]})"
    fi
    return 0
  fi

  local targets=()
  mapfile -t targets < <(expand_target "$target")
  for t in "${targets[@]}"; do
    local host
    host=$(target_host "$t")
    local key
    key=$(fetch_staging_api_key "$t")
    wipe_one "$t" "$host" "$key" "$dry_run"
  done
  if [[ "$dry_run" == "true" ]]; then
    warn "Dry-run only - re-run with --no-dry-run to actually delete."
  else
    ok "Wipe complete on staging targets: ${targets[*]}"
  fi
}

# -----------------------------------------------------------------------------
# Run Bruno test collection
# -----------------------------------------------------------------------------

cmd_test() {
  local tier="${1:-$TIER}"
  if ! command -v bru >/dev/null 2>&1; then
    die "bru (Bruno CLI) is not installed. Install with: npm install -g @usebruno/cli"
  fi
  cmd_secrets

  # Verification folders only - exclude seeders (10/12/13) and the destructive 09-wipe.
  local pre_folders=(00-auth 20-catalog-discovery 30-negotiation)
  local post_folders=(99-negative-auth)

  log "Running Bruno tests (tier=$tier)"
  for folder in "${pre_folders[@]}"; do
    # shellcheck disable=SC2046
    ( cd "$BRUNO_DIR" \
      && bru run "$folder" --env local --env-var "tier=$tier" $(bruno_env_flags) \
    ) || die "Bruno folder $folder failed - see output above"
  done

  # 30→40 bridge: Bruno bru-files can't carry env vars across `bru run` processes,
  # and 30-negotiation/01 sends a synthetic offer @id that EDC rejects. Do a real
  # catalog→negotiate→finalize roundtrip here and inject the agreement id into 40-transfer.
  local agreement_id
  agreement_id=$(m1_negotiate_bridge) || die "M1 negotiation bridge failed - see logs above"
  ok "M1 contract agreement: $agreement_id"

  # shellcheck disable=SC2046
  ( cd "$BRUNO_DIR" \
    && bru run 40-transfer --env local --env-var "tier=$tier" \
       --env-var "m1_contract_agreement_id=$agreement_id" \
       $(bruno_env_flags) \
  ) || die "Bruno folder 40-transfer failed - see output above"

  for folder in "${post_folders[@]}"; do
    # shellcheck disable=SC2046
    ( cd "$BRUNO_DIR" \
      && bru run "$folder" --env local --env-var "tier=$tier" $(bruno_env_flags) \
    ) || die "Bruno folder $folder failed - see output above"
  done

  ok "Bruno run green at $tier"
}

# Drive a real white-buffalo→caney-fork M1 negotiation (InternalAnalysis purpose) using the
# catalog-discovered offer verbatim. Polls until FINALIZED; echoes contractAgreementId on stdout.
m1_negotiate_bridge() {
  local asset='urn:glcdi:asset:caney-fork:grazing-soc-2024'
  local wb="http://localhost:${ORG_PORTS[white-buffalo]}"
  local cf_dsp="http://host.docker.internal:${ORG_PORTS[caney-fork]}/protocol"
  local cf_pid="glcdi-connector-caney-fork"
  local api_key="${WHITE_BUFFALO_API_KEY:-}"
  [[ -z "$api_key" ]] && { log "  WHITE_BUFFALO_API_KEY missing" >&2; return 1; }

  log "  catalog query: white-buffalo → caney-fork" >&2
  local cat_body
  cat_body=$(jq -nc --arg dsp "$cf_dsp" --arg pid "$cf_pid" \
    '{ "@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"CatalogRequest",
       counterPartyAddress:$dsp, counterPartyId:$pid,
       protocol:"dataspace-protocol-http", querySpec:{offset:0,limit:200} }')
  local cat
  cat=$(curl -fsS -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $api_key" \
    "$wb/management/v3/catalog/request" -d "$cat_body") \
    || { log "  catalog query failed" >&2; return 1; }

  local offer
  offer=$(printf '%s' "$cat" | jq --arg a "$asset" '
    (."dcat:dataset" | (if type=="array" then . else [.] end))
    | map(select(."@id" == $a)) | first | ."odrl:hasPolicy"
    | (if type=="array" then . else [.] end)
    | map(select(
        (."odrl:permission" | (if type=="array" then . else [.] end))
        | map(."odrl:constraint" | (if type=="array" then . else [.] end))
        | flatten | map(."odrl:rightOperand") | any(. == "glcdi:InternalAnalysis")
      )) | first')
  [[ -z "$offer" || "$offer" == "null" ]] && { log "  no InternalAnalysis offer for $asset in catalog" >&2; return 1; }

  log "  POST negotiation" >&2
  local cr_body neg_id
  cr_body=$(jq -nc --arg dsp "$cf_dsp" --arg pid "$cf_pid" --arg a "$asset" --argjson o "$offer" \
    '{ "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/","odrl":"http://www.w3.org/ns/odrl/2/","glcdi":"https://w3id.org/glcdi/v0.1.0/ns/"},
       "@type":"ContractRequest", counterPartyAddress:$dsp, protocol:"dataspace-protocol-http",
       policy: ($o + { "@type":"odrl:Offer", "odrl:assigner": {"@id":$pid}, "odrl:target": {"@id":$a} }) }')
  neg_id=$(curl -fsS -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $api_key" \
    "$wb/management/v3/contractnegotiations" -d "$cr_body" | jq -r '."@id" // empty')
  [[ -z "$neg_id" ]] && { log "  negotiation POST returned no id" >&2; return 1; }
  log "  negotiation $neg_id - polling for FINALIZED" >&2

  local state agreement_id body
  for _ in $(seq 1 30); do
    body=$(curl -fsS -H "X-Api-Key: $api_key" "$wb/management/v3/contractnegotiations/$neg_id" 2>/dev/null) || { sleep 2; continue; }
    state=$(printf '%s' "$body" | jq -r '.state // empty')
    if [[ "$state" == "FINALIZED" ]]; then
      agreement_id=$(printf '%s' "$body" | jq -r '.contractAgreementId // empty')
      break
    fi
    if [[ "$state" == "TERMINATED" ]]; then
      log "  negotiation TERMINATED: $(printf '%s' "$body" | jq -r '.errorDetail // "(no detail)"')" >&2
      return 1
    fi
    sleep 2
  done
  [[ -z "$agreement_id" ]] && { log "  negotiation did not FINALIZE within 60s (last state: $state)" >&2; return 1; }
  printf '%s' "$agreement_id"
}

# Print the exact `bru run` invocation a user would need to run by hand.
# Useful when iterating on a single .bru file from the Bruno dir.
cmd_print_bruno_cmd() {
  cmd_secrets
  local tier="${1:-$TIER}"
  printf 'cd %q\n' "$BRUNO_DIR"
  # shellcheck disable=SC2046
  printf 'bru run --env local --env-var %q %s [folder|file]\n' \
    "tier=$tier" \
    "$(bruno_env_flags)"
}

# -----------------------------------------------------------------------------
# farmOS - one-shot site install inside caney-fork's farmos container
# -----------------------------------------------------------------------------
#
# Runs participant-agent-services/farmos/install.sh inside the caney-fork
# farmos container. Idempotent (re-running after a successful install just
# re-syncs the module list + clears caches), so safe to invoke whenever
# the farmos image or module repo has changed.
cmd_farmos_install() {
  [[ "$FARMOS_ENABLED" == "1" ]] \
    || die "GLCDI_FARMOS=1 not set - farmOS isn't enabled, so there's no container to install into."
  local org_dir="$LOCAL_DIR/caney-fork"
  [[ -f "$org_dir/.env" ]] \
    || die "caney-fork not started yet - run \`$0 up\` first (with GLCDI_FARMOS=1)."
  local container
  container=$(compose_for caney-fork ps -q farmos 2>/dev/null || true)
  [[ -n "$container" ]] \
    || die "farmos container not running. Run \`GLCDI_FARMOS=1 $0 up\` first."
  log "Running farmOS install.sh inside caney-fork's farmos container"
  # --user root: install.sh needs to write composer.json + run drush
  # site:install + chown sites/default/files. The farmos image's default
  # exec UID can't do any of that on the bind-mounted root.
  compose_for caney-fork exec -T --user root \
    -e FARMOS_OAUTH_CLIENT_ID="${FARMOS_ANIMAL_CLIENT_ID:-}" \
    -e FARMOS_OAUTH_CLIENT_SECRET="${FARMOS_ANIMAL_CLIENT_SECRET:-}" \
    farmos bash /opt/drupal/install.sh \
    || die "farmOS install failed - check the container logs: $0 logs caney-fork"
  ok "farmOS ready at http://localhost:8091/admin/api-urls"
}

# -----------------------------------------------------------------------------
# farmOS - end-to-end OAuth2 transfer test
# -----------------------------------------------------------------------------
#
# Thin wrapper around scripts/test-farmos-transfer.sh - passes the same
# secrets.env env vars in scope and forwards any --target etc. arg.
cmd_test_farmos() {
  cmd_secrets
  "$SCRIPT_DIR/test-farmos-transfer.sh" "$@"
}

# -----------------------------------------------------------------------------
# Status / logs / down / reset
# -----------------------------------------------------------------------------

cmd_status() {
  cmd_secrets
  hr
  log "Authority KC"
  curl -fsSL --max-time 3 \
    "http://localhost:${AUTHORITY_KC_PORT}/auth/realms/glcdi/.well-known/openid-configuration" \
    | jq -r '"  issuer: \(.issuer)\n  token_endpoint: \(.token_endpoint)"' \
    2>/dev/null \
    || warn "  Authority KC not reachable on port $AUTHORITY_KC_PORT"

  log "Onboarding"
  local reg_code
  reg_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:${AUTHORITY_ONBOARDING_PORT}/registration/" || echo "000")
  if [[ "$reg_code" =~ ^(200|301|302)$ ]]; then
    ok "  /registration/ → $reg_code"
  else
    warn "  /registration/ → $reg_code (expected 200/301/302)"
  fi
  local gov_token_code
  gov_token_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    -X POST "http://localhost:${AUTHORITY_KC_PORT}/auth/realms/glcdi/protocol/openid-connect/token" \
    -d "grant_type=client_credentials&client_id=governance&client_secret=${GOVERNANCE_CLIENT_SECRET}" \
    || echo "000")
  if [[ "$gov_token_code" == "200" ]]; then
    ok "  governance client_credentials → 200 (realm-admin token mintable)"
  else
    warn "  governance client_credentials → $gov_token_code (expected 200)"
  fi

  for org in "${LOCAL_ORGS[@]}"; do
    local port="${ORG_PORTS[$org]}"
    local org_upper
    org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
    local api_key_var="${org_upper}_API_KEY"
    log "$org (port $port)"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
      -X POST "http://localhost:${port}/management/v3/assets/request" \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${!api_key_var}" \
      -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}' \
      || echo "000")
    if [[ "$status" == "200" ]]; then
      ok "  /management → 200"
    else
      warn "  /management → $status"
    fi
  done
  hr
}

cmd_logs() {
  local svc="${1:-}"
  [[ -z "$svc" ]] && die "Usage: $0 logs <authority|onboarding|caney-fork|point-blue|white-buffalo>"

  if [[ "$svc" == "authority" ]]; then
    ( cd "$AUTHORITY_DIR" && docker compose logs -f --tail=200 )
  elif [[ "$svc" == "onboarding" ]]; then
    ( cd "$AUTHORITY_DIR" && docker compose logs -f --tail=200 onboarding-backend )
  elif [[ -n "${ORG_PORTS[$svc]:-}" ]]; then
    local org_dir="$LOCAL_DIR/$svc"
    [[ -f "$org_dir/.env" ]] || die "Participant $svc not started - no .env at $org_dir"
    ( cd "$PARTICIPANT_DIR" \
      && docker compose \
           --env-file "$org_dir/.env" \
           --profile dev \
           $(farmos_profile_args "$svc") \
           -f docker-compose.yml \
           -f "$org_dir/docker-compose.override.yml" \
           logs -f --tail=200 \
    )
  else
    die "Unknown service: $svc"
  fi
}

cmd_down() {
  log "Bringing down stacks (preserving volumes)"
  for org in "${LOCAL_ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    if [[ -f "$org_dir/.env" ]]; then
      ( cd "$PARTICIPANT_DIR" \
        && docker compose \
             --env-file "$org_dir/.env" \
             --profile dev \
             $(farmos_profile_args "$org") \
             -f docker-compose.yml \
             -f "$org_dir/docker-compose.override.yml" \
             down \
      ) || warn "down failed for $org"
    fi
  done

  if [[ -f "$LOCAL_DIR/authority.env" ]]; then
    ( cd "$AUTHORITY_DIR" \
      && docker compose --env-file "$LOCAL_DIR/authority.env" \
           -f docker-compose.yml \
           -f "$LOCAL_DIR/authority.override.yml" \
           down \
    ) || warn "down failed for authority"
  fi
  ok "Stacks down"
}

cmd_reset() {
  log "RESET - bringing down + removing volumes + deleting $LOCAL_DIR"
  for org in "${LOCAL_ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    if [[ -f "$org_dir/.env" ]]; then
      ( cd "$PARTICIPANT_DIR" \
        && docker compose \
             --env-file "$org_dir/.env" \
             --profile dev \
             $(farmos_profile_args "$org") \
             -f docker-compose.yml \
             -f "$org_dir/docker-compose.override.yml" \
             down -v \
      ) || warn "down -v failed for $org"
    fi
  done

  if [[ -f "$LOCAL_DIR/authority.env" ]]; then
    ( cd "$AUTHORITY_DIR" \
      && docker compose --env-file "$LOCAL_DIR/authority.env" \
           -f docker-compose.yml \
           -f "$LOCAL_DIR/authority.override.yml" \
           down -v --remove-orphans \
    ) || warn "down -v failed for authority (with override)"
  fi

  # Always also issue a base-only down -v across all profiles. Covers:
  # (a) authority.env was wiped previously, the override-aware path above did
  #     nothing, and the named volume + containers from the prior run linger
  #     - the next `up` would then hit a stale password on the keycloak DB.
  # (b) orphan containers from earlier compose versions (e.g. the removed
  #     onboarding-approval service, the now-unused dev nginx) need cleanup.
  ( cd "$AUTHORITY_DIR" \
    && KC_GOVERNANCE_CLIENT_SECRET=stub-for-reset-only docker compose --profile dev --profile prod down -v --remove-orphans \
  ) || warn "base-only down -v failed for authority (likely nothing to do)"

  # On-disk artefacts left behind by onboarding-backend (the file-based mail
  # outbox, uploaded org logos): wipe so the next `up` starts clean.
  rm -rf "$AUTHORITY_DIR/onboarding/mails" "$AUTHORITY_DIR/onboarding/media" 2>/dev/null || true

  rm -rf "$LOCAL_DIR"
  ok "Reset complete. Re-run: $0 up"
}

# -----------------------------------------------------------------------------
# `all` - happy path
# -----------------------------------------------------------------------------

cmd_all() {
  cmd_preflight
  cmd_build
  cmd_up
  # Seed the LDP Farm first so its urlid is on disk before Bruno builds the
  # M1 asset that points at it. Order is load-bearing - see seed-ldp header.
  cmd_seed_ldp
  # Bootstrap farmOS (site install + OAuth2 keys/scope/consumer) before seed,
  # so the asset PUT and the dataplane OAuth2 exchange both find what they need.
  [[ "$FARMOS_ENABLED" == "1" ]] && cmd_farmos_install
  cmd_seed
  cmd_test "$TIER"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

cmd_help() {
  sed -n '/^# glcdi\.sh -/,/^set -euo/p' "${BASH_SOURCE[0]}" \
    | sed -e '1,2d;$d' -e 's/^# \?//'
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    preflight) cmd_preflight ;;
    secrets)   cmd_secrets_show ;;
    build)     cmd_build ;;
    up)        cmd_up ;;
    seed)      cmd_seed "$@" ;;
    seed-ldp)  cmd_seed_ldp ;;
    wipe)      cmd_wipe "$@" ;;
    test)      cmd_test "${1:-$TIER}" ;;
    status)    cmd_status ;;
    logs)      cmd_logs "${1:-}" ;;
    down)      cmd_down ;;
    reset)     cmd_reset ;;
    all)       cmd_all ;;
    bruno-cmd) cmd_print_bruno_cmd "${1:-$TIER}" ;;
    farmos-install) cmd_farmos_install ;;
    test-farmos) cmd_test_farmos "$@" ;;
    help|-h|--help) cmd_help ;;
    *)         err "Unknown subcommand: $cmd"; cmd_help; exit 2 ;;
  esac
}

main "$@"
