# Phase 4.6: Decouple participant-ui from `@startinblox/solid-tems`

In-scope for M1. Promoted from the post-prototype backlog because the upstream `tems-modal` only renders rich content for `RDFTYPE_OBJECT` / `RDFTYPE_SERVICE` - for plain `Asset` types (what GLCDI seeds) it shows only the description, no title, no data-address, no Negotiate CTA. The same upstream ownership gap surfaced as the catalog-card `[object Object]` provider badge, the "0 datasets" miscount, and the auth-gating leak (background calls bypassing the paste form). All of them trace to internals we can't change without owning the code.

| Item | Detail |
|------|--------|
| **Task** | Fork or duplicate the catalogue / asset / policy / contract / negotiation components currently sourced from `@startinblox/solid-tems` (+ `solid-tems-ui`) into the GLCDI-owned `solid-glcdi` bundle. |
| **Approach** | Bias to (a) **light fork** - copy only the components GLCDI actually uses (`solid-dsp-catalog`, `tems-modal`, `tems-catalog-data-holder`, `tems-*-management`) into `solid-glcdi`, drop solid-tems from `npm[]`, iterate freely. Alternative (b) is a full fork of `solid-tems-v2` under a GLCDI repo with upstream contribs for dataspace-generic fixes. |
| **Wins this unlocks** | Asset modal showing full props (name, `@id`, data-address, providers, access-policy summary) + a real "Negotiate" CTA that builds the ContractRequest body in the JSON-LD shape EDC 0.15.x accepts; consistent GLCDI branding (no more design-token tug-of-war vs. TEMS' defaults); Cypress test coverage on components GLCDI owns. |
| **Why now (not post-M1)** | M1 explicitly demos catalog → modal → negotiate → transfer. The modal gap blocks the demo. Inheriting upstream bugs while we're stabilising the M1 fixtures consumes more triage time than owning the source would. |
| **Status** | [ ] Not started |

## 4.6.1 Asset detail modal - completion checklist

Specific gaps the fork has to close (acceptance criteria for the modal's M1 cut):

- [ ] Modal title = asset `properties.name`
- [ ] Modal subtitle = `@id` (clickable copy-to-clipboard)
- [ ] Properties section - render `properties.*` excluding internal keys
- [ ] Data address section - `type` + `baseUrl` + `proxyPath` if HttpData
- [ ] Provider badge with `_provider.name` (not `[object Object]`)
- [ ] Access policy summary - fetch the contract-def by id, render constraints in human-readable form (e.g. "Requires: producer + regen-verified")
- [ ] "Negotiate contract" CTA - builds the ContractRequest body in the JSON-LD shape EDC 0.15.x accepts (`odrl:permission` + `{"@id":"..."}` for action/operator/leftOperand, see `management/build/bruno/30-negotiation/01-negotiate-internal-purpose.bru`), POSTs to `/management/v3/contractnegotiations` with the operator's X-Api-Key
- [ ] Negotiation status drawer - polls `/management/v3/contractnegotiations/{id}` and surfaces state transitions until FINALIZED / TERMINATED
- [ ] "Initiate transfer" CTA once an agreement exists

## 4.6.2 Other follow-ups to fold in during the fork

- [ ] Auth gating - sib-auth-apikey now propagates the operator key to `[participant-api-key]` elements on activation. Once the components live in `solid-glcdi`, replace the attribute-pushing approach with reading the key directly from `sib-auth:activated` events (cleaner: no DOM walk).
- [ ] Provider Statistics counter - use `_provider.participantId` for matching (today it tries `_provider === provider.name`, which is always false because `_provider` is an object).
- [ ] Catalog list - distinct cards per provider rely on per-org asset `properties.name` (already fixed in seeding), but the rendering still leaks the raw `_provider` object as a tag. Drop that tag, or render `_provider.name` + provider color swatch.

## Dependencies

- Builds on § 4.5.F (Tier-1 UI strip-down), which lands the `sib-auth-apikey` + `glcdi-sidebar` baseline. Once those are in, the fork lives entirely inside `solid-glcdi/`.
- Doesn't block § 4.5.E's Bruno green run - Bruno tests the connector layer, independent of the UI.

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 4.5: Bruno Test Suite + Participant-UI Configuration (Parallel Tracks)](phase-4.5-bruno-and-ui.md) · [next: Phase 5: Testing & Validation →](phase-5-testing.md)
