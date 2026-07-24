# Payment-Gated Data Exchange - Implementation Design (Proposal)

A proposal for how a payment-required contract policy could be enforced end-to-end across the EDC connector and external payment infrastructure. Everything below is a working design for the project team and Dataspace Authority to validate; nothing here is a decided commitment.

This document complements [`policies/contract/payment-required.json`](policies/contract/payment-required.json) (the policy template), [`policies/README.md`](policies/README.md) (the policy catalogue with feasibility ratings), and [`policies/diagrams/09-payment-gated-data-exchange.puml`](policies/diagrams/09-payment-gated-data-exchange.puml) (sequence diagram for the end-to-end flow). The focus here is **how EDC would enforce it** - the connector extension shape, the storage model, the gating mechanism, and the parts that fundamentally cannot be enforced by code and must live in the DSA.

---

## TL;DR

- A rich `payment-required` ODRL agreement (permission + duty + prohibition + obligation + consequence) cannot be enforced *as-written* by stock EDC 0.15.x. About half of it can be enforced with a custom extension; the rest is governance-level.
- Proposed split: **v0** filter-based gate at the management API (small, fast to ship); **v1** ODRL constraint function so the policy is actually evaluated by EDC; **v2** scheduled re-evaluation of time-bound duties + agreement invalidation.
- Storage: reuse EDC's `ContractNegotiation.privateProperties` for v0/v1 (no schema migration); migrate to a side-table only if/when atomic CAS or refund/audit history are needed.
- Governance carve-outs apply to **execution and adjudication** only - the connector still **records** the refund obligation as part of the immutable agreement and surfaces it for audit. Triggering, evaluating, and executing the refund itself live in the Trust Framework + DSA.

---

## 1. The reference policy

The agreement template under discussion (informal - to be ratified). Participant and asset identifiers follow the URN convention proposed in §3.7 (provider's connector-configured participant ID; assets namespaced under their owning provider):

```jsonc
{
  "@context": "http://www.w3.org/ns/odrl.jsonld",
  "@type": "Agreement",
  "uid": "urn:glcdi:agreement:caney-fork:dataAccessPayment-12345",
  "permission": [{
    "@type": "Permission",
    "target":   "urn:glcdi:asset:caney-fork:grazing-soc-2024",
    "action":   { "@id": "http://www.w3.org/ns/odrl/2/use" },
    "assigner": "urn:glcdi:participant:caney-fork",
    "assignee": "urn:glcdi:participant:point-blue",
    "duty": [{
      "@type": "Duty",
      "action":   { "@id": "http://www.w3.org/ns/odrl/2/pay" },
      "target":   "urn:glcdi:invoice:caney-fork:INV-2026-05-001",
      "assigner": "urn:glcdi:participant:caney-fork",
      "assignee": "urn:glcdi:participant:point-blue",
      "constraint": [{ "leftOperand": "dateTime", "operator": "lteq", "rightOperand": "2026-05-10T23:59:59Z" }],
      "consequence": { "action": "invalidate", "target": "urn:glcdi:agreement:caney-fork:dataAccessPayment-12345" }
    }]
  }],
  "prohibition": [{
    "@type": "Prohibition",
    "target":   "urn:glcdi:asset:caney-fork:grazing-soc-2024",
    "action":   { "@id": "http://www.w3.org/ns/odrl/2/use" },
    "assigner": "urn:glcdi:participant:caney-fork",
    "assignee": "urn:glcdi:participant:point-blue",
    "constraint": [{ "or": [
      { "leftOperand": "payAmount", "operator": "neq", "rightOperand": "100.00" },
      { "leftOperand": "dateTime",  "operator": "gt",  "rightOperand": "2026-05-10T23:59:59Z" }
    ]}]
  }],
  "obligation": [{
    "@type": "Obligation",
    "target":   "urn:glcdi:invoice:caney-fork:INV-2026-05-001",
    "action":   { "@id": "http://www.w3.org/ns/odrl/2/compensate" },
    "assigner": "urn:glcdi:participant:point-blue",
    "assignee": "urn:glcdi:participant:caney-fork",
    "constraint": [{ "and": [
      { "leftOperand": "paymentStatus",         "operator": "eq", "rightOperand": "completed" },
      { "leftOperand": "glcdi:accessOutcome",   "operator": "eq", "rightOperand": "denied"    }
    ]}]
  }]
}
```

Note the two semantic adjustments folded in alongside the identifier change: `glcdi:accessOutcome` replaces the misused `odrl:systemDevice` (per §3.5), and the agreement / asset / invoice URNs are namespaced under `urn:glcdi:…` to match the existing GLCDI vocabulary at `https://w3id.org/glcdi/v0.1.0/ns/`.

In plain English:
- **Permission:** the consumer may use the dataset; they have a duty to pay by 2026-05-10. If they don't, the agreement is invalidated.
- **Prohibition:** use is forbidden if the amount paid is anything other than 100.00, or if the deadline has passed.
- **Obligation:** the provider must compensate (refund) the consumer if the consumer paid but was denied access.

It is meaningfully richer than the existing [`payment-required.json`](policies/contract/payment-required.json), which only encodes a `payAmount ≥ 500 USD` duty without deadline, prohibition, consequence, or refund clause.

---

## 2. Clause-by-clause enforcement responsibility

| Clause | Who would enforce it | Mechanism (proposed) | Native to EDC? |
|--------|----------------------|----------------------|:---:|
| Permission `use` action | EDC | Standard contract-policy evaluation at transfer scope | Yes |
| Permission duty: `pay` by deadline (during negotiation) | EDC + extension | Custom constraint function reading `privateProperties["payment.status"]` and `payment.amount` | No - needs custom function |
| Permission duty: deadline has passed (after negotiation) | Extension scheduler | Periodic job that walks negotiations, checks duty deadlines, fires invalidation flow | No - needs scheduled job |
| Consequence: `invalidate` agreement on duty breach | Extension orchestrates native EDC APIs | `POST /v3/contractnegotiations/{id}/terminate` (DSP `ContractNegotiationTermination`) + cascade `POST /v3/transferprocesses/{id}/terminate` for in-flight transfers | Native primitives, custom orchestration only |
| Prohibition: `payAmount ≠ 100.00` | EDC + extension | Same constraint function as duty; reads `payment.amount` | No - needs custom function |
| Prohibition: `dateTime > deadline` | EDC | Built-in `dateTime` constraint function; needs explicit scope registration | Partially native |
| Obligation clause is part of the agreement (immutable, mutually-agreed) | EDC | Standard DSP negotiation - both parties hold a signed copy of the `Agreement` JSON, including the obligation clauses | Yes |
| Obligation discoverability / audit queries | Extension | Read endpoint that lists obligations attached to a negotiation; flag negotiations whose agreement carries refund-trigger obligations | No - needs extension support |
| Obligation: `compensate` adjudication (was the refund actually owed?) | **Dataspace Authority + DSA** | Dispute-resolution process referencing the agreement + the audit trail the connector exposes | **Out of EDC scope** |
| Obligation: `compensate` execution (actually moving the money) | **External payment system** | Same channel that processed the original payment; triggered by the adjudication outcome | **Out of EDC scope** |
| Cross-cutting: `paymentStatus = completed` lookup | EDC + extension | Constraint function reads `privateProperties["payment.status"]` | No - needs custom function |

**Net:** roughly 5 of the 8 clauses are in scope for the connector with custom extensions; 1 is partially native; 1 is fully native; 1 (refund) is governance-only.

---

## 3. Blockers and design constraints

### 3.1 Time-bound duties without re-evaluation

EDC's policy engine evaluates policies at well-defined moments - primarily contract negotiation and transfer-process initiation. There is no native mechanism for "re-check this policy when the deadline passes." A `pay by 2026-05-10` duty cannot be enforced reactively by EDC alone.

**Proposed mitigation:** the payment-status extension exposes a periodic job (cron-like) that walks contract negotiations whose duty deadline has passed without `payment.status = paid` and triggers the invalidation flow described in §3.2.

### 3.2 Mapping `consequence: invalidate` onto DSP contract-negotiation termination

The ODRL `consequence: invalidate` instruction has no *dedicated* counterpart in EDC, but DSP's contract-negotiation lifecycle already provides the right primitive: `ContractNegotiationTermination`. EDC exposes this as `POST /v3/contractnegotiations/{id}/terminate` (with `code` and `reason`), valid as a transition out of `FINALIZED`. The semantics line up cleanly with `invalidate` - the agreement is no longer in force from now on (forward-only; previously transferred data is not retroactively unsent).

What DSP termination gives us automatically:
- **Counterparty notification** via the standard `ContractNegotiationTermination` DSP message. Both connectors transition their respective negotiation to `TERMINATED`.
- **Future transfers refused** by EDC core: `TransferProcessManager` will not create a transfer against a non-`FINALIZED` negotiation, so the v0 filter doesn't even need to check this case - it's enforced upstream.
- **Audit trail as part of the protocol**: the `reason` field is persisted on both sides and exposed via the management API. No additional logging is needed to record *why* the agreement was killed.

What still requires custom code:
- **Cascading TransferProcess termination.** Terminating a negotiation does **not** auto-cancel in-flight `TransferProcess` instances bound to its agreement. The v2 enforcer must walk active transfers for the affected agreement and call `POST /v3/transferprocesses/{id}/terminate` on each. Native API; thin wrapper.
- **Convention for the termination payload.** Recommend `code = "duty-breach"` and `reason = "payment.duty.deadline-exceeded: <duty-uri>"` so an auditor (or the Dataspace Authority) reading the negotiation history can link the termination back to the policy clause that triggered it.

**Net effect on the design:** the v2 `DutyDeadlineEnforcer` becomes a thin orchestrator over two native EDC APIs (terminate negotiation → cascade terminate transfers). The custom `payment.invalidated*` `privateProperties` flagged in §5 are **redundant** - the negotiation's own `state == TERMINATED` is the source of truth, and the termination's `reason` is the audit message. Removing those keys is a strict simplification.

**Stable wire-string convention.** DSP's `ContractNegotiationTermination` carries free-text `reason` only - no structured field for "the policy clause that triggered the termination". The convention adopted here is to use a stable wire-level `reason` string (e.g. `payment.duty.deadline-exceeded:<duty-uri>`) and to mirror it locally as `payment.terminationReason` in `privateProperties` (§5). The local copy is the source of truth for audit queries by the Dataspace Authority; the wire-level string carries the same information across to the counterparty's connector. A standardised structured DSP field would be cleaner - that's an upstream community item, not a blocker here.

### 3.3 Refund / `compensate` obligation: connector records, governance executes

Distinguish three things that often get conflated:

1. **Recording the obligation.** That the provider is *bound* to refund under specific conditions is part of the negotiated `Agreement`. EDC stores the agreement immutably on both sides as a normal outcome of contract negotiation - the obligation clause is preserved verbatim in that JSON. **This is exactly the connector's job, and it is one of the core values of using EDC + ODRL in the first place.** Without a connector-recorded agreement the refund clause would be a side-letter; with it, both parties have a non-repudiable copy of what they agreed to.

2. **Adjudicating whether a refund is actually owed.** Did the consumer pay? Did access genuinely fail in a way that warrants a refund (vs. consumer-side error, vs. provider's reasonable refusal)? This is a **Dataspace Authority** concern - see [`AUTHORITY.md` § D Compliance, monitoring & incident response](AUTHORITY.md). The DSA and Trust Framework specify the dispute-resolution process; the connector contributes evidence (the agreement + the audit trail described below) but does not arbitrate.

3. **Executing the refund.** Moving the money happens through the same external payment system that processed the original payment, triggered by the adjudication outcome. The connector has no payment rails and should not acquire any.

**What the connector needs to provide for (1) to be useful in (2):**

- **Agreement persistence with the obligation clause intact.** Native to EDC - the `Agreement` JSON returned by `GET /v3/contractagreements/{id}` includes obligations as written.
- **Obligation discoverability.** A query/listing endpoint exposed by the extension so an auditor or the Dataspace Authority can ask "which agreements involving party X carry a refund obligation, and what's their payment + access history?" - see §6 for the proposed `GET /v3/contractnegotiations/{id}/obligations` endpoint and the audit query.
- **Audit trail of payment + access events** keyed by negotiation ID: `payment.status` transitions, the negotiation's own `state` (including `TERMINATED` if the agreement was killed), `payment.terminationReason` if applicable, and transfer-process attempts (success/denial), with timestamps and `externalRef` values. All of this is captured by the storage schema in §5 (and by EDC's own negotiation-state history) - no additional design needed beyond exposing it on a read endpoint.

**Cross-reference to the existing pattern:** the recording-vs-execution split applies the same shape that `attribution`, `anonymisation`, and `data-retention-limit` already use in [`policies/README.md` § Implementation Feasibility](policies/README.md#implementation-feasibility) - the connector binds the parties to the obligation through the agreement; governance handles compliance verification and consequences. The novelty here is that for refunds, "execution" eventually means a money transfer, which makes the boundary between connector and external system more visible.

**What this means for the Trust Framework:** the document needs to spell out (a) what evidence the Dataspace Authority would request from each party in a refund dispute (and what the connector exposes to satisfy that request), (b) the adjudication procedure, (c) the timeline expected for the provider to honour an upheld refund claim. The connector's audit endpoint is the substrate; the procedure is policy.

**Proposed authority-side service & UI.** To make the audit substrate operational, an **auditing service** on the Dataspace Authority side is proposed: it consumes the per-participant connectors' obligation-listing and audit-log endpoints (§5.3), aggregates evidence across negotiations and parties, and exposes it through a UI the Dataspace Authority uses when handling refund claims, compliance reviews, and incident investigations. The connector-side endpoints are designed to be the data plane for exactly this kind of service. Scope, ownership, deployment topology, and access controls for that service are to be agreed by the Dataspace Authority alongside the Trust Framework - flagged as a proposal here so the connector-side endpoints in §5.3 are sized correctly for an aggregating consumer rather than only ad-hoc human queries. Cross-reference: [`AUTHORITY.md` § D Compliance, monitoring & incident response](AUTHORITY.md).

### 3.4 Custom constraint functions required

At least three left-operands in the reference policy have no built-in EDC evaluator: `payAmount`, `paymentStatus`, and `systemDevice`. Each requires an `AtomicConstraintFunction<Object>` registered with the `PolicyEngine` for the relevant scope (typically `TRANSFER_SCOPE`).

The functions would all read from the same `privateProperties` keys set by the payment-status update endpoint (§5.2). This means the **storage schema and the constraint-function contract are tightly coupled** - they must agree on key names and value formats. Treat this as a single design artefact, not two independent ones.

### 3.5 `systemDevice` is being misused in the reference policy

`odrl:systemDevice` in the ODRL vocabulary is for restricting use to specific devices/systems identified by URI (e.g. "this license is valid only on this server"). The reference policy uses it as a string flag (`"accessDenied"`) which is not how the vocabulary works.

**Proposed mitigation:** introduce a project-namespaced term in `https://w3id.org/glcdi/v0.1.0/ns/` (e.g. `glcdi:accessOutcome` with values `granted` / `denied`) and use that in the obligation. Constraint-function evaluation is identical; only the vocabulary URI changes. This keeps the policy syntactically valid against ODRL and semantically honest.

### 3.6 Where does "the agreed amount" live?

The Prohibition checks `payAmount ≠ 100.00`, but nothing in the Permission states that 100.00 is the agreed amount - it's only implicit. EDC needs to know the agreed amount to evaluate the prohibition.

**Convention:** the agreed amount is stamped onto the `ContractNegotiation` as a `privateProperty` at negotiation finalization, sourced from the policy template's `payAmount` constraint. The `NegotiationFinalizedObserver` (§6) parses the agreement's policy at the `finalized` lifecycle event, extracts the `payAmount` (and `unit` → `payment.currency`) from the relevant constraint, and writes `payment.amount` + `payment.currency` to `privateProperties`. From that point on, the constraint functions in v1 read these stamped values and the agreed amount is immutable for the life of the agreement.

This matches the policy-template-as-source-of-truth model already used elsewhere in GLCDI: the template is the canonical specification of the offer; runtime values derive from it deterministically. Per-asset dynamic pricing (computing the amount at offer-generation time rather than reading it from the template) is **explicitly not adopted at this stage** - it would require a separate offer-generation pipeline that doesn't exist in the connector today and would couple the payment extension to upstream offer logic. If dynamic pricing is needed later (e.g. tiered consumer pricing), revisit by adding the pricing decision *before* the policy template is selected, so the stamped value still comes from the policy that was actually presented to the consumer.

**Residual implementation question (a small spike, not a design choice):** at the `finalized` lifecycle event, does the observer have access to the literal `payAmount` value, or has the policy already been canonicalised into a form where the constraint values are harder to extract? Either way the data is available - worst case the observer parses the stored `Agreement.policy` JSON. Worth a 30-minute check against EDC 0.15.x's `ContractNegotiationListener.finalized()` callback before writing the observer.

### 3.7 Participant identifier format

ODRL accepts any IRI for `assigner`/`assignee`, but EDC's policy engine compares against the participant ID configured per-connector (`participant.id` in `participant/configuration.properties`). Mixing HTTPS URLs (as the original reference policy did) with the configured IDs causes silent comparison failures in policy evaluation.

**Convention:** policy templates and agreements use the connector-configured participant ID, expressed as a URN under the GLCDI namespace:

| URN form | Used for | Example |
|----------|----------|---------|
| `urn:glcdi:participant:<connector-id>` | `assigner`, `assignee`, anywhere a party is referenced | `urn:glcdi:participant:caney-fork` |
| `urn:glcdi:asset:<provider>:<asset-id>` | `target` for Permission/Prohibition acting on data | `urn:glcdi:asset:caney-fork:grazing-soc-2024` |
| `urn:glcdi:agreement:<provider>:<agreement-id>` | `Agreement.uid`, `consequence.target` invalidating the agreement | `urn:glcdi:agreement:caney-fork:dataAccessPayment-12345` |
| `urn:glcdi:invoice:<provider>:<invoice-id>` | `target` of `pay` duty / `compensate` obligation | `urn:glcdi:invoice:caney-fork:INV-2026-05-001` |

**Forward path to DIDs.** [`IDENTITY.md`](IDENTITY.md) documents the planned migration from OIDC/JWT to DCP/DID/VC. When that lands, the participant URN evolves to its DID form (e.g. `did:web:caney-fork.glcdi.startinblox.com`). The policy templates do not need a structural rewrite at that point - only the participant-ID strings change. Asset/agreement/invoice URNs stay as-is (they are not identity-claim subjects).

**HTTPS URLs in incoming agreements.** The catalogue UI and onboarding flow may surface participants by HTTPS URL for human readability. Treat that as a presentation concern: the policy engine's source of truth is the URN, and any URL-to-URN mapping happens at the UI / onboarding layer, not in policy evaluation.

### 3.8 Permission/Prohibition redundancy in the reference policy

The Permission duty + Prohibition encode overlapping conditions (the deadline appears in both; the amount appears in the Prohibition only). This is technically valid ODRL but doubles the surface area for constraint evaluation and for keeping the two clauses consistent over time.

**Proposed mitigation:** during the formal policy template review (Dataspace Authority), simplify to either (a) Permission + duty form *or* (b) Permission + Prohibition form, not both. Recommendation: keep the Permission + duty (with consequence) as the primary form because it directly expresses the obligation; drop the Prohibition. The Prohibition's deadline check becomes redundant once the scheduled-invalidation job (§3.1) is in place.

---

## 4. Three-stage rollout

A staged rollout that ships value early without locking in design choices that depend on later phases.

### v0 - Procedural gate at the management API

**Scope:** boolean payment status, manual update from external payment system, transfer initiation refused at the management API if unpaid. Does **not** evaluate the ODRL policy.

**Components:**
- Storage: `ContractNegotiation.privateProperties` with keys `payment.status`, `payment.paidAt`, `payment.amount`, `payment.externalRef`.
- Update endpoint: `POST /v3/contractnegotiations/{id}/payment` with body `{"paid": true, "amount": "100.00", "externalRef": "stripe_pi_..."}`. Uses the standard `X-Api-Key` from `web.http.management.auth.key`. Idempotent (re-applying the same paid=true is a 200, not a 409).
- Gate: a JAX-RS `ContainerRequestFilter` on `POST /v3/transferprocesses` that resolves the request body's `contractId` → agreement → source negotiation, reads `privateProperties["payment.status"]` and the duty deadline (also stamped at finalization), and aborts with HTTP 402 Payment Required if either the agreement is unpaid or the deadline has passed without payment. The deadline check is included in v0 because v2's scheduler is not yet in place to terminate overdue agreements; once v2 ships, the deadline check becomes redundant (EDC core will reject transfers against a `TERMINATED` negotiation upstream of the filter) and can be removed.
- Notification hook: `ContractNegotiationListener.finalized()` sends an email to a configured contact address (the provider's finance/ops team) with the negotiation ID, agreement summary, agreed amount, deadline, and the URL of the payment update endpoint. SMTP host and recipient address are pulled from extension config (see §6.1). This is deliberately the simplest channel for the prototype: no webhook receiver to stand up, no automation contract with an external system, just an email a human acts on by issuing an invoice and (later) calling the payment endpoint to flip the flag. The send happens asynchronously off the state-machine thread to avoid stalling negotiations on SMTP latency.
  - **Consumer-side notification is out of scope.** The external billing/payment solution is the canonical channel that tells the consumer "you owe payment for negotiation X" (typically the invoice itself, sent by the provider's finance system). The connector does not duplicate this.
  - **Webhook is the planned forward addition, not a replacement.** When automated payment-platform integration becomes worth supporting, a `WebhookNotificationSender` plugs in alongside the email sender via the `NotificationSender` interface (see §6) and is selectable per-deployment via config. Email stays available because human-in-the-loop workflows remain the right shape for smaller participants.

**Trade-off accepted:** the ODRL policy is documentation-only at this stage. The connector enforces the *intent* (no transfer without payment) but does not actually evaluate the constraint expressions. Rich clauses like `payAmount = 100` are not checked - only the boolean `paid` flag is.

**What this catches:** consumer-initiated transfers via the management API (which is the only path in GLCDI's current topology).
**What this misses:** any transfer initiated through a non-management path (provider push, programmatic creation, future flows).

### v1 - ODRL constraint functions

**Scope:** the connector's policy engine actually evaluates the reference policy's constraints. The filter from v0 stays as defence-in-depth.

**Components added:**
- `PaymentStatusConstraintFunction` for `paymentStatus` left-operand: returns true iff `privateProperties["payment.status"] == "paid"` AND `privateProperties["payment.amount"] == constraint.rightOperand`.
- `PayAmountConstraintFunction` for `payAmount` left-operand: returns the stored `payment.amount` for comparison.
- `dateTime` constraint function registration on `TRANSFER_SCOPE` (uses EDC's built-in time function, just needs explicit scope wiring).
- (Optional) `AccessOutcomeConstraintFunction` for the `glcdi:accessOutcome` term introduced to replace the misused `systemDevice` (§3.5).

**What v1 unlocks:** transfers initiated through any code path are gated, not just the management API. The policy is now machine-evaluated, which is the dataspace-native enforcement model.

### v2 - Time-bound duty enforcement

**Scope:** automated invalidation when a duty deadline passes without payment.

**Components added:**
- A scheduled job (e.g. via EDC's `@Provides` hook or a simple `ScheduledExecutorService` in the extension) that runs hourly and queries negotiations with active duty deadlines.
- For each negotiation past its deadline with `payment.status != paid`: write `payment.terminationReason` to `privateProperties`, then call `POST /v3/contractnegotiations/{id}/terminate` (DSP-level termination - propagates to the counterparty), then walk that negotiation's active `TransferProcess` instances and call `POST /v3/transferprocesses/{id}/terminate` on each.
- No additional short-circuit needed in the v0 filter or v1 constraint functions - EDC's `TransferProcessManager` already refuses transfer creation against non-`FINALIZED` negotiations, so terminated agreements are rejected upstream of our gate.

**What v2 unlocks:** the `consequence: invalidate` clause becomes operational and propagates through DSP. Both the provider's and consumer's connectors converge on `TERMINATED` for the affected negotiation; future transfers are refused on both sides without further logic.

### Out of scope at every stage

- **Refund execution.** Triggering a refund is the external payment system's job; deciding whether a refund is owed is the Dataspace Authority's job (per the dispute-resolution process documented in the Trust Framework). The connector logs evidence; that is its entire role here.
- **Structured "policy clause that triggered termination" field in DSP.** DSP's `ContractNegotiationTermination` carries free-text `reason`; there is no standardised structured field for "this termination was caused by ODRL clause X". We work around this by storing `payment.terminationReason` locally (§5) and using a stable convention for the free-text `reason` payload. A standardised field is a research item for the wider EDC / Dataspace community.
- **Multi-payment / partial payments / instalments.** v0–v2 assume a single boolean transition (unpaid → paid). Richer payment models (instalments, partial refunds, top-ups) require migrating from `privateProperties` to a side-table - defer.

---

## 5. Storage schema

Single source of truth for the `payment.*` keys on `ContractNegotiation.privateProperties`.

| Key | Type | Set by | Read by | Notes |
|-----|------|--------|---------|-------|
| `payment.status` | string | Update endpoint (§5.2) | Filter (v0), `PaymentStatusConstraintFunction` (v1), scheduled job (v2) | Allowed values: `pending` (default at negotiation finalization), `paid`, `failed`, `refunded` |
| `payment.amount` | string (xsd:decimal) | Negotiation finalization listener | `PayAmountConstraintFunction` (v1), refund-adjudication process | Set from the policy template at finalization; immutable thereafter |
| `payment.currency` | string (ISO 4217) | Negotiation finalization listener | Audit, refund process | e.g. `USD`, `EUR` |
| `payment.paidAt` | string (ISO 8601) | Update endpoint | Audit, refund process | Set when `payment.status` transitions to `paid` |
| `payment.externalRef` | string | Update endpoint | Audit, refund process | External payment system's transaction reference; opaque to EDC |
| `payment.terminationReason` | string | Scheduled job (v2), set just before calling `POST /contractnegotiations/{id}/terminate` | Audit endpoint, Dataspace Authority queries | Structured local copy of the termination cause (e.g. `payment.duty.deadline-exceeded:<duty-uri>`). Avoids parsing free-text DSP `reason` strings later. The negotiation's own `state == TERMINATED` is the authoritative "is this agreement still in force" signal - see §3.2 |

**Migration trigger to a side-table:** any of (a) more than one payment event per negotiation (instalments, refunds), (b) atomic CAS becomes a hard requirement (concurrent webhook deliveries are causing measurable data loss), (c) refund-adjudication needs queryable history rows rather than blob-style audit log.

### 5.1 Concurrency note

`privateProperties` is a JSON map; updates are not atomic at the SQL level. Two concurrent `POST /payment` calls can race and overwrite each other. Mitigation for v0:
- Make the update endpoint **idempotent on the same `externalRef`** - re-applying the same payment confirmation is a 200 with no state change.
- Treat conflicting `externalRef` values on the same negotiation as a 409 Conflict (the second caller has a different external transaction ID for the same negotiation - that's a real conflict that needs investigation).

This handles webhook duplication and most operator-error cases without needing a side-table.

### 5.2 Update endpoint contract

```http
POST /v3/contractnegotiations/{id}/payment
Content-Type: application/json
X-Api-Key: <web.http.management.auth.key>

{
  "paid": true,
  "amount": "100.00",
  "currency": "USD",
  "externalRef": "stripe_pi_3MXa..."
}
```

Responses:
- `200 OK` - payment recorded (or already recorded with the same `externalRef`).
- `409 Conflict` - payment already recorded with a different `externalRef`.
- `404 Not Found` - no negotiation with this ID.
- `409 Conflict` - negotiation is not in `FINALIZED` state with an `Agreement`.
- `401 Unauthorized` - missing or invalid `X-Api-Key`.

Read endpoint (symmetric):

```http
GET /v3/contractnegotiations/{id}/payment
```

Returns the `payment.*` keys as a JSON object, or `404` if no payment record exists yet.

### 5.3 Audit & obligation-discovery endpoints

To satisfy the recording role described in §3.3, the extension exposes two read-only endpoints intended for the Dataspace Authority and the participants themselves (same `X-Api-Key` auth):

```http
GET /v3/contractnegotiations/{id}/obligations
```

Parses the agreement bound to the negotiation, extracts the `obligation` clauses (and any `duty` clauses with `consequence`), and returns them as a structured list with: action (e.g. `compensate`, `pay`), assigner, assignee, constraints, and the `glcdi:`-namespaced trigger terms. Returns `404` if no agreement exists yet, `200` with `[]` if the agreement carries none.

```http
GET /v3/contractnegotiations/{id}/audit
```

Returns the per-negotiation audit log: `payment.*` transitions with timestamps, the negotiation's lifecycle states (especially any `TERMINATED` transition with its DSP `reason` and the local `payment.terminationReason`), and a list of transfer-process attempts (created-at, terminal state, denial reason if any). This is the evidence bundle a refund-adjudication process would request.

Both endpoints derive their content from data already stored by EDC (the agreement) and by the extension (the `payment.*` `privateProperties` and the transfer-process events the extension observes). No additional storage is introduced.

A coarser cross-negotiation query (`GET /v3/obligations?assignee=...`) is *not* in scope for v0 - the Dataspace Authority looks up obligations one negotiation at a time. Bulk listing is a v1+ consideration if audit volume justifies it.

---

## 6. Extension layout (proposed)

A new sibling of `example-extension` in `edc-connector/extensions/`:

```
edc-connector/extensions/payment-status-extension/
├── build.gradle.kts
└── src/main/java/com/startinblox/glcdi/edc/extension/payment/
    ├── PaymentStatusExtension.java          # @Extension, wires v0 components; v1 adds constraint-function registration; v2 adds scheduler
    ├── controller/PaymentController.java    # JAX-RS controller for the payment update + read endpoints (§5.2)
    ├── controller/AuditController.java      # JAX-RS controller for obligation-listing + audit-log endpoints (§5.3)
    ├── filter/PaymentRequiredFilter.java    # v0 ContainerRequestFilter on POST /v3/transferprocesses
    ├── observer/NegotiationFinalizedObserver.java  # ContractNegotiationListener.finalized() - stamps payment.amount/currency, triggers email notifier
    ├── observer/TransferAttemptRecorder.java       # TransferProcessListener - appends transfer-process attempts to the per-negotiation audit log
    ├── notify/NotificationSender.java              # interface - pluggable channel; v0 has one impl
    ├── notify/EmailNotificationSender.java         # v0 - jakarta.mail SMTP; runs on a small async ExecutorService
    ├── policy/PaymentStatusConstraintFunction.java # v1 - registered to TRANSFER_SCOPE
    ├── policy/PayAmountConstraintFunction.java     # v1
    ├── scheduler/DutyDeadlineEnforcer.java         # v2 - periodic invalidation of overdue duties
    ├── service/ObligationExtractor.java            # parses the Agreement JSON, extracts obligation/duty/consequence clauses
    └── model/PaymentRecord.java                    # value object marshalled to/from privateProperties
```

### 6.1 Configuration

The extension reads its config from EDC's standard configuration mechanism (so values can be supplied via `participant/configuration.properties`, environment variables, or any other configured source). v0 keys:

| Key | Purpose | Required |
|-----|---------|----------|
| `glcdi.payment.notify.email.to` | Recipient address for finalization notifications (provider's finance/ops contact) | Yes for v0 |
| `glcdi.payment.notify.email.from` | Sender address (defaults to `noreply@<participant-host>` if unset) | No |
| `glcdi.payment.notify.smtp.host` | SMTP host | Yes |
| `glcdi.payment.notify.smtp.port` | SMTP port (typically 587) | No, default 587 |
| `glcdi.payment.notify.smtp.user` | SMTP auth username | If SMTP requires auth |
| `glcdi.payment.notify.smtp.password` | SMTP auth password | If SMTP requires auth |
| `glcdi.payment.notify.smtp.starttls` | `true`/`false` | No, default true |

If `glcdi.payment.notify.email.to` is unset, the extension logs at WARN on finalization and skips the email - the rest of the v0 flow (storage, gating, payment update endpoint) still works without notifications, so a deployment can run unconfigured for testing.

Wired in `runtimes/controlplane/build.gradle.kts` as `runtimeOnly(project(":extensions:payment-status-extension"))`.

---

## 7. Documentation & cross-references to update

When the v0 extension lands:
- [`policies/README.md`](policies/README.md) - `payment-required` row in the Implementation Feasibility table moves from "post-prototype, requires custom function + external payment API" to reflect the v0 shape (filter + privateProperties + external payment system + audit endpoints for the refund-obligation substrate).
- [`policies/contract/payment-required.json`](policies/contract/payment-required.json) - replace with the richer reference template once the Dataspace Authority approves it; remove the misused `systemDevice` term in favour of a `glcdi:`-namespaced equivalent (§3.5).
- [`README.md`](README.md) "Technical vs. Governance Enforcement" table - `payment-required` row updated to reference this document; add a row (or footnote) clarifying the recording-vs-execution split for refund obligations (§3.3).
- [`IMPLEM_PLAN.md`](IMPLEM_PLAN.md) Phase 6 (governance-level enforcement) - link to this document; mark v0/v1/v2 as substages of the payment workstream.
- [`STANDARDS.md`](STANDARDS.md) - ODRL Duty + Consequence + Obligation row gets a footnote pointing to this document for the GLCDI-specific implementation.
- [`AUTHORITY.md` § D](AUTHORITY.md) - add a sub-bullet under "Compliance, monitoring & incident response" pointing to this document's audit endpoints (§5.3) as the evidence substrate the Authority would query when adjudicating a refund claim, and reflecting the proposal in §3.3 for an authority-side auditing service + UI that aggregates evidence across participant connectors.
- **Trust Framework v0/v1** (drafted by the Dataspace Authority, not in this repo yet) - needs sections covering: refund-claim intake procedure, evidence the Authority can request from each party, adjudication timeline, expected provider behaviour on an upheld claim. The connector's audit endpoints provide the substrate; the procedure itself is governance.

---

## References

- [`policies/README.md`](policies/README.md) - policy catalogue & feasibility ratings
- [`policies/contract/payment-required.json`](policies/contract/payment-required.json) - current policy template (simpler than the reference policy in §1)
- [`README.md` § Technical vs. Governance Enforcement](README.md) - the bridging table this document elaborates one row of
- [`IMPLEM_PLAN.md` § Phase 6](IMPLEM_PLAN.md) - governance-level enforcement phase
- [`AUTHORITY.md` § D Compliance, monitoring & incident response](AUTHORITY.md) - the body that would adjudicate refund claims
- [`STANDARDS.md`](STANDARDS.md) - ODRL Duty / Consequence / Obligation as standards
- [Eclipse EDC docs - Custom Policy Functions](https://eclipse-edc.github.io/docs/) - for the v1 constraint-function implementation
