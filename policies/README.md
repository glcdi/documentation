# GLCDI Policy Examples

ODRL-based policy definitions for the GLCDI (Grazing Lands Carbon Data Initiative) dataspace,
designed for Eclipse EDC 0.15.x connectors.

## How EDC Policies Work

In an EDC dataspace, two kinds of policies govern data sharing:

- **Access policies** control **who can see an offer in the catalog**. When a consumer queries a
  provider's catalog via DSP, the provider's connector evaluates the access policy. If the
  consumer does not satisfy the constraints, the offer is hidden from the catalog response.

- **Contract policies** control **what the consumer is allowed to do with the data** once a contract
  is negotiated. These encode usage conditions (time limits, purpose, redistribution rules, etc.)
  that the consumer must accept before a transfer can take place.

Both are linked to assets through **Contract Definitions**, which bind an asset selector to an
access policy and a contract policy:

```json
{
  "@type": "ContractDefinition",
  "accessPolicyId": "glcdi:access:members-only",
  "contractPolicyId": "glcdi:contract:time-limited-6m",
  "assetsSelector": [{ "operandLeft": "id", "operator": "=", "operandRight": "my-asset-id" }]
}
```

## Constraint Mechanism

EDC evaluates ODRL constraints by checking claims from the consumer's identity. In GLCDI,
participant attributes come from **Keycloak tokens** (via OIDC) or **Verifiable Credentials**.
The `leftOperand` in each constraint refers to a claim or credential attribute that the
provider's connector must be configured to resolve.

For example, `glcdi:participantType` would map to a Keycloak realm role or a VC claim
that identifies whether the participant is a `producer`, `researcher`, `data-steward`, etc.

### Custom Namespace

These examples use the prefix `glcdi:` mapped to `https://w3id.org/glcdi/v0.1.0/ns/`.
This namespace is specific to GLCDI and would be defined in the dataspace's vocabulary registry.

## Directory Structure

```
policies/
├── access/                     # Access policies (catalog visibility)
│   ├── members-only.json       # Any GLCDI participant
│   ├── organic-producers.json  # Organic/regenerative producers only
│   └── researchers-only.json   # Research institutions only
├── contract/                   # Contract policies (usage terms)
│   ├── time-limited.json       # Time-bounded usage (6 months)
│   ├── internal-use-only.json  # No redistribution
│   ├── anonymisation.json      # Must anonymise before processing
│   ├── payment-required.json   # Compensation required
│   ├── attribution.json        # Citation/attribution required
│   ├── non-commercial.json     # Non-commercial use only
│   ├── purpose-model-training.json  # Model training purpose only
│   └── data-retention-limit.json    # Delete after agreed period
├── combined/                   # Realistic combined policy examples
│   ├── researcher-model-feeding.json       # Agronomic model use case
│   ├── rancher-benchmarking.json           # Regional benchmarking use case
│   └── corporate-supply-chain.json         # Supply chain / ESG reporting
├── diagrams/                   # PlantUML sequence diagrams
│   ├── 01-researcher-accesses-soc-data.puml      # Full model calibration flow
│   ├── 02-producer-blocked-from-research-data.puml  # Access policy filtering
│   ├── 03-rancher-benchmarking.puml               # Peer-to-peer benchmarking
│   ├── 04-wrong-purpose-rejected.puml             # Contract rejection on wrong purpose
│   ├── 05-organic-producers-exclusive.puml        # Certification-based inner circle
│   ├── 06-time-limited-expiry.puml                # Temporal constraint & renewal
│   └── 07-corporate-supply-chain-flow.puml        # Corporate ESG with payment & retention
└── README.md
```

## Sequence Diagrams

The `diagrams/` directory contains PlantUML sequence diagrams illustrating how policies
affect end-users in concrete scenarios. Each diagram shows the full interaction flow —
authentication, catalog discovery, policy evaluation, contract negotiation, and data transfer
— from the perspective of a real GLCDI participant persona.

### Diagram Index

| # | Diagram | Policies illustrated | End-user story |
|---|---------|---------------------|----------------|
| 01 | [Researcher accesses SOC data](diagrams/01-researcher-accesses-soc-data.puml) | `researchers-only` + `model-calibration-terms` | Dr. Martinez (Point Blue) authenticates, discovers Caney Fork's SOC data in the catalog, negotiates a contract for model training, and receives the data with obligations to anonymise, attribute, and not redistribute. Shows the complete happy path for the **agronomic model calibration** use case. |
| 02 | [Producer blocked from research data](diagrams/02-producer-blocked-from-research-data.puml) | `researchers-only` vs `members-only` | Will Thompson (Caney Fork rancher) browses Point Blue's catalog but cannot see GHG Flux data restricted to researchers. He can still see and access the 3 assets with members-only access. Demonstrates how **access policies filter the catalog** without the user knowing hidden offers exist. |
| 03 | [Rancher-to-rancher benchmarking](diagrams/03-rancher-benchmarking.puml) | `members-only` + `benchmarking-terms` | Sarah Chen (White Buffalo) and Will Thompson (Caney Fork) share grazing data for peer comparison. Shows the full **regional benchmarking** use case including reciprocal sharing, what the rancher can learn, and what they cannot do with the data. |
| 04 | [Wrong purpose rejected](diagrams/04-wrong-purpose-rejected.puml) | `members-only` + `benchmarking-terms` | A corporate ESG analyst can *see* an offer (passes members-only access) but cannot *negotiate a contract* because their declared purpose (Scope3Reporting) doesn't match the permitted purposes (benchmarking only). Shows how **contract policies enforce purpose constraints** even when access is open. |
| 05 | [Organic producers exclusive](diagrams/05-organic-producers-exclusive.puml) | `organic-producers` | Three participants query the same asset: a regenerative producer (sees it), a researcher (blocked), and a corporate analyst (blocked). Shows how **multi-constraint access policies** create tiered visibility based on participant type and certification status. |
| 06 | [Time-limited expiry](diagrams/06-time-limited-expiry.puml) | `time-limited` | A researcher negotiates successfully during the prototype phase, then gets rejected after the expiry date. Shows the **natural consent renewal cycle**: the provider decides whether to publish a new policy for the next phase. |
| 07 | [Corporate supply chain](diagrams/07-corporate-supply-chain-flow.puml) | `corporate-partners` + `supply-chain-terms` | Lisa Park (FoodCorp ESG analyst) discovers SOC data, pays $1,000, negotiates a Scope 3 reporting contract, receives data with anonymisation and retention obligations, and must delete after 12 months. Shows the **post-prototype corporate scenario** with payment, anonymisation, attribution, and retention enforcement. |

To render the diagrams, use any PlantUML-compatible tool:

```bash
# Command line (requires plantuml.jar or Docker)
docker run --rm -v "$PWD/diagrams":/data plantuml/plantuml /data/*.puml

# Or use VS Code extension: "PlantUML" by jebbs
# Or online: paste into https://www.plantuml.com/plantuml/uml
```

## Access Policies

### `access/members-only.json` — Any GLCDI Participant

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:access:members-only` |
| **What it does** | Checks that the consumer holds an `active` GLCDI membership claim. Any onboarded participant — rancher, researcher, NGO, data steward — can see the offer in the catalog. |
| **ODRL mechanism** | Single constraint: `glcdi:membership eq "active"`. |
| **GLCDI relevance** | This is the **default baseline** for the dataspace. The blueprint emphasises that GLCDI is a trust-based alliance: once a participant has gone through the onboarding process (Keycloak account, signed MOU/Data Sharing Agreement), they should be able to discover what data is available. Especially important for the **Peer-to-Peer Data Sharing** and **Regional Benchmarking** use cases, where all participants need catalog visibility as a starting point. |
| **Implementation** | Requires a custom EDC policy function that resolves `glcdi:membership` from the consumer's Keycloak token or Verifiable Credential. The governance Keycloak realm at `governance.glcdi.startinblox.com` would be the source of truth. |

### `access/organic-producers.json` — Organic/Regenerative Producers Only

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:access:organic-producers` |
| **What it does** | Restricts catalog visibility to participants who are (a) active members, (b) of type `producer`, and (c) hold a certification status of `organic-certified`, `regenerative-verified`, or `transitioning-organic`. |
| **ODRL mechanism** | Three constraints combined (AND logic): membership check, participant type check, and certification status using `isAnyOf` for multiple accepted values. |
| **GLCDI relevance** | Some producers may only want to share data with **peers who are on a similar regenerative journey**. Caney Fork Farms, for example, wants to "promote regenerative grazing" and "sell at a premium by participating in regenerative markets". Sharing sensitive grazing rotation data or SOC measurements only with fellow organic/regenerative producers creates a trusted inner circle — addressing the stakeholder fear of "harmful use of data by buyers or competitors". This is also relevant as the dataspace grows to include participants like PASA (a members association of sustainable agriculture practitioners). |
| **Implementation** | Requires `glcdi:certificationStatus` to be a verifiable claim. Could be populated during onboarding (self-declared + steering committee validation) or eventually tied to third-party certification (USDA Organic, ROC, etc.). |

### `access/researchers-only.json` — Research Institutions Only

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:access:researchers-only` |
| **What it does** | Limits catalog visibility to participants flagged as `researcher` or `data-steward`. This hides sensitive producer data from other producers or corporate actors. |
| **ODRL mechanism** | Two constraints: active membership + participant type `isAnyOf ["researcher", "data-steward"]`. |
| **GLCDI relevance** | Central to the **Agronomic Model Calibration** use case. Point Blue Conservation Science and University of Florida need access to detailed SOC time-series and grazing records to train predictive models. Producers like Caney Fork may be comfortable sharing raw, non-anonymised data with trusted research partners (who are bound by institutional ethics protocols) but not with the broader membership. Data stewards (like TSIP) are included because they play a bridging role — maintaining datasets and facilitating research access with producer consent. |
| **Implementation** | The `glcdi:participantType` claim would be set during onboarding based on the participant's category (as documented in the blueprint's Stakeholders section). |

## Contract Policies

### `contract/time-limited.json` — Time-Bounded Usage

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:time-limited-6m` |
| **What it does** | Permits usage only until a specific date (default: `2026-09-30`, end of the GLCDI prototype phase). After that date, the contract is no longer valid and no new data transfers should occur. |
| **ODRL mechanism** | `odrl:dateTime lteq "2026-09-30T23:59:59Z"` — EDC evaluates this at contract negotiation and transfer time. |
| **GLCDI relevance** | The prototype phase runs January–September 2026 (Walmart Foundation funded). Producers need assurance that data shared for the prototype won't be accessible indefinitely. This directly addresses the stakeholder concern about "Data Space participation time" listed by Caney Fork Farms. Also critical for the iterative cohort model: Cohort 1 (Q1) agreements may expire before Cohort 2 (Q2) begins, giving producers a natural consent renewal point. |
| **Implementation** | **Works out of the box** with vanilla EDC — temporal constraints are natively supported. |

### `contract/internal-use-only.json` — No Redistribution

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:internal-use-only` |
| **What it does** | Allows the consumer to use data for internal analysis only. Redistribution to third parties is explicitly prohibited. Derived works may only be shared back with the original provider. |
| **ODRL mechanism** | Permission with `odrl:purpose eq "glcdi:InternalAnalysis"`, plus prohibitions on `distribute` and conditional prohibition on `derive` (blocked if recipient is not the original provider). |
| **GLCDI relevance** | This is a core trust-building policy. Ranchers' primary fear is that their data could be used against their interests — by competitors for pricing intelligence, by buyers for negotiation leverage, or by advocacy groups out of context. "Internal use only" gives producers a safe default: share with a researcher for their own analysis, but that researcher cannot pass the raw data to a third party. This policy supports the blueprint's emphasis on "functional data sovereignty" and "consent-governed" data exchange. Particularly relevant for the **Peer-to-Peer Data Sharing** use case. |
| **Implementation** | The `purpose` constraint is supported by EDC if the consumer includes it in their contract offer. The `distribute` prohibition is contractual/legal — EDC enforces it at negotiation time (the consumer agrees to it) but cannot technically prevent the consumer from copying data after transfer. |

### `contract/anonymisation.json` — Anonymisation Required

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:anonymisation-required` |
| **What it does** | Permits usage and derivation, but imposes a duty to anonymise all farm-identifiable information (ranch names, precise GPS coordinates, field IDs) before any processing or publication. Also requires notifying the provider before publishing any derived dataset. Raw data redistribution is prohibited. |
| **ODRL mechanism** | Permissions for `use` and `derive`, obligations for `anonymize` and `inform` (with recipient = original provider), prohibition on distributing raw data. |
| **GLCDI relevance** | Essential for scenarios where data needs to flow beyond the immediate consumer. For example, a researcher training an ecosystem model may need to publish model validation results — but the underlying ranch-level data must not be identifiable. The blueprint notes that Point Blue faces "governance uncertainty and permissioned access for derived data" as a barrier. This policy provides a clear answer: derive freely, but anonymise first and notify the provider. Also critical for future **corporate supply chain** use, where ESG reports must reference aggregated data without exposing individual farm details. Addresses the "unlawful/unfair use of data" fear from Caney Fork. |
| **Implementation** | Anonymisation is a **governance-level obligation** — EDC cannot technically verify that data has been anonymised. Enforcement relies on the Data Sharing Agreement, institutional ethics review, and audit mechanisms. The `inform` duty could be partially automated via webhook notifications. |

### `contract/payment-required.json` — Compensation Required

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:payment-required` |
| **What it does** | Attaches a payment duty to the usage permission. The consumer must pay a minimum amount (default: $500 USD) per dataset access agreement. |
| **ODRL mechanism** | Permission with `duty` containing `compensate` action and `odrl:payAmount gteq 500.00` constraint with USD unit. |
| **GLCDI relevance** | The blueprint mentions that future phases will require "diversified resourcing tied to the value delivered for academic, producer, and corporate participants" and may involve "a data space membership model". Payment policies enable a transition from grant-funded to sustainable operations. For producers like Caney Fork, whose expected value includes "increase productivity and profitability", being compensated for sharing valuable SOC and grazing data is a tangible incentive. This is especially relevant for corporate/supply-chain consumers who derive significant value from the data (Scope 3 reporting, certification claims). Not expected in the prototype phase, but important to model now. |
| **Implementation** | Requires a **custom policy function** and an external payment/invoicing system. EDC has no built-in payment verification. The policy function would check a payment ledger or API before approving the contract negotiation. |

### `contract/attribution.json` — Citation / Attribution Required

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:attribution-required` |
| **What it does** | Requires the consumer to cite the data provider and GLCDI in any publication, report, model output, or derived dataset. Suggested format: `"[Provider Name] via GLCDI Data Space"`. |
| **ODRL mechanism** | Permissions for `use` and `derive`, each carrying an `attribute` duty. |
| **GLCDI relevance** | Attribution serves multiple purposes in GLCDI. For **producers**, it recognises their contribution — Caney Fork wants to "participate in labeling, verification, and certification programs", and proper attribution builds their reputation in regenerative markets. For **researchers** like Point Blue, citation is a professional norm and builds their publication record. For **GLCDI itself**, consistent attribution demonstrates the dataspace's impact to funders (Walmart Foundation, USDA, NSF) and builds the case for continued investment. The blueprint emphasises "recognition of [data stewards'] role in stewarding relationships and signals" — attribution is the simplest mechanism for that recognition. |
| **Implementation** | Governance-level obligation. Could be partially tracked by requiring consumers to register publications/reports back into the dataspace catalog. |

### `contract/non-commercial.json` — Non-Commercial Use Only

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:non-commercial` |
| **What it does** | Restricts usage to non-commercial purposes: scientific research, education, conservation planning, and regional benchmarking. Commercial exploitation (resale, paid products, carbon credit generation) is prohibited. |
| **ODRL mechanism** | Permission constrained by `odrl:purpose isAnyOf [ScientificResearch, EducationalUse, ConservationPlanning, RegionalBenchmarking]`, plus a `commercialize` prohibition. |
| **GLCDI relevance** | Directly addresses the most frequently cited stakeholder fear: **"harmful use of data by buyers or competitors"** (Caney Fork) and the broader concern about data being exploited for commercial gain without fair compensation. During the prototype phase, where the goal is to build trust and validate governance, a non-commercial default protects producers while they evaluate the value exchange. This is analogous to Creative Commons NC licenses — familiar to the research community (Point Blue, University of Florida, TSIP). Also relevant for data steward organisations who need "tools that uphold producer consent and revocation rather than symbolic sovereignty". |
| **Implementation** | The `purpose` constraint is evaluable at negotiation time. The `commercialize` prohibition is contractual. |

### `contract/purpose-model-training.json` — Model Training Purpose Only

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:purpose-model-training` |
| **What it does** | Restricts data usage to agronomic model training and ecosystem model calibration. Derived model outputs are allowed (with attribution), but raw training data may not be redistributed. |
| **ODRL mechanism** | Two permissions: `use` constrained to `AgronomicModelTraining` or `EcosystemModelCalibration` purpose, and `derive` constrained to `ModelOutput` purpose (with attribution duty). Prohibition on distributing raw data. |
| **GLCDI relevance** | This is the **core contract policy for the Agronomic Model Calibration use case** — one of the three prototype use cases in the blueprint. Point Blue and other research partners need SOC time-series and grazing rotation data to "feed predictive models and scientific analysis". The producer's concern is that raw data (which may reveal competitive farm practices) stays locked within the model training pipeline. Only the model outputs — predictions, aggregated insights, calibration parameters — may be shared further. This balances the researcher's need for rich input data with the producer's need for control over raw records. |
| **Implementation** | Purpose constraints work with EDC if the consumer declares purpose in the contract offer. Raw data redistribution prohibition is contractual. |

### `contract/data-retention-limit.json` — Delete After Agreed Period

| Aspect | Detail |
|--------|--------|
| **ID** | `glcdi:contract:data-retention-12m` |
| **What it does** | Permits usage for a maximum of 12 months from the date of transfer (ISO 8601 duration: `P12M`). After that period, the consumer must delete all copies and non-anonymised derivatives, and confirm deletion to the provider. |
| **ODRL mechanism** | Permission constrained by `odrl:elapsedTime lteq P12M`. Obligations for `delete` (triggered after 12 months) and `inform` (notify provider of deletion). |
| **GLCDI relevance** | Data retention limits are critical for **data sovereignty** — a core principle of the dataspace architecture. The blueprint describes the cohort model (Q1 foundational, Q2 cross-context, Q3 stress-testing), each with different participants and trust levels. Retention limits ensure that data shared during one cohort phase doesn't persist indefinitely in a consumer's systems. This is especially important for producers who may want to revoke or renegotiate access as the Trust Framework evolves from v0 to v1. Also relevant for **corporate consumers** in post-prototype phases, where data access should be tied to active partnership agreements, not permanent grants. |
| **Implementation** | The `elapsedTime` constraint may need a custom policy function (vanilla EDC supports `dateTime` but `elapsedTime` from transfer date requires tracking the transfer timestamp). The `delete` and `inform` obligations are governance-level. |

## Combined Scenario Policies

### `combined/researcher-model-feeding.json` — Agronomic Model Calibration

| Aspect | Detail |
|--------|--------|
| **ID** | Access: `glcdi:access:model-calibration-researchers` / Contract: `glcdi:contract:model-calibration-terms` |
| **Scenario** | A research institution (e.g., Point Blue Conservation Science) wants to access SOC and grazing management data from multiple ranches to train a predictive model that estimates how SOC changes in response to grazing practices. |
| **Access policy** | Only researchers and data stewards with active GLCDI membership can see the offer. |
| **Contract policy** | Usage restricted to model training/calibration purposes. Time-limited to the prototype phase (2026-09-30). Anonymisation of farm-identifiable data is mandatory before model training. Attribution required in all publications. Raw data redistribution and commercial use are prohibited. |
| **Includes contract definition** | Example binding to the `caney-fork-soc-measurements` asset. |
| **GLCDI relevance** | This is a **complete, ready-to-adapt implementation** of the blueprint's "Agronomic model calibration" use case. It combines five policy building blocks (researcher access + purpose limit + time limit + anonymisation + attribution + non-commercial) into a single coherent scenario. It reflects the real dynamic between Caney Fork (data provider concerned about misuse) and Point Blue (researcher needing rich data for ecosystem modelling). The blueprint states the ambition is to "accurately predict how soil organic carbon levels may change (or not) based on grazing management practices" — this policy package enables exactly that data flow while protecting the producer. |

### `combined/rancher-benchmarking.json` — Regional Benchmarking

| Aspect | Detail |
|--------|--------|
| **ID** | Access: `glcdi:access:peer-benchmarking` / Contract: `glcdi:contract:benchmarking-terms` |
| **Scenario** | A rancher (e.g., White Buffalo Land Trust) wants to compare their SOC levels and grazing strategies against regional peers. Another rancher (e.g., Caney Fork Farms) shares data so participating producers can benchmark against each other. |
| **Access policy** | Any active GLCDI member can see the offer (members-only). Benchmarking is meant to be inclusive across all participant types. |
| **Contract policy** | Usage restricted to regional benchmarking and internal analysis purposes. Time-limited to the prototype phase. Attribution to GLCDI required. Redistribution to non-participants and commercial use are both prohibited. |
| **Includes contract definition** | Example binding to the `caney-fork-grazing-rotation` asset. |
| **GLCDI relevance** | This is the **complete policy package for the "Regional benchmarking" use case** — the first of the three prototype use cases listed in the blueprint. The blueprint describes it as "early feasibility demonstrations showing how harmonized SOC and grazing datasets can enable peer comparison, help to identify successful grazing strategies and collect feedback for future versions of the tool". Caney Fork's expected value includes "access regional benchmarks and model-informed decision support". The non-commercial prohibition is essential here: benchmarking data should help producers improve their practices, not be exploited for market intelligence by competitors or buyers. |

### `combined/corporate-supply-chain.json` — Corporate Supply Chain / ESG Reporting

| Aspect | Detail |
|--------|--------|
| **ID** | Access: `glcdi:access:corporate-partners` / Contract: `glcdi:contract:supply-chain-terms` |
| **Scenario** | A food company or certification body needs aggregated SOC data to support Scope 3 emissions calculations, ESG reporting, or regenerative sourcing claims. A ranch provides data under strict conditions. |
| **Access policy** | Only participants flagged as `corporate`, `certification-body`, or `supply-chain-partner` with active membership can see the offer. |
| **Contract policy** | Usage restricted to Scope 3 reporting, ESG compliance, or certification verification purposes. Payment required ($1,000 USD minimum per dataset). Attribution to GLCDI and participating producers required. Anonymisation to regional level mandatory. 12-month retention limit with deletion obligation and renewal requirement. Redistribution prohibited (including to subsidiaries). |
| **Includes contract definition** | Example using asset category selectors (all SOC data assets) rather than individual asset IDs. |
| **GLCDI relevance** | This **anticipates the post-prototype corporate participation** described in the blueprint. The blueprint's "Key Audience" section identifies "Corporate & Supply-Chain Stakeholders" (food companies, procurement programs, certification bodies, ESG reporting teams, Scope 3 analysts) who value "consent-governed auditability infrastructure". The blueprint also notes a comment about "Scope 3 emissions calculations" and mentions that future resourcing will be "tied to the value delivered for academic, producer, and corporate participants". This policy package models the most demanding scenario: corporate consumers who derive significant commercial value from the data, requiring the strongest protections (payment, anonymisation, retention limits, no redistribution) to maintain producer trust. It demonstrates to funders that GLCDI has a credible path to sustainability beyond grant funding. |

## Applying Policies via EDC Management API

```bash
# 1. Create a policy definition
curl -X POST http://localhost:29193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d @access/members-only.json

# 2. Create a contract definition binding it to an asset
curl -X POST http://localhost:29193/management/v3/contractdefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "cd-soc-measurements",
    "@type": "ContractDefinition",
    "accessPolicyId": "glcdi:access:members-only",
    "contractPolicyId": "glcdi:contract:time-limited-6m",
    "assetsSelector": [{
      "@type": "Criterion",
      "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
      "operator": "=",
      "operandRight": "caney-fork-soc-measurements"
    }]
  }'
```

## Implementation Notes

### What Requires Custom EDC Extensions

Not all constraints in these examples work out of the box with vanilla EDC. Specifically:

- **Membership / role-based constraints** (`glcdi:participantType`, `glcdi:membership`):
  Require a custom policy function that resolves participant claims from Keycloak tokens
  or Verifiable Credentials. See `edc-connector/extensions/` for where to add this.

- **Payment constraints** (`odrl:compensation`): ODRL defines the vocabulary, but EDC has
  no built-in payment verification. This would need an external settlement system and a
  custom policy function to verify payment status.

- **Anonymisation obligations** (`odrl:anonymize`): These are **duty-based** — they express
  what the consumer must do, but enforcement is governance-level (contractual/legal),
  not technically enforced by the connector at transfer time.

### What Works With Vanilla EDC

- **Temporal constraints** (`odrl:dateTime`): Supported natively by EDC.
- **Basic permission/prohibition structure**: Fully supported.
- **`odrl:purpose` constraints**: Supported if the consumer includes purpose in their offer.

### Relation to GLCDI Use Cases

| Blueprint Use Case              | Access Policy               | Contract Policy                     |
|---------------------------------|-----------------------------|-------------------------------------|
| Regional benchmarking           | members-only                | attribution + non-commercial        |
| Agronomic model calibration     | researchers-only            | time-limited + purpose-model        |
| Peer-to-peer data sharing       | members-only                | internal-use-only or time-limited   |
| Supply chain / ESG reporting    | (future) corporate partners | anonymisation + attribution         |
