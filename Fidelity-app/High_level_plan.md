# High-Level Architecture & ETL Plan: Firebase to Snowflake POC

## 1. Objective
To design and implement a Proof of Concept (POC) that establishes a zero-infrastructure data pipeline. The pipeline will extract operational data (simulating Google Firebase) and enrichment data (Google Maps API), load it securely into a Snowflake Data Warehouse via Internal Stages, and transform it into a structured analytical model. The ultimate goal is to power a Streamlit application for Business Intelligence (BI) Analysts, while preparing the architectural runway for a future Flutter-based frontend migration.

> **POC Scope (Current Phase):** The initial implementation focuses on building the Snowflake data model end-to-end using synthetic data generated directly in SQL. All new objects are created in dedicated schemas within the existing `PINNACLE_FINANCIAL_DEMO_33` database. External integrations (Google Maps API, Firebase) and the Streamlit app are deferred to subsequent phases.

## 2. Background for a BI Analyst
**What the App Does:** The platform operates as a digital directory and loyalty ecosystem for local food businesses. It connects consumers with local dining options while providing merchants with tools to track foot traffic, manage loyalty programs (Cashback, Punch Cards, VIP Passes), and monitor customer retention.

**Analytical Goals:** BI Analysts will use the Streamlit app to uncover insights such as:
* **Geospatial Trends:** Which neighborhoods have the highest concentration of active users vs. registered businesses?
* **Loyalty Conversion:** What is the redemption rate of loyalty rewards, and how does it impact Customer Lifetime Value (CLV)?
* **Foot Traffic Heatmaps:** Identifying peak operational hours across different business categories using Google Maps enriched data and app visit logs.

## 3. Company Background
**Mon TI Labs** is a technology company developing a comprehensive software ecosystem aimed at empowering local businesses (SMEs). Key products within this ecosystem include **Fidely App** (a SaaS loyalty program solution) and **Gula Maps** (a local food business directory). The company focuses on bridging the gap between local commerce and data-driven decision-making, providing enterprise-grade analytics to small merchants.

## 4. Suggested Technical Requirements
The architecture is decoupled into operational and analytical planes:

**Operational Plane (Future Phase):**
* **Frontend:** Flutter (Dart) for cross-platform mobile and web deployment.
* **Backend:** Google Firebase (Firestore, Auth).

**Analytical Plane & ETL (Current POC Focus):**
* **Database:** `PINNACLE_FINANCIAL_DEMO_33` (shared database; Fidely objects live in their own schemas, isolated from existing `FINANCE_ANALYTICS` data).
* **Staging:** Snowflake Internal Stages (Zero external cloud infrastructure required).
* **Data Warehouse:** Snowflake (Columnar, cloud-native OLAP database).
* **Data Generation (POC):** Synthetic data generated directly in Snowflake SQL using `GENERATOR()`, `UNIFORM()`, `RANDOM()`, and array-based lookups.
* **Data Extraction (Future):** Custom Python scripts for Firebase export and Google Maps API enrichment.
* **Data Transformation:** Snowflake SQL views and INSERT...SELECT to transform raw JSON into a star schema.
* **Data Presentation (Future):** Streamlit (Python framework for building interactive data apps).

## 5. ETL Logical Construction Steps (The Pipeline)

### POC Phase (Current — Synthetic Data)
1.  **Generation (Snowflake SQL):** Synthetic JSON payloads are generated directly in Snowflake and inserted into `RAW_ZONE` tables with VARIANT columns.
2.  **Transformation (Views):** `STAGING_ZONE` views flatten the VARIANT JSON into typed relational columns.
3.  **Loading (SQL):** `INSERT INTO ... SELECT` statements populate the `ANALYTICS_ZONE` star schema from the staging views.
4.  **Validation (SQL):** Data quality checks verify completeness, referential integrity, geospatial bounds, and business logic.

### Production Phase (Future — Live Data)
1.  **Extraction (Python):** Script connects to the Google Maps API for enrichment data and extracts Firebase JSON payloads. The script saves these as local NDJSON (Newline Delimited JSON) files.
2.  **Staging (Python + Snowflake Connector):** The script executes a Snowflake `PUT` command to securely upload the local files into `@RAW_ZONE.FIDELY_STAGE`.
3.  **Ingestion (Snowflake SQL):** A `COPY INTO` command moves data from the Internal Stage into the `RAW_ZONE` tables.
4.  **Transformation (SQL):** Same views and INSERT...SELECT statements as the POC phase.
5.  **Consumption (Streamlit):** The Streamlit app connects directly to `ANALYTICS_ZONE` to render dashboards.

## 6. Database Requirements & Zoning
* **Database:** `PINNACLE_FINANCIAL_DEMO_33`
* **Source Formats:** Unstructured/semi-structured event data (JSON) and REST API payloads.
* **Snowflake Target Zones (new schemas, isolated from existing data):**
    * `RAW_ZONE`: Landing area for raw Firebase JSON dumps and Google Maps API payloads (using `VARIANT` columns). Includes internal stage `@FIDELY_STAGE`.
    * `STAGING_ZONE`: Cleansed, flattened, and data-typed views.
    * `ANALYTICS_ZONE`: Star schema modeled tables optimized for Streamlit queries.

## 7. Database Modeling (Snowflake Analytics Zone)
To optimize the Streamlit app's performance, the data will be modeled into a **Star Schema**:

| Table Type | Table Name | Description | Key Fields |
| :--- | :--- | :--- | :--- |
| **Fact** | `FACT_VISITS` | Logs every user-business interaction (check-in, redemption, referral). | `visit_key`, `date_key` FK, `user_key` FK, `business_key` FK, `loyalty_type_key` FK, `visit_id`, `visit_type`, `visit_timestamp`, `points_earned`, `cashback_amount`, `punch_count` |
| **Dimension** | `DIM_USERS` | Consumer profiles. | `user_key`, `user_id`, `first_name`, `last_name`, `email`, `registration_date`, `status`, `preferred_zone` |
| **Dimension** | `DIM_BUSINESSES`| Merchant profiles, enriched with Google Maps data. | `business_key`, `business_id`, `business_name`, `category`, `subcategory`, `loyalty_type`, `cashback_pct`, `punch_goal`, `lat`, `long`, `google_rating`, `address`, `neighborhood` |
| **Dimension** | `DIM_TIME` | Standard date/time dimension for time-series analysis. | `date_key`, `calendar_date`, `year`, `month`, `month_name`, `day_of_week`, `day_name`, `quarter`, `is_weekend`, `is_holiday` |
| **Dimension** | `DIM_LOYALTY_TYPE` | Loyalty program type reference. | `loyalty_type_key`, `loyalty_type_name`, `description`, `reward_mechanism` |

## 8. Generation of Realistic Sample Data
To validate the Snowflake model and build the Streamlit app before the Flutter frontend is live, synthetic data will be generated:
1.  **Tool (POC):** Snowflake SQL using `GENERATOR()`, `UNIFORM()`, `RANDOM()`, `DATEADD()`, and array-based lookups. No external dependencies.
2.  **Tool (Future):** Python using the `Faker` library, exported as NDJSON to mimic Firebase exports.
3.  **Scope:** Generate 12 months of historical data (Jul 2025 — Jun 2026).
    * *Users:* ~5,000 realistic profiles with Mexican names, Merida neighborhoods.
    * *Businesses:* ~150 simulated local food businesses (coordinates clustered around Merida, Yucatan).
    * *Visits:* ~50,000 transaction records simulating realistic patterns (e.g., spikes on Friday evenings, higher volume near holidays, realistic loyalty redemption rates).

## 9. Validate Data (Data Quality Checks)
Once data lands in the `ANALYTICS_ZONE`, the following validation checks must be executed:
* **Completeness:** Ensure row counts in `FACT_VISITS`, `DIM_USERS`, and `DIM_BUSINESSES` match the corresponding `RAW_ZONE` source tables.
* **Referential Integrity:** Verify that every `user_key`, `business_key`, and `date_key` in `FACT_VISITS` exists in its corresponding dimension.
* **Geospatial Validity:** Ensure all `lat` values fall within 20.90–21.05 and `long` values within -89.70 to -89.50 (Merida bounding box).
* **Business Logic:** Ensure `cashback_amount > 0` only where the linked business has `loyalty_type = 'Cashback'`; `punch_count > 0` only for `Punch Card` businesses; no visits occur before the user's `registration_date`.

## 10. Additional Considerations
* **Security & Access Control (RBAC):** Define Snowflake roles (`DATA_ENGINEER` for pipeline execution, `BI_ANALYST` for Streamlit read-only access).
* **Warehouse Sizing:** Start with an `X-Small` Snowflake warehouse for the POC to minimize compute credit consumption.
* **File Management (Future):** When the Python extraction pipeline is active, ensure cleanup of local files after successful `PUT`, and configure `COPY INTO` to purge staged files after ingestion.

## 11. Implementation Phases

| Phase | Scope | Status |
|---|---|---|
| **Phase 1** | Schema creation, table/view DDL, internal stage | Current |
| **Phase 2** | Synthetic data generation in Snowflake SQL | Current |
| **Phase 3** | Data quality validation | Current |
| **Phase 4** | Streamlit BI application | Future |
| **Phase 5** | Google Maps API + Firebase integration | Future |

> See `implementation_plan.md` for the detailed step-by-step breakdown.