-- ============================================================================
-- 02_silver/procedures.sql
-- Silver layer: stored procedure to clean and merge raw data into BIKE_STATIONS.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SP_CLEAN_BIKE_STATIONS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    MERGE INTO URBAN_BIKER_DB_33.SILVER.BIKE_STATIONS AS tgt
    USING (
        SELECT
            raw_data:"id"::STRING                       AS station_id,
            raw_data:"name"::STRING                     AS station_name,
            raw_data:"extra.number"::STRING             AS station_number,
            raw_data:"extra.uid"::INT                   AS station_uid,
            raw_data:"latitude"::FLOAT                  AS latitude,
            raw_data:"longitude"::FLOAT                 AS longitude,
            raw_data:"free_bikes"::INT                  AS free_bikes,
            raw_data:"empty_slots"::INT                 AS empty_slots,
            raw_data:"extra.slots"::INT                 AS total_slots,
            TRIM(RTRIM(raw_data:"extra.address"::STRING, ',')) AS address,
            raw_data:"extra.online"::BOOLEAN            AS is_online,
            raw_data:"extra.light"::STRING              AS availability_light,
            TRY_TO_TIMESTAMP_TZ(raw_data:"timestamp"::STRING) AS api_timestamp,
            raw_data:"extraction_at"::TIMESTAMP_NTZ     AS extraction_at
        FROM URBAN_BIKER_DB_33.RAW.BIKE_STATIONS_RAW
        WHERE raw_data:"latitude" IS NOT NULL
          AND raw_data:"longitude" IS NOT NULL
          AND raw_data:"extra.slots"::INT > 0
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY raw_data:"id"::STRING, raw_data:"extraction_at"::TIMESTAMP_NTZ
            ORDER BY INGESTION_TIME DESC
        ) = 1
    ) AS src
    ON tgt.station_id = src.station_id AND tgt.extraction_at = src.extraction_at
    WHEN MATCHED THEN UPDATE SET
        tgt.station_name        = src.station_name,
        tgt.station_number      = src.station_number,
        tgt.station_uid         = src.station_uid,
        tgt.latitude            = src.latitude,
        tgt.longitude           = src.longitude,
        tgt.free_bikes          = src.free_bikes,
        tgt.empty_slots         = src.empty_slots,
        tgt.total_slots         = src.total_slots,
        tgt.address             = src.address,
        tgt.is_online           = src.is_online,
        tgt.availability_light  = src.availability_light,
        tgt.api_timestamp       = src.api_timestamp
    WHEN NOT MATCHED THEN INSERT (
        station_id, station_name, station_number, station_uid,
        latitude, longitude, free_bikes, empty_slots, total_slots,
        address, is_online, availability_light, api_timestamp, extraction_at
    ) VALUES (
        src.station_id, src.station_name, src.station_number, src.station_uid,
        src.latitude, src.longitude, src.free_bikes, src.empty_slots, src.total_slots,
        src.address, src.is_online, src.availability_light, src.api_timestamp, src.extraction_at
    );

    RETURN 'Merge completed successfully';
END;
