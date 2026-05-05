# GLCDI M1 — Bruno HTTP test collection (skeleton)

End-to-end HTTP tests for the **M1 milestone** scenario: a regenerative-only
access policy plus an internal-use-only contract policy, exercised across
three participants (caney-fork, point-blue, white-buffalo).

> **Status: skeleton, not yet runnable.** The collection is openable in Bruno
> today and useful as a structured contract for the M1 acceptance tests, but
> running it green requires Phase 1.5 (auth simplification) and Phase 4
> (seeded data) to land first. See "Not yet runnable" below.

## What this collection tests

The Phase 4.5.E charter (`../IMPLEM_PLAN.md` § 4.5.E) and the M1 acceptance
list (`../IMPLEM_PLAN.md` § Milestone M1) decompose to:

- A researcher (point-blue, claim `glcdi_researcher`) sees the M1 fixture
  asset in the catalog.
- A non-matching member (white-buffalo) does **not** see the asset — the
  access policy filters it out.
- A contract negotiation declaring `purpose = InternalAnalysis` reaches
  `FINALIZED`.
- A negotiation declaring a different purpose reaches `TERMINATED`.
- A transfer-process initiated against the agreed contract reaches a
  terminal success state.
- The management API rejects calls with no / wrong `X-Api-Key`.

## Auth model

Per `../IMPLEM_PLAN.md` § 1.5.8 (post-Phase-1.5 auth):

- **`X-Api-Key`** is required on **every** management-API call. This is the
  floor — never optional.
- **`Authorization: Bearer <token>`** is additionally required for
  identity-driven steps (catalog query as user X, negotiation as user X).
  Tokens are obtained from the Authority Keycloak via the `client_credentials`
  flow against per-org service-account clients
  (`glcdi-connector-caney-fork`, `glcdi-connector-point-blue`,
  `glcdi-connector-white-buffalo`).
- For pure-CRUD seeding steps (`10-provider-seeding/`) the Bearer token is
  not strictly required, but the collection includes it for parity with
  identity-driven steps and so the dual-credential path is exercised.

The `00-auth/` folder fetches each org's token first and stores it in env
vars `caney_fork_token`, `point_blue_token`, `white_buffalo_token` via
post-response scripts. JWT payloads are decoded inline (no signature
verification) to assert the `glcdi_*` claim shape from § 2.7.

## How to run

### Bruno UI (recommended for skeleton review today)

1. Install Bruno: <https://www.usebruno.com/downloads>.
2. Open this folder via *Open Collection* — select
   `glcdi/management/bruno/`.
3. Pick an environment (`local` or `staging`).
4. Populate the secret env vars (see "Environment variables" below).
5. Step through the folders in numeric order
   (`00-auth/` → `10-provider-seeding/` → ...).

### Bruno CLI (Phase 4.5.E target)

```sh
npm install -g @usebruno/cli
cd glcdi/management/bruno/

# Once Phase 1.5 has landed and credentials are populated:
bru run --env staging
# or scope to a folder:
bru run 20-catalog-discovery --env staging
```

## Environment variables

Two environments are defined under `environments/`:

| File | Purpose |
|------|---------|
| `environments/local.bru` | Two participant connectors on `host.docker.internal:8080/8081/8082`, Authority KC at `localhost:8090`. |
| `environments/staging.bru` | `caney-fork.glcdi.startinblox.com`, `point-blue.glcdi.startinblox.com`, etc., per `../../CLAUDE.md`. |

Public vars (hosts, URNs, fixture IDs) are checked into the env files.
Secret vars (API keys, client secrets, tokens, captured negotiation IDs)
are declared but **not populated** — Bruno stores the values locally per
user.

### Where secrets come from

| Secret | Source |
|--------|--------|
| `<org>_api_key` | The connector's `web.http.management.auth.key`, rotated per `../../CLAUDE.md` "Things that will bite you". |
| `<org>_client_secret` | Authority Keycloak client secret for `glcdi-connector-<org>` (created in IMPLEM_PLAN.md § 1.5.6). |
| `<org>_token` | Auto-populated by `00-auth/0[1-3]-fetch-token-*.bru`. |
| `m1_negotiation_id`, `m1_contract_agreement_id`, `m1_transfer_process_id` | Auto-populated by `30-negotiation/` and `40-transfer/` scripts. |

## Folder structure

```
bruno/
├── bruno.json                      # Collection metadata
├── README.md
├── environments/
│   ├── local.bru                   # Local-dev hosts + placeholder secrets
│   └── staging.bru                 # *.glcdi.startinblox.com hosts + placeholder secrets
├── 00-auth/                        # Fetch Bearer tokens via client_credentials
├── 10-provider-seeding/            # caney-fork creates asset / policies / contract def
├── 20-catalog-discovery/           # Positive (researcher) + negative (non-matching) catalog queries
├── 30-negotiation/                 # Positive (InternalAnalysis) + negative (other purpose)
├── 40-transfer/                    # Initiate transfer against the agreed contract
└── 99-negative-auth/               # X-Api-Key floor checks (no key / wrong key)
```

## Not yet runnable — dependencies

The collection cannot be expected to pass green until the following are in
place (per the M1 acceptance criteria in `../IMPLEM_PLAN.md` § Milestone M1):

- **Phase 1.5** — Authority KC has `glcdi-connector-<org>` clients with
  `client_credentials` enabled and the per-org claim mappers configured;
  `X-Api-Key`-only management auth confirmed; per-participant Keycloak gone
  from the compose stack.
- **Phase 2** — Realm roles + user attributes + protocol mappers configured
  on the Authority KC so tokens carry `glcdi_membership`, `glcdi_roles`,
  `glcdi_certification_status`.
- **Phase 3** — Custom `AtomicConstraintFunction`s registered for
  `glcdi:membership`, `glcdi:participantType`, `glcdi:certificationStatus`,
  and `iam-mock` swapped for `iam-oauth2` against the Authority KC.
- **Phase 4** — Provider seeding scripts publish the M1 fixture asset with
  the correct policies (this collection's `10-provider-seeding/` mirrors
  what those scripts will do, but state will be re-created if the seeding
  scripts are also run).

The catalog / negotiation / transfer assertions also depend on EDC's async
state machines reaching terminal states — see the polling notes in
`30-negotiation/01-*.bru` and `40-transfer/01-*.bru`. Polling files
(`*b-poll-*.bru`) are left as a TODO for Phase 4.5.E to add once the
preceding chain is exercising real data.

## Pointers

- Design context for this collection: `../IMPLEM_PLAN.md` § 4.5.E.
- M1 acceptance criteria: `../IMPLEM_PLAN.md` § Milestone M1.
- Auth flow & credential roles: `../IMPLEM_PLAN.md` § 1.5.8.
- URN conventions: `../PAYMENT_GATING.md` § 3.7.
- GLCDI vocabulary: `../context.jsonld` (and the hosted copy at
  `https://cdn.startinblox.com/owl/glcdi/context.jsonld`).
- Staging hosts and ufw caveat: `../../CLAUDE.md`.
