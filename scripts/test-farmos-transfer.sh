#!/usr/bin/env bash
#
# test-farmos-transfer.sh
#
# End-to-end OAuth2 transfer test for the caney-fork farmOS asset.
# Drives a peer (point-blue) through the full DSP flow:
#
#   1. catalog/request  → discover the farmOS asset, capture the offer policy
#   2. contractnegotiations → initiate (with the captured offer)
#   3. poll until FINALIZED, capture agreement id
#   4. transferprocesses → initiate transfer (HttpProxy destination)
#   5. poll until STARTED, capture EDR endpoint + auth
#   6. call the EDR proxy → provider's dataplane fetches farmOS
#      (which is where glcdi-dataplane-oauth2-inline does its work)
#   7. assert the response is a farmOS JSON:API payload
#
# Exit codes: 0 = success; 1 = any step failed.
#
# Usage:
#   ./management/scripts/test-farmos-transfer.sh                   # local
#   ./management/scripts/test-farmos-transfer.sh --target staging  # staging
#
# Both modes read EDC credentials from .glcdi.local/secrets.env. Local
# also reuses the local Bruno env URLs; staging hits the public host.
#
# Pre-reqs (local):
#   - GLCDI_FARMOS=1 ./management/scripts/glcdi.sh up
#   - GLCDI_FARMOS=1 ./management/scripts/glcdi.sh farmos-install
#   - GLCDI_FARMOS=1 ./management/scripts/glcdi.sh seed
#       (lands the caney-fork-farmos-animals-cd that we negotiate against)
#
# Known trap (see memory `reference_glcdi_edc_transfer_diag` § 7): if the
# transfer terminates with "agreement not found or not valid", it's
# usually PurposeConstraintFunction denying at transfer.process scope.
# Check the caney-fork connector logs for `[glcdi-policy] [odrl:purpose]`
# denies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$SCRIPT_DIR/.glcdi.local"
SECRETS_FILE="$LOCAL_DIR/secrets.env"

# -----------------------------------------------------------------------------
# Args + output
# -----------------------------------------------------------------------------

TARGET="local"
ASSET_ID="urn:glcdi:asset:caney-fork:farmos-animals-2024"
NEGOTIATION_TIMEOUT_S=60
TRANSFER_TIMEOUT_S=60
EDR_TIMEOUT_S=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 || { echo "--target needs a value" >&2; exit 2; } ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --asset-id) ASSET_ID="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RED='\033[31m'; C_GREEN='\033[32m'
  C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_RESET='\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi
log()  { printf '%b==>%b %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf '%b✓%b %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%b⚠%b %s\n'   "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%b✗%b %s\n'   "$C_RED"    "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%b%s%b\n' "$C_DIM" "----------------------------------------------------------------" "$C_RESET"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
require_cmd curl
require_cmd jq

# -----------------------------------------------------------------------------
# Hosts + secrets per target
# -----------------------------------------------------------------------------

case "$TARGET" in
  local)
    [[ -f "$SECRETS_FILE" ]] || die "secrets file not found at $SECRETS_FILE. Run `glcdi.sh secrets` first."
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
    PROVIDER_MGMT="http://localhost:8080"
    PROVIDER_DSP="http://host.docker.internal:8080/protocol"
    CONSUMER_MGMT="http://localhost:8081"
    PROVIDER_KEY="${CANEY_FORK_API_KEY:-}"
    CONSUMER_KEY="${POINT_BLUE_API_KEY:-}"
    PROVIDER_PARTICIPANT_ID="glcdi-connector-caney-fork"
    ;;
  staging)
    # On staging the orchestrator hits public URLs. Provider/consumer
    # X-Api-Keys must be in the shell environment (e.g. exported by the
    # operator's wrapper, or via glcdi.sh fetch_staging_api_key).
    PROVIDER_MGMT="https://caney-fork.glcdi.startinblox.com"
    PROVIDER_DSP="https://caney-fork.glcdi.startinblox.com/protocol"
    CONSUMER_MGMT="https://point-blue.glcdi.startinblox.com"
    PROVIDER_KEY="${CANEY_FORK_STAGING_API_KEY:-${CANEY_FORK_API_KEY:-}}"
    CONSUMER_KEY="${POINT_BLUE_STAGING_API_KEY:-${POINT_BLUE_API_KEY:-}}"
    PROVIDER_PARTICIPANT_ID="glcdi-connector-caney-fork"
    ;;
  *) die "unknown --target: $TARGET (expected local|staging)" ;;
esac

[[ -n "$PROVIDER_KEY" ]] || die "provider API key empty - check secrets.env or env vars for target=$TARGET"
[[ -n "$CONSUMER_KEY" ]] || die "consumer API key empty - same"

log "Test config:"
echo "  target              = $TARGET"
echo "  provider mgmt API   = $PROVIDER_MGMT"
echo "  provider DSP        = $PROVIDER_DSP"
echo "  consumer mgmt API   = $CONSUMER_MGMT"
echo "  asset id            = $ASSET_ID"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Wrap curl with sane defaults; bail with status + body on any non-2xx.
edc_post() {
  local mgmt="$1" key="$2" path="$3" body="$4"
  local url="${mgmt}${path}"
  local resp http
  resp=$(curl -sS -w '\n__HTTP_STATUS__:%{http_code}\n' --max-time 30 \
    -X POST "$url" \
    -H 'Content-Type: application/json' \
    -H "X-Api-Key: $key" \
    -d "$body" 2>&1) || { err "curl failed for POST $url: $resp"; return 1; }
  http=$(printf '%s' "$resp" | awk -F: '/^__HTTP_STATUS__:/{print $2}')
  local body_out
  body_out=$(printf '%s' "$resp" | sed -e '/^__HTTP_STATUS__:/d')
  if [[ "$http" != 2* ]]; then
    err "POST $url returned $http"
    printf '%s\n' "$body_out" >&2
    return 1
  fi
  printf '%s' "$body_out"
}

edc_get() {
  local mgmt="$1" key="$2" path="$3"
  local url="${mgmt}${path}"
  local resp http
  resp=$(curl -sS -w '\n__HTTP_STATUS__:%{http_code}\n' --max-time 30 \
    -X GET "$url" \
    -H "X-Api-Key: $key" 2>&1) || { err "curl failed for GET $url"; return 1; }
  http=$(printf '%s' "$resp" | awk -F: '/^__HTTP_STATUS__:/{print $2}')
  local body_out
  body_out=$(printf '%s' "$resp" | sed -e '/^__HTTP_STATUS__:/d')
  if [[ "$http" != 2* ]]; then
    err "GET $url returned $http"
    printf '%s\n' "$body_out" >&2
    return 1
  fi
  printf '%s' "$body_out"
}

# -----------------------------------------------------------------------------
# 1. Catalog discovery - find the farmOS asset + capture its offer policy
# -----------------------------------------------------------------------------

hr
log "1/6  Catalog discovery from consumer → provider"

catalog=$(edc_post "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/catalog/request" "$(jq -nc \
  --arg cp "$PROVIDER_DSP" \
  --arg cpId "$PROVIDER_PARTICIPANT_ID" \
  '{
    "@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
    "@type":"CatalogRequest",
    "counterPartyAddress":$cp,
    "counterPartyId":$cpId,
    "protocol":"dataspace-protocol-http",
    "querySpec":{"offset":0,"limit":200}
  }')") || die "catalog discovery failed"

# Find the dataset with our asset id, extract its hasPolicy offer.
offer=$(printf '%s' "$catalog" \
  | jq -e --arg aid "$ASSET_ID" '
      ((.["dcat:dataset"] // .["http://www.w3.org/ns/dcat#dataset"] // [])
        | (if type == "array" then . else [.] end))
      | map(select(.["@id"] == $aid))
      | first
      | (."odrl:hasPolicy" // ."http://www.w3.org/ns/odrl/2/hasPolicy")
      | (if type == "array" then .[0] else . end)
    ' 2>/dev/null) || die "catalog response did not include asset $ASSET_ID - has the seed run with GLCDI_FARMOS=1?"

offer_id=$(printf '%s' "$offer" | jq -r '."@id"')
[[ "$offer_id" != "null" && -n "$offer_id" ]] || die "could not extract offer id from catalog response"
ok "catalog includes $ASSET_ID with offer @id=$offer_id"

# -----------------------------------------------------------------------------
# 2. Initiate contract negotiation
# -----------------------------------------------------------------------------

hr
log "2/6  Initiate contract negotiation"

neg_req=$(jq -nc \
  --arg cp "$PROVIDER_DSP" \
  --arg cpId "$PROVIDER_PARTICIPANT_ID" \
  --argjson offer "$offer" \
  --arg aid "$ASSET_ID" \
  '{
    "@context":{
      "@vocab":"https://w3id.org/edc/v0.0.1/ns/",
      "odrl":"http://www.w3.org/ns/odrl/2/",
      "glcdi":"https://w3id.org/glcdi/v0.1.0/ns/"
    },
    "@type":"ContractRequest",
    "counterPartyAddress":$cp,
    "counterPartyId":$cpId,
    "protocol":"dataspace-protocol-http",
    "policy": ($offer + {
      "@type":"odrl:Offer",
      "odrl:assigner":{"@id":$cpId},
      "odrl:target":{"@id":$aid}
    })
  }')

neg_resp=$(edc_post "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/contractnegotiations" "$neg_req") \
  || die "negotiation initiation failed"
NEG_ID=$(printf '%s' "$neg_resp" | jq -r '."@id"')
[[ -n "$NEG_ID" && "$NEG_ID" != "null" ]] || die "negotiation response missing @id"
ok "negotiation initiated, id=$NEG_ID"

# -----------------------------------------------------------------------------
# 3. Poll negotiation until FINALIZED, capture agreement id
# -----------------------------------------------------------------------------

hr
log "3/6  Poll negotiation until FINALIZED (timeout ${NEGOTIATION_TIMEOUT_S}s)"

AGREEMENT_ID=""
NEG_STATE=""
deadline=$(( $(date +%s) + NEGOTIATION_TIMEOUT_S ))
while [[ $(date +%s) -lt $deadline ]]; do
  neg_state=$(edc_get "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/contractnegotiations/$NEG_ID") \
    || die "negotiation state query failed"
  NEG_STATE=$(printf '%s' "$neg_state" | jq -r '.state // .["@state"] // empty')
  AGREEMENT_ID=$(printf '%s' "$neg_state" | jq -r '.contractAgreementId // .["contractAgreementId"] // empty')
  case "$NEG_STATE" in
    FINALIZED)
      [[ -n "$AGREEMENT_ID" && "$AGREEMENT_ID" != "null" ]] || die "FINALIZED but no agreement id"
      ok "negotiation FINALIZED, agreement=$AGREEMENT_ID"
      break ;;
    TERMINATED|TERMINATING)
      err_detail=$(printf '%s' "$neg_state" | jq -r '.errorDetail // "<none>"')
      die "negotiation TERMINATED - errorDetail: $err_detail (see memory reference_glcdi_edc_transfer_diag § 7)" ;;
    *)
      printf '  state=%s\n' "$NEG_STATE"
      sleep 2 ;;
  esac
done
[[ -n "$AGREEMENT_ID" && "$AGREEMENT_ID" != "null" ]] \
  || die "negotiation did not reach FINALIZED within ${NEGOTIATION_TIMEOUT_S}s (last state: $NEG_STATE)"

# -----------------------------------------------------------------------------
# 4. Initiate transfer
# -----------------------------------------------------------------------------

hr
log "4/6  Initiate transfer (HttpData-PULL via HttpProxy)"

xfer_req=$(jq -nc \
  --arg cp "$PROVIDER_DSP" \
  --arg cpId "$PROVIDER_PARTICIPANT_ID" \
  --arg aid "$ASSET_ID" \
  --arg agr "$AGREEMENT_ID" \
  '{
    "@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
    "@type":"TransferRequest",
    "counterPartyAddress":$cp,
    "counterPartyId":$cpId,
    "contractId":$agr,
    "assetId":$aid,
    "protocol":"dataspace-protocol-http",
    "transferType":"HttpData-PULL",
    "dataDestination":{"type":"HttpProxy"}
  }')

xfer_resp=$(edc_post "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/transferprocesses" "$xfer_req") \
  || die "transfer initiation failed"
TID=$(printf '%s' "$xfer_resp" | jq -r '."@id"')
[[ -n "$TID" && "$TID" != "null" ]] || die "transfer response missing @id"
ok "transfer initiated, id=$TID"

# -----------------------------------------------------------------------------
# 5. Poll transfer until STARTED, fetch EDR
# -----------------------------------------------------------------------------

hr
log "5/6  Poll transfer until STARTED + fetch EDR (timeout ${TRANSFER_TIMEOUT_S}s)"

XFER_STATE=""
deadline=$(( $(date +%s) + TRANSFER_TIMEOUT_S ))
while [[ $(date +%s) -lt $deadline ]]; do
  xfer_state=$(edc_get "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/transferprocesses/$TID") \
    || die "transfer state query failed"
  XFER_STATE=$(printf '%s' "$xfer_state" | jq -r '.state // empty')
  case "$XFER_STATE" in
    STARTED|COMPLETED)
      ok "transfer reached $XFER_STATE"
      break ;;
    TERMINATED|TERMINATING)
      err_detail=$(printf '%s' "$xfer_state" | jq -r '.errorDetail // "<none>"')
      die "transfer TERMINATED - errorDetail: $err_detail" ;;
    *)
      printf '  state=%s\n' "$XFER_STATE"
      sleep 2 ;;
  esac
done
[[ "$XFER_STATE" == "STARTED" || "$XFER_STATE" == "COMPLETED" ]] \
  || die "transfer did not reach STARTED within ${TRANSFER_TIMEOUT_S}s (last state: $XFER_STATE)"

# EDR endpoint may take a moment to register after STARTED.
log "  Fetching EDR (poll up to ${EDR_TIMEOUT_S}s)"
EDR_BODY=""
deadline=$(( $(date +%s) + EDR_TIMEOUT_S ))
while [[ $(date +%s) -lt $deadline ]]; do
  if EDR_BODY=$(edc_get "$CONSUMER_MGMT" "$CONSUMER_KEY" "/management/v3/edrs/$TID/dataaddress" 2>/dev/null); then
    break
  fi
  sleep 2
done
[[ -n "$EDR_BODY" ]] || die "EDR /dataaddress 404 - see memory reference_glcdi_edc_transfer_diag"

EDR_ENDPOINT=$(printf '%s' "$EDR_BODY" | jq -r '.endpoint // .["endpoint"] // empty')
EDR_AUTH_KEY=$(printf '%s' "$EDR_BODY" | jq -r '.authKey // "Authorization"')
EDR_AUTH_VAL=$(printf '%s' "$EDR_BODY" | jq -r '.authorization // .authCode // empty')
[[ -n "$EDR_ENDPOINT" && -n "$EDR_AUTH_VAL" ]] || { printf '%s\n' "$EDR_BODY" >&2; die "EDR missing endpoint/auth fields"; }
ok "EDR endpoint=$EDR_ENDPOINT"

# -----------------------------------------------------------------------------
# 6. Call the EDR proxy → triggers provider dataplane → triggers OAuth2 exchange → farmOS fetch
# -----------------------------------------------------------------------------

hr
log "6/6  Call EDR proxy (provider dataplane will OAuth2-fetch farmOS)"

proxy_resp_file=$(mktemp)
proxy_http=$(curl -sS --max-time 30 -o "$proxy_resp_file" -w '%{http_code}' \
  -X GET "$EDR_ENDPOINT" \
  -H "${EDR_AUTH_KEY}: ${EDR_AUTH_VAL}" || true)

if [[ "$proxy_http" != "200" ]]; then
  err "EDR proxy call returned HTTP $proxy_http"
  head -c 2000 "$proxy_resp_file" >&2
  rm -f "$proxy_resp_file"
  die "transfer-time fetch failed - check the provider's edc-connector logs for glcdi-inline-oauth2 errors"
fi

# Detect farmOS JSON:API shape: contains "data" array AND a "jsonapi" / "links" /
# "type":"asset--animal" marker. Drupal JSON:API uses both top-level "jsonapi"
# and per-resource "type" fields.
body=$(cat "$proxy_resp_file")
rm -f "$proxy_resp_file"

if printf '%s' "$body" | jq -e '.data and (.jsonapi or .links or (.data | type == "array"))' >/dev/null 2>&1; then
  count=$(printf '%s' "$body" | jq -r '.data | if type == "array" then length else 1 end')
  ok "received JSON:API payload from farmOS - data records: $count"
  # Render a short sample of the first record so the test output is a
  # concrete proof (not just a count). Picks 5 readable attributes so the
  # block stays compact in the terminal; falls back to the raw first
  # record if attributes are absent (defensive against farmOS rewrites).
  sample=$(printf '%s' "$body" \
    | jq -r '
        .data
        | (if type == "array" then .[0] else . end)
        | if type == "object" then
            { type: .type, id: .id }
            + ((.attributes // {}) | to_entries | map(select(.value != null and .value != "")) | .[0:5] | from_entries | with_entries(.key |= "attr." + .))
          else .
          end
      ' 2>/dev/null)
  if [[ -n "$sample" && "$sample" != "null" ]]; then
    printf '\n  %bSample (first record):%b\n' "$C_DIM" "$C_RESET"
    printf '%s\n' "$sample" | sed 's/^/    /'
  fi
else
  err "response is NOT a farmOS JSON:API payload"
  printf '%s\n' "${body:0:500}" >&2
  die "OAuth2 path returned something but not what farmOS would emit"
fi

hr
ok "ALL STEPS PASSED - OAuth2 token exchange runs at transfer-time, farmOS data flows back through EDC dataplane."
