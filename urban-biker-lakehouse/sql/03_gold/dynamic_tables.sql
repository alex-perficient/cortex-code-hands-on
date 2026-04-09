-- ============================================================================
-- 03_gold/dynamic_tables.sql
-- Gold layer: dynamic tables for aggregated metrics.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA GOLD;

-- ---------------------------------------------------------------------------
-- Network-level summary per extraction snapshot
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_NETWORK_SUMMARY(
    EXTRACTION_AT,
    TOTAL_STATIONS,
    ONLINE_STATIONS,
    TOTAL_FREE_BIKES,
    TOTAL_EMPTY_SLOTS,
    TOTAL_SLOTS,
    NETWORK_OCCUPANCY_PCT
)
    TARGET_LAG    = '1 hour'
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    WAREHOUSE     = COCO_HOL_WH
AS
SELECT
    extraction_at,
    COUNT(DISTINCT station_id)                                             AS total_stations,
    SUM(CASE WHEN is_online THEN 1 ELSE 0 END)                            AS online_stations,
    SUM(free_bikes)                                                        AS total_free_bikes,
    SUM(empty_slots)                                                       AS total_empty_slots,
    SUM(total_slots)                                                       AS total_slots,
    ROUND(SUM(free_bikes)::FLOAT / NULLIF(SUM(total_slots), 0) * 100, 2)  AS network_occupancy_pct
FROM URBAN_BIKER_DB_33.SILVER.BIKE_STATIONS
GROUP BY extraction_at;

-- ---------------------------------------------------------------------------
-- Station-level hourly metrics
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_STATION_HOURLY_METRICS(
    STATION_ID,
    STATION_NAME,
    STATION_NUMBER,
    LATITUDE,
    LONGITUDE,
    ADDRESS,
    HOUR_BUCKET,
    AVG_FREE_BIKES,
    AVG_EMPTY_SLOTS,
    MIN_FREE_BIKES,
    MAX_FREE_BIKES,
    AVG_TOTAL_SLOTS,
    AVG_OCCUPANCY_PCT,
    SNAPSHOT_COUNT
)
    TARGET_LAG    = '1 hour'
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    WAREHOUSE     = COCO_HOL_WH
AS
SELECT
    station_id,
    station_name,
    station_number,
    latitude,
    longitude,
    address,
    DATE_TRUNC('HOUR', extraction_at)                                    AS hour_bucket,
    AVG(free_bikes)                                                      AS avg_free_bikes,
    AVG(empty_slots)                                                     AS avg_empty_slots,
    MIN(free_bikes)                                                      AS min_free_bikes,
    MAX(free_bikes)                                                      AS max_free_bikes,
    AVG(total_slots)                                                     AS avg_total_slots,
    ROUND(AVG(free_bikes) / NULLIF(AVG(total_slots), 0) * 100, 2)       AS avg_occupancy_pct,
    COUNT(*)                                                             AS snapshot_count
FROM URBAN_BIKER_DB_33.SILVER.BIKE_STATIONS
GROUP BY station_id, station_name, station_number, latitude, longitude, address,
         DATE_TRUNC('HOUR', extraction_at);
