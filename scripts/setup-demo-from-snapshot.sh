#!/usr/bin/env bash
# setup-demo-from-snapshot.sh
#
# Convert a participant VM snapshotted from white-buffalo (or any other
# M1 participant) into the `demo` VM. Tear down the stack, drop all named
# volumes (assets / policies / DjangoLDP data / media), regenerate
# .env + participant/configuration.properties + participant/idh-configuration.properties
# with demo values and freshly rotated secrets, then bring it back up.
#
# Runs ON the VM as root, after SSH-ing in:
#   ssh root@demo.glcdi.startinblox.com
#   cd ~/participant-agent-services
#   bash management/scripts/setup-demo-from-snapshot.sh                            # dry-run
#   bash management/scripts/setup-demo-from-snapshot.sh --no-dry-run --kc-secret X # commit
#
# Usage:
#   setup-demo-from-snapshot.sh [--no-dry-run] [--kc-secret SECRET] [-h|--help]
#
#   --no-dry-run        actually execute (default: dry-run preview)
#   --kc-secret SECRET  governance Keycloak client secret for glcdi-connector-demo
#                       (you get this from the governance KC admin console
#                       AFTER you register the client there - see step "manual" below)
#                       Required only with --no-dry-run, omit on dry-run.
#                       Can also be passed via env var DEMO_KC_CLIENT_SECRET.
#   --keep-volumes      do NOT drop the named volumes (state survives).
#                       Use only if you've already wiped manually.
#
# Out-of-band manual steps NOT covered by this script (do these on the
# governance VM via the Keycloak admin console - there is no API key
# auto-discovery here):
#
#   1. Governance KC realm `glcdi`:
#      - Create client `glcdi-connector-demo` (client-credentials flow,
#        scope `glcdi-claims`). Mint a client secret; that's what you pass
#        via --kc-secret.
#      - Realm role `glcdi_member` (create if missing).
#      - Group `demo-team` with role mapping → `glcdi_member`.
#      - User `demo@demo.glcdi.startinblox.com` (any local user), member of
#        `demo-team`. Set a password if you want to log in via the catalogue UI.
#      - Protocol mapper: ensure `glcdi_member` role membership emits the
#        `glcdi:membership=active` claim on tokens (mirrors the M1 trio's
#        mapping).
#
#   2. From your laptop, seed the demo VM with M1 fixtures:
#         ./management/scripts/glcdi.sh seed --target demo
#
# Failure recovery: rerun in dry-run mode. The backup .env is at
# .env.snapshot-backup-<TIMESTAMP> in the participant-agent-services repo.

set -euo pipefail

DEMO_SLUG=demo
DEMO_DOMAIN=demo.glcdi.startinblox.com
DEMO_PARTICIPANT_ID=glcdi-connector-${DEMO_SLUG}
DEMO_TITLE="Demo - GLCDI"
DEMO_PRIMARY="#7B1FA2"
DEMO_SECONDARY="#4A148C"
DEMO_ACCENT="#BA68C8"

# Reuse the baseline djangoldp package. The demo VM doesn't actually
# serve LDP-backed assets (data backing = static JSON stubs per
# OTHER_PARTICIPANTS.md §5 Option A), but the LDP container still boots
# so it needs SOME package.
DEMO_LDP_PACKAGE=djangoldp_glcdi

REPO_DEFAULT=~/participant-agent-services
REPO_PATH="${REPO_PATH:-$REPO_DEFAULT}"

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_DIM='\033[2m'; C_RED='\033[31m'; C_GREEN='\033[32m'
  C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_RESET='\033[0m'
else
  C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi
log()  { printf '%b==>%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%b✓%b %s\n'   "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b⚠%b %s\n'   "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%b✗%b %s\n'   "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%b%s%b\n' "$C_DIM" "----------------------------------------------------------------" "$C_RESET"; }

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------

DRY_RUN=true
KEEP_VOLUMES=false
KC_SECRET="${DEMO_KC_CLIENT_SECRET:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-dry-run)    DRY_RUN=false; shift ;;
    --keep-volumes)  KEEP_VOLUMES=true; shift ;;
    --kc-secret)     KC_SECRET="${2:-}"; shift 2 || die "--kc-secret needs a value" ;;
    --kc-secret=*)   KC_SECRET="${1#--kc-secret=}"; shift ;;
    -h|--help)       sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               die "unknown argument: $1 - see --help" ;;
  esac
done

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

preflight() {
  log "Preflight"

  for tool in docker openssl sed grep; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
  done
  docker compose version >/dev/null 2>&1 || die "docker compose v2 missing"

  [[ -d "$REPO_PATH" ]] || die "REPO_PATH '$REPO_PATH' is not a directory - set REPO_PATH=/glcdi/... if your VM uses that layout"
  [[ -f "$REPO_PATH/.env" ]] || die "$REPO_PATH/.env missing - is this a snapshot of a participant VM?"
  [[ -f "$REPO_PATH/docker-compose.yml" ]] || die "$REPO_PATH/docker-compose.yml missing"

  local old_name
  old_name=$(grep '^PARTICIPANT_NAME=' "$REPO_PATH/.env" | head -1 | cut -d= -f2- | tr -d $'\r')
  if [[ -z "$old_name" ]]; then
    die "could not read PARTICIPANT_NAME from $REPO_PATH/.env"
  fi
  log "Current PARTICIPANT_NAME: $old_name"
  if [[ "$old_name" == "$DEMO_SLUG" ]]; then
    warn "Already PARTICIPANT_NAME=$DEMO_SLUG - script seems already-applied. Re-running will rewrite secrets."
  else
    log "Will convert: $old_name → $DEMO_SLUG"
  fi
  OLD_PARTICIPANT_NAME="$old_name"

  if ! $DRY_RUN; then
    if [[ -z "$KC_SECRET" ]]; then
      die "--no-dry-run requires --kc-secret SECRET (or DEMO_KC_CLIENT_SECRET env). Get the secret from the governance KC client glcdi-connector-demo."
    fi
    if [[ ${#KC_SECRET} -lt 16 ]]; then
      warn "KC client secret looks short (${#KC_SECRET} chars) - KC mints 36+ char secrets by default. Continuing anyway."
    fi
  fi

  ok "Preflight OK"
}

# -----------------------------------------------------------------------------
# Compose helpers
# -----------------------------------------------------------------------------

compose_in() {
  ( cd "$REPO_PATH" && docker compose --profile prod "$@" )
}

stop_stack() {
  log "Stopping compose stack (project glcdi-${OLD_PARTICIPANT_NAME})"
  if $DRY_RUN; then
    log "  [dry-run] cd $REPO_PATH && docker compose --profile prod down --remove-orphans"
    return 0
  fi
  compose_in down --remove-orphans || warn "compose down returned non-zero - continuing"
  ok "  stack stopped"
}

drop_volumes() {
  if $KEEP_VOLUMES; then
    warn "Skipping volume drop (--keep-volumes). State from $OLD_PARTICIPANT_NAME survives."
    return 0
  fi
  local project="glcdi-${OLD_PARTICIPANT_NAME}"
  local vols
  vols=$(docker volume ls --format '{{.Name}}' | grep "^${project}_" || true)
  if [[ -z "$vols" ]]; then
    warn "No volumes matching ^${project}_ - already wiped, or compose project named differently"
    return 0
  fi
  log "Found volumes for project $project:"
  while IFS= read -r v; do log "  - $v"; done <<<"$vols"
  if $DRY_RUN; then
    log "  [dry-run] would drop each volume above"
    return 0
  fi
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    docker volume rm "$v" >/dev/null \
      || die "failed to remove $v (container still using it? try compose down --remove-orphans first)"
    ok "  dropped $v"
  done <<<"$vols"
}

# -----------------------------------------------------------------------------
# .env regeneration
# -----------------------------------------------------------------------------

# Globals populated by mint_secrets, consumed by write_env / write_properties.
NEW_API_KEY=""
NEW_DB_PWD=""
NEW_LDP_PWD=""
NEW_LDP_BOOTSTRAP_PWD=""
NEW_DJANGO_SECRET=""

mint_secrets() {
  NEW_API_KEY=$(openssl rand -hex 32)
  NEW_DB_PWD=$(openssl rand -hex 24)
  NEW_LDP_PWD=$(openssl rand -hex 24)
  NEW_LDP_BOOTSTRAP_PWD=$(openssl rand -hex 24)
  NEW_DJANGO_SECRET=$(openssl rand -hex 32)
}

write_env() {
  local env_file="$REPO_PATH/.env"
  local backup_file="$REPO_PATH/.env.snapshot-backup-$(date +%Y%m%d-%H%M%S)"

  log "Backing up old .env"
  if $DRY_RUN; then
    log "  [dry-run] cp $env_file $backup_file"
  else
    cp "$env_file" "$backup_file" || die "backup failed"
    ok "  saved as $backup_file"
  fi

  log "Generating fresh .env"

  # DSP_PROVIDERS lists the other 3 M1 participants visible from demo.
  local dsp_providers='[{"name":"Caney Fork","address":"https://caney-fork.glcdi.startinblox.com/protocol","color":"#2E7D32","participantId":"glcdi-connector-caney-fork"},{"name":"Point Blue","address":"https://point-blue.glcdi.startinblox.com/protocol","color":"#1565C0","participantId":"glcdi-connector-point-blue"},{"name":"White Buffalo","address":"https://white-buffalo.glcdi.startinblox.com/protocol","color":"#C0392B","participantId":"glcdi-connector-white-buffalo"}]'

  local new_env
  new_env=$(cat <<EOF
# Generated by setup-demo-from-snapshot.sh on $(date -Iseconds)
# Source: snapshot of glcdi-${OLD_PARTICIPANT_NAME}

# --- Identity ---
PARTICIPANT_NAME=${DEMO_SLUG}
PARTICIPANT_ID=${DEMO_SLUG}
PARTICIPANT_DOMAIN=${DEMO_DOMAIN}
PARTICIPANT_CONNECTOR_URI=https://${DEMO_DOMAIN}
NGINX_PORT=443

# --- EDC connector secrets (rotated) ---
EDC_API_KEY=${NEW_API_KEY}
CONNECTOR_DB_PASSWORD=${NEW_DB_PWD}

# --- DjangoLDP ---
LDP_DOMAIN_PACKAGE=${DEMO_LDP_PACKAGE}
LDP_BASE_URL=https://${DEMO_DOMAIN}/ldp

DJANGO_SECRET_KEY=${NEW_DJANGO_SECRET}
LDP_DB_PASSWORD=${NEW_LDP_PWD}
LDP_DB_BOOTSTRAP_PASSWORD=${NEW_LDP_BOOTSTRAP_PWD}

# --- EDC permissions V3 wiring ---
EDC_URL=http://edc-connector:9193/management
EDC_PARTICIPANT_ID=${DEMO_PARTICIPANT_ID}
EDC_ASSET_ID_STRATEGY=full_url
EDC_AGREEMENT_VALIDATION_ENABLED=True
EDC_AUTO_NEGOTIATION_ENABLED=False
EDC_POLICY_DISCOVERY_ENABLED=False

# --- Identity Hub ---
IDH_LOG_LEVEL=INFO

# --- UI Branding ---
APP_TITLE=${DEMO_TITLE}
PRIMARY_COLOR=${DEMO_PRIMARY}
SECONDARY_COLOR=${DEMO_SECONDARY}
ACCENT_COLOR=${DEMO_ACCENT}

# --- DSP Catalog Providers ---
DSP_PROVIDERS=${dsp_providers}

# --- Static data backing for asset dataAddress.baseUrl (OTHER_PARTICIPANTS.md §5 A) ---
PARTICIPANT_DATA_DIR=./data/demo
EOF
)

  if $DRY_RUN; then
    log "  [dry-run] would write $env_file (preview, secrets masked):"
    printf '%s\n' "$new_env" | sed -E 's/(_KEY|_PASSWORD|_SECRET|_PWD)=.*/\1=<rotated>/' | sed 's/^/    /'
  else
    printf '%s\n' "$new_env" > "$env_file"
    chmod 600 "$env_file"
    ok "  wrote $env_file (mode 600)"
  fi
}

# -----------------------------------------------------------------------------
# participant/configuration.properties regeneration
# -----------------------------------------------------------------------------

# We don't want to fight the .example layout - instead, rewrite the live
# .properties file in-place by substituting placeholders / known values.
# The 3 substitutions that matter:
#   - PARTICIPANT_NAME placeholder OR existing slug → demo slug
#   - host.docker.internal → demo public domain (DSP, IDH, dataplane refs)
#   - rotated secrets in 4 well-known keys
write_properties() {
  local cfg="$REPO_PATH/participant/configuration.properties"
  local cfg_example="$REPO_PATH/participant/configuration.properties.example"

  if [[ ! -f "$cfg" && -f "$cfg_example" ]]; then
    log "$cfg missing - bootstrapping from $cfg_example"
    if $DRY_RUN; then
      log "  [dry-run] cp $cfg_example $cfg"
    else
      cp "$cfg_example" "$cfg"
    fi
  elif [[ ! -f "$cfg" ]]; then
    die "$cfg missing AND no .example to bootstrap from"
  fi

  log "Rewriting $cfg"
  # The JDBC datasource user/url use ${PARTICIPANT_NAME} as the postgres role and
  # database name. On the snapshot they were already substituted with the source
  # slug (e.g. white-buffalo); rewrite to demo. Also handle the .example state
  # where it's still the literal "participant" placeholder.
  local sed_script=(
    -e "s|glcdi-connector-PARTICIPANT_NAME|${DEMO_PARTICIPANT_ID}|g"
    -e "s|glcdi-connector-${OLD_PARTICIPANT_NAME}|${DEMO_PARTICIPANT_ID}|g"
    -e "s|host.docker.internal|${DEMO_DOMAIN}|g"
    -e "s|${OLD_PARTICIPANT_NAME}.glcdi.startinblox.com|${DEMO_DOMAIN}|g"
    -e "s|^web.http.management.auth.key=.*|web.http.management.auth.key=${NEW_API_KEY}|"
    -e "s|^edc.api.auth.key=.*|edc.api.auth.key=${NEW_API_KEY}|"
    -e "s|^edc.api.control.auth.apikey.value=.*|edc.api.control.auth.apikey.value=${NEW_API_KEY}|"
    -e "s|^edc.datasource.default.url=jdbc:postgresql://db-connector:5432/${OLD_PARTICIPANT_NAME}|edc.datasource.default.url=jdbc:postgresql://db-connector:5432/${DEMO_SLUG}|"
    -e "s|^edc.datasource.default.url=jdbc:postgresql://db-connector:5432/participant|edc.datasource.default.url=jdbc:postgresql://db-connector:5432/${DEMO_SLUG}|"
    -e "s|^edc.datasource.default.user=${OLD_PARTICIPANT_NAME}|edc.datasource.default.user=${DEMO_SLUG}|"
    -e "s|^edc.datasource.default.user=participant|edc.datasource.default.user=${DEMO_SLUG}|"
    -e "s|^edc.datasource.default.password=.*|edc.datasource.default.password=${NEW_DB_PWD}|"
    -e "s|^edc.participant.id=.*|edc.participant.id=${DEMO_PARTICIPANT_ID}|"
    -e "s|^glcdi.iam.kc.client.id=.*|glcdi.iam.kc.client.id=${DEMO_PARTICIPANT_ID}|"
    -e "s|^glcdi.iam.kc.client.secret=.*|glcdi.iam.kc.client.secret=${KC_SECRET}|"
  )

  if $DRY_RUN; then
    log "  [dry-run] would run sed with these substitutions (KC secret + new API key elided):"
    log "    glcdi-connector-{PARTICIPANT_NAME|${OLD_PARTICIPANT_NAME}} → ${DEMO_PARTICIPANT_ID}"
    log "    host.docker.internal → ${DEMO_DOMAIN}"
    log "    web.http.management.auth.key / edc.api.auth.key / edc.api.control.auth.apikey.value → <rotated>"
    log "    edc.datasource.default.password → <rotated>"
    log "    edc.participant.id → ${DEMO_PARTICIPANT_ID}"
    log "    glcdi.iam.kc.client.id → ${DEMO_PARTICIPANT_ID}"
    log "    glcdi.iam.kc.client.secret → <from --kc-secret>"
  else
    sed -i.bak "${sed_script[@]}" "$cfg"
    ok "  rewrote $cfg (.bak alongside)"
  fi
}

# -----------------------------------------------------------------------------
# participant/idh-configuration.properties regeneration
# -----------------------------------------------------------------------------

write_idh_properties() {
  local idh="$REPO_PATH/participant/idh-configuration.properties"
  local idh_example="$REPO_PATH/participant/idh-configuration.properties.example"

  if [[ ! -f "$idh" && -f "$idh_example" ]]; then
    log "$idh missing - bootstrapping from $idh_example"
    if $DRY_RUN; then
      log "  [dry-run] cp $idh_example $idh"
    else
      cp "$idh_example" "$idh"
    fi
  elif [[ ! -f "$idh" ]]; then
    warn "$idh missing AND no .example - skipping IDH config rewrite"
    return 0
  fi

  log "Rewriting $idh"
  if $DRY_RUN; then
    log "  [dry-run] would substitute: host.docker.internal:8080 → ${DEMO_DOMAIN} (and host.docker.internal%3A8080 → URL-encoded variant)"
  else
    # The IDH config uses both the bare hostname and the URL-encoded form
    # (`host.docker.internal%3A8080`) in did:web URIs. Replace both.
    sed -i.bak \
      -e "s|host.docker.internal:8080|${DEMO_DOMAIN}|g" \
      -e "s|host.docker.internal%3A8080|${DEMO_DOMAIN}|g" \
      -e "s|host.docker.internal|${DEMO_DOMAIN}|g" \
      -e "s|${OLD_PARTICIPANT_NAME}.glcdi.startinblox.com|${DEMO_DOMAIN}|g" \
      "$idh"
    ok "  rewrote $idh (.bak alongside)"
  fi
}

# -----------------------------------------------------------------------------
# Bring stack up + health check
# -----------------------------------------------------------------------------

start_stack() {
  log "Starting compose stack (project glcdi-${DEMO_SLUG})"
  if $DRY_RUN; then
    log "  [dry-run] cd $REPO_PATH && docker compose --profile prod up -d"
    return 0
  fi
  compose_in pull || warn "compose pull returned non-zero - continuing with cached images"
  compose_in up -d || die "compose up failed"
  ok "  stack starting"
}

health_check() {
  if $DRY_RUN; then
    log "  [dry-run] would poll http://localhost:8080/check/health on edc-connector container for ~150s"
    return 0
  fi
  local container="glcdi-${DEMO_SLUG}-edc-connector-1"
  log "Waiting for $container liveness"
  local i status
  for i in $(seq 1 30); do
    if docker exec "$container" curl -sf -o /dev/null --max-time 5 http://localhost:8080/check/health 2>/dev/null; then
      ok "  connector healthy after $((i*5))s"
      return 0
    fi
    sleep 5
  done
  warn "  connector did not pass /check/health within 150s - inspect with: docker logs $container"
}

# -----------------------------------------------------------------------------
# Next-steps summary
# -----------------------------------------------------------------------------

next_steps() {
  hr
  ok "Conversion DONE - next manual steps:"
  printf '\n'
  printf '  1. On the GOVERNANCE Keycloak admin console (glcdi realm):\n'
  printf '     - Client %s (created already if you passed --kc-secret)\n' "$DEMO_PARTICIPANT_ID"
  printf '     - Realm role glcdi_member (create if missing)\n'
  printf '     - Group demo-team → role glcdi_member\n'
  printf '     - User demo@%s in demo-team\n' "$DEMO_DOMAIN"
  printf '     - Protocol mapper: glcdi_member role → claim glcdi:membership=active\n'
  printf '\n'
  printf '  2. From your laptop:\n'
  printf '     ./management/scripts/glcdi.sh seed --target %s\n' "$DEMO_SLUG"
  printf '\n'
  printf '  3. Validate:\n'
  printf '     - Open https://%s/ in a browser; catalogue loads.\n' "$DEMO_DOMAIN"
  printf '     - Unauthenticated, you should see 3 anonymous (public-policy) assets.\n'
  printf '     - As demo@%s, you should additionally see the Stone Barns asset (members-policy).\n' "$DEMO_DOMAIN"
  if ! $DRY_RUN; then
    printf '\n'
    printf '  NEW EDC_API_KEY (preserve - your laptop glcdi.sh fetches this via SSH):\n'
    printf '     %s\n' "$NEW_API_KEY"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  hr
  preflight
  hr

  if $DRY_RUN; then
    warn "DRY-RUN - no destructive action will run. Add --no-dry-run to commit."
  else
    warn "LIVE RUN. Stack will be torn down and reinitialized. Ctrl-C within 5s to abort."
    local i; for i in 5 4 3 2 1; do printf '  %d...\n' "$i"; sleep 1; done
  fi

  mint_secrets
  stop_stack
  drop_volumes
  write_env
  write_properties
  write_idh_properties
  start_stack
  health_check
  next_steps

  hr
  if $DRY_RUN; then
    warn "Was dry-run. Re-run with --no-dry-run --kc-secret SECRET to commit."
  else
    ok "Demo VM ready at https://${DEMO_DOMAIN}"
  fi
}

main "$@"
