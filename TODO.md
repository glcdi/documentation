# GLCDI Policy Support — Implementation Plan

Implementation steps to make the ODRL policies defined in `./policies/` operational in the
GLCDI dataspace. This covers vocabulary registration, Keycloak configuration, EDC extension
development, integration into seeding scripts, and testing.

Phases are ordered by dependency. Steps within a phase can largely be parallelised.

---

## Phase 1: GLCDI Vocabulary & Namespace

Before any policy can be evaluated, the custom terms used in constraints need to be formally
defined and resolvable.

### 1.1 Register the `glcdi:` namespace

| Item | Detail |
|------|--------|
| **Task** | Define the JSON-LD context file for `https://w3id.org/glcdi/v0.1.0/ns/` |
| **Deliverable** | `glcdi-context.jsonld` hosted at the namespace URI (or bundled into the connector) |
| **Content** | Map all custom terms: `membership`, `participantType`, `certificationStatus`, `InternalAnalysis`, `ScientificResearch`, `AgronomicModelTraining`, `EcosystemModelCalibration`, `ModelOutput`, `RegionalBenchmarking`, `EducationalUse`, `ConservationPlanning`, `Scope3Reporting`, `ESGCompliance`, `CertificationVerification`, `RawData`, `OriginalProvider` |
| **Where** | Could live in `tems-vocabulary-registry` alongside TEMS vocabularies, or in a new `glcdi-vocabulary` repo. For the prototype, bundling in the connector classpath is simplest. |
| **Status** | [ ] Not started |

### 1.2 Document participant types and certification statuses

| Item | Detail |
|------|--------|
| **Task** | Agree on the canonical list of `participantType` and `certificationStatus` values with the Steering Committee |
| **Proposed participant types** | `producer`, `researcher`, `data-steward`, `conservation-org`, `technology-provider`, `corporate`, `certification-body`, `supply-chain-partner`, `funder` |
| **Proposed certification statuses** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Deliverable** | Enumeration documented in the vocabulary context and in the Trust Framework (v0) |
| **Status** | [ ] Not started |

### 1.3 Define ODRL purpose taxonomy

| Item | Detail |
|------|--------|
| **Task** | Formalise the set of purpose values that consumers can declare in contract offers |
| **Proposed values** | `InternalAnalysis`, `ScientificResearch`, `AgronomicModelTraining`, `EcosystemModelCalibration`, `RegionalBenchmarking`, `EducationalUse`, `ConservationPlanning`, `Scope3Reporting`, `ESGCompliance`, `CertificationVerification`, `ModelOutput` |
| **Why** | Purpose constraints in policies (e.g., `purpose-model-training.json`) rely on consumers declaring a purpose from this controlled vocabulary. Without agreement on the terms, policies cannot be consistently evaluated. |
| **Status** | [ ] Not started |

---

## Phase 2: Keycloak Claims Configuration — Participant Types via OIDC

Policies like `members-only`, `regenerative-producers`, and `researchers-only` evaluate claims from
the consumer's identity token. For the prototype, we rely on **Keycloak realm roles** serialised
as OIDC claims in access tokens, rather than Verifiable Credentials (which are a post-prototype
goal — see Phase 7.2).

### Architecture Decision: Realm Roles vs. User Attributes

Two Keycloak mechanisms can carry participant type information into tokens:

| Approach | How it works | Pros | Cons |
|----------|-------------|------|------|
| **Realm roles** | Create roles like `glcdi_producer`, `glcdi_researcher`, assign to users. Roles appear in `realm_access.roles[]` in the token by default. | Zero mapper configuration needed. Roles are built into Keycloak's RBAC. Easy to manage in admin console. Can be assigned during onboarding. | Flat list — no structured key/value. Checking "is this user a researcher?" means looking for `glcdi_researcher` in an array. |
| **User attributes** | Set custom key/value pairs on user profiles (`glcdi_participant_type=researcher`). Add protocol mappers to serialize into token claims. | Structured data. Clean namespace. Can represent multi-valued attributes naturally. | Requires explicit protocol mapper configuration per client. Slightly more setup. |

**Recommendation for prototype:** Use **realm roles for participant type and membership** (simplest
path — no mapper config, works immediately) and **user attributes for certification status**
(since it's a structured value, not a boolean flag). This hybrid approach minimises
configuration while keeping the data model clean.

### 2.1 Create GLCDI realm roles

| Item | Detail |
|------|--------|
| **Task** | Add realm roles to the `glcdi` realm in governance Keycloak |
| **Roles to create** | `glcdi_member` (active membership), `glcdi_producer`, `glcdi_researcher`, `glcdi_data_steward`, `glcdi_conservation_org`, `glcdi_technology_provider`, `glcdi_corporate`, `glcdi_certification_body`, `glcdi_supply_chain_partner`, `glcdi_funder` |
| **Where** | `governance-services/resources/keycloak/realms/glcdi-realm.json` — in the `roles.realm[]` array |
| **Status** | [ ] Not started |

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

### 2.2 Add certification status and contribution status as user attributes

| Item | Detail |
|------|--------|
| **Task** | Define `glcdi_certification_status` and `glcdi_contribution_status` as custom user attributes |
| **Certification values** | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |
| **Contribution values** | `contributing` (has published data), `observer` (onboarded but no data published yet), `pending` (awaiting verification) |
| **Where** | Set per-user in Keycloak admin console or via Admin API. Not part of the realm export by default — attributes are per-user, not schema-level. |
| **Who updates contribution status** | For the prototype (3–5 participants): the Steering Committee sets this manually after verifying that a participant's connector has published assets. For scaling: a periodic automated service queries each participant's catalog and updates the attribute. |
| **Status** | [ ] Not started |

### 2.3 Create protocol mappers for token serialisation

Realm roles are already included in tokens by default (in `realm_access.roles[]`), but we need
explicit mappers to surface claims in the format the EDC policy functions expect.

| Item | Detail |
|------|--------|
| **Task** | Add protocol mappers to relevant Keycloak clients so that GLCDI claims appear as top-level claims in access tokens |
| **Status** | [ ] Not started |

**Three mappers to create, on each of these clients:** `edc-api-client`, `participant-broker`, `catalog-ui-governance`

#### Mapper 1: Realm roles → `glcdi_roles` claim

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

#### Mapper 2: User attribute → `glcdi_certification_status` claim

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

#### Mapper 2b: User attribute → `glcdi_contribution_status` claim

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

#### Mapper 3 (optional): Hardcoded `glcdi_membership` claim

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

### 2.4 Assign roles to prototype participants

| Item | Detail |
|------|--------|
| **Task** | Assign the correct realm roles and user attributes to each prototype participant's service account or user |
| **Status** | [ ] Not started |

| Participant | Realm Roles | Certification Status | Contribution Status |
|-------------|-------------|---------------------|---------------------|
| Caney Fork Farms | `glcdi_member`, `glcdi_producer` | `regenerative-verified` | `contributing` (after seeding) |
| Point Blue Conservation Science | `glcdi_member`, `glcdi_researcher` | `not-applicable` | `contributing` (after seeding) |
| White Buffalo Land Trust | `glcdi_member`, `glcdi_producer` | `regenerative-verified` | `observer` (until data published) |
| TSIP (if onboarded Q2) | `glcdi_member`, `glcdi_data_steward` | `not-applicable` | `observer` (until data published) |
| University of Florida (if onboarded Q2) | `glcdi_member`, `glcdi_researcher` | `not-applicable` | `observer` (until data published) |

**Via Keycloak Admin API:**

```bash
KEYCLOAK_URL="https://governance.glcdi.startinblox.com"
REALM="glcdi"

# Get admin token
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq -r '.access_token')

# Get user ID (example: Caney Fork service account)
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users?username=caney-fork-sa" \
  | jq -r '.[0].id')

# Get role IDs
MEMBER_ROLE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/roles/glcdi_member" \
  | jq -r '.id')
PRODUCER_ROLE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/roles/glcdi_producer" \
  | jq -r '.id')

# Assign realm roles
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID/role-mappings/realm" \
  -d "[
    {\"id\": \"$MEMBER_ROLE_ID\", \"name\": \"glcdi_member\"},
    {\"id\": \"$PRODUCER_ROLE_ID\", \"name\": \"glcdi_producer\"}
  ]"

# Set certification status attribute
curl -s -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$KEYCLOAK_URL/auth/admin/realms/$REALM/users/$USER_ID" \
  -d "{\"attributes\": {\"glcdi_certification_status\": [\"regenerative-verified\"]}}"
```

### 2.5 Update identity provider mappers for federation

| Item | Detail |
|------|--------|
| **Task** | When a participant authenticates via their local Keycloak (e.g., caney-fork IdP) and is brokered to governance Keycloak, the GLCDI roles and attributes must be present in the resulting token |
| **Status** | [ ] Not started |

There are two approaches depending on where the source of truth for roles lives:

#### Option A: Governance Keycloak is source of truth (recommended for prototype)

Roles and attributes are assigned **on the governance Keycloak user** (the federated/brokered
identity), not on the participant's local Keycloak. The local Keycloak only handles
authentication; the governance Keycloak handles authorisation.

- No IdP mapper changes needed for roles — they are already on the governance-side user.
- Protocol mappers on the `edc-api-client` / `participant-broker` clients serialize them.
- Simpler: one place to manage all role assignments.

#### Option B: Participant Keycloak is source of truth (for future decentralisation)

Roles are assigned on the participant's local Keycloak and imported into governance during
federation. This requires:

1. **On participant Keycloak** (`edc` realm): add the same `glcdi_*` realm roles and assign them.
2. **On governance Keycloak** (IdP configuration for `caney-fork`): add an "Attribute Importer"
   or "Claim to Role" mapper:

```json
{
  "name": "import-glcdi-roles",
  "identityProviderMapper": "oidc-advanced-role-idp-mapper",
  "identityProviderAlias": "caney-fork",
  "config": {
    "syncMode": "INHERIT",
    "claims": "[{\"key\":\"glcdi_roles\",\"value\":\"glcdi_producer\"}]",
    "role": "glcdi_producer"
  }
}
```

> **Recommendation:** Start with Option A (governance as source of truth). It's the right
> choice for a prototype with 3-5 participants managed by a central governance team.
> Move to Option B when participants need to self-manage their roles (post-prototype scaling).

### 2.6 Verify token contents

| Item | Detail |
|------|--------|
| **Task** | Confirm that tokens issued by governance Keycloak contain the expected GLCDI claims |
| **Status** | [ ] Not started |

**Manual verification:**

```bash
# Request a token for Caney Fork's service account
TOKEN=$(curl -s -X POST \
  "https://governance.glcdi.startinblox.com/auth/realms/glcdi/protocol/openid-connect/token" \
  -d "client_id=edc-api-client" \
  -d "client_secret=changeme-edc-api-client-secret" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Decode and inspect (JWT is base64-encoded, middle segment is the payload)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**Expected output (relevant claims):**

```json
{
  "iss": "https://governance.glcdi.startinblox.com/auth/realms/glcdi",
  "sub": "...",
  "glcdi_membership": "active",
  "glcdi_roles": ["glcdi_member", "glcdi_producer"],
  "glcdi_certification_status": "regenerative-verified",
  "realm_access": {
    "roles": ["glcdi_member", "glcdi_producer", "user", "default-roles-glcdi"]
  }
}
```

### 2.7 Mapping from token claims to policy constraints

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

### 2.8 Integration with the onboarding flow

| Item | Detail |
|------|--------|
| **Task** | When a new participant is onboarded via the onboarding app, automatically assign appropriate GLCDI roles |
| **Where** | `governance-services/onboarding/backend/` — the DjangoLDP approval workflow should call the Keycloak Admin API to assign roles upon approval |
| **Status** | [ ] Not started |

**Flow:**

1. Participant submits onboarding request (name, organisation, type, certification evidence)
2. Steering Committee reviews and approves via the approval UI
3. On approval, the backend calls the Keycloak Admin API to:
   - Create or update the user
   - Assign `glcdi_member` + the appropriate type role (e.g., `glcdi_producer`)
   - Set `glcdi_certification_status` attribute (validated by governance team)
4. Participant receives confirmation and can now authenticate

This automates the role assignment from step 2.4, removing the need for manual admin
console operations as the dataspace grows beyond the initial 3 participants.

---

## Phase 3: EDC Policy Extension Development

The EDC connector needs custom policy functions to evaluate GLCDI-specific constraints.
Without these, constraints referencing `glcdi:membership` or `glcdi:participantType` will be
silently ignored (default: permit) or fail closed, depending on EDC configuration.

### 3.1 Create `glcdi-policy-functions` extension

| Item | Detail |
|------|--------|
| **Task** | Create a new EDC extension in `edc-connector/extensions/glcdi-policy-functions/` |
| **Language** | Java 17 |
| **Build** | Add to `settings.gradle.kts`, create `build.gradle.kts` with EDC policy SPI dependencies |
| **Status** | [ ] Not started |

### 3.2 Implement membership policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:membership` |
| **Behaviour** | Extract the `glcdi_membership` claim from the participant's identity (via `ParticipantAgent`), compare it to the constraint's `rightOperand` |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/membership"` |
| **Used by** | `access/members-only.json`, `access/regenerative-producers.json`, `access/researchers-only.json`, and all combined policies |
| **Status** | [ ] Not started |

### 3.3 Implement participant type policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:participantType` |
| **Behaviour** | Extract `glcdi_participant_type` claim, support `eq` and `isAnyOf` operators |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/participantType"` |
| **Used by** | `access/regenerative-producers.json`, `access/researchers-only.json`, `combined/corporate-supply-chain.json` |
| **Status** | [ ] Not started |

### 3.4 Implement certification status policy function

| Item | Detail |
|------|--------|
| **Task** | Implement an `AtomicConstraintFunction` that evaluates `glcdi:certificationStatus` |
| **Behaviour** | Extract `glcdi_certification_status` claim, support `eq` and `isAnyOf` operators |
| **Registers for** | `leftOperand = "https://w3id.org/glcdi/v0.1.0/ns/certificationStatus"` |
| **Used by** | `access/regenerative-producers.json` |
| **Status** | [ ] Not started |

### 3.5 Configure claim resolution from Keycloak tokens

| Item | Detail |
|------|--------|
| **Task** | Ensure the EDC connector can extract custom claims from the OIDC tokens presented during DSP interactions |
| **Mechanism** | The `IdentityService` / `ParticipantAgent` in EDC must be configured to pass through the Keycloak claims. This may require configuring the `oauth2` or `iam` extension to include custom claim mappings. |
| **Where** | `participant/configuration.properties` or the identity hub configuration |
| **Status** | [ ] Not started |

### 3.6 Register extension in connector runtime

| Item | Detail |
|------|--------|
| **Task** | Add `glcdi-policy-functions` as a dependency in `runtimes/controlplane/build.gradle.kts` |
| **Deliverable** | Rebuilt connector image with the policy functions available |
| **Status** | [ ] Not started |

---

## Phase 4: Update Seeding Scripts & Contract Definitions

Replace the current `glcdi:policy:open-research` (simple "use" permission with no constraints)
with the richer policies from `./policies/`.

### 4.1 Update `seed-caney-fork.sh`

| Item | Detail |
|------|--------|
| **Task** | Replace the single open-research policy with appropriate policies per asset |
| **SOC measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `time-limited` + `attribution` (for model calibration use case) |
| **Grazing rotation** | Access: `members-only` / Contract: `non-commercial` + `attribution` (for benchmarking use case) |
| **Paddock boundaries** | Access: `members-only` / Contract: `internal-use-only` + `time-limited` (sensitive spatial data) |
| **NDVI time series** | Access: `members-only` / Contract: `attribution` (lower sensitivity, broader sharing) |
| **Status** | [ ] Not started |

### 4.2 Update `seed-point-blue.sh`

| Item | Detail |
|------|--------|
| **Task** | Replace open-research policy with policies appropriate for a research institution's data |
| **Rangeland SOC inventory** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **GHG flux measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `attribution` |
| **Biodiversity surveys** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **Weather station data** | Access: `members-only` / Contract: `attribution` (low sensitivity) |
| **Carbon credit reports** | Access: `members-only` / Contract: `internal-use-only` + `anonymisation` (commercially sensitive) |
| **Status** | [ ] Not started |

### 4.3 Create seeding helper for policy registration

| Item | Detail |
|------|--------|
| **Task** | Add a section to seeding scripts that registers all needed policy definitions before creating contract definitions, reading from the JSON files in `management/policies/` |
| **Approach** | Loop over the required policy JSON files and POST them to `/management/v3/policydefinitions`. Then create contract definitions that reference the registered policy IDs. |
| **Status** | [ ] Not started |

---

## Phase 5: Testing & Validation

### 5.1 Unit test policy functions

| Item | Detail |
|------|--------|
| **Task** | Write JUnit tests for each policy function (membership, participantType, certificationStatus) |
| **Test cases** | Active member passes, suspended member fails, correct type passes, wrong type fails, `isAnyOf` with multiple values, missing claim handling |
| **Where** | `edc-connector/extensions/glcdi-policy-functions/src/test/` |
| **Status** | [ ] Not started |

### 5.2 Integration test: access policy filtering

| Item | Detail |
|------|--------|
| **Task** | Verify that catalog queries correctly filter offers based on access policies |
| **Test scenario 1** | Caney Fork (producer) queries Point Blue's catalog → sees assets with `members-only` access, does NOT see assets with `researchers-only` access |
| **Test scenario 2** | Point Blue (researcher) queries Caney Fork's catalog → sees all assets (both `members-only` and `researchers-only`) |
| **Test scenario 3** | Unauthenticated or non-member query → sees nothing |
| **Where** | Extend `test-dsp-catalog-query.sh` or create `test-policy-filtering.sh` |
| **Status** | [ ] Not started |

### 5.3 Integration test: contract negotiation with constraints

| Item | Detail |
|------|--------|
| **Task** | Verify that contract negotiation enforces contract policy constraints |
| **Test scenario 1** | Point Blue negotiates for SOC data with `purpose=AgronomicModelTraining` → negotiation succeeds |
| **Test scenario 2** | Point Blue negotiates for SOC data with `purpose=Scope3Reporting` → negotiation is rejected (wrong purpose) |
| **Test scenario 3** | Caney Fork negotiates for Point Blue benchmarking data with `purpose=RegionalBenchmarking` → succeeds |
| **Where** | Extend `negotiate-and-transfer.sh` or create `test-contract-policies.sh` |
| **Status** | [ ] Not started |

### 5.4 Integration test: temporal constraint enforcement

| Item | Detail |
|------|--------|
| **Task** | Verify that time-limited policies are enforced |
| **Test scenario** | Set a policy with a past expiry date → contract negotiation should be rejected |
| **Note** | This is the easiest policy to test since temporal constraints work natively in EDC |
| **Status** | [ ] Not started |

### 5.5 End-to-end combined scenario test

| Item | Detail |
|------|--------|
| **Task** | Run the full agronomic model calibration flow end-to-end |
| **Steps** | 1. Register policies from `combined/researcher-model-feeding.json` on Caney Fork's connector. 2. Create contract definition linking SOC asset to these policies. 3. From Point Blue's connector, query Caney Fork's catalog → SOC asset visible. 4. Negotiate contract with `purpose=AgronomicModelTraining` → FINALIZED. 5. Initiate data transfer → succeeds. 6. Repeat from a producer connector → catalog query should NOT show the asset (researchers-only access). |
| **Deliverable** | `test-model-calibration-scenario.sh` script |
| **Status** | [ ] Not started |

---

## Phase 6: Governance-Level Enforcement (Non-Technical)

Some policy obligations cannot be technically enforced by the connector. These need
governance-level support through the Trust Framework and Data Sharing Agreements.

### 6.1 Embed policy obligations in Data Sharing Agreement templates

| Item | Detail |
|------|--------|
| **Task** | Update MOU/DSA templates to include clauses that map to ODRL obligations |
| **Clauses needed** | Anonymisation requirements (what counts as anonymised, at what geographic granularity), attribution format and placement, data retention/deletion procedures and confirmation process, non-redistribution commitments, purpose limitations |
| **Deliverable** | Updated DSA template in the Trust Framework (v0 → v1) |
| **Status** | [ ] Not started |

### 6.2 Define audit and compliance mechanisms

| Item | Detail |
|------|--------|
| **Task** | Establish how governance-level obligations (anonymisation, deletion, attribution) will be verified |
| **Options** | Self-attestation (lightweight, suitable for prototype), periodic review by Steering Committee, automated checks where possible (e.g., scanning published papers for attribution) |
| **Deliverable** | Compliance section in Trust Framework v1 |
| **Status** | [ ] Not started |

### 6.3 Design consent revocation flow

| Item | Detail |
|------|--------|
| **Task** | Define what happens when a producer wants to revoke consent for a previously shared dataset |
| **Considerations** | Contracts already finalized cannot be technically un-done, but new transfers can be blocked. Retention limits (e.g., `data-retention-limit.json`) provide a natural expiry. The revocation should trigger a notification to the consumer with a deletion request. |
| **Deliverable** | Revocation procedure documented in Trust Framework |
| **Status** | [ ] Not started |

---

## Phase 7: Future Enhancements (Post-Prototype)

Items from `./policies/` that are relevant for later phases but not required for the prototype.

### 7.1 Payment infrastructure

| Item | Detail |
|------|--------|
| **Task** | Implement the `payment-required` contract policy |
| **Requires** | External payment/invoicing system, custom EDC policy function to verify payment status before approving negotiation |
| **When** | Post-prototype, when corporate participants join and a sustainability model is needed |
| **Status** | [ ] Not started |

### 7.2 Verifiable Credentials integration

| Item | Detail |
|------|--------|
| **Task** | Replace Keycloak-based claims with W3C Verifiable Credentials for participant attributes |
| **Why** | VCs are the long-term standard for decentralised identity in dataspaces (aligned with Gaia-X, DSBA). Keycloak claims are a pragmatic prototype shortcut. |
| **Requires** | EDC Identity Hub configuration, VC issuance by the governance authority, updated policy functions to resolve from VCs instead of OIDC tokens |
| **When** | Phase following prototype, aligned with broader GLCDI scaling |
| **Status** | [ ] Not started |

### 7.3 Federated Catalogue policy metadata

| Item | Detail |
|------|--------|
| **Task** | Publish policy summaries as part of self-descriptions in the Federated Catalogue |
| **Why** | Allows participants to discover what terms apply to an asset before initiating contract negotiation — improving UX and reducing failed negotiations |
| **Requires** | Federated Catalogue deployment (currently deferred from governance stack) |
| **Status** | [ ] Not started |

### 7.4 Policy UI in participant dashboard

| Item | Detail |
|------|--------|
| **Task** | Add a policy management interface to the participant UI, allowing producers to select from pre-defined policy templates when publishing assets |
| **Why** | Currently policies are registered via API/scripts. A UI lowers the barrier for non-technical participants (ranchers). |
| **Requires** | `participant-ui` development |
| **Status** | [ ] Not started |

---

## Dependency Graph

```
Phase 1 (Vocabulary)
    │
    ├──→ Phase 2 (Keycloak Claims)
    │        │
    │        └──→ Phase 3 (EDC Extension) ──→ Phase 5 (Testing)
    │                    │
    │                    └──→ Phase 4 (Seeding Scripts)
    │
    └──→ Phase 6 (Governance / Legal) — can proceed in parallel
                                         with technical phases

Phase 7 (Future) — independent, post-prototype
```

## Relation to Main Project Phases

| This TODO phase | Maps to project TODO.md phase |
|-----------------|-------------------------------|
| Phase 1–2 | Between Phase 1 (done) and Phase 2 (infra) — can start now |
| Phase 3 | During Phase 2–3, before first deployment |
| Phase 4 | Replaces the simple policies in Phase 5 (seeding) |
| Phase 5 | Extends Phase 5 (integration testing) |
| Phase 6 | Parallel to Phase 5, aligned with Trust Framework v0→v1 |
| Phase 7 | Maps to Phase 6 (production hardening) and beyond |
