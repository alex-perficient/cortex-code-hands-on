-- ============================================================================
-- 01_raw/tables.sql
-- Bronze layer: raw ingestion table for CityBikes Parquet data.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA RAW;

CREATE OR REPLACE TABLE BIKE_STATIONS_RAW (
    RAW_DATA        VARIANT,
    FILENAME        VARCHAR(16777216),
    INGESTION_TIME  TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);
