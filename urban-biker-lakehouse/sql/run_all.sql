-- ============================================================================
-- run_all.sql
-- Master orchestration script for the Urban Biker Lakehouse.
--
-- Execute each file below in order from a Snowflake worksheet or CLI.
-- Snowflake SQL does not support file includes, so run each file manually
-- in the order listed here.
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 1 — Setup: Database & Schemas                                     │
-- │ File: sql/00_setup.sql                                                 │
-- │ Creates: URBAN_BIKER_DB_33, schemas RAW / SILVER / GOLD                │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 2 — Bronze: Raw Tables                                            │
-- │ File: sql/01_raw/tables.sql                                            │
-- │ Creates: RAW.BIKE_STATIONS_RAW                                         │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 3 — Bronze: Stages & Initial Load                                 │
-- │ File: sql/01_raw/stages.sql                                            │
-- │ Creates: RAW.CITYBIKES_STG, RAW.BIKE_STAGE_S3                          │
-- │ Runs:    COPY INTO to load Parquet data from S3                        │
-- │ NOTE:    Update AWS credentials before running.                        │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 4 — Silver: Cleaned Tables                                        │
-- │ File: sql/02_silver/tables.sql                                         │
-- │ Creates: SILVER.BIKE_STATIONS                                          │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 5 — Silver: Transformation Procedures                             │
-- │ File: sql/02_silver/procedures.sql                                     │
-- │ Creates: SILVER.SP_CLEAN_BIKE_STATIONS                                 │
-- │ Run:     CALL SP_CLEAN_BIKE_STATIONS(); to populate Silver table       │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 6 — Gold: Dynamic Tables                                          │
-- │ File: sql/03_gold/dynamic_tables.sql                                   │
-- │ Creates: GOLD.DT_NETWORK_SUMMARY, GOLD.DT_STATION_HOURLY_METRICS      │
-- │ NOTE:    These auto-refresh from SILVER.BIKE_STATIONS every 1 hour.    │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 7 — Gold: Streamlit Stage                                         │
-- │ File: sql/03_gold/stages.sql                                           │
-- │ Creates: GOLD.STREAMLIT_STAGE                                          │
-- │ After:   Upload app files with PUT commands:                           │
-- │   PUT file://app/streamlit_app.py @STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE│
-- │   PUT file://app/environment.yml  @STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE│
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 8 — Gold: Streamlit Application                                   │
-- │ File: sql/03_gold/streamlit.sql                                        │
-- │ Creates: GOLD.BICIMAD_DASHBOARD (Streamlit in Snowflake)               │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ STEP 9 — Automation: Scheduled Hourly Ingestion Task                   │
-- │ File: sql/04_automation/tasks.sql                                      │
-- │ Creates: RAW.TASK_HOURLY_INGESTION                                     │
-- │ Runs:    Every hour — COPY INTO from S3 + CALL SP_CLEAN_BIKE_STATIONS  │
-- │ NOTE:    Gold Dynamic Tables auto-refresh from Silver automatically.   │
-- └─────────────────────────────────────────────────────────────────────────┘
