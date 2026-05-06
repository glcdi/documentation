# GLCDI M1 — Bruno HTTP test collection

End-to-end HTTP tests for the **M1 milestone** scenario: a regenerative-only
access policy plus an internal-use-only contract policy, exercised across
three participants (caney-fork, point-blue, white-buffalo).

Designed to run in two **identity tier** modes (per
`../IMPLEM_PLAN.md` § Identity Tiering Strategy):

- **Tier 1** (default) — `X-Api-Key` only on every `/management` call. No
  Bearer token; oauth2-proxy is not in the participant compose at this tier
  (`../IMPLEM_PLAN.md` § 1.5.2). The 00-auth/ folder is **diagnostic** —
  it mints connector-SA tokens to verify the Authority KC carries the right
  claim shape, but those tokens are not attached to /management traffic.
- **Tier 2** — `X-Api-Key` **+** `Authorization: Bearer` on every
  /management call. Anticipates the post-M1 user-OIDC layer
  (`../IMPLEM_PLAN.md` § 7.2). Bruno automation uses the connector-SA
  tokens already minted by 00-auth/ as Bearer values — oauth2-proxy
  accepts any token signed by Authority KC, which is sufficient for
  test traffic. (Real human operators going through the catalogue UI
  use the per-user OIDC flow against the `glcdi-ui` client; Bruno
  doesn't drive a browser flow.)

Switch tiers by setting the `tier` env var to `tier1` (default) or
`tier2`. The Bearer-injection logic lives in the collection-level
pre-request script in `collection.bru` — individual `.bru` files don't
need to know about the tier.

> **Status: skeleton, not yet runnable green.** The collection is openable
> in Bruno today and useful as a structured contract for the M1 acceptance
> tests. Running it green requires Phase 1.5 (Tier 1 cutover) and Phases
> 2–4 (claims + functions + seeded data) to land first. See
> "Not yet runnable" below.

## What this collection tests

The Phase 4.5.E charter (`../IMPLEM_PLAN.md` § 4.5.E) and the M1 acceptance
list (`../IMPLEM_PLAN.md` § Milestone M1) decompose to:

- A regenerative producer (white-buffalo) sees the M1 fixture asset in the
  catalog query against caney-fork.
- A researcher (point-blue) does **not** see the asset — the access policy
  filters it out.
- A contract negotiation declaring `purpose = InternalAnalysis` reaches
  `FINALIZED`.
- A negotiation declaring a different purpose reaches `TERMINATED`.
- A transfer-process initiated against the agreed contract reaches a
  terminal success state.
- The management API rejects calls with no / wrong `X-Api-Key`
  (Tier 1 + Tier 2).
- At **Tier 2 only**, the management API rejects calls with no / malformed
  Bearer token (oauth2-proxy in front of /management).

## Auth model by tier

### Tier 1 (M1 default — `tier=tier1`)

```
Bruno → /management/* → connector
  headers: X-Api-Key only
```

No Bearer header on /management calls. The `00-auth/` folder still mints
connector-SA tokens against Authority KC and decodes them to assert the
`glcdi_*` claim shape (`../IMPLEM_PLAN.md` § 2.6) — those minted tokens
are not used downstream at this tier; the assertion is verifying that
Authority KC is correctly configured.

The DSP-level claim chain (catalog query, negotiation) flows over a
different channel: each connector mints its own `client_credentials`
token at startup and presents it to the remote connector via DSP;
`iam-oauth2` (post-§ 3.5) extracts the `glcdi_*` claims into ClaimToken
for policy evaluation. Bruno doesn't drive that path — the connector
does it itself.

### Tier 2 (post-M1 — `tier=tier2`)

```
Bruno → oauth2-proxy → /management/* → connector
  headers: X-Api-Key + Authorization: Bearer <connector-SA token>
```

The collection-level pre-request script (`collection.bru`) inspects each
request's URL host and injects the matching org's connector-SA token as
`Authorization: Bearer` — `caney_fork_host` → `caney_fork_token`,
`point_blue_host` → `point_blue_token`, `white_buffalo_host` →
`white_buffalo_token`. 00-auth/ requests target the Authority KC and are
skipped by the URL filter (they're requesting tokens, not using them).

For real per-user audit at Tier 2, human operators still go through the
catalogue UI's OIDC flow against the `glcdi-ui` client — that's not what
Bruno automates. Bruno uses SA tokens because the goal here is to
exercise the oauth2-proxy validation path, not to fake user identities.

## How to run

### Bruno UI (recommended for skeleton review today)

1. Install Bruno: <https://www.usebruno.com/downloads>.
2. Open this folder via *Open Collection* — select
   `glcdi/management/bruno/`.
3. Pick an environment (`local` or `staging`).
4. Confirm `tier=tier1` (default) or set to `tier2` if validating
   the post-M1 layer.
5. Populate the secret env vars (see "Environment variables" below).
6. Step through the folders in numeric order
   (`00-auth/` → `10-provider-seeding/` → ...).

### Bruno CLI (Phase 4.5.E target)

```sh
npm install -g @usebruno/cli
cd glcdi/management/bruno/

# Tier 1 (default at M1):
bru run --env staging

# Tier 2 (post-§ 7.2 cutover):
bru run --env staging --env-var tier=tier2

# Or scope to a folder:
bru run 20-catalog-discovery --env staging
```

## Environment variables

Two environments are defined under `environments/`:

| File | Purpose |
|------|---------|
| `environments/local.bru` | Two participant connectors on `host.docker.internal:8080/8081/8082`, Authority KC at `localhost:8090`. |
| `environments/staging.bru` | `caney-fork.glcdi.startinblox.com`, `point-blue.glcdi.startinblox.com`, etc., per `../../CLAUDE.md`. |

Public vars (hosts, URNs, fixture IDs, the `tier` selector) are checked
into the env files. Secret vars (API keys, client secrets, captured tokens
+ negotiation/transfer IDs) are declared but **not populated** — Bruno
stores the values locally per user.

### Where secrets come from

| Secret | Source | Tier(s) using it |
|--------|--------|------------------|
| `<org>_api_key` | The connector's `web.http.management.auth.key`, rotated per `../../CLAUDE.md` "Things that will bite you" | Tier 1 + Tier 2 |
| `<org>_client_secret` | Authority Keycloak client secret for `glcdi-connector-<org>` (rotated from realm-JSON `changeme-*` placeholders, per `../IMPLEM_PLAN.md` § 1.5.4) | Tier 1 + Tier 2 (00-auth/ at Tier 1 is diagnostic; at Tier 2 it sources the Bearer tokens) |
| `<org>_token` | Auto-populated by `00-auth/0[1-3]-fetch-token-*.bru` | Tier 2 (used by `collection.bru` to inject Bearer); Tier 1 ignores |
| `m1_negotiation_id`, `m1_contract_agreement_id`, `m1_transfer_process_id` | Auto-populated by `30-negotiation/` and `40-transfer/` scripts | Tier 1 + Tier 2 |

## Folder structure

```
bruno/
├── bruno.json                       # Collection metadata
├── collection.bru                   # Collection-level pre-request script
│                                    #   (Tier-2 Bearer injection)
├── README.md                        # This file
├── environments/
│   ├── local.bru                    # Local-dev hosts + tier selector + placeholder secrets
│   └── staging.bru                  # *.glcdi.startinblox.com hosts + tier selector + placeholder secrets
├── 00-auth/                         # Mint connector-SA tokens via client_credentials
│                                    #   (diagnostic at Tier 1; token source at Tier 2)
├── 10-provider-seeding/             # caney-fork creates asset / policies / contract def
├── 20-catalog-discovery/            # Positive (regen-producer) + negative (researcher) catalog queries
├── 30-negotiation/                  # Positive (InternalAnalysis) + negative (other purpose)
├── 40-transfer/                     # Initiate transfer against the agreed contract
└── 99-negative-auth/                # Tier-1+2: no/wrong X-Api-Key. Tier-2 only: no/wrong Bearer.
```

## Not yet runnable — dependencies

The collection cannot be expected to pass green until the following are in
place (per the M1 acceptance criteria in `../IMPLEM_PLAN.md` § Milestone M1):

- **Phase 1.5 (Tier 1)** — Authority KC has `glcdi-connector-<org>` clients
  with `client_credentials` enabled and the per-org `glcdi-claims` scope
  attached; per-org connector secrets rotated from `changeme-*` placeholders;
  `X-Api-Key`-only management auth confirmed; per-participant Keycloak +
  oauth2-proxy gone from the participant compose stack.
- **Phase 2** — Realm roles + service-account-user attributes + protocol
  mappers configured on the Authority KC so connector-SA tokens carry
  `glcdi_membership`, `glcdi_organisation`, `glcdi_roles`,
  `glcdi_certification_status`, `glcdi_contribution_status`.
- **Phase 3** — Custom `AtomicConstraintFunction`s registered for
  `glcdi:membership`, `glcdi:participantType`, `glcdi:certificationStatus`,
  and `iam-mock` swapped for `iam-oauth2` against the Authority KC
  (§ 3.5 — load-bearing for the catalog-discovery + negotiation
  scenarios to actually exercise policy logic).
- **Phase 4** — Provider seeding scripts publish the M1 fixture asset with
  the correct policies (this collection's `10-provider-seeding/` mirrors
  what those scripts will do, but state will be re-created if the seeding
  scripts are also run).

For Tier 2 also requires:
- **Phase 7.2** — `glcdi-ui` client active in Authority KC, oauth2-proxy
  reintroduced in the participant compose stack and configured against
  Authority KC, per-org groups + human users provisioned. Until 7.2 is
  signed off, the Tier-2 mode (`tier=tier2`) doesn't have a working
  oauth2-proxy to validate against — running it pre-7.2 will fail.

The catalog / negotiation / transfer assertions also depend on EDC's async
state machines reaching terminal states — see the polling notes in
`30-negotiation/01-*.bru` and `40-transfer/01-*.bru`. Polling files
(`*b-poll-*.bru`) are left as a TODO once the preceding chain exercises
real data.

## Pointers

- Identity tiering strategy: `../IMPLEM_PLAN.md` § Identity Tiering Strategy.
- Tier 1 design + auth flow reference: `../IMPLEM_PLAN.md` § 1.5.6.
- Tier 2 design (post-M1): `../IMPLEM_PLAN.md` § 7.2.
- Bruno track design context: `../IMPLEM_PLAN.md` § 4.5.E.
- M1 acceptance criteria: `../IMPLEM_PLAN.md` § Milestone M1.
- URN conventions: `../PAYMENT_GATING.md` § 3.7.
- GLCDI vocabulary: `../context.jsonld` (and the hosted copy at
  `https://cdn.startinblox.com/owl/glcdi/context.jsonld`).
- Staging hosts and ufw caveat: `../../CLAUDE.md`.
