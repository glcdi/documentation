# AGENTS.md — GLCDI Management & Policies Context

This file provides context for AI agents working in the `management/` sub-directory of the
GLCDI project. It covers what this directory contains, how it relates to the broader project,
and what an agent needs to know to contribute effectively.

## What This Directory Is

`management/` is the **governance and policy design space** for the GLCDI dataspace. It
contains ODRL policy definitions, sequence diagrams showing end-user flows, and an
implementation plan for making those policies operational. It is not a deployable service —
it feeds into the three deployable sub-projects (`edc-connector/`, `governance-services/`,
`participant-agent-services/`).

```
management/
├── AGENTS.md                          # This file
├── TODO.md                            # Policy implementation plan (7 phases)
└── policies/
    ├── README.md                      # Full policy documentation
    ├── access/                        # Access policies (catalog visibility)
    │   ├── members-only.json          # Any active GLCDI participant
    │   ├── organic-producers.json     # Certified organic/regenerative producers only
    │   └── researchers-only.json      # Research institutions and data stewards only
    ├── contract/                      # Contract policies (usage terms)
    │   ├── time-limited.json          # Usage until a specific date
    │   ├── internal-use-only.json     # No redistribution to third parties
    │   ├── anonymisation.json         # Must anonymise before processing
    │   ├── payment-required.json      # Payment duty before access
    │   ├── attribution.json           # Citation/attribution required
    │   ├── non-commercial.json        # No commercial exploitation
    │   ├── purpose-model-training.json  # Model training purpose only
    │   └── data-retention-limit.json  # Delete data after agreed period
    ├── combined/                      # End-to-end scenario examples
    │   ├── researcher-model-feeding.json    # Agronomic model calibration
    │   ├── rancher-benchmarking.json        # Regional benchmarking
    │   └── corporate-supply-chain.json      # ESG / Scope 3 reporting
    └── diagrams/                      # PlantUML sequence diagrams
        ├── 01-researcher-accesses-soc-data.puml
        ├── 02-producer-blocked-from-research-data.puml
        ├── 03-rancher-benchmarking.puml
        ├── 04-wrong-purpose-rejected.puml
        ├── 05-organic-producers-exclusive.puml
        ├── 06-time-limited-expiry.puml
        └── 07-corporate-supply-chain-flow.puml
```

## What is GLCDI?

The **Grazing Lands Carbon Data Initiative (GLCDI)** is a federated data space that links
soil organic carbon (SOC) measurements with grazing management records across U.S. grazing
lands. Funded by the Walmart Foundation, the prototype runs **January–September 2026**.

Three use cases drive the prototype:

1. **Regional benchmarking** — ranchers compare grazing strategies and SOC outcomes
2. **Agronomic model calibration** — researchers train models predicting SOC response
3. **Peer-to-peer data sharing** — consent-governed exchange between participants

## Key Participants

| Participant | Type | Token role | Assets |
|-------------|------|-----------|--------|
| Caney Fork Farms | Producer (ranch) | `glcdi_producer` | SOC measurements, grazing rotation, paddock boundaries, NDVI |
| Point Blue Conservation Science | Researcher (NGO) | `glcdi_researcher` | Rangeland SOC, GHG flux, biodiversity surveys, weather, carbon credits |
| White Buffalo Land Trust | Producer (NGO/ranch) | `glcdi_producer` | Monitoring datasets, grazing records |
| TSIP (Q2) | Data steward | `glcdi_data_steward` | SOC sampling metadata |
| University of Florida (Q2) | Researcher | `glcdi_researcher` | TBD |

Future (post-prototype): corporate supply-chain partners, certification bodies, funders.

## How Policies Work in This Dataspace

### Two-Layer Model

Every data asset published by a participant is governed by two policies:

- **Access policy** — evaluated when a consumer queries the catalog. Controls **who can see**
  the offer. If the consumer's identity doesn't satisfy the constraints, the offer is hidden.
- **Contract policy** — evaluated during contract negotiation. Controls **what the consumer
  can do** with the data. The consumer must accept these terms before transfer.

Both are linked to assets through a **Contract Definition**:

```
Contract Definition = Asset Selector + Access Policy ID + Contract Policy ID
```

### Constraint Mechanism (OIDC Claims)

Policy constraints reference claims from the consumer's Keycloak token. For the prototype,
the implementation uses:

| Claim | Source | Values |
|-------|--------|--------|
| `glcdi_membership` | Hardcoded claim mapper (all authenticated users = `"active"`) | `active`, `suspended`, `pending` |
| `glcdi_roles` | Realm role mapper (prefix `glcdi_`) | `["glcdi_member", "glcdi_producer"]`, etc. |
| `glcdi_certification_status` | User attribute mapper | `organic-certified`, `regenerative-verified`, `transitioning-organic`, `conventional`, `not-applicable` |

### Mapping: Policy Constraint → Token Claim → Check Logic

| Policy `leftOperand` | Token claim | How the EDC policy function checks it |
|----------------------|-------------|--------------------------------------|
| `glcdi:membership` | `glcdi_membership` (string) | `claim == rightOperand` |
| `glcdi:participantType` | `glcdi_roles` (array) | `"glcdi_" + rightOperand` present in array |
| `glcdi:participantType` (isAnyOf) | `glcdi_roles` (array) | any of `["glcdi_" + v for v in rightOperand]` present |
| `glcdi:certificationStatus` | `glcdi_certification_status` (string) | `claim == rightOperand` or `claim in rightOperand` |
| `odrl:dateTime` | System clock | Native EDC — no custom function needed |
| `odrl:purpose` | Consumer's contract offer | Native EDC — consumer declares purpose |
| `odrl:elapsedTime` | Transfer timestamp + clock | Needs custom function |
| `odrl:payAmount` | External payment system | Needs custom function + external API |

### Custom Namespace

All GLCDI-specific terms use the prefix `glcdi:` mapped to `https://w3id.org/glcdi/v0.1.0/ns/`.

## Architecture Context

### Identity Federation Flow

```
User → Participant Keycloak (local auth) → Governance Keycloak (OIDC broker)
                                                  ↓
                                           Adds GLCDI roles + claims
                                                  ↓
                                           Token issued to connector
                                                  ↓
                                    Provider's EDC evaluates token claims
                                    against access/contract policies
```

The **governance Keycloak** (`governance.glcdi.startinblox.com`, realm `glcdi`) is the source
of truth for roles and membership. Participants authenticate at their local Keycloak, which
brokers to governance via OIDC identity providers (`caney-fork`, `point-blue`).

### Data Exchange Flow (with policy evaluation)

```
1. Consumer connector sends DSP Catalog Query to Provider connector
2. Provider evaluates ACCESS POLICY for each asset against consumer's token
3. Only matching assets are returned in the catalog response
4. Consumer selects an offer and initiates CONTRACT NEGOTIATION (with purpose declaration)
5. Provider evaluates CONTRACT POLICY against the offer
6. If accepted → Contract Agreement (FINALIZED)
7. Consumer requests DATA TRANSFER
8. Provider sends data via HTTP data plane
```

See `policies/diagrams/` for detailed PlantUML sequence diagrams of each scenario.

## Current Implementation State (March 2026)

| Component | Status |
|-----------|--------|
| Policy JSON definitions | Done (this directory) |
| Sequence diagrams | Done (7 diagrams) |
| Implementation plan | Done (`TODO.md`) |
| GLCDI vocabulary / namespace | Not started (TODO Phase 1) |
| Keycloak realm roles | Not started (TODO Phase 2) |
| Keycloak protocol mappers | Not started (TODO Phase 2) |
| EDC policy functions extension | Not started (TODO Phase 3) |
| Updated seeding scripts | Not started (TODO Phase 4) |
| Integration tests | Not started (TODO Phase 5) |
| DSA/legal templates | Not started (TODO Phase 6) |

**Currently deployed:** The seeding scripts in `participant-agent-services/scripts/` use a
single `glcdi:policy:open-research` policy (simple `"action": "use"` with no constraints).
The policies in this directory are the target state.

## Files That Will Be Affected by This Work

When implementing the policies from this directory, agents will need to modify:

| File | What changes |
|------|-------------|
| `governance-services/resources/keycloak/realms/glcdi-realm.json` | Add realm roles, protocol mappers, user attributes |
| `edc-connector/extensions/` (new) | New `glcdi-policy-functions` extension |
| `edc-connector/settings.gradle.kts` | Include new extension module |
| `edc-connector/runtimes/controlplane/build.gradle.kts` | Add extension dependency |
| `participant-agent-services/scripts/seed-caney-fork.sh` | Replace open-research with per-asset policies |
| `participant-agent-services/scripts/seed-point-blue.sh` | Same |
| `participant-agent-services/scripts/` (new) | New test scripts for policy validation |
| `governance-services/onboarding/backend/` | Auto-assign roles on participant approval |

## Conventions in This Directory

- **Policy files** are valid JSON-LD, using the EDC Management API format (can be POSTed directly to `/management/v3/policydefinitions`)
- **Policy IDs** follow `glcdi:access:<name>` or `glcdi:contract:<name>`
- **Combined files** are documentation-oriented — they group an access policy, contract policy, and contract definition example in one file (not directly POSTable as-is)
- **Diagrams** are PlantUML `.puml` files, renderable with `docker run --rm -v "$PWD/diagrams":/data plantuml/plantuml /data/*.puml`
- **Comments** in JSON use a `"comment"` field (not standard JSON but common in EDC examples for documentation)

## Broader Project Context

This `management/` directory sits within the GLCDI workspace:

```
glcdi/
├── edc-connector/                 # Eclipse EDC connector (Java 17, Gradle, EDC 0.15.1)
├── governance-services/           # Keycloak + onboarding (Docker Compose)
├── participant-agent-services/    # Per-participant stack (Docker Compose)
├── participant-ui/                # Frontend (early stage)
├── management/                    # ← You are here
├── diagrams/                      # Architecture diagrams (PlantUML)
└── TODO.md                        # Main project plan (6 phases, Phase 1 done)
```

Parent workspace `~/workspace/dataspaces/` contains sister projects (TEMS, MVD, EDC core,
Federated Catalogue, vocabulary registry) that serve as reference implementations.

## Important Caveats

- **Policy functions don't exist yet** — the `glcdi:membership` and `glcdi:participantType`
  constraints in policy files require a custom EDC extension (see `TODO.md` Phase 3)
- **Governance-level obligations are not technically enforced** — anonymisation, attribution,
  deletion duties rely on the Data Sharing Agreement, not the connector
- **`combined/` files are not directly POSTable** — they bundle access + contract + contract
  definition for documentation; extract the individual policies to use them
- **Temporal constraints work natively** in EDC; all other custom constraints need the
  `glcdi-policy-functions` extension
- **The `glcdi:` namespace is not yet registered** — it needs a JSON-LD context file
  (see `TODO.md` Phase 1)
