# Audit Trails - Implementation Design (Proposal)

A proposal for how participants can review, on demand, **when and if their datasets have been accessed, and by whom**. Everything below is a working design for the project team and Dataspace Authority to validate; nothing here is a decided commitment.

This document complements the phase-doc [`../build/plan/phase-4.7-audit-trails.md`](../build/plan/phase-4.7-audit-trails.md) (the tactical checklist). Its purpose is to justify the shape — extension boundary, storage schema, event choice, retention posture — so an implementer or reviewer can trace *why* each choice was made.

---

## TL;DR

- **Provider-side only** for M1. The Authority sees nothing (no central log service); each participant's connector holds its own audit for the assets it publishes.
- **Three signals persist to one table:**
  1. Transfer lifecycle transitions (started / completed / terminated) - from the controlplane `EventRouter`.
  2. EDR issuance - same event as (1); the `TransferProcessStarted` event carries the `DataAddress` that becomes the EDR, so no separate hook is needed.
  3. Public-API access - one row per fetch, recorded inside `GlcdiPublicApiController.proxy()`, which already resolves `agreement_id` + `participant_id` + `asset_id` from the EDR token.
- **Storage:** one Postgres table (`glcdi_audit`) in the connector's existing datasource, via a Liquibase migration in a new `glcdi-audit-store` extension.
- **Retention:** soft 90-day retention (configurable) enforced by a scheduled prune job inside the extension. Display-time row-collapse coalesces consecutive fetches for the same `(participant, asset)` within N seconds.
- **Query surface:** one management endpoint `/v3/glcdi/audit`, filterable; UI reads it via a new `audit-list` component in `solid-glcdi`.

---

## 1. What the participant needs to see

A dataset producer opens the participant UI and asks two questions:

1. *"Has anyone accessed dataset X? When? Who?"*
2. *"Is there ongoing activity right now?"*

Neither is answerable today. The connector stores the contract negotiation, the agreement, and the transfer-process row - but the transfer-process row transitions to a terminal state once EDR issuance succeeds; **it does not record the actual data-plane fetches that the EDR then authorises**. A consumer can pull the payload once or a thousand times over the EDR's lifetime; the provider has no record of either.

The gap is narrow and concrete: three signals that the connector already computes but discards after emitting a monitor log line.

---

## 2. Feasibility: the hook points already exist

### 2.1 Signal 1 - transfer lifecycle

EDC's controlplane emits typed events via `EventRouter`:

- `TransferProcessInitiated` (consumer side; discarded on provider)
- `TransferProcessRequested` / `Started` / `Completed` / `Terminated` (provider side)
- `TransferProcessSuspended` (rare)

A subscriber registered in an `Extension.initialize()` hook receives every event synchronously. For each provider-side event we care about, we can look up the associated `ContractAgreement` → `assetId` and the consumer's participant ID via `TransferProcess.getCallbackAddresses()` / `TransferProcess.getContractId()` + `ContractNegotiationStore.findContractAgreement()`.

**No custom interception is needed** - this is the documented extension pattern.

### 2.2 Signal 2 - EDR issuance

For HTTP-pull transfers, the EDR is minted as part of the `STARTED` transition. The `TransferProcessStarted` event carries the `DataAddress` that the consumer will use to derive their EDR token. Recording (1) with `event_type = "STARTED"` is *already* the EDR-issued signal - no separate hook.

If per-EDR-refresh visibility is ever needed, `DataPlaneAccessTokenService.obtainToken` is the point to wrap. For M1 this is out of scope.

### 2.3 Signal 3 - public-API access

This is the "actual API called through the public API" signal in the ask. **The hook already exists in our own code.**

`edc-glcdi-extension/extensions/glcdi-dataplane-public-api/.../GlcdiPublicApiController.java` is the JAX-RS resource that handles every data-plane fetch. Inside `proxy()`:

- Line 137 - `authorizationService.authorize(token, requestData)` validates the EDR token.
- Lines 152-169 - `accessTokenService.resolve(token)` extracts `agreement_id`, `participant_id`, `asset_id` from the token's `additionalProperties`.
- Lines 190-198 - the upstream fetch runs; `upstreamResp.code()` and `body.length` are known.

Today those values get logged (`monitor.debug` / `monitor.warning`) and thrown away. The proposal is: **write them to `AuditStore` once per proxy call**, adjacent to the existing log line.

That's a two-line change in the existing method plus a constructor parameter.

---

## 3. Architecture

### 3.1 New extension: `glcdi-audit-store`

Sibling module under `edc-glcdi-extension/extensions/`, mirroring `glcdi-policy-functions` in shape:

```
edc-glcdi-extension/extensions/glcdi-audit-store/
├── build.gradle.kts
└── src/main/java/com/startinblox/glcdi/edc/extension/audit/
    ├── AuditRecord.java              # POJO
    ├── AuditStore.java               # SPI
    ├── AuditEventType.java           # enum
    ├── sql/
    │   ├── SqlAuditStore.java        # Postgres impl
    │   └── AuditRecordMapper.java
    ├── event/
    │   └── TransferAuditSubscriber.java  # EventRouter subscription
    ├── api/
    │   ├── AuditApiController.java   # /v3/glcdi/audit
    │   └── AuditFilter.java
    ├── prune/
    │   └── ScheduledAuditPrune.java
    ├── GlcdiAuditExtension.java      # controlplane wiring (subscriber + API + prune)
    └── GlcdiAuditDataplaneExtension.java  # dataplane wiring (Store into PublicApiController)
```

Two extension classes because the controlplane and dataplane can run as separate JVMs. In our single-runtime dev setup they coexist, but the split keeps the wiring honest.

`SqlAuditStore` reuses the connector's existing `DataSourceRegistry` (same Postgres the transfer-process store uses). Liquibase changelog under `src/main/resources/glcdi-audit-schema.xml` creates one table on first boot.

### 3.2 Storage schema

Single table, denormalised on purpose (audit rows should survive deletion of the source negotiation/asset):

```sql
CREATE TABLE glcdi_audit (
  id               UUID PRIMARY KEY,
  ts               TIMESTAMPTZ NOT NULL,
  event_type       VARCHAR(32) NOT NULL,   -- TRANSFER_STARTED / TRANSFER_COMPLETED / TRANSFER_TERMINATED / ACCESS
  participant_id   VARCHAR(255),            -- consumer's participant id (nullable if unresolved)
  agreement_id     VARCHAR(255),
  asset_id         VARCHAR(255),
  transfer_id      VARCHAR(255),            -- populated for TRANSFER_* events, null for ACCESS
  path             TEXT,                    -- populated for ACCESS
  status_code      INT,                     -- populated for ACCESS
  bytes            BIGINT,                  -- populated for ACCESS
  extra            JSONB                    -- future-proof escape hatch
);

CREATE INDEX glcdi_audit_asset_ts     ON glcdi_audit (asset_id, ts DESC);
CREATE INDEX glcdi_audit_participant  ON glcdi_audit (participant_id, ts DESC);
CREATE INDEX glcdi_audit_ts           ON glcdi_audit (ts);   -- for the prune job
```

Rationale:

- One table not per-event-type - simpler queries and one prune job.
- `event_type` string not enum column - lets us add new signal types without a migration.
- Denormalised participant/agreement/asset IDs so audit history stays readable even if the source rows are later deleted (compliance / GDPR view).
- `extra JSONB` so we can attach event-type-specific fields (e.g. TerminationReason on TRANSFER_TERMINATED) without schema churn.

### 3.3 AuditStore SPI

```java
public interface AuditStore {
  void record(AuditRecord record);
  Stream<AuditRecord> query(AuditFilter filter);
  long prune(Instant olderThan);
}
```

Deliberately minimal. In-memory impl for unit tests; SQL impl for production.

### 3.4 Controlplane wiring - transfer events

`TransferAuditSubscriber` implements `EventSubscriber` and is registered via `EventRouter.registerSync(TransferProcessEvent.class, subscriber)` in `GlcdiAuditExtension.initialize()`. Per-event handling:

| Event | Recorded as | Notes |
|---|---|---|
| `TransferProcessStarted` | `TRANSFER_STARTED` (= EDR issued) | Look up asset/participant via `TransferProcess.contractId → ContractAgreement`. |
| `TransferProcessCompleted` | `TRANSFER_COMPLETED` | Same lookup. |
| `TransferProcessTerminated` | `TRANSFER_TERMINATED` | Include `TerminationReason` in `extra`. |
| `TransferProcessInitiated` / `Requested` | *not recorded* | Consumer-side or pre-negotiation; adds noise, no signal a producer cares about. |

### 3.5 Dataplane wiring - public-API access

`GlcdiPublicApiController` gets one new constructor parameter:

```java
public GlcdiPublicApiController(
    DataPlaneAuthorizationService authorizationService,
    DataPlaneAccessTokenService accessTokenService,
    AssetIndex assetIndex,
    Oauth2Client oauth2Client,
    ContractNegotiationStore contractNegotiationStore,
    Monitor monitor,
    Map<String, String> hostRewrite,
    AuditStore auditStore              // <-- new (nullable → no-op if unwired)
) { ... }
```

`GlcdiDataplanePublicApiExtension` resolves `AuditStore` via `ServiceExtensionContext.getService(AuditStore.class, /* required */ false)` so the extension remains loadable without the audit-store module. Inside `proxy()`, one call at the end:

```java
if (auditStore != null) {
    auditStore.record(AuditRecord.access(
        Instant.now(), participantId, agreementId, assetId,
        subpath, upstreamResp.code(), body.length));
}
```

That's the entire dataplane change - no interception, no wrapping, no filters.

### 3.6 Retention

Two mechanisms, one at write time (implicit) and one at cleanup time (explicit):

- **Configurable retention floor** - `edc.glcdi.audit.retention.days` (default `90`). A `ScheduledExecutorService` in `GlcdiAuditExtension` runs `auditStore.prune(now - retention)` once every 24h. On boot the extension runs one immediate prune to handle downtime gaps.
- **Display-time row collapse** - performed in the UI, not the store: when the audit-list component renders, consecutive `ACCESS` rows for the same `(participant_id, asset_id)` within `GLCDI_AUDIT_COLLAPSE_WINDOW_SECONDS` (default `60`) render as one row with a fetch count + total bytes. Preserves the underlying rows for forensic drill-down; only the default view collapses.

Rationale for keeping raw rows and collapsing at display: a lazy-loading UI (e.g. a viewer requesting the payload in chunks) can produce hundreds of ACCESS rows per session. Collapsing at write time would lose the per-fetch status codes (useful when some chunks failed); collapsing at display time keeps forensic value while cleaning up the default view.

### 3.7 Query surface

One JAX-RS resource on the management port, path `/v3/glcdi/audit`. Auth: same `X-Api-Key` gate as the other `/management/*` endpoints.

```
GET /v3/glcdi/audit?asset=<id>&participant=<id>&type=ACCESS&from=<iso>&to=<iso>&limit=100&offset=0
→ 200 { total: 4213, items: [ AuditRecord, ... ] }
```

All filters optional; `limit` defaults to 100, capped at 1000; `offset` for pagination. Ordering: `ts DESC` (newest first).

Deliberately not RESTful-CRUD - audit records are append-only, not user-mutable. No POST/PUT/DELETE. Prune is internal only.

### 3.8 UI component

`solid-glcdi/src/components/management/audit-list.ts`, following the pattern established by `negotiations-list.ts`:

- Reads `sib-auth-apikey` from context, calls `/v3/glcdi/audit`.
- Default view: table grouped by `asset_id`, ordered by most-recent activity. Each row shows most-recent event + total access count + distinct consumer count.
- Drill-down: click an asset row → expanded per-event timeline with `ts`, `event_type`, consumer `participant_id`, path, status, bytes.
- Display-time collapse per § 3.6.
- Registered in `participant-ui/config.json.template` + sidebar entry.

---

## 4. What this proposal does not do

Explicitly out of scope for the M1 audit cut, so the reviewer can spot missing coverage:

- **Consumer-side view** ("what have *I* pulled from other providers?") - same signals but subscribed on the consumer's connector; deferred until asked.
- **Aggregation across participants** - the Authority sees no audit stream. Each participant queries its own connector.
- **Payload snapshots** - the audit records that a fetch happened + status + byte count. It does not store the payload or a hash of the payload.
- **Real-time push** - the UI polls the endpoint. No WebSocket / SSE stream. If oncall visibility becomes a need, we'd add it as a separate change.
- **Immutability guarantees** - the audit table is append-only by convention, not by database-level enforcement. If tamper-evidence becomes a requirement (Trust Framework v1 material), we can layer on a hash chain or WORM storage. Not needed for M1.
- **Access-attempt logging** - only *successful* authorize() → proxy attempts get an ACCESS row today. Failed EDR-token validations (`authorizationService.authorize()` returning `failed()`) are logged but not audited; adding them is trivial but expands noise, so deferred pending a stated need.

---

## 5. Risks + open questions

| # | Question | Current stance |
|---|---|---|
| 1 | Should audit rows survive `docker compose down -v`? | Yes for staging (Postgres volume persists across normal restarts; `-v` is a deliberate destructive op). For local dev, the `glcdi.sh reset` workflow explicitly wipes them - acceptable. |
| 2 | Does the extension need to run when the audit-store module is absent? | Yes - `GlcdiDataplanePublicApiExtension` resolves `AuditStore` as optional. The public API keeps working without audit recording. |
| 3 | What happens if `AuditStore.record()` throws? | Wrapped in try/catch inside `proxy()` and the subscriber; the audit failure is logged as a warning but does not fail the underlying proxy or transfer event. Audit is best-effort, not load-bearing. |
| 4 | Does the retention prune need to be transactional or chunked? | For M1: a single `DELETE WHERE ts < ?` is fine (indexed on `ts`). If row counts grow past a few million, revisit with batched deletes. Not premature to optimise now. |
| 5 | Should `participant_id` be resolved from the DSP counterparty rather than the token claim? | Same value at Tier 1 (the connector-SA JWT carries `glcdi_organisation`). At Tier 2/3 the mapping stays the same; no change needed. |

---

## 6. Related documents

- [`../build/plan/phase-4.7-audit-trails.md`](../build/plan/phase-4.7-audit-trails.md) - tactical implementation checklist.
- [`../reference/identity.md`](../reference/identity.md) - identity + claim model that populates `participant_id`.
- `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/` - the existing dataplane extension the ACCESS hook lives in.
- [`../build/scripts/README.md`](../build/scripts/README.md) - orchestration script that wires extensions into the controlplane distribution.
