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
#   bruno-cmd   — print the `bru run` command line (with secrets baked in)
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
      echo "KC_DB_PASSWORD=$(openssl rand -hex 16)"
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

  # init-secrets.sh skips files that already exist — so on re-runs the
  # populated files would keep their first-run substituted values while
  # secrets.env carries the rotated current values. We bypass it entirely
  # and re-copy from the .template files ourselves on every up.
  substitute_authority_secrets

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
  #
  # `ports: !override` REPLACES the in-repo `ports` list instead of merging
  # with it. Without this, the in-repo `8080:8080` mapping stays AND our
  # `8090:8080` is appended — KC ends up on both ports and we hog the
  # caney-fork nginx port.
  local override="$LOCAL_DIR/authority.override.yml"
  cat > "$override" <<EOF
# Auto-generated by glcdi.sh — do not edit by hand.
services:
  keycloak:
    ports: !override
      - "${AUTHORITY_KC_PORT}:8080"
    volumes:
      - ${LOCAL_DIR}/glcdi-realm.json:/opt/keycloak/data/import/glcdi-realm.json:ro
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: \${KEYCLOAK_ADMIN_PASSWORD}
      # Cap JVM heap. JAVA_TOOL_OPTIONS is read by every JVM regardless of
      # how the image's entrypoint is written. KC needs ~512MB headroom for
      # realm import + admin console; bump to 1024m if tight.
      JAVA_TOOL_OPTIONS: "-Xmx768m -Xms128m -XX:MaxMetaspaceSize=256m"
EOF

  ( cd "$AUTHORITY_DIR" \
    && docker compose --env-file "$authority_env" -f docker-compose.yml -f "$override" up -d \
  ) || die "docker compose up failed for Authority Keycloak"

  wait_for_authority
  ok "Authority Keycloak running at http://localhost:${AUTHORITY_KC_PORT}/auth"
  ok "Admin: admin / ${KC_ADMIN_PASSWORD}"
}

# Substitutes {{POSTGRES_USER}}, {{POSTGRES_PASSWORD}}, {{KC_DB_USERNAME}},
# {{KC_DB_PASSWORD}}, {{KC_ADMIN_USERNAME}}, {{KC_BOOTSTRAP_ADMIN_PASSWORD}}
# in the secret files written by init-secrets.sh. Idempotent — re-running on
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
      warn "Template missing — skipping: $template"
      continue
    fi
    # Always re-copy from .template, then substitute. This is what fixes the
    # "first-run password sticks across resets" bug — the populated file
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

  # Sanity-check leftovers — only the populated files matter; .template
  # originals are expected to keep their {{...}} markers.
  local leftover
  leftover=$(grep -rE '\{\{[A-Z_]+\}\}' "$AUTHORITY_DIR/secrets" \
               --exclude='*.template' 2>/dev/null || true)
  if [[ -n "$leftover" ]]; then
    warn "Unsubstituted placeholders remain in populated secrets — KC may fail to start:"
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
    # Tier 1 (IMPLEM_PLAN.md § 1.5): X-Api-Key only on the UI, connector
    # client_credentials against Authority KC for DSP. No OIDC envvars at
    # this tier — they (KEYCLOAK_URL / OIDC_CLIENT_ID / KC_IDP_HINT /
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

# Local-package iteration (mirrors TEMS catalogue-ui pattern):
# Set GLCDI_USE_LOCAL_PACKAGES=true on the glcdi.sh invocation to toggle
# the catalogue-ui's npm[] paths from jsdelivr to localhost Vite dev-server
# URLs. Defaults to false — production-style CDN loading.
USE_LOCAL_PACKAGES=${GLCDI_USE_LOCAL_PACKAGES:-false}
SIB_CORE_PATH=${GLCDI_SIB_CORE_PATH:-}
SOLID_TEMS_UI_PATH=${GLCDI_SOLID_TEMS_UI_PATH:-}
SOLID_TEMS_PATH=${GLCDI_SOLID_TEMS_PATH:-}
GLCDI_PATH=${GLCDI_PKG_PATH:-}

APP_TITLE=$(echo "$org" | sed 's/.*/\u&/' | tr - ' ') - GLCDI
PRIMARY_COLOR=#2E7D32
SECONDARY_COLOR=#1B5E20
ACCENT_COLOR=#66BB6A

DSP_PROVIDERS=$(other_dsp_providers_json "$org")
EOF

    # Per-org configuration.properties — patched from the example.
    # The DB triple (url/user/password) must match what the compose's
    # `db-connector` postgres is created with. Compose sets POSTGRES_DB and
    # POSTGRES_USER to ${PARTICIPANT_NAME} and POSTGRES_PASSWORD to
    # ${CONNECTOR_DB_PASSWORD}. The example properties hardcode `participant`
    # for all three — that mismatch is the root cause of "password
    # authentication failed for user participant" on first boot.
    sed -e "s|web.http.management.auth.key=.*|web.http.management.auth.key=$api_key|" \
        -e "s|edc.api.auth.key=.*|edc.api.auth.key=$api_key|" \
        -e "s|edc.api.control.auth.apikey.value=.*|edc.api.control.auth.apikey.value=$api_key|" \
        -e "s|edc.dsp.callback.address=.*|edc.dsp.callback.address=http://host.docker.internal:${nginx_port}/protocol|" \
        -e "s|edc.participant.id=.*|edc.participant.id=glcdi-connector-${org}|" \
        -e "s|glcdi.iam.kc.client.id=.*|glcdi.iam.kc.client.id=glcdi-connector-${org}|" \
        -e "s|glcdi.iam.kc.client.secret=.*|glcdi.iam.kc.client.secret=${connector_secret}|" \
        -e "s|edc.datasource.default.url=.*|edc.datasource.default.url=jdbc:postgresql://db-connector:5432/$org|" \
        -e "s|edc.datasource.default.user=.*|edc.datasource.default.user=$org|" \
        -e "s|edc.datasource.default.password=.*|edc.datasource.default.password=$db_pass|" \
        "$PARTICIPANT_DIR/participant/configuration.properties.example" \
        > "$org_dir/participant/configuration.properties"

    # idh-configuration.properties — copy if example exists.
    if [[ -f "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" ]]; then
      cp "$PARTICIPANT_DIR/participant/idh-configuration.properties.example" \
         "$org_dir/participant/idh-configuration.properties"
    fi

    # Tier-1 nginx config — drops every route that depends on services we
    # disable at this tier (per-participant Keycloak, oauth2-proxy, identity-hub).
    # Adds an /auth/ proxy to the Authority KC on the host (via host.docker.internal,
    # which the nginx container CAN resolve via its extra_hosts entry) so the
    # browser-side UI hits same-origin (localhost:NGINX_PORT/auth/*) instead
    # of cross-origin to the KC's port.
    # Open CORS (Access-Control-Allow-Origin *) on every route — local dev
    # only; production deployments narrow this to specific origins.
    # Mounted into the nginx container via the override below in place of the
    # in-repo nginx-dev.conf.
    cat > "$org_dir/participant/nginx-dev.conf" <<EOF
# Auto-generated by glcdi.sh (Tier 1) — do not edit by hand.

# Reusable CORS handler. Responds to OPTIONS preflight + sets ACAO on every
# response. * is fine for local dev; tighten in prod.
map \$request_method \$cors_method {
    OPTIONS 1;
    default 0;
}

server {
    listen 8080;
    server_name _;

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

    location /ui/ {
        proxy_pass http://catalogue-ui:80/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Override file — Tier-1 stack:
    #   - edc-connector: locally-built image (fastest iteration when changing
    #                    extension code) + re-bound config dir + JVM heap cap
    #   - nginx:         dev nginx config from the local org dir
    #   - catalogue-ui:  locally-built image (fastest iteration when changing
    #                    orbit/solid-glcdi/config). Since the new self-contained
    #                    Dockerfile clones the same hubl branch as CI, the
    #                    :local image is functionally identical to the
    #                    published :latest — this override is purely a build-
    #                    speed optimisation; you can omit it without breaking
    #                    Tier-1 behaviour, at the cost of pulling on every up.
    #
    # NOTE: identity-hub and oauth2-proxy used to be stubbed here because
    # they appeared in the upstream compose; they were removed from
    # docker-compose.yml at Tier 1, so no stub is needed anymore.
    cat > "$org_dir/docker-compose.override.yml" <<EOF
# Auto-generated by glcdi.sh — do not edit by hand.
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
    # participantId must match the connector's edc.participant.id (set to
    # glcdi-connector-<org> after the Tier-1 IAM swap). Without this, the
    # catalogue UI matches incoming dataset._provider.participantId
    # against the wrong value and counts 0 datasets per provider.
    out+="{\"name\":\"$nice\",\"address\":\"http://host.docker.internal:${port}/protocol\",\"color\":\"#1565C0\",\"participantId\":\"glcdi-connector-${org}\"}"
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
           --profile dev \
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

  log "Building participant-ui image (clones hubl branch at build time)"
  if [[ -f "$PARTICIPANT_UI_DIR/Dockerfile" ]]; then
    # Build context is participant-ui/ itself — the Dockerfile clones
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

  # Seed each org's connector with its own asset / policies / contract-def.
  # The bruno collection is hard-coded to use `{{caney_fork_host}}` and
  # `{{caney_fork_api_key}}` because that's how its files were authored,
  # but bruno's `--env-var` flags happily override either of those names.
  # We also rewrite `m1_asset_id` and `m1_contract_definition_id` to be
  # org-specific so the dsp-catalog of any peer sees distinct datasets
  # instead of three copies of the same URN colliding.
  for org in "${ORGS[@]}"; do
    local port="${ORG_PORTS[$org]}"
    local org_upper
    org_upper=$(echo "$org" | tr 'a-z-' 'A-Z_')
    local api_key_var="${org_upper}_API_KEY"
    local api_key="${!api_key_var}"

    # Friendly display name for the asset titles (Title Case from kebab).
    local org_display
    org_display=$(echo "$org" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')

    log "Seeding M1 fixtures on $org (http://localhost:${port}) via Bruno"
    # shellcheck disable=SC2046
    ( cd "$BRUNO_DIR" && bru run 10-provider-seeding --env local $(bruno_env_flags) \
        --env-var "caney_fork_host=http://localhost:${port}" \
        --env-var "caney_fork_api_key=${api_key}" \
        --env-var "org_display_name=${org_display}" \
        --env-var "m1_asset_id=urn:glcdi:asset:${org}:grazing-soc-2024" \
        --env-var "m1_contract_definition_id=${org}-grazing-soc-2024-cd" \
        --env-var "m1_research_asset_id=urn:glcdi:asset:${org}:grazing-summary-2024" \
        --env-var "m1_research_contract_definition_id=${org}-grazing-summary-2024-cd" \
        --env-var "m1_researcher_only_asset_id=urn:glcdi:asset:${org}:grazing-raw-observations-2024" \
        --env-var "m1_researcher_only_contract_definition_id=${org}-grazing-raw-observations-2024-cd" \
    ) || die "Bruno seeding folder failed for $org — see output above"
  done
  ok "M1 fixtures seeded on all orgs (${ORGS[*]})"
}

# Build the --env-var flags `bru run` needs to populate secret env vars
# (Bruno's vars:secret declarations are empty by default; the CLI reads
# values from --env-var flags or the Bruno UI's secret store).
#
# Echoes the flags as one line — caller does:
#   bru run --env local $(bruno_env_flags) ...
bruno_env_flags() {
  printf -- '--env-var caney_fork_api_key=%s ' "$CANEY_FORK_API_KEY"
  printf -- '--env-var point_blue_api_key=%s ' "$POINT_BLUE_API_KEY"
  printf -- '--env-var white_buffalo_api_key=%s ' "$WHITE_BUFFALO_API_KEY"
  printf -- '--env-var caney_fork_client_secret=%s ' "$CANEY_FORK_CONNECTOR_SECRET"
  printf -- '--env-var point_blue_client_secret=%s ' "$POINT_BLUE_CONNECTOR_SECRET"
  printf -- '--env-var white_buffalo_client_secret=%s ' "$WHITE_BUFFALO_CONNECTOR_SECRET"
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

  log "Running Bruno collection (tier=$tier)"
  # shellcheck disable=SC2046
  ( cd "$BRUNO_DIR" \
    && bru run --env local --env-var "tier=$tier" $(bruno_env_flags) \
  ) \
    && ok "Bruno run green at $tier" \
    || die "Bruno run failed — see output above"
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
           --profile dev \
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
             --profile dev \
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
             --profile dev \
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
    bruno-cmd) cmd_print_bruno_cmd "${1:-$TIER}" ;;
    help|-h|--help) cmd_help ;;
    *)         err "Unknown subcommand: $cmd"; cmd_help; exit 2 ;;
  esac
}

main "$@"
