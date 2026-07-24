# Phase 2: Keycloak Claims Configuration - Connector Service-Account Tokens

Policies like `members-only`, `regenerative-producers`, and `researchers-only` evaluate claims from
the consumer's identity token. **At Tier 1 the consumer is a connector** - claims live on the
Keycloak service-account user that backs each `glcdi-connector-<org>` client (§ 1.5.4), and reach
the receiving connector's policy engine via the Authority-KC-issued JWT minted at startup. Verifiable
Credentials (the long-term replacement) are out of scope at this tier - see [§ Phase 7.3](phase-7-future.md#73-identity-tier-3---decentralised-claims-via-vc--dcp).

## Architecture decision: where the claims live

Two Keycloak surfaces can carry participant attributes into a token. At Tier 1 each connector's
*service-account user* is the carrier:

| Surface | How it works at Tier 1 | When to use |
|---------|------------------------|-------------|
| **Realm roles** assigned to the SA user | Roles like `glcdi_member`, `glcdi_producer`. Inherited automatically into the token's `realm_access.roles`; surfaced as a clean `glcdi_roles` array via § 2.3 mapper 1. | Participant-type membership: which type buckets does this org belong to? Multi-valued, naturally fits a role list. |
| **User attributes** on the SA user | Key/value pairs on the SA user record (`glcdi_certification_status=regenerative-verified`). Surfaced via `oidc-usermodel-attribute-mapper` entries - § 2.3 mappers 2–2b. | Structured single-valued state: certification status, contribution status, organisation slug. |

**Why SA users, not client attributes:** stock Keycloak's standard mappers read user-level fields
only - there is no built-in `oidc-client-attribute-mapper`. Each client's SA *is* a user record,
so attribute-based mappers Just Work without custom mappers or admin extensions.

**Tier 2 / Tier 3 forward look:** Tier 2 (§ 7.2) introduces *human* users who join per-org groups
that carry the same role/attribute shape - the mappers in § 2.3 are unchanged. Tier 3 (§ 7.3)
moves the issuance off Keycloak entirely; § 2.7's claim → constraint table survives because the
policy functions only see claim *names*, not the issuer.

## 2.1 Create GLCDI realm roles

| Item | Detail |
|------|--------|
| **Task** | Add realm roles to the `glcdi` realm in Authority Keycloak |
| **Roles to create** | `glcdi_member` (active membership), `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder` |
| **Where** | `authority-services/resources/keycloak/realms/glcdi-realm.json` - in the `roles.realm[]` array |
| **Status** | [x] Declared in realm JSON (13 roles total: 2 inherited + 11 GLCDI) · [x] Imported into live Authority KC (verified after each `glcdi.sh reset && up`) |

**Realm JSON snippet to add:**

```json
{
  "roles": {
    "realm": [
      { "name": "user", "description": "Default user role" },
      { "name": "admin", "description": "Admin role" },
      { "name": "glcdi_member", "description": "Active GLCDI dataspace participant" },
      { "name": "glcdi_producer", "description": "Rancher / farming organisation" },
      { "name": "glcdi_researcher", "description": "Academic or scientific research institution" },
      { "name": "glcdi_data_steward", "description": "Data steward / conservation alliance" },
      { "name": "glcdi_conservation_org", "description": "Conservation organisation" },
      { "name": "glcdi_technology_provider", "description": "Ag-tech / data platform provider" },
      { "name": "glcdi_corporate", "description": "Food company / supply chain actor" },
      { "name": "glcdi_certification_body", "description": "Certification / verification body" },
      { "name": "glcdi_supply_chain_partner", "description": "Procurement / ESG reporting partner" },
      { "name": "glcdi_funder", "description": "Funding body / public sector partner" }
    ]
  }
}
```

## 2.2 Add certification status and contribution status as user attributes

| Item | Detail |
|------|--------|
| **Task** | Define `glcdi_certification_status` and `glcdi_contribution_status` as custom user attributes on each connector service-account user |
| **Certification values** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Contribution values** | `contributing` (has published data), `observer` (onboarded but no data published yet), `pending` (awaiting verification) |
| **Where** | Set on each `service-account-glcdi-connector-<org>` user in the realm JSON (`users[].attributes`). Adding a fourth participant = new connector client + SA user with the same attribute shape. |
| **Proposed owner for contribution status** | For the prototype (small participant set): it is proposed that the Dataspace Authority sets this manually after verifying that a participant's connector has published assets. For scaling: a periodic automated service could query each participant's catalog and update the attribute. |
| **Status** | [x] Declared on the 3 connector SA users in the realm JSON · [x] Imported into live Authority KC (verified by decoding a live JWT - § 2.5) |

## 2.3 Create protocol mappers for token serialisation

Realm roles are already included in tokens by default (in `realm_access.roles[]`), but we need
explicit mappers to surface claims in the format the EDC policy functions expect.

| Item | Detail |
|------|--------|
| **Task** | Add protocol mappers to relevant Keycloak clients so that GLCDI claims appear as top-level claims in access tokens |
| **Approach** | Realm-level **client scope** `glcdi-claims` carries all five mappers (one for `glcdi_roles` from realm roles; four `oidc-usermodel-attribute-mapper` entries for `glcdi_membership`, `glcdi_organisation`, `glcdi_certification_status`, `glcdi_contribution_status`). The scope is added to `defaultClientScopes` on each `glcdi-connector-<org>` client at Tier 1 (and on the future `glcdi-ui` client at Tier 2 - see § 7.2). No per-client mapper duplication. |
| **Where** | `authority-services/resources/keycloak/realms/glcdi-realm.json` - `clientScopes[]` array (the `glcdi-claims` scope) plus `defaultClientScopes` on each consuming client. |
| **Status** | [x] `glcdi-claims` client scope declared (5 mappers) · [x] Wired into `defaultClientScopes` on the 3 connector clients · [x] Imported into live Authority KC (decoded JWT shows `glcdi_membership`, `glcdi_roles`, `glcdi_certification_status` populated) |

**Five mappers in the `glcdi-claims` client scope (declarative, in the realm JSON):**

### Mapper 1: Realm roles → `glcdi_roles` claim

This mapper serialises all `glcdi_*` realm roles into a dedicated array claim, separate from
the default `realm_access.roles` which also includes Keycloak internal roles.

```json
{
  "name": "glcdi-roles",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-realm-role-mapper",
  "config": {
    "claim.name": "glcdi_roles",
    "jsonType.label": "String",
    "multivalued": "true",
    "usermodel.realmRoleMapping.rolePrefix": "glcdi_",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_roles": ["glcdi_member", "glcdi_producer"]
}
```

### Mapper 2: User attribute → `glcdi_certification_status` claim

```json
{
  "name": "glcdi-certification-status",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "claim.name": "glcdi_certification_status",
    "jsonType.label": "String",
    "user.attribute": "glcdi_certification_status",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_certification_status": "regenerative-verified"
}
```

### Mapper 2b: User attribute → `glcdi_contribution_status` claim

```json
{
  "name": "glcdi-contribution-status",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "claim.name": "glcdi_contribution_status",
    "jsonType.label": "String",
    "user.attribute": "glcdi_contribution_status",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

**Resulting token claim:**
```json
{
  "glcdi_contribution_status": "contributing"
}
```

### Mapper 3 (optional): Hardcoded `glcdi_membership` claim

As a shortcut, instead of checking for the `glcdi_member` role in the roles array, add a
hardcoded claim mapper on the client scope that applies to all authenticated users:

```json
{
  "name": "glcdi-membership-active",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-hardcoded-claim-mapper",
  "config": {
    "claim.name": "glcdi_membership",
    "claim.value": "active",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true"
  }
}
```

> **Note:** This gives `glcdi_membership=active` to every authenticated user. If you need to
> distinguish `suspended` or `pending` users, use a User Attribute mapper instead (like
> certification status) and manage the value per-user. For the prototype, all onboarded
> users are active, so a hardcoded claim is the simplest path.

## 2.4 Assign roles + attributes to the connector service-account users

| Item | Detail |
|------|--------|
| **Task** | Each `service-account-glcdi-connector-<org>` user in the realm JSON carries that org's realm roles directly and the `glcdi_membership` / `glcdi_organisation` / `glcdi_certification_status` / `glcdi_contribution_status` attributes. The realm JSON is the source of truth; live edits go through the admin console. |
| **Status** | [x] Declared in realm JSON: 3 connector clients + 3 SA users with role + attribute assignments · [x] Imported into live Authority KC (caney-fork → `glcdi_producer`; point-blue → `glcdi_researcher`; white-buffalo same as caney-fork) |

The Tier-1 assignment for the M1 trio (`caney-fork` / `white-buffalo` as regenerative producers, `point-blue` as researcher) is the canonical table in [`phase-1.5-identity-tier1.md § 1.5.4`](phase-1.5-identity-tier1.md#154-provision-connector-service-account-clients-in-the-authority-keycloak).

The proposed assignment *pattern* by participant type (for new onboardings beyond the M1 trio):

| Participant type | Realm roles | Cert status | Contribution status |
|------------------|-------------|-------------|---------------------|
| Regenerative producer | `glcdi_member`, `glcdi_producer` | `regenerative-verified` | `contributing` (after seeding) |
| Producer (non-regen) | `glcdi_member`, `glcdi_producer` | per declared status | `contributing` (after seeding) |
| Research institution | `glcdi_member`, `glcdi_researcher` | `not-applicable` | `contributing` (after seeding) |
| Data steward / monitoring alliance | `glcdi_member`, `glcdi_data_steward` | `not-applicable` | `observer` (until data published) |
| Newly onboarded (any type, no data yet) | `glcdi_member` + type role | per declared type | `observer` (until data published) |

**Live edit recipe** (post-import attribute tweaks via admin console - keep the realm JSON in sync afterwards):

```bash
KEYCLOAK_URL="https://authority.glcdi.startinblox.com"
REALM="glcdi"

# Get admin token
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq -r '.access_token')

# Resolve the SA user ID (example: caney-fork's connector)
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users?username=service-account-glcdi-connector-caney-fork" \
  | jq -r '.[0].id')

# Update the certification status attribute (e.g. promotion to regenerative-verified)
curl -s -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID" \
  -d "{\"attributes\": {\"glcdi_certification_status\": [\"regenerative-verified\"]}}"
```

## 2.5 Verify token contents

| Item | Detail |
|------|--------|
| **Task** | Confirm that tokens issued by Authority Keycloak contain the expected GLCDI claims |
| **Status** | [x] Done - for white-buffalo's SA token the decoded JWT showed `glcdi_membership=active`, `glcdi_roles=[glcdi_producer, glcdi_member]`, `glcdi_certification_status=regenerative-verified`, `glcdi_organisation=white-buffalo`, `glcdi_contribution_status=contributing` |

**Manual verification** (mint a token for a connector SA via `client_credentials` and decode):

```bash
# Request a token for a connector service account
TOKEN=$(curl -s -X POST \
  "https://authority.glcdi.startinblox.com/auth/realms/glcdi/protocol/openid-connect/token" \
  -d "client_id=glcdi-connector-caney-fork" \
  -d "client_secret=<rotated-from-changeme-glcdi-connector-caney-fork-secret>" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Decode and inspect (JWT is base64-encoded, middle segment is the payload)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**Expected output (relevant claims):**

```json
{
  "iss": "https://authority.glcdi.startinblox.com/auth/realms/glcdi",
  "sub": "<sa-user-uuid>",
  "azp": "glcdi-connector-caney-fork",
  "glcdi_membership": "active",
  "glcdi_organisation": "caney-fork",
  "glcdi_roles": ["glcdi_member", "glcdi_producer"],
  "glcdi_certification_status": "regenerative-verified",
  "glcdi_contribution_status": "contributing",
  "realm_access": {
    "roles": ["glcdi_member", "glcdi_producer", "user", "default-roles-glcdi"]
  }
}
```

## 2.6 Mapping from token claims to policy constraints

This table shows how each policy constraint maps to what the EDC policy function should
read from the token:

| Policy constraint | `leftOperand` | Token claim to read | Check logic |
|-------------------|---------------|---------------------|-------------|
| `glcdi:membership eq "active"` | `https://w3id.org/glcdi/v0.1.0/ns/membership` | `glcdi_membership` (string) | `claim == rightOperand` |
| `glcdi:participantType eq "producer"` | `https://w3id.org/glcdi/v0.1.0/ns/participantType` | `glcdi_roles` (array) | `"glcdi_" + rightOperand` present in array |
| `glcdi:participantType isAnyOf ["researcher","data-steward"]` | same | `glcdi_roles` (array) | any of `["glcdi_researcher","glcdi_data_steward"]` present in array |
| `glcdi:certificationStatus eq "regenerative-verified"` | `https://w3id.org/glcdi/v0.1.0/ns/certificationStatus` | `glcdi_certification_status` (string) | `claim == rightOperand` |
| `glcdi:certificationStatus isAnyOf [...]` | same | same | `claim` in `rightOperand` list |
| `glcdi:contributionStatus eq "contributing"` | `https://w3id.org/glcdi/v0.1.0/ns/contributionStatus` | `glcdi_contribution_status` (string) | `claim == rightOperand` |

> **Important:** The policy function for `participantType` needs to translate between the
> policy value (e.g., `"researcher"`) and the Keycloak role name (e.g., `"glcdi_researcher"`).
> The convention is: `"glcdi_" + participantType`. The function should handle this prefix
> transparently.

## 2.7 Integration with the onboarding flow (Tier 1: out-of-band)

| Item | Detail |
|------|--------|
| **Task** | At Tier 1, **connector** onboarding is **out-of-band**: the Authority operator extends the realm JSON with a new `glcdi-connector-<org>` client + SA user (same shape as § 2.4) and ships the secret to the participant operator via a side channel. Connectors are infrastructure, not human users - there is no need for a self-serve form here. The *human-org* onboarding case (registering the organization itself, creating its first operator user) is covered by the packaged flow in [§ Phase 1.6](phase-1.6-onboarding.md). |
| **Where** | `authority-services/resources/keycloak/realms/glcdi-realm.json` - append to `clients[]` and `users[]`. After import, also distribute the rotated `client_secret` via a vault / out-of-band channel for the participant's `participant/configuration.properties`. |
| **Status** | [ ] Not started - first new onboarding post-M1 will exercise this |

**Tier-1 onboarding sequence** (to be ratified by the Dataspace Authority):

1. Participant submits onboarding request (name, organisation, type, certification evidence).
2. The Dataspace Authority reviews and approves.
3. On approval, the Authority operator:
   - Adds a `glcdi-connector-<new-org>` client (with `serviceAccountsEnabled: true`, `glcdi-claims` default scope) and its SA user (with the right `glcdi_*` realm roles + attributes) to the realm JSON.
   - Imports / patches the live realm (admin console for a single client; Option 2 (partial import via Admin API) - see [`ops/vm-deployment.md` § 3](../../ops/vm-deployment.md)).
   - Rotates the placeholder secret and ships `client_id` / `client_secret` to the participant operator via vault / out-of-band channel.
4. The participant operator drops `client_id` / `client_secret` into `participant/configuration.properties` (`edc.oauth.client.id` / `edc.oauth.client.secret.alias` per § 3.5) and restarts the connector.

> **Tier-2 evolution:** when human-user onboarding becomes a requirement (per-user audit, role-gated UI views), the onboarding-app workflow described in § 7.2 takes over: the DjangoLDP approval UI calls the Keycloak Admin API to create human users in the org's group. The connector-SA flow above continues unchanged underneath.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 1.6: Packaged Organization Onboarding - Current Intermediate Delivery](phase-1.6-onboarding.md) · [next: Phase 3: EDC Policy Extension Development →](phase-3-edc-policy-extension.md)
