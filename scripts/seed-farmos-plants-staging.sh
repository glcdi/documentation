#!/usr/bin/env bash
# Seed the caney-fork EDC with a farmOS-plants asset + contract definition
# using operator-provided OAuth2 creds (e.g. ones generated from the farmOS
# admin UI). Reuses the M1 `members-policy` + `internal-use-only-policy`
# already seeded by 10-provider-seeding/.
#
# Usage:
#   ./seed-farmos-plants-staging.sh <client_id> <client_secret>
#
# Idempotent: POST first (tolerates 409), then PUT to converge content.

set -euo pipefail

CLIENT_ID="${1:?client_id required}"
CLIENT_SECRET="${2:?client_secret required}"

HOST="https://caney-fork.glcdi.startinblox.com"
ASSET_ID="urn:glcdi:asset:caney-fork:farmos-plants-2024"
CD_ID="caney-fork-farmos-plants-cd"
BASE_URL="https://farmos.caney-fork.glcdi.startinblox.com/api/asset/plant"
TOKEN_URL="https://farmos.caney-fork.glcdi.startinblox.com/oauth/token"
SCOPE="farm_viewer"

echo "==> fetching EDC_API_KEY from caney-fork VM"
KEY=$(ssh root@caney-fork.glcdi.startinblox.com \
  "grep '^EDC_API_KEY=' /root/participant-agent-services/.env | cut -d= -f2-")
[[ -n "$KEY" ]] || { echo "FATAL: EDC_API_KEY not found on VM" >&2; exit 1; }

ASSET_BODY=$(jq -nc \
  --arg id "$ASSET_ID" \
  --arg base "$BASE_URL" \
  --arg tok  "$TOKEN_URL" \
  --arg cid  "$CLIENT_ID" \
  --arg sec  "$CLIENT_SECRET" \
'{
  "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/","glcdi":"https://w3id.org/glcdi/v0.1.0/ns/"},
  "@id": $id, "@type": "Asset",
  "properties": {
    "name": "Caney Fork — plant inventory (farmOS)",
    "description": "JSON:API feed of farmOS asset/plant records, fetched at transfer time via OAuth2 client_credentials (UI-generated creds proof).",
    "contenttype": "application/vnd.api+json",
    "glcdi:assetClass": "plant-inventory",
    "glcdi:source": "farmos"
  },
  "privateProperties": {"oauth2:clientSecret": $sec},
  "dataAddress": {
    "type": "HttpData",
    "name": "farmos-plants",
    "baseUrl": $base,
    "proxyPath": "false",
    "proxyQueryParams": "true",
    "oauth2:tokenUrl": $tok,
    "oauth2:clientId": $cid,
    "oauth2:scope": "farm_viewer"
  }
}')

echo "==> POST asset $ASSET_ID"
post_code=$(curl -sk -o /tmp/seed-plants-post.json -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $KEY" \
  "$HOST/management/v3/assets" -d "$ASSET_BODY")
case "$post_code" in
  2*)   echo "  + created (HTTP $post_code)" ;;
  409)  echo "  ~ already exists (HTTP 409) — will converge via PUT" ;;
  *)    echo "FATAL: POST failed (HTTP $post_code)"; cat /tmp/seed-plants-post.json; exit 1 ;;
esac

echo "==> PUT asset $ASSET_ID  (idempotent content converge)"
put_code=$(curl -sk -o /tmp/seed-plants-put.json -w '%{http_code}' \
  -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: $KEY" \
  "$HOST/management/v3/assets" -d "$ASSET_BODY")
case "$put_code" in
  2*)   echo "  ✓ converged (HTTP $put_code)" ;;
  *)    echo "FATAL: PUT failed (HTTP $put_code)"; cat /tmp/seed-plants-put.json; exit 1 ;;
esac

CD_BODY=$(jq -nc --arg id "$CD_ID" --arg asset "$ASSET_ID" \
'{
  "@context": {"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},
  "@id": $id, "@type": "ContractDefinition",
  "accessPolicyId": "members-policy",
  "contractPolicyId": "internal-use-only-policy",
  "assetsSelector": [{
    "@type": "Criterion",
    "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
    "operator": "=",
    "operandRight": $asset
  }]
}')

echo "==> POST contract definition $CD_ID"
cd_code=$(curl -sk -o /tmp/seed-plants-cd.json -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $KEY" \
  "$HOST/management/v3/contractdefinitions" -d "$CD_BODY")
case "$cd_code" in
  2*)   echo "  + created (HTTP $cd_code)" ;;
  409)  echo "  ~ already exists (HTTP 409)" ;;
  *)    echo "FATAL: CD POST failed (HTTP $cd_code)"; cat /tmp/seed-plants-cd.json; exit 1 ;;
esac

echo
echo "==> verify asset shape"
curl -sk -X POST -H "X-Api-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec","limit":50}' \
  "$HOST/management/v3/assets/request" \
  | jq ".[] | select(.\"@id\" == \"$ASSET_ID\") | {id: .\"@id\", baseUrl: .dataAddress.baseUrl, clientId: .dataAddress[\"oauth2:clientId\"], scope: .dataAddress[\"oauth2:scope\"], privProps: .privateProperties}"

echo
echo "Done. Asset $ASSET_ID + CD $CD_ID are live on caney-fork."
echo "Try a catalog request from point-blue to see it; then negotiate + transfer for the proof."
