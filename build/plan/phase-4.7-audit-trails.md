# Phase 4.7: Audit Trails (Provider-Side)

In-scope for M1. Answers the participant question *"who accessed my datasets, when?"* — a gap in the M1 demo today because the connector logs transfer/EDR/access events but does not persist them for review. Full design rationale in [`../../design/audit-trails.md`](../../design/audit-trails.md); this file is the tactical checklist.

| Item | Detail |
|------|--------|
| **Task** | Ship a new `glcdi-audit-store` extension that persists transfer-lifecycle events and public-API accesses to Postgres, exposes them via a management endpoint, and prunes rows past a configurable retention (default 90 days). Add a matching `audit-list` component to `solid-glcdi` and register it in `participant-ui`. |
| **Approach** | Reuse hooks that already exist: `EventRouter` for transfer events, `GlcdiPublicApiController.proxy()` (already resolves `agreement_id` / `participant_id` / `asset_id` from the EDR token) for API access. One table, one endpoint, one component. |
| **Scope carve-out** | Provider-side only. No consumer-side view, no Authority aggregation, no payload capture, no real-time push. All deferred to a post-M1 follow-up. |
| **Status** | Implemented (extension + UI + Bruno tests land in one pass). Local smoke pending — needs `glcdi.sh reset && glcdi.sh all` to confirm rows appear after a real transfer + EDR fetch. |

## 4.7.1 Extension - `glcdi-audit-store`

New Gradle module under `edc-glcdi-extension/extensions/glcdi-audit-store/`, mirroring `glcdi-policy-functions`.

- [x] `build.gradle.kts` declares deps on `spi/data-plane/data-plane-spi`, `spi/control-plane/transfer-spi`, `spi/common/transaction-spi`, `spi/common/web-spi`, and the Postgres SQL utilities the connector already uses.
- [x] Register the module in `edc-glcdi-extension/settings.gradle.kts`.
- [x] `AuditRecord` POJO — `id`, `ts`, `eventType`, `participantId`, `agreementId`, `assetId`, `transferId`, `path`, `statusCode`, `bytes`, `extra` (Map<String, Object>). Factory helpers `AuditRecord.access(...)`, `AuditRecord.transferEvent(...)`.
- [x] `AuditEventType` enum — `TRANSFER_STARTED`, `TRANSFER_COMPLETED`, `TRANSFER_TERMINATED`, `ACCESS`.
- [x] `AuditStore` SPI — `record(AuditRecord)`, `query(AuditFilter)`, `prune(Instant olderThan)`.
- [x] `SqlAuditStore` — SQL impl backed by the connector's `DataSourceRegistry`.
- [x] `AuditRecordMapper` — `ResultSet` → `AuditRecord`.
- [x] Liquibase changelog `src/main/resources/glcdi-audit-schema.xml` creating `glcdi_audit` + three indices (see design doc § 3.2).
- [x] `GlcdiAuditExtension` (controlplane wiring) — registers `AuditStore`, `TransferAuditSubscriber`, `AuditApiController`, `ScheduledAuditPrune`.
- [x] `GlcdiAuditDataplaneExtension` (dataplane wiring) — resolves `AuditStore` as optional and hands it to the public-API controller factory.

## 4.7.2 Transfer-event subscriber

- [x] `TransferAuditSubscriber implements EventSubscriber<TransferProcessEvent>`.
- [x] Registered via `EventRouter.registerSync(TransferProcessEvent.class, subscriber)`.
- [x] Handles `TransferProcessStarted` → `TRANSFER_STARTED`, `TransferProcessCompleted` → `TRANSFER_COMPLETED`, `TransferProcessTerminated` → `TRANSFER_TERMINATED`.
- [x] Ignores `Initiated`, `Requested`, `Suspended` (rationale in design doc § 3.4).
- [x] Resolves `assetId` + `assignee participantId` via `ContractNegotiationStore.findContractAgreement(contractId)`. Falls back to leaving the field `null` if lookup fails (record is still useful for forensics).
- [x] Wraps `auditStore.record(...)` in try/catch — audit failure logs a warning; the event pipeline continues.

## 4.7.3 Dataplane public-API access recording

Change to the existing `edc-glcdi-extension/extensions/glcdi-dataplane-public-api/`:

- [x] Add `AuditStore auditStore` as a **nullable** constructor arg on `GlcdiPublicApiController`.
- [x] In `proxy()`, after the upstream fetch succeeds (or fails with an upstream status), one call: `if (auditStore != null) auditStore.record(AuditRecord.access(...))`. Wrapped in try/catch.
- [x] `GlcdiDataplanePublicApiExtension` resolves `AuditStore` via `context.getService(AuditStore.class, false)` so the public-API extension stays loadable when `glcdi-audit-store` is not on the classpath.
- [x] Extend the existing unit test (once one exists) or add a smoke test that verifies one `ACCESS` row lands per successful proxy call.

## 4.7.4 Retention prune

- [x] `ScheduledAuditPrune` uses a `ScheduledExecutorService` scheduled at 24h intervals in `GlcdiAuditExtension.start()`.
- [x] Config keys: `edc.glcdi.audit.retention.days` (default `90`), `edc.glcdi.audit.prune.enabled` (default `true`).
- [x] On extension start, run one immediate prune to cover downtime gaps.
- [x] Logs `n rows pruned older than <ts>` at INFO on each run.

## 4.7.5 Management API

- [x] `AuditApiController` — JAX-RS resource at `/v3/glcdi/audit`, registered on the management port.
- [x] `GET /v3/glcdi/audit?asset=&participant=&type=&from=&to=&limit=&offset=` — all filters optional; `limit` defaults to 100, capped at 1000.
- [x] Response: `{ total: number, items: AuditRecord[] }` ordered `ts DESC`.
- [x] Auth: same `X-Api-Key` gate as the other management endpoints (already handled by the connector's management-api authz filter — nothing extra to wire).
- [x] `AuditFilter` DTO for the query string.

## 4.7.6 solid-glcdi UI component

- [x] `solid-glcdi/src/components/management/audit-list.ts` — Lit component named `<glcdi-audit-list>`.
- [x] Reads the operator API key from the `sib-auth-apikey` context (pattern from `negotiations-list.ts`).
- [x] Fetches `/v3/glcdi/audit`, groups by `asset_id` for the default view.
- [x] Row-collapse consecutive `ACCESS` events for the same `(participant_id, asset_id)` within `GLCDI_AUDIT_COLLAPSE_WINDOW_SECONDS` (default `60`) — display-time only, does not mutate stored rows.
- [x] Drill-down: click an asset row → per-event timeline (`ts`, `event_type`, `participant_id`, `path`, `status_code`, `bytes`).
- [x] Filter chips for `event_type` (`ACCESS` / `TRANSFER_*` / All).
- [x] Refresh button + optional 30s poll toggle (off by default).
- [x] Unit tests where the existing components have them (test setup pattern only — extending coverage is a separate follow-up).

## 4.7.7 participant-ui registration

- [x] Add `<glcdi-audit-list>` to `participant-ui/config.json.template` under the management section.
- [x] Add a sidebar entry pointing at the new route (pattern from `glcdi-sidebar.ts` in solid-glcdi).
- [x] Rebuild the participant-ui image (`docker build -t glcdi-participant-ui .`) and verify the view renders in the local stack.

## 4.7.8 Controlplane distribution wiring

- [x] `build/scripts/sync-glcdi-extensions.sh` copies extensions via `cp -r` from `edc-glcdi-extension/extensions/` into `edc-connector/extensions/`. Verify the new `glcdi-audit-store` module is picked up on the next sync.
- [x] Declare the module as a runtime dependency in the controlplane's runtime module (`edc-connector/runtimes/controlplane/build.gradle.kts` — same pattern as `glcdi-policy-functions`).
- [x] Verify the connector starts, the Liquibase migration runs, and `\dt glcdi_audit` shows the table after `glcdi.sh reset && glcdi.sh up`.

## 4.7.9 Bruno acceptance test

New folder `management/build/bruno/50-audit/`:

- [x] `01-baseline.bru` — GET `/v3/glcdi/audit`, assert `total == 0` on a fresh stack.
- [x] `02-transfer-produces-rows.bru` — chains from `40-transfer/`'s successful flow, then GET `/v3/glcdi/audit?type=TRANSFER_STARTED` and asserts at least one row with the expected asset + consumer.
- [x] `03-access-produces-rows.bru` — issues a GET against the EDR endpoint (public API), then queries `?type=ACCESS` and asserts at least one row.
- [x] `04-filter-by-asset.bru` — verifies filter narrows correctly.
- [x] Document the folder in `build/bruno/README.md` under the acceptance-signals table.

## Dependencies

- **Requires Phase 4** (seeding scripts) — need seeded assets for a transfer to run against in the Bruno test.
- **Requires Phase 4.5.E** (Bruno collection) — new tests live alongside the existing collection.
- **Does not depend on Phase 4.6** (decouple-ui) — the audit-list component lives in solid-glcdi (which is GLCDI-owned already); no upstream fork required.
- **Optional post-M1 extension:** consumer-side visibility, real-time push, Authority-side aggregation. Design carve-outs documented in [`../../design/audit-trails.md`](../../design/audit-trails.md) § 4.

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 4.6: Decouple participant-ui from `@startinblox/solid-tems`](phase-4.6-decouple-ui.md) · [next: Phase 5: Testing & Validation →](phase-5-testing.md)
