-- ============================================================================
-- 02_silver/tables.sql
-- Silver layer: cleaned and structured bike station data.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA SILVER;

CREATE OR REPLACE TABLE BIKE_STATIONS (
    STATION_ID          VARCHAR(16777216),
    STATION_NAME        VARCHAR(16777216),
    STATION_NUMBER      VARCHAR(16777216),
    STATION_UID         NUMBER(38,0),
    LATITUDE            FLOAT,
    LONGITUDE           FLOAT,
    FREE_BIKES          NUMBER(38,0),
    EMPTY_SLOTS         NUMBER(38,0),
    TOTAL_SLOTS         NUMBER(38,0),
    ADDRESS             VARCHAR(16777216),
    IS_ONLINE           BOOLEAN,
    AVAILABILITY_LIGHT  VARCHAR(16777216),
    API_TIMESTAMP       TIMESTAMP_TZ(9),
    EXTRACTION_AT       TIMESTAMP_NTZ(9)
);
