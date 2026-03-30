# AGENTS.md — GLCDI Dataspace Project Context

This file provides context for AI agents (Claude Code, Copilot, Cursor, etc.) working in
this repository. It captures the project's purpose, architecture, conventions, and current
state to help agents make informed decisions without needing to rediscover context each time.

## What is GLCDI?

The **Grazing Lands Carbon Data Initiative (GLCDI)** is building a federated data space
that links soil organic carbon (SOC) measurements with grazing management records across
U.S. grazing lands. The goal is to help ranchers, researchers, and conservation organisations
share data in a trusted, consent-governed way to:

- Enable **regional benchmarking** of grazing strategies and SOC outcomes
- Feed **predictive agronomic models** that estimate SOC response to management practices
- Support **peer-to-peer data sharing** between ranches and research institutions

GLCDI is funded by the Walmart Foundation. The prototype phase runs **January–September 2026**.

## Project Structure

This is a **monorepo workspace** containing three logical sub-projects plus shared management
resources:

```
glcdi/
├── edc-connector/                 # Eclipse EDC connector (control + data plane)
├── governance-services/           # Central authority (Keycloak, onboarding, Nginx)
├── participant-agent-services/    # Per-participant deployment stack
├── participant-ui/                # Frontend (early stage)
├── management/                    # Policies, implementation plans
│   ├── policies/                  # ODRL policy definitions + diagrams
│   └── TODO.md                    # Policy implementation plan
├── diagrams/                      # Architecture diagrams (PlantUML)
└── TODO.md                        # Main project implementation plan (6 phases)
```

Each of the three main sub-projects also has its own GitLab repo at
`git.startinblox.com/applications/glcdi/`.

## Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Connector runtime | Eclipse Dataspace Components (EDC) | 0.15.1 |
| Build system | Gradle | 8.10 |
| Language (connector) | Java | 17+ |
| Identity / Auth | Keycloak | Latest |
| Onboarding backend | DjangoLDP | Python 3.12+ |
| Reverse proxy | Nginx | Latest |
| Container orchestration | Docker Compose | Latest |
| CI/CD | GitLab CI | - |
| Container registry | `registry.startinblox.com` | - |
| Diagrams | PlantUML | - |

## Key Participants

| Participant | Type | Hosted at | Role |
|-------------|------|-----------|------|
| Caney Fork Farms | Producer (ranch) | `caney-fork.glcdi.startinblox.com` | Data provider: SOC, grazing rotation, paddock boundaries, NDVI |
| Point Blue Conservation Science | Researcher (NGO) | `point-blue.glcdi.startinblox.com` | Data provider/consumer: rangeland SOC, GHG flux, biodiversity, weather |
| White Buffalo Land Trust | Producer (NGO/ranch) | (not yet deployed) | Data provider/consumer: monitoring + grazing records |
| Governance authority | Central services | `governance.glcdi.startinblox.com` | Keycloak, onboarding, (future) Federated Catalogue |

## Architecture

### Per-Participant Stack

Each participant runs:
- **EDC Connector** (control plane + data plane) — handles catalog, negotiation, transfer
- **Local Keycloak** (`edc` realm) — participant-level authentication
- **Catalogue UI** — browse offers from other participants
- **OAuth2 Proxy** — protects the UI
- **Nginx** — reverse proxy with TLS termination
- **PostgreSQL** — connector + Keycloak persistence

### Governance Stack

Central services shared by all participants:
- **Governance Keycloak** (`glcdi` realm) — central identity, federation hub
- **Onboarding app** (DjangoLDP + approval UI + search UI)
- **PostgreSQL** — Keycloak + onboarding persistence
- **Nginx** — reverse proxy with TLS termination

### Identity Federation

Participants authenticate at their local Keycloak, which brokers to the governance Keycloak
via OIDC identity providers. The governance Keycloak is the source of truth for GLCDI roles
and membership status.

### Data Exchange Protocol

1. Consumer queries provider's catalog via **DSP (Dataspace Protocol)**
2. Provider evaluates **access policy** → filters visible offers
3. Consumer initiates **contract negotiation** with declared purpose
4. Provider evaluates **contract policy** → accepts or rejects
5. On agreement, consumer requests **data transfer**
6. Provider sends data via HTTP data plane

## Policies

ODRL-based policies are defined in `management/policies/`. Two types:

- **Access policies** (`access/`) — control catalog visibility (who can *see* an offer)
- **Contract policies** (`contract/`) — control usage terms (what you can *do* with the data)

Policies reference custom claims from Keycloak tokens:
- `glcdi_membership` — active/suspended/pending
- `glcdi_roles` — array of `glcdi_member`, `glcdi_producer`, `glcdi_researcher`, etc.
- `glcdi_certification_status` — organic-certified, regenerative-verified, etc.

See `management/policies/README.md` for full documentation and `management/TODO.md` for
the implementation plan.

## Current State (as of March 2026)

**Phase 1 (Code & Configuration): DONE**
- All three repos configured and working locally
- Seeding scripts for both participants (sample assets with open-research policies)
- CI/CD pipelines defined

**Phase 2 (Infrastructure Setup): NEXT**
- DNS, VMs, SSH keys, GitLab CI variables not yet provisioned
- No production deployment yet

**Not yet implemented:**
- Custom GLCDI policy functions (EDC extension) — currently using simple open-access
- Keycloak GLCDI roles and claim mappers
- Federated Catalogue (deferred)
- Participant UI (placeholder only)

## Conventions

### Naming

- **Policy IDs**: `glcdi:access:<name>` or `glcdi:contract:<name>`
- **Asset IDs**: `<participant>-<dataset-name>` (e.g., `caney-fork-soc-measurements`)
- **Contract Definition IDs**: `cd-<asset-id>` or `cd-<asset-id>-for-<purpose>`
- **Keycloak roles**: `glcdi_<type>` (e.g., `glcdi_producer`, `glcdi_researcher`)
- **Docker services**: lowercase with hyphens

### Ports (local development)

| Port | Service |
|------|---------|
| 29191 | EDC Default API |
| 29192 | EDC Control API |
| 29193 | EDC Management API |
| 29194 | EDC DSP Protocol |
| 29195 | EDC Version API |
| 29291 | EDC Public Data API |

### Configuration

- EDC: `.properties` files or environment variables
- Keycloak: realm JSON exports in `resources/keycloak/realms/`
- Docker: `.env` files (never committed — `.env.example` templates provided)
- Secrets: `./secrets/` directories with templates, managed via `init-secrets.sh`

### API Authentication

- EDC Management API: `X-Api-Key` header (default: `password` in dev, must be changed for prod)
- Keycloak Admin API: Bearer token from `admin-cli` client

## Parent Repository Context

This project sits within `~/workspace/dataspaces/` alongside related projects:

| Project | Relation to GLCDI |
|---------|-------------------|
| `Connector` | Upstream EDC framework (reference, not forked directly) |
| `MinimumViableDataspace` | EDC reference implementation (architectural patterns) |
| `tems-*` | TEMS dataspace — sister project, shared infrastructure patterns |
| `edc-extensions` | Sovity EDC extensions (reference for extension patterns) |
| `edc-ce` | Sovity community edition (UI reference) |
| `federated-catalogue` | Federated Catalogue components (future integration) |
| `tems-vocabulary-registry` | Vocabulary/ontology registry (model for GLCDI vocabulary) |

The GLCDI connector is adapted from the AFP-Tralalere EDC connector (another Startin'Blox
project), with the DSIF extension removed and rebranded for GLCDI.

## Common Tasks for Agents

### Reading existing policies
```
management/policies/access/*.json      — access policies
management/policies/contract/*.json    — contract policies
management/policies/combined/*.json    — end-to-end scenario examples
management/policies/diagrams/*.puml    — sequence diagrams
```

### Understanding the deployment
```
TODO.md                                — main 6-phase implementation plan
management/TODO.md                     — policy implementation plan
```

### Working on the EDC connector
```
edc-connector/extensions/              — custom extensions go here
edc-connector/runtimes/controlplane/   — control plane config + Dockerfile
edc-connector/runtimes/dataplane/      — data plane runtime
edc-connector/docker-compose.local.yml — local dev environment
```

### Working on governance
```
governance-services/resources/keycloak/realms/glcdi-realm.json  — realm config
governance-services/onboarding/                                  — onboarding app
governance-services/docker-compose.yml                           — all services
```

### Working on participant deployment
```
participant-agent-services/docker-compose.yml                    — all services
participant-agent-services/participant/configuration.properties  — EDC config
participant-agent-services/scripts/seed-*.sh                     — data seeding
participant-agent-services/scripts/test-*.sh                     — integration tests
```

### Building
```bash
cd edc-connector && ./gradlew build -x test                     # Build connector
cd edc-connector && ./gradlew :runtimes:controlplane:shadowJar  # Fat JAR
cd edc-connector && docker compose -f docker-compose.local.yml up  # Local dev
```

## Important Caveats

- **No git repo at the workspace root** — each sub-project has its own GitLab repo
- **Default API keys are insecure** — `password`, `123456`, `ApiKeyDefaultValue` must be
  changed before any production deployment
- **No Federated Catalogue yet** — deferred from the prototype scope
- **Policy functions not yet implemented** — the `glcdi:membership` and `glcdi:participantType`
  constraints in policy files require a custom EDC extension that doesn't exist yet
  (see `management/TODO.md` Phase 3)
- **Character encoding** — some tools in the ecosystem don't support accented/special
  characters (inherited limitation from TEMS)
