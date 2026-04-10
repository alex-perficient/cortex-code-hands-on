-- ============================================================================
-- 04_automation/tasks.sql
-- Scheduled Task: hourly ingestion from S3 + Silver refresh.
--
-- Pipeline flow automated by this task:
--   S3 (Parquet) -> COPY INTO RAW.BIKE_STATIONS_RAW -> CALL SP_CLEAN_BIKE_STATIONS
--   Gold Dynamic Tables auto-refresh from Silver (no action needed here).
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE WAREHOUSE COCO_HOL_WH;
USE SCHEMA RAW;

-- Hourly task: ingest new files from S3 and refresh Silver layer
CREATE OR REPLACE TASK TASK_HOURLY_INGESTION
    WAREHOUSE = COCO_HOL_WH
    SCHEDULE  = 'USING CRON 0 * * * * UTC'
    COMMENT   = 'Hourly: COPY INTO from S3 stage + Silver MERGE via SP_CLEAN_BIKE_STATIONS'
AS
BEGIN
    -- Step 1: Load any new Parquet files from S3 into Bronze
    -- COPY INTO is idempotent: already-loaded files are skipped automatically.
    COPY INTO URBAN_BIKER_DB_33.RAW.BIKE_STATIONS_RAW (RAW_DATA, FILENAME)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @URBAN_BIKER_DB_33.RAW.BIKE_STAGE_S3
    )
    FILE_FORMAT = (TYPE = 'PARQUET');

    -- Step 2: Merge new raw records into Silver
    CALL URBAN_BIKER_DB_33.SILVER.SP_CLEAN_BIKE_STATIONS();
END;

-- Resume the task so it starts running on schedule
ALTER TASK TASK_HOURLY_INGESTION RESUME;
