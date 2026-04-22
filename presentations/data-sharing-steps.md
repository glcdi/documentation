# Technical Steps of Sharing Data on a Data Space

One slide per step. Two parts: the **Provider** publishes data, the **Consumer** discovers and negotiates access.

---

## Part 1: Publishing Data (Provider's perspective)

Persona: **Will Thompson, rancher at Caney Fork Farms**
Will has quarterly Soil Organic Carbon measurements that he wants to share with other GLCDI participants.

---

### Slide 1 — I log in on my Connector

Will opens his participant portal at `https://caney-fork.glcdi.startinblox.com/catalogue/`

He clicks "Log in" and is redirected to his local Keycloak.
He authenticates with his credentials.

Behind the scenes, his local Keycloak brokers to the **governance Keycloak**, which adds
GLCDI-specific claims to his token:
- `glcdi_membership: "active"`
- `glcdi_roles: ["glcdi_member", "glcdi_producer"]`
- `glcdi_certification_status: "regenerative-verified"`
- `glcdi_contribution_status: "contributing"`

Will doesn't see any of this — he just logs in.

---

### Slide 2 — I go to the "dataset publication" section

Will navigates to the **"My Assets"** section of the connector dashboard.

He sees his previously published datasets:
- Grazing Rotation Schedule
- Paddock Boundaries (GeoJSON)
- NDVI Vegetation Index

He clicks **"Publish a new dataset"**.

---

### Slide 3 — I click "publish a new dataset"

The connector presents a **publication form** with two parts:

**Part A — Dataset description** (what the data is):
- Name, description, keywords
- Data format, content type
- Spatial and temporal coverage
- Category

**Part B — Data source** (where the data lives):
- API endpoint or file URL that the connector will serve
- Authentication method for the backend data source

---

### Slide 4 — I submit the asset description form

Will fills in:

| Field | Value |
|-------|-------|
| **Name** | Soil Organic Carbon Measurements — Caney Fork |
| **Description** | Quarterly SOC measurements at 3 depth strata (0–10cm, 10–30cm, 30–50cm) across 42 paddocks |
| **Keywords** | soil organic carbon, SOC, grazing land, carbon sequestration, regenerative |
| **Format** | JSON |
| **Category** | soil-organic-carbon |
| **Spatial coverage** | Caney Fork, Tennessee, USA |
| **Temporal coverage** | 2023–2026 |
| **Data endpoint** | `https://caney-fork-internal.example.com/api/soc-measurements` |

This creates an **Asset** in the connector — a description of the dataset, not the data itself.
The data stays on Will's infrastructure. The connector acts as a gateway.

---

### Slide 5 — I then have to associate pre-defined policies

Before the dataset can appear in other participants' catalogs, Will must attach **policies**
that define the rules of engagement.

The connector presents a **policy selection screen** with pre-defined policy templates
created by the GLCDI governance team.

Will must choose **two types of policies**:

---

### Slide 6 — Two types of policies

**Access Policy — Who can see my offer in the catalog?**

This controls **visibility**. When another participant browses the catalog, the connector
checks their identity against this policy. If they don't match, they don't even know the
dataset exists.

| Template | Who can see it |
|----------|---------------|
| Any GLCDI member | All onboarded participants |
| Researchers only | Only research institutions and data stewards |
| Regenerative producers only | Only certified regenerative producers |
| Contributing members only | Only participants who also share their own data |

**Contract Policy — What can they do with my data?**

This controls **usage terms**. The consumer must accept these conditions before they can
access the data. Think of it as an automated Data Sharing Agreement.

| Template | What it requires |
|----------|-----------------|
| Time-limited (6 months) | Usage expires at the end of the prototype phase |
| Attribution required | Must cite Caney Fork and GLCDI in any publication |
| Non-commercial | No commercial use — research and benchmarking only |
| Internal use only | No redistribution to third parties |
| Anonymisation required | Must remove farm-identifiable details before processing |
| Model training only | Can only use data for agronomic model training |
| Share back insights | Must return derived results to the data provider |

Will can **combine** multiple contract policies (e.g., time-limited + attribution + non-commercial).

---

### Slide 7 — Will selects his policies

For his SOC measurements, Will chooses:

**Access policy:** `Researchers only`
> Only Point Blue, University of Florida, and similar research participants can see this
> dataset. Other ranchers and corporate actors won't even know it exists.

**Contract policies (combined):**
- `Model training only` — can only use for agronomic model calibration
- `Time-limited` — expires September 2026
- `Attribution required` — must cite Caney Fork in publications
- `Anonymisation required` — must remove farm name and precise GPS before processing
- `Share back insights` — must return model outputs and predictions to Will

Will reviews the summary:
> "Researchers can see this dataset. They can use it for model training until September 2026.
> They must anonymise it, cite me, and share their results back with me."

He confirms.

---

### Slide 8 — I publish my dataset

Will clicks **"Publish"**.

Behind the scenes, the connector creates three objects:

1. **Asset** — the dataset description and data source endpoint
2. **Policy Definitions** — the selected access and contract policies
3. **Contract Definition** — the binding that links the asset to its policies

The dataset is now **live**. It will appear in the catalog of any participant who satisfies
the access policy.

Will sees a confirmation:
> "SOC Measurements published. Visible to: researchers and data stewards."

---

## Part 2: Accessing Data (Consumer's perspective)

Persona: **Dr. Elena Martinez, soil scientist at Point Blue Conservation Science**
Elena wants SOC data from multiple ranches to train a predictive model.

---

### Slide 9 — Elena logs in on her Connector

Elena opens Point Blue's portal at `https://point-blue.glcdi.startinblox.com/catalogue/`

She logs in. Her token carries:
- `glcdi_membership: "active"`
- `glcdi_roles: ["glcdi_member", "glcdi_researcher"]`
- `glcdi_contribution_status: "contributing"`

---

### Slide 10 — Elena browses the federated catalog

Elena navigates to **"Discover Data"** and selects **Caney Fork Farms** as a data source.

Her connector sends a **DSP Catalog Query** to Caney Fork's connector, carrying her
identity token.

Caney Fork's connector evaluates the **access policy** for each of Will's published assets:

| Asset | Access Policy | Elena's profile | Visible? |
|-------|--------------|-----------------|----------|
| SOC Measurements | Researchers only | `glcdi_researcher` | **Yes** |
| Grazing Rotation | Contributing members | `contributing` | **Yes** |
| Paddock Boundaries | Members only | `glcdi_member` | **Yes** |
| NDVI Time Series | Members only | `glcdi_member` | **Yes** |

Elena sees **all 4 datasets**. A corporate analyst with `glcdi_corporate` role would
only see the 3 datasets with members-only access — the SOC measurements would be hidden.

---

### Slide 11 — Elena selects a dataset and reviews the terms

Elena clicks on **"SOC Measurements — Caney Fork"**.

The connector displays the **contract terms** attached to this dataset:

> **Usage terms for this dataset:**
>
> - Purpose: Agronomic model training or ecosystem model calibration only
> - Valid until: September 30, 2026
> - You must: anonymise all farm-identifiable information before processing
> - You must: cite "Caney Fork Farms via GLCDI Data Space" in publications
> - You must: share your model outputs and predictions back with the provider
> - You must not: redistribute the raw data
> - You must not: use for commercial purposes

Elena reviews and decides these terms are acceptable for her research.

---

### Slide 12 — Elena negotiates the contract

Elena clicks **"Request Access"** and declares her intended purpose:

> **Purpose:** Agronomic Model Training

Her connector sends a **Contract Negotiation Request** to Caney Fork's connector.

Caney Fork's connector automatically evaluates the **contract policy**:

| Check | Result |
|-------|--------|
| Purpose in [AgronomicModelTraining, EcosystemModelCalibration]? | "AgronomicModelTraining" — **Pass** |
| Current date <= 2026-09-30? | March 2026 — **Pass** |

All constraints are satisfied.

**No human intervention from Will is needed** — the connector accepts the contract
automatically based on the policies Will defined when publishing.

Result: **Contract Agreement — FINALIZED**

---

### Slide 13 — Elena transfers the data

With an active contract, Elena clicks **"Download Dataset"**.

Her connector sends a **Transfer Request** to Caney Fork's connector.

Caney Fork's connector verifies the valid contract agreement exists, then serves the
SOC measurements data via the HTTP data plane.

Elena receives the dataset in her connector's data store.

The transfer is **logged** on both sides — an auditable record of who accessed what,
when, and under which contract terms.

---

### Slide 14 — Elena uses the data (obligations in effect)

Elena now has the SOC data. Her **contractual obligations** are active:

| Obligation | What Elena must do | Enforced by |
|------------|-------------------|-------------|
| **Anonymise** | Replace "Caney Fork" with "Tennessee Region", generalise GPS to county level | Data Sharing Agreement |
| **Attribute** | Add "Caney Fork Farms via GLCDI Data Space" to her paper's data section | Data Sharing Agreement |
| **Share back** | Send her model predictions back to Will via the dataspace | Data Sharing Agreement |
| **Time limit** | Stop using the data after September 2026 | Connector (blocks new transfers) + DSA |
| **No redistribution** | Do not share raw data with colleagues outside Point Blue | Data Sharing Agreement |

Some obligations are **technically enforced** (time limit — the connector won't allow new
transfers after expiry). Others are **governance-enforced** (anonymisation, attribution —
tracked by the Steering Committee).

---

### Slide 15 — Elena shares back her results (reciprocity)

Six months later, Elena has trained her SOC prediction model.

She **publishes her model outputs** as a new dataset on Point Blue's connector, with
Caney Fork as a target audience.

Will receives a notification and can see Elena's predictions for his paddocks:
> "Based on your current rotation schedule, SOC at 0–10cm depth is projected to increase
> by 0.3% annually over the next 5 years."

**The reciprocity loop is complete:**
- Will shared raw SOC data
- Elena trained a model
- Elena shared predictions back with Will
- Will gets actionable insights for his farm

This is the core value proposition of the GLCDI data space: **data providers get value back**.

---

### Slide 16 — What happens when the contract expires?

**September 30, 2026** — the prototype phase ends.

- Elena tries to request new SOC data from Caney Fork
- The connector **automatically rejects** the negotiation: the time constraint has expired
- Elena's existing data is still on her system (the connector doesn't delete it retroactively)
- Her **retention obligations** from the DSA still apply

**To continue sharing**, Will must:
1. Review the partnership
2. Publish a new policy with an updated expiry date
3. Elena negotiates a new contract

This creates a **natural consent renewal point** — Will decides each phase whether to
continue sharing, with whom, and under what terms.

---

## Summary: The 8 key steps

| # | Step | Who | Technical action |
|---|------|-----|-----------------|
| 1 | Log in | Provider | OIDC authentication via Keycloak federation |
| 2 | Describe dataset | Provider | Create Asset (metadata + data source endpoint) |
| 3 | Select policies | Provider | Choose access policy + contract policy templates |
| 4 | Publish | Provider | Create Contract Definition (asset + policies) |
| 5 | Discover | Consumer | DSP Catalog Query (filtered by access policy) |
| 6 | Negotiate | Consumer | DSP Contract Negotiation (validated by contract policy) |
| 7 | Transfer | Consumer | DSP Transfer Request (data delivered via HTTP data plane) |
| 8 | Fulfill obligations | Consumer | Anonymise, attribute, share back, respect time limits |

**Key principle:** The provider defines the rules once. The connector enforces them
automatically for every consumer. No manual approval needed per request — trust is encoded
in the policies.
