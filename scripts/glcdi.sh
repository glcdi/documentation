#!/usr/bin/env bash
#
# glcdi.sh — local-stack orchestrator for the GLCDI workspace.
#
# Brings up the Authority Keycloak + 3 participant connectors (caney-fork,
# point-blue, white-buffalo) in the right order with the right config, seeds
# the M1 fixtures, and runs the Bruno collection. Idempotent: re-running
# `up` is safe; `reset` is the destructive nuclear option.
#
# Run from anywhere — paths are resolved relative to the workspace root
# (the directory holding governance-services/, participant-agent-services/,
# edc-connector/, edc-glcdi-extension/, participant-ui/, management/).
#
# Subcommands:
#   preflight   — verify required tools are installed
#   secrets     — generate (once) and print local secrets
#   build       — build edc-connector + participant-ui images
#   up          — bring up authority + 3 participants
#   seed        — seed M1 fixtures via Bruno
#   test [tier] — run the Bruno collection (tier1 default; tier2 anticipated)
#   status      — quick health check on every service
#   logs <svc>  — tail logs for a service (svc = authority|caney-fork|point-blue|white-buffalo)
#   down        — bring down stacks (preserves volumes)
#   reset       — bring down + remove volumes + delete .glcdi.local/
#   all         — preflight + build + up + seed + test (the happy path)
#   help        — show this list
#
# Config: GLCDI_TIER (default tier1) — switches Bruno test mode.
# Working dir: ./.glcdi.local/ (gitignored) holds rotated secrets + per-org configs.

set -euo pipefail

# -----------------------------------------------------------------------------
# Resolve paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The script lives in management/scripts/. The workspace root is two levels up.
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCAL_DIR="$SCRIPT_DIR/.glcdi.local"
SECRETS_FILE="$LOCAL_DIR/secrets.env"

# The governance-services dir is renamed to authority-services in the in-flight
# AUTHORITY_MIGRATION.md cutover. Support both — the local script picks whichever
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
BRUNO_DIR="$WORKSPACE_ROOT/management/bruno"

# Participants (M1 trio).
ORGS=(caney-fork point-blue white-buffalo)
declare -A ORG_PORTS=(
  [caney-fork]=8080
  [point-blue]=8081
  [white-buffalo]=8082
)
declare -A ORG_TYPES=(
  [caney-fork]=regenerative-producer
  [point-blue]=researcher
  [white-buffalo]=regenerative-producer
)

AUTHORITY_KC_PORT=8090
TIER="${GLCDI_TIER:-tier1}"

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

  # Bruno CLI is optional — only needed for `test`.
  if command -v bru >/dev/null 2>&1; then
    ok "bru (Bruno CLI) found — $(bru --version 2>/dev/null | head -1 || echo 'unknown version')"
  else
    warn "bru (Bruno CLI) not installed — \`test\` subcommand will be unavailable. Install with: npm install -g @usebruno/cli"
  fi

  if [[ -z "$AUTHORITY_DIR" ]]; then
    die "Neither $WORKSPACE_ROOT/authority-services nor governance-services exists. Are you in the right workspace?"
  fi

  for d in "$PARTICIPANT_DIR" "$EDC_CONNECTOR_DIR" "$EDC_EXTENSION_DIR" "$PARTICIPANT_UI_DIR" "$BRUNO_DIR"; do
    if [[ ! -d "$d" ]]; then
      die "Expected directory missing: $d"
    fi
  done

  # Port availability — warn only (some users intentionally remap).
  for port in "$AUTHORITY_KC_PORT" "${ORG_PORTS[@]}"; do
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"; then
      warn "Port $port appears already in use — local stack will fail to bind."
    fi
  done

  ok "Preflight OK"
  log "Workspace root: $WORKSPACE_ROOT"
  log "Authority dir:  $AUTHORITY_DIR"
  log "Local dir:      $LOCAL_DIR"
  log "Tier:           $TIER"
}

# -----------------------------------------------------------------------------
# Secrets — generate once, reuse on subsequent runs
# -----------------------------------------------------------------------------

cmd_secrets() {
  mkdir -p "$LOCAL_DIR"

  if [[ -f "$SECRETS_FILE" ]]; then
    log "Reusing existing secrets at $SECRETS_FILE"
  else
    log "Generating local secrets at $SECRETS_FILE"
    {
      echo "# GLCDI local-stack secrets — generated $(date -Iseconds)"
      echo "# Regenerate with: rm $SECRETS_FILE && $0 secrets"
      echo
      echo "KC_ADMIN_PASSWORD=$(openssl rand -hex 16)"
      echo "DJANGO_SECRET_KEY=$(openssl rand -hex 32)"
      echo "GOVERNANCE_CLIENT_SECRET=$(openssl rand -hex 32)"
      echo "GLCDI_UI_CLIENT_SECRET=$(openssl rand -hex 32)"
      echo
      for org in "${ORGS[@]}"; do
        local upper
        upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
        echo "${upper}_API_KEY=$(openssl rand -hex 32)"
        echo "${upper}_CONNECTOR_SECRET=$(openssl rand -hex 32)"
        echo "${upper}_DB_PASSWORD=$(openssl rand -hex 16)"
      done
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
# Realm JSON patching — replace `changeme-*` secrets with rotated values
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
     '
     .clients |= map(
       if .clientId == "glcdi-connector-caney-fork" then .secret = $cf
       elif .clientId == "glcdi-connector-point-blue" then .secret = $pb
       elif .clientId == "glcdi-connector-white-buffalo" then .secret = $wb
       elif .clientId == "glcdi-ui" and (.publicClient // false) == false then .secret = $ui
       else . end
     )
     ' "$source_realm" > "$target"
  ok "Realm JSON patched"
}

# -----------------------------------------------------------------------------
# Authority Keycloak — bring up
# -----------------------------------------------------------------------------

up_authority() {
  log "Bringing up Authority Keycloak"
  cmd_secrets
  patch_realm_json

  # Run init-secrets.sh if it exists (creates secrets/* from templates).
  if [[ -x "$AUTHORITY_DIR/init-secrets.sh" ]]; then
    ( cd "$AUTHORITY_DIR" && ./init-secrets.sh ) >/dev/null
  fi

  # Stage a per-run .env with our rotated values.
  local authority_env="$LOCAL_DIR/authority.env"
  cat > "$authority_env" <<EOF
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
KEYCLOAK_BASE_URL=http://localhost:${AUTHORITY_KC_PORT}
KEYCLOAK_REALM=glcdi
KEYCLOAK_CLIENT_ID=governance
KEYCLOAK_CLIENT_SECRET=${GOVERNANCE_CLIENT_SECRET}
KC_START_MODE=start-dev
KC_HOSTNAME=http://localhost:${AUTHORITY_KC_PORT}/auth
KC_BACKCHANNEL_DYNAMIC=false
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD}
EOF

  # Override file: bind-mounts the patched realm JSON over the in-repo one,
  # remaps the KC port, and pins the admin password from .env.
  local override="$LOCAL_DIR/authority.override.yml"
  cat > "$override" <<EOF
# Auto-generated by glcdi.sh — do not edit by hand.
services:
  keycloak:
    ports:
      - "${AUTHORITY_KC_PORT}:8080"
    volumes:
      - ${LOCAL_DIR}/glcdi-realm.json:/opt/keycloak/data/import/glcdi-realm.json:ro
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: \${KEYCLOAK_ADMIN_PASSWORD}
EOF

  ( cd "$AUTHORITY_DIR" \
    && docker compose --env-file "$authority_env" -f docker-compose.yml -f "$override" up -d \
  ) || die "docker compose up failed for Authority Keycloak"

  wait_for_authority
  ok "Authority Keycloak running at http://localhost:${AUTHORITY_KC_PORT}/auth"
  ok "Admin: admin / ${KC_ADMIN_PASSWORD}"
}

wait_for_authority() {
  local url="http://localhost:${AUTHORITY_KC_PORT}/auth/realms/glcdi/.well-known/openid-configuration"
  log "Waiting for Authority KC to import realm and serve OIDC discovery"
  local i
  for i in {1..60}; do
    if curl -fsSL --max-time 2 "$url" >/dev/null 2>&1; then
      ok "Authority KC ready (after ~${i}s)"
      return 0
    fi
    sleep 1
  done
  die "Authority KC did not become ready within 60s. Check: docker compose -f $AUTHORITY_DIR/docker-compose.yml logs keycloak"
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
  for org in "${ORGS[@]}"; do
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

    # .env — consumed by docker compose and the catalogue-ui image entrypoint.
    cat > "$org_dir/.env" <<EOF
PARTICIPANT_NAME=$org
PARTICIPANT_ID=$org
EDC_API_KEY=$api_key
CONNECTOR_DB_PASSWORD=$db_pass

AUTHORITY_KEYCLOAK_URL=http://host.docker.internal:${AUTHORITY_KC_PORT}
KEYCLOAK_REALM=glcdi

# Tier-1 default: no Bearer flow at the UI; oauth2-proxy is in compose but
# the UI doesn't authenticate against it. The OIDC vars are populated for
# Tier-2 forward-compat (\$GLCDI_TIER=tier2), inert at Tier 1.
OIDC_CLIENT_ID=glcdi-ui
GLCDI_UI_CLIENT_SECRET=$GLCDI_UI_CLIENT_SECRET
KC_IDP_HINT=

# Connector self-auth: client_credentials against Authority KC.
EDC_OAUTH_CLIENT_ID=glcdi-connector-$org
EDC_OAUTH_CLIENT_SECRET=$connector_secret

PARTICIPANT_CONNECTOR_URI=http://localhost:${nginx_port}
PARTICIPANT_DOMAIN=localhost
NGINX_PORT=$nginx_port
IDH_LOG_LEVEL=INFO

OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -hex 16)
OAUTH2_PROXY_REDIRECT_URL=http://localhost:${nginx_port}/oauth2/callback
OAUTH2_PROXY_COOKIE_DOMAIN=localhost

APP_TITLE=$(echo "$org" | sed 's/.*/\u&/' | tr - ' ') - GLCDI
PRIMARY_COLOR=#2E7D32
SECONDARY_COLOR=#1B5E20
ACCENT_COLOR=#66BB6A

DSP_PROVIDERS=$(other_dsp_providers_json "$org")
EOF

    # Per-org configuration.properties — patched from the example.
    sed -e "s|web.http.management.auth.key=.*|web.http.management.auth.key=$api_key|" \
        -e "s|edc.api.auth.key=.*|edc.api.auth.key=$api_key|" \
        -e "s|edc.api.control.auth.apikey.value=.*|edc.api.control.auth.apikey.value=$api_key|" \
        -e "s|edc.dsp.callback.address=.*|edc.dsp.callback.address=http://host.docker.internal:${nginx_port}/protocol|" \
        -e "s|edc.participant.id=.*|edc.participant.id=did:web:host.docker.internal%3A${nginx_port}|" \
        -e "s|edc.iam.issuer.id=.*|edc.iam.issuer.id=did:web:host.docker.internal%3A${nginx_port}|" \
        -e "s|edc.iam.sts.oauth.client.id=.*|edc.iam.sts.oauth.client.id=did:web:host.docker.internal%3A${nginx_port}|" \
        "$PARTICIPANT_DIR/participant/configuration.properties.example" \
        > "$org_dir/participant/configuration.properties"

    # idh-configuration.properties — copy if example exists.
    if [[ -f "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" ]]; then
      cp "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" \
         "$org_dir/participant/idh-configuration.properties"
    fi

    # Override file — re-binds the connector's config volume to this org's dir.
    cat > "$org_dir/docker-compose.override.yml" <<EOF
# Auto-generated by glcdi.sh — do not edit by hand.
services:
  edc-connector:
    volumes:
      - ${org_dir}/participant:/app/conf:ro
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
  for org in "${ORGS[@]}"; do
    [[ "$org" == "$me" ]] && continue
    [[ $first -eq 1 ]] || out+=","
    first=0
    local port="${ORG_PORTS[$org]}"
    local nice
    nice=$(echo "$org" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')
    out+="{\"name\":\"$nice\",\"address\":\"http://host.docker.internal:${port}/protocol\",\"color\":\"#1565C0\",\"participantId\":\"$org\"}"
  done
  out+="]"
  printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# Per-participant compose up
# -----------------------------------------------------------------------------

up_participants() {
  write_participant_configs

  for org in "${ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    log "Bringing up participant: $org"
    ( cd "$PARTICIPANT_DIR" \
      && docker compose \
           --env-file "$org_dir/.env" \
           -f docker-compose.yml \
           -f "$org_dir/docker-compose.override.yml" \
           up -d \
    ) || die "docker compose up failed for $org"
  done

  for org in "${ORGS[@]}"; do
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
  for i in {1..60}; do
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
  warn "$org did not respond 200 within 60s (last status: ${status:-unknown}). Check: $0 logs $org"
}

cmd_up() {
  cmd_preflight
  up_authority
  up_participants
  hr
  ok "Stack up. Endpoints:"
  printf '  Authority KC: http://localhost:%s/auth/admin (admin / from secrets)\n' "$AUTHORITY_KC_PORT"
  for org in "${ORGS[@]}"; do
    printf '  %-15s http://localhost:%s/  (UI)  +  /management/* with X-Api-Key\n' "$org" "${ORG_PORTS[$org]}"
  done
  hr
  log "Next: $0 seed   then   $0 test"
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
    warn "scripts/sync-glcdi-extensions.sh not found — skipping extension sync"
  fi

  if [[ -x "$EDC_CONNECTOR_DIR/gradlew" ]]; then
    ( cd "$EDC_CONNECTOR_DIR" && ./gradlew :runtimes:controlplane:dockerize ) \
      || die "Gradle build failed"
    ok "edc-connector image built"
  else
    warn "$EDC_CONNECTOR_DIR/gradlew not found — bootstrap with: gradle wrapper, then re-run"
  fi

  log "Building participant-ui image"
  if [[ -f "$PARTICIPANT_UI_DIR/Dockerfile" ]]; then
    ( cd "$PARTICIPANT_UI_DIR" && docker build -t glcdi-participant-ui:local . ) \
      || die "participant-ui build failed"
    ok "participant-ui image built"
  else
    warn "$PARTICIPANT_UI_DIR/Dockerfile not found — UI image not built"
  fi
}

# -----------------------------------------------------------------------------
# Seed M1 fixtures via Bruno
# -----------------------------------------------------------------------------

cmd_seed() {
  cmd_secrets
  if ! command -v bru >/dev/null 2>&1; then
    warn "bru not installed — falling back to manual curl-based seeding"
    seed_via_curl
    return
  fi

  populate_bruno_env
  log "Seeding M1 fixtures via Bruno (10-provider-seeding/)"
  ( cd "$BRUNO_DIR" && bru run 10-provider-seeding --env local ) \
    || die "Bruno seeding folder failed — see output above"
  ok "M1 fixtures seeded on caney-fork"
}

# Push generated secrets into Bruno's `local` env so test runs use them.
# Bruno stores secrets per-user outside the repo, but for local automation
# we accept that the script writes them into a separate sidecar file the
# user can also load manually. The collection's environments/local.bru
# carries declarations only; values come from this file or Bruno's UI.
populate_bruno_env() {
  local secrets_target="$BRUNO_DIR/environments/.local.secrets.env"
  cat > "$secrets_target" <<EOF
# Auto-generated by glcdi.sh. Do not commit.
caney_fork_api_key=$CANEY_FORK_API_KEY
point_blue_api_key=$POINT_BLUE_API_KEY
white_buffalo_api_key=$WHITE_BUFFALO_API_KEY
caney_fork_client_secret=$CANEY_FORK_CONNECTOR_SECRET
point_blue_client_secret=$POINT_BLUE_CONNECTOR_SECRET
white_buffalo_client_secret=$WHITE_BUFFALO_CONNECTOR_SECRET
EOF
  chmod 600 "$secrets_target"
  ok "Wrote Bruno secrets sidecar: $secrets_target"
  warn "If Bruno's CLI doesn't pick this up, paste these values into the Bruno UI's environments/local.bru secret panel."
}

seed_via_curl() {
  local host="http://localhost:${ORG_PORTS[caney-fork]}"
  local key="$CANEY_FORK_API_KEY"
  log "Seeding asset, policies, contract def via curl against $host"
  warn "Phase 4 seeding scripts are not in place yet — this curl-fallback is a stub."
  warn "Run 'bru run 10-provider-seeding --env local' after installing the Bruno CLI for the real seeding path."
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
  populate_bruno_env

  log "Running Bruno collection (tier=$tier)"
  ( cd "$BRUNO_DIR" \
    && bru run --env local --env-var "tier=$tier" \
  ) \
    && ok "Bruno run green at $tier" \
    || die "Bruno run failed — see output above"
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

  for org in "${ORGS[@]}"; do
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
  [[ -z "$svc" ]] && die "Usage: $0 logs <authority|caney-fork|point-blue|white-buffalo>"

  if [[ "$svc" == "authority" ]]; then
    ( cd "$AUTHORITY_DIR" && docker compose logs -f --tail=200 )
  elif [[ -n "${ORG_PORTS[$svc]:-}" ]]; then
    local org_dir="$LOCAL_DIR/$svc"
    [[ -f "$org_dir/.env" ]] || die "Participant $svc not started — no .env at $org_dir"
    ( cd "$PARTICIPANT_DIR" \
      && docker compose \
           --env-file "$org_dir/.env" \
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
  for org in "${ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    if [[ -f "$org_dir/.env" ]]; then
      ( cd "$PARTICIPANT_DIR" \
        && docker compose \
             --env-file "$org_dir/.env" \
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
  log "RESET — bringing down + removing volumes + deleting $LOCAL_DIR"
  for org in "${ORGS[@]}"; do
    local org_dir="$LOCAL_DIR/$org"
    if [[ -f "$org_dir/.env" ]]; then
      ( cd "$PARTICIPANT_DIR" \
        && docker compose \
             --env-file "$org_dir/.env" \
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
           down -v \
    ) || warn "down -v failed for authority"
  fi

  rm -rf "$LOCAL_DIR"
  ok "Reset complete. Re-run: $0 up"
}

# -----------------------------------------------------------------------------
# `all` — happy path
# -----------------------------------------------------------------------------

cmd_all() {
  cmd_preflight
  cmd_build
  cmd_up
  cmd_seed
  cmd_test "$TIER"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

cmd_help() {
  sed -n '/^# glcdi\.sh —/,/^set -euo/p' "${BASH_SOURCE[0]}" \
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
    seed)      cmd_seed ;;
    test)      cmd_test "${1:-$TIER}" ;;
    status)    cmd_status ;;
    logs)      cmd_logs "${1:-}" ;;
    down)      cmd_down ;;
    reset)     cmd_reset ;;
    all)       cmd_all ;;
    help|-h|--help) cmd_help ;;
    *)         err "Unknown subcommand: $cmd"; cmd_help; exit 2 ;;
  esac
}

main "$@"
