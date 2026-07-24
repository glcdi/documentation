# AGENTS.md - GLCDI Management Context

Context for AI agents working in the `management/` directory of the GLCDI project — what this directory contains, how it relates to the broader project, and what an agent needs to know to contribute effectively.

## What this directory is

`management/` is the **governance, design, and operations space** for the GLCDI dataspace. It holds the architecture reference, the phased implementation plan, ODRL policy templates, operator runbooks, and the local-stack orchestrator that runs the whole system on a laptop. It is not itself a deployable service — its outputs feed the sibling code repos of the workspace.

## Directory layout

```
management/
├── README.md                 # Entry point + index grouped by intent
├── ARCHITECTURE.md           # Head document for the "Data Space Architecture Design" deliverable
├── AGENTS.md                 # This file
├── IMPLEM_PLAN.md            # Phased implementation plan (master backlog)
├── architecture.mmd/.png     # Reference topology diagram (Mermaid source + rendered PNG)
├── context.jsonld            # GLCDI JSON-LD namespace definition
│
├── strategy/                 # Governance-body-facing proposals + open questions
│   ├── authority.md          # Proposed responsibilities of the Dataspace Authority
│   ├── standards.md          # Full specification traceability (ODRL / DSP / identity / semantic)
│   └── open-questions.md     # Decisions pending (project team + Authority)
│
├── reference/                # As-designed technical reference
│   ├── identity.md           # Identity architecture: tiers, claim model, OIDC-vs-VC rationale
│   ├── authentication.md     # Per-tier authentication roadmap (with PlantUML sequence diagrams)
│   ├── policies/             # ODRL policy templates (access + contract + combined + diagrams)
│   └── assets/
│       └── workshop-inputs-2026.md   # Frozen workshop-phase participant policy inputs
│
├── design/                   # Design proposals under review, not yet as-built
│   └── payment-gating.md     # Payment-required contract policy design
│
├── ops/                      # Runbooks — anything an operator opens under time pressure
│   ├── deployment.md         # Deployment + local end-to-end validation runbook
│   ├── authority-migration.md # Rename runbook (governance-* → authority-*) + Tier-1 cutover
│   ├── staging-wipe.md       # Staging-participant full-reset runbook
│   └── demo-vm.md            # Co-located demo staging VM plan
│
├── bruno/                    # HTTP test collection driving the M1 scenario end-to-end
├── scripts/                  # Local-stack orchestrator (glcdi.sh) + deploy helpers
└── presentations/            # reveal.js slide decks
```

The **`README.md` contents block** is grouped by reader intent (Start here / Reference / Design / Build / Operate / Meta) — an agent scanning for where something belongs should read that first.

## What is GLCDI?

The **Grazing Lands Carbon Data Initiative (GLCDI)** is a federated, permissioned data space linking soil organic carbon (SOC) measurements with grazing management records across U.S. grazing lands. The prototype runs January–September 2026 and drives three use cases: **regional benchmarking**, **agronomic model calibration**, and **peer-to-peer consent-governed data sharing** between participants.

## Participant types

Specific participant identities per cohort are under discussion and intentionally omitted here. The prototype expects a mix of the following types, each mapping to a GLCDI role:

| Participant type | Token role | Typical assets |
|------------------|-----------|----------------|
| Producer (ranch / farming organisation) | `glcdi_producer` | SOC measurements, grazing rotation, paddock boundaries, NDVI |
| Research institution (university / NGO) | `glcdi_researcher` | Rangeland SOC, GHG flux, biodiversity surveys, weather, carbon credits |
| Data steward / monitoring alliance | `glcdi_data_steward` | SOC sampling metadata, curated datasets |

Post-prototype types (corporate supply-chain partners, certification bodies, funders) exist as realm roles but no participants of those types are onboarded yet.

## How policies work in GLCDI

### Two-layer model

Every asset is governed by two policies:

- **Access policy** — evaluated when a consumer queries the catalog. Controls **who can see** the offer. If the consumer's identity doesn't satisfy the constraints, the offer is hidden.
- **Contract policy** — evaluated during contract negotiation. Controls **what the consumer can do** with the data.

Both are linked to assets through a **Contract Definition**:

```
Contract Definition = Asset Selector + Access Policy ID + Contract Policy ID
```

### Constraint mechanism — Tier 1

At Tier 1 (M1 target), constraints reference claims carried on the consumer connector's **Authority Keycloak JWT**, minted via `client_credentials` at connector startup:

| Claim | Source | Values |
|-------|--------|--------|
| `glcdi_membership` | Hardcoded claim mapper (all active users = `"active"`) | `active`, `suspended`, `pending` |
| `glcdi_roles` | Realm role mapper (prefix `glcdi_`) | `["glcdi_member", "glcdi_producer"]`, etc. |
| `glcdi_certification_status` | User-attribute mapper on the connector's service-account user | `regenerative-verified`, `organic-certified`, `transitioning-organic`, `conventional`, `not-applicable` |
| `glcdi_contribution_status` | User-attribute mapper | `contributing`, `observer`, `pending` |
| `glcdi_organisation` | User-attribute mapper | Slugged participant name (`caney-fork`, `point-blue`, etc.) |

### Mapping: policy constraint → token claim → check logic

| Policy `leftOperand` | Token claim | How the EDC policy function checks it |
|----------------------|-------------|--------------------------------------|
| `glcdi:membership` | `glcdi_membership` (string) | `claim == rightOperand` |
| `glcdi:participantType` | `glcdi_roles` (array) | `"glcdi_" + rightOperand` present in array |
| `glcdi:participantType` (isAnyOf) | `glcdi_roles` (array) | any of `["glcdi_" + v for v in rightOperand]` present |
| `glcdi:certificationStatus` | `glcdi_certification_status` (string) | `claim == rightOperand` or `claim in rightOperand` |
| `odrl:dateTime` | System clock | Native EDC — no custom function needed |
| `odrl:purpose` | Consumer's contract offer | Native EDC — consumer declares purpose |
| `odrl:elapsedTime` | Transfer timestamp + clock | Needs custom function (deferred, Phase 3) |
| `odrl:payAmount` | External payment system | Needs custom function + external API (see `design/payment-gating.md`) |

### Custom namespace

All GLCDI-specific terms use the prefix `glcdi:` mapped to `https://w3id.org/glcdi/v0.1.0/ns/`. The context is served from `context.jsonld` and pinned in every policy file's `@context` block.

## Identity architecture (Tier 1)

The M1 target is **Tier 1**: one central Authority Keycloak, one `glcdi-connector-«org»` service-account client per participant, connector-only DSP-level identity, `X-Api-Key` at the UI edge. **No end-user OIDC anywhere at this tier** — the two-tier federated flow that older versions of this document described is Tier 2 territory (Phase 7.2), deliberately deferred to post-M1.

```
Participant connector
  ↓ client_credentials against Authority KC
Authority KC (realm `glcdi`)
  ↓ mints JWT with glcdi_* claims via the `glcdi-claims` scope mappers
Participant connector caches JWT
  ↓ attaches as Authorization: Bearer on outbound DSP requests
Peer connector (running iam-oauth2)
  ↓ verifies JWT against Authority JWKS
  ↓ surfaces glcdi_* claims to the policy engine
Policy engine evaluates access + contract policies
```

Full architecture snapshot in [`reference/identity.md`](reference/identity.md); per-tier operational roadmap in [`reference/authentication.md`](reference/authentication.md); topology diagram + component breakdown in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Data exchange flow (with policy evaluation)

```
1. Consumer connector sends DSP Catalog Query to Provider (Authority JWT attached)
2. Provider evaluates ACCESS POLICY per-asset against consumer's glcdi_* claims
3. Only matching assets return in the catalog response
4. Consumer selects an offer and initiates CONTRACT NEGOTIATION (with purpose)
5. Provider evaluates CONTRACT POLICY at REQUESTED → OFFERED
6. FINALIZED → Contract Agreement recorded
7. Consumer requests DATA TRANSFER; Provider issues EDR
8. Consumer calls Provider's data-plane with the EDR; bytes flow directly
```

Per-scenario sequence diagrams: `reference/policies/diagrams/*.puml`.

## Implementation status (current)

Track the authoritative status in [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md); the summary below is a snapshot for orientation.

| Component | Status |
|-----------|--------|
| ODRL policy templates | Done (`reference/policies/`) |
| GLCDI vocabulary + `context.jsonld` | Done (Phase 1) |
| Authority KC realm JSON (roles, mappers, connector SA clients) | Done in-repo (Phase 1.5); awaiting staging cutover |
| Onboarding portal (form → admin approve → KC group + user + mail) | Local smoke passing (Phase 1.6); awaiting staging cutover |
| Keycloak protocol mappers + Bruno auth checks | Done (Phase 2) |
| EDC custom policy functions (participant-type, cert-status) | Drafted (Phase 3.1–3.2); unit tests deferred |
| `iam-mock` → `iam-oauth2` swap | Not started (Phase 3.5 — this is the load-bearing gate to real DSP identity) |
| Seeding scripts + Bruno M1 scenario | Done (Phase 4.5 tracks E + F) |
| Milestone M1 sign-off | Blocked on staging cutover + Phase 3.5 |
| DSA / Trust Framework v0/v1 | Not started (Phase 6, governance-body-owned) |

## Sibling repositories

`management/` is one of six workspace repos:

```
<workspace-root>/
├── management/                    ← this repo (docs, policies, scripts, tests)
├── authority-services/            # Authority KC + onboarding portal (formerly governance-services/)
├── edc-connector/                 # EDC control-plane / data-plane distribution (Gradle, Java 17+, EDC 0.15.1)
├── edc-glcdi-extension/           # GLCDI-specific EDC extensions (copy-merged into edc-connector/ at build)
├── participant-agent-services/    # Per-participant Docker Compose stack
└── participant-ui/                # Catalogue UI image (Hubl / Lit)
```

`scripts/glcdi.sh` in this repo drives the whole stack locally; see `ops/deployment.md § Fast local bootstrap` for the one-command recipe and the sibling-repo `git clone` list.

## Files typically touched when implementing plan items

| Plan phase | Files affected |
|------------|----------------|
| Phase 1 (vocabulary) | `context.jsonld`, `reference/policies/*.json` `@context` blocks |
| Phase 1.5 (Tier-1 identity + rename) | `authority-services/resources/keycloak/realms/glcdi-realm.json`, `participant-agent-services/docker-compose.yml`, `participant-agent-services/nginx/*.conf`, `participant-agent-services/participant/configuration.properties.example`, `ops/authority-migration.md` |
| Phase 2 (KC claims on connector SAs) | Realm JSON protocol mappers (`glcdi-claims` scope), Bruno `00-auth/*.bru` |
| Phase 3 (EDC policy extension) | `edc-glcdi-extension/policy-functions/src/main/java/...`, `edc-connector/runtimes/controlplane/build.gradle.kts` |
| Phase 3.5 (iam-oauth2 swap) | `edc-connector/runtimes/controlplane/build.gradle.kts` (BOM swap), `participant/configuration.properties.example` |
| Phase 4 (seeding) | `bruno/10-provider-seeding/*.bru`, `scripts/glcdi.sh` `seed_one`/`seed_demo` |
| Phase 4.5.E (Bruno M1 scenario) | `bruno/00-auth/`, `20-catalog-discovery/`, `30-negotiation/`, `40-transfer/`, `99-negative-auth/` |
| Phase 4.5.F (Participant UI) | `participant-ui/config.json.template`, `participant-ui/docker-entrypoint.sh` |
| Phase 6 (governance) | Trust Framework docs (external to this repo, tracked here) |
| Phase 7.1 (payment) | `design/payment-gating.md` + `edc-glcdi-extension/payment-status-extension/` |
| Phase 7.2 (Tier 2 user OIDC) | Realm JSON `glcdi-ui` client + groups + users, participant compose `oauth2-proxy` reintroduction, participant-ui OIDC envvars |

## Conventions

- **Policy files** are valid JSON-LD, using the EDC Management API format (POSTable directly to `/management/v3/policydefinitions`).
- **Policy IDs** follow `glcdi:access:<name>` or `glcdi:contract:<name>`.
- **Combined files** are documentation-oriented; they group an access policy, contract policy, and contract definition in one file (not directly POSTable as-is).
- **Diagrams** are PlantUML `.puml` files under `reference/policies/diagrams/`; regenerable via the recipe in the folder's README, or via `scripts/plantuml-encode.py` for the reveal.js decks.
- **Comments in JSON** use a `"comment"` field (non-standard JSON but common in EDC examples for documentation).
- **Value casing** is deliberately mixed (see the user memory `feedback_glcdi_value_casing`): kebab-case for statuses / types / outcomes, PascalCase for ODRL purposes, snake_case `glcdi_`-prefix for realm roles.

## Important caveats

- **`iam-mock` is still in place** — until Phase 3.5 swaps it for `iam-oauth2`, DSP-level identity is a fixed mock and the policy engine doesn't actually evaluate the `glcdi_*` claims at the receiving connector. Bruno's positive-case tests pass against the *expected* outcome, but the negative-case filtering (`researcher` blocked from `regenerative-producers-only` assets) only becomes load-bearing after Phase 3.5.
- **Governance-level obligations are not technically enforced** — anonymisation, attribution, deletion duties rely on the Data Sharing Agreement, not the connector. Full enforcement-boundary table in [`ARCHITECTURE.md § 8`](ARCHITECTURE.md).
- **The Authority KC realm JSON is imported only on first boot.** Post-init edits to the JSON do nothing; changes must go through the admin console, or the KC Postgres volume must be wiped for a re-import. See `ops/authority-migration.md` Paths A/B.
- **`combined/` policy files are not directly POSTable** — they bundle access + contract + contract definition for documentation; extract the individual policies to use them.
- **`w3id.org/glcdi/…` redirect is not registered yet** — the JSON-LD context is served from `cdn.startinblox.com` for the prototype; namespace stewardship (redirect via the w3id PR process) is post-prototype work.

## Where to point questions

| Kind of question | Doc |
|------------------|-----|
| "What does the system look like?" | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| "How do I run it locally?" | [`ops/deployment.md`](ops/deployment.md) § Fast local bootstrap |
| "What is planned next?" | [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) |
| "What decisions are still open?" | [`strategy/open-questions.md`](strategy/open-questions.md) |
| "How does auth work today / next / later?" | [`reference/identity.md`](reference/identity.md) + [`reference/authentication.md`](reference/authentication.md) |
| "Which specifications is X built on?" | [`strategy/standards.md`](strategy/standards.md) |
| "What is the Dataspace Authority proposed to do?" | [`strategy/authority.md`](strategy/authority.md) |
| "How would payment-gated exchange work?" | [`design/payment-gating.md`](design/payment-gating.md) |
