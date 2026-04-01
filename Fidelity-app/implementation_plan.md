# Fidely App — Implementation Plan (POC)

## Context & Decisions

- **Database:** `PINNACLE_FINANCIAL_DEMO_33` (shared; no new databases).
- **Existing schemas (`FINANCE_ANALYTICS`, `AGENTS`):** Not touched. Unrelated to this project.
- **Domain:** Food business directory + loyalty ecosystem (Fidely App / Gula Maps) focused on Merida, Yucatan.
- **Synthetic data:** Generated directly in Snowflake SQL — no Python extraction scripts for now.
- **Future phases:** Google Maps API enrichment, Firebase integration, and Streamlit app will be built after the Snowflake data model is validated.

---

## Phase 1 — Snowflake Schema & Object Creation

### Step 1.1: Create Schemas

Create three schemas inside `PINNACLE_FINANCIAL_DEMO_33`:

| Schema | Purpose |
|---|---|
| `RAW_ZONE` | Landing area for raw JSON payloads (VARIANT columns). Simulates Firebase exports and Google Maps API responses. |
| `STAGING_ZONE` | Views that flatten and type-cast the raw JSON into relational columns. |
| `ANALYTICS_ZONE` | Star schema tables optimized for Streamlit consumption. |

### Step 1.2: Create RAW_ZONE Tables

These tables use `VARIANT` columns to store semi-structured JSON, simulating what would arrive from Firebase and external APIs.

| Table | Description |
|---|---|
| `RAW_USERS` | Raw user profile JSON payloads (simulating Firebase Auth + Firestore user docs). |
| `RAW_BUSINESSES` | Raw business listing JSON payloads (simulating Firestore business docs + Google Maps enrichment). |
| `RAW_VISITS` | Raw visit/transaction event JSON payloads (simulating Firestore event logs). |

Each table will have:
- `RAW_DATA VARIANT` — the JSON payload.
- `FILENAME VARCHAR` — source file name (for lineage).
- `LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()` — ingestion timestamp.

### Step 1.3: Create Internal Stage

Create an internal stage `@RAW_ZONE.FIDELY_STAGE` with `FILE_FORMAT = (TYPE = JSON)` to support future PUT/COPY INTO workflows.

### Step 1.4: Create STAGING_ZONE Views

Flattening views over RAW_ZONE tables:

| View | Source | Key Columns Extracted |
|---|---|---|
| `STG_USERS` | `RAW_ZONE.RAW_USERS` | `user_id`, `first_name`, `last_name`, `email`, `phone`, `registration_date`, `status`, `preferred_zone` |
| `STG_BUSINESSES` | `RAW_ZONE.RAW_BUSINESSES` | `business_id`, `business_name`, `category`, `subcategory`, `loyalty_type`, `cashback_pct`, `punch_goal`, `lat`, `long`, `google_rating`, `google_place_id`, `address`, `neighborhood` |
| `STG_VISITS` | `RAW_ZONE.RAW_VISITS` | `visit_id`, `user_id`, `business_id`, `visit_timestamp`, `visit_type` (check-in, redemption, referral), `points_earned`, `cashback_amount`, `punch_count` |

### Step 1.5: Create ANALYTICS_ZONE Star Schema

#### Dimensions

| Table | Description | Key Fields |
|---|---|---|
| `DIM_USERS` | Consumer profiles. | `user_key` (surrogate), `user_id`, `first_name`, `last_name`, `email`, `registration_date`, `status`, `preferred_zone` |
| `DIM_BUSINESSES` | Merchant profiles with Google Maps enrichment. | `business_key` (surrogate), `business_id`, `business_name`, `category`, `subcategory`, `loyalty_type`, `cashback_pct`, `punch_goal`, `lat`, `long`, `google_rating`, `address`, `neighborhood` |
| `DIM_TIME` | Standard date dimension for time-series analysis. | `date_key`, `calendar_date`, `year`, `month`, `month_name`, `day_of_week`, `day_name`, `quarter`, `is_weekend`, `is_holiday` |
| `DIM_LOYALTY_TYPE` | Loyalty program type reference. | `loyalty_type_key`, `loyalty_type_name`, `description`, `reward_mechanism` |

#### Facts

| Table | Description | Key Fields |
|---|---|---|
| `FACT_VISITS` | Every user-business interaction (check-in, redemption, referral). | `visit_key` (surrogate), `date_key` FK, `user_key` FK, `business_key` FK, `loyalty_type_key` FK, `visit_id`, `visit_type`, `visit_timestamp`, `points_earned`, `cashback_amount`, `punch_count` |

---

## Phase 2 — Synthetic Data Generation (Snowflake SQL)

All data generated directly in Snowflake using `GENERATOR()`, `UNIFORM()`, `RANDOM()`, `DATEADD()`, and array-based lookups.

### Step 2.1: Generate RAW_ZONE JSON Data

Insert synthetic JSON into the three RAW_ZONE tables:

- **RAW_USERS:** ~5,000 user profiles.
  - Realistic Mexican first/last names.
  - Registration dates spread over 12 months (Jul 2025 — Jun 2026).
  - Status distribution: ~85% active, ~10% inactive, ~5% suspended.
  - `preferred_zone`: neighborhoods in Merida (Centro, Montejo, Garcia Gineres, Altabrisa, etc.).

- **RAW_BUSINESSES:** ~150 food businesses.
  - Categories: Restaurant, Cafe, Taqueria, Bakery, Bar, Food Truck, Ice Cream Shop.
  - Subcategories per category (e.g., Restaurant -> Mexican, Italian, Seafood, etc.).
  - Loyalty types distributed: ~40% Cashback, ~35% Punch Card, ~15% VIP Pass, ~10% None.
  - Coordinates clustered around Merida (lat ~20.93–21.02, long ~-89.55 to -89.68).
  - Google ratings: 3.0–5.0 (weighted toward 4.0–4.5).
  - Neighborhoods matching the Merida geography.

- **RAW_VISITS:** ~50,000 transaction events.
  - Dates spanning the same 12-month window as DIM_TIME.
  - Visit types: ~70% check-in, ~20% redemption, ~8% referral, ~2% VIP activation.
  - Realistic patterns: higher volume on Fri/Sat evenings, lunch peaks, seasonal spikes (December holidays, Carnival in Feb).
  - `cashback_amount` only populated when loyalty_type = Cashback; `punch_count` only for Punch Card businesses.
  - Points earned proportional to visit type and loyalty program.

### Step 2.2: Populate STAGING_ZONE

No action needed — views read from RAW_ZONE automatically.

### Step 2.3: Populate ANALYTICS_ZONE

- **DIM_TIME:** Generate 365 days (Jul 2025 — Jun 2026) with full calendar attributes.
- **DIM_LOYALTY_TYPE:** Insert 4 static rows (Cashback, Punch Card, VIP Pass, None).
- **DIM_USERS:** `INSERT INTO ... SELECT` from `STG_USERS` with surrogate key generation.
- **DIM_BUSINESSES:** `INSERT INTO ... SELECT` from `STG_BUSINESSES` with surrogate key generation.
- **FACT_VISITS:** `INSERT INTO ... SELECT` from `STG_VISITS` joined to dimensions for surrogate key lookups.

---

## Phase 3 — Data Quality Validation

### Step 3.1: Completeness Checks
- Row count in `FACT_VISITS` matches `RAW_VISITS`.
- Row count in `DIM_USERS` matches `RAW_USERS`.
- Row count in `DIM_BUSINESSES` matches `RAW_BUSINESSES`.

### Step 3.2: Referential Integrity
- Every `user_key` in `FACT_VISITS` exists in `DIM_USERS`.
- Every `business_key` in `FACT_VISITS` exists in `DIM_BUSINESSES`.
- Every `date_key` in `FACT_VISITS` exists in `DIM_TIME`.

### Step 3.3: Geospatial Validity
- All `lat` values in `DIM_BUSINESSES` fall within 20.90–21.05 (Merida bounding box).
- All `long` values in `DIM_BUSINESSES` fall within -89.70 to -89.50.

### Step 3.4: Business Logic
- `cashback_amount > 0` only where the linked business has `loyalty_type = 'Cashback'`.
- `punch_count > 0` only where the linked business has `loyalty_type = 'Punch Card'`.
- `points_earned >= 0` for all visits.
- No visits occur before the user's `registration_date`.

---

## Phase 4 — Streamlit App (Future)

Build the Streamlit app (`streamlit_app.py`) connecting to `ANALYTICS_ZONE` to deliver:
- Geospatial heatmaps of business density and user activity.
- Loyalty program performance dashboard (redemption rates, CLV by tier).
- Foot traffic analysis by time of day, day of week, and category.
- Business category breakdown and top-performing merchants.

---

## Phase 5 — External Integrations (Future)

### Step 5.1: Google Maps API Enrichment
- Python script to call the Google Places API for real business data around Merida.
- Enrich `RAW_BUSINESSES` with real `google_place_id`, `google_rating`, verified coordinates, and opening hours.

### Step 5.2: Firebase Integration
- Connect to Firebase Firestore to extract real user and event data.
- Replace synthetic `RAW_USERS` and `RAW_VISITS` with live exports.
- Implement PUT/COPY INTO pipeline using the `@FIDELY_STAGE` internal stage.

---

## Schema Dependency Diagram

```
Internal Stage (@FIDELY_STAGE)
        |
        v
   ┌──────────┐      ┌──────────────┐      ┌────────────────┐
   │ RAW_ZONE │ ---> │ STAGING_ZONE │ ---> │ ANALYTICS_ZONE │ ---> Streamlit App
   │          │      │   (Views)    │      │ (Star Schema)  │
   │RAW_USERS │      │ STG_USERS    │      │ DIM_USERS      │
   │RAW_BUSNS │      │ STG_BUSNS    │      │ DIM_BUSINESSES │
   │RAW_VISITS│      │ STG_VISITS   │      │ DIM_TIME       │
   └──────────┘      └──────────────┘      │ DIM_LOYALTY    │
                                           │ FACT_VISITS    │
                                           └────────────────┘
```

## Object Summary

| Schema | Object Type | Count |
|---|---|---|
| `RAW_ZONE` | Tables | 3 |
| `RAW_ZONE` | Stages | 1 |
| `STAGING_ZONE` | Views | 3 |
| `ANALYTICS_ZONE` | Tables | 5 |
| **Total** | | **12** |
