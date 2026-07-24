# Phase 4: Update Seeding Scripts & Contract Definitions

Replace the current `glcdi:policy:open-research` (simple "use" permission with no constraints)
with the richer policies from `./policies/`.

## 4.1 Update producer-participant seeding scripts

| Item | Detail |
|------|--------|
| **Task** | Replace the single open-research policy with appropriate policies per asset on each producer participant's seeding script |
| **Typical producer asset classes and proposed policies:** | |
| **SOC measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `time-limited` + `attribution` (for model calibration use case) |
| **Grazing rotation** | Access: `members-only` / Contract: `non-commercial` + `attribution` (for benchmarking use case) |
| **Paddock boundaries** | Access: `members-only` / Contract: `internal-use-only` + `time-limited` (sensitive spatial data) |
| **NDVI time series** | Access: `members-only` / Contract: `attribution` (lower sensitivity, broader sharing) |
| **Status** | [x] M1 fixture subset implemented via Bruno (`management/build/bruno/10-provider-seeding/`): 3 assets per producer org (`grazing-soc-2024` regen-producers-only, `grazing-summary-2024` all-members, `grazing-raw-observations-2024` researchers-only). All 3 access tiers exercised in the test suite. · [ ] Full asset-class taxonomy from this table (paddock boundaries, NDVI, etc.) - out of M1 scope, expand when real producer data lands |

## 4.2 Update research-participant seeding scripts

| Item | Detail |
|------|--------|
| **Task** | Replace open-research policy with policies appropriate for a research institution's data |
| **Typical research asset classes and proposed policies:** | |
| **Rangeland SOC inventory** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **GHG flux measurements** | Access: `researchers-only` / Contract: `purpose-model-training` + `attribution` |
| **Biodiversity surveys** | Access: `members-only` / Contract: `attribution` + `non-commercial` |
| **Weather station data** | Access: `members-only` / Contract: `attribution` (low sensitivity) |
| **Carbon credit reports** | Access: `members-only` / Contract: `internal-use-only` + `anonymisation` (commercially sensitive) |
| **Status** | [x] M1 fixture subset implemented via Bruno - point-blue (the M1 researcher participant) seeds the same 3-asset shape as producers, with the `researchers-only` and `all-members` tiers serving the negative-test cases for the policy matrix. · [ ] Full research-asset-class taxonomy from this table - post-M1 when real research data lands |

## 4.3 Create seeding helper for policy registration

| Item | Detail |
|------|--------|
| **Task** | Add a section to seeding scripts that registers all needed policy definitions before creating contract definitions, reading from the JSON files in `management/policies/` |
| **Approach** | Loop over the required policy JSON files and POST them to `/management/v3/policydefinitions`. Then create contract definitions that reference the registered policy IDs. |
| **Status** | [x] Implemented as the Bruno `10-provider-seeding/` collection - `glcdi.sh seed` loops over all 3 orgs and runs all 10 requests (assets + 3 policies + 3 contract-defs) per org. Idempotent (re-running accepts 409 conflicts). Re-seed integrated into `glcdi.sh all`. |

---

---

**Navigation:** [← index](../implementation-plan.md) · [← prev: Phase 3: EDC Policy Extension Development](phase-3-edc-policy-extension.md) · [next: Phase 4.5: Bruno Test Suite + Participant-UI Configuration (Parallel Tracks) →](phase-4.5-bruno-and-ui.md)
