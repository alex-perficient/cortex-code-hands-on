-- ============================================================================
-- 01_raw/stages.sql
-- Bronze layer: internal and external stages for data landing.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA RAW;

-- Internal stage for manual Parquet uploads
CREATE OR REPLACE STAGE CITYBIKES_STG
    DIRECTORY = (ENABLE = TRUE);

-- External stage pointing to the S3 landing zone
-- NOTE: Replace <your_aws_key_id> and <your_aws_secret_key> with real credentials.
CREATE OR REPLACE STAGE BIKE_STAGE_S3
    URL = 's3://citybikes-stg/citybikes_parquet/'
    CREDENTIALS = (
        AWS_KEY_ID     = '<your_aws_key_id>'
        AWS_SECRET_KEY = '<your_aws_secret_key>'
    )
    FILE_FORMAT = (TYPE = 'PARQUET');

-- Load data from external stage into raw table
COPY INTO BIKE_STATIONS_RAW (RAW_DATA, FILENAME)
FROM (
    SELECT $1, METADATA$FILENAME
    FROM @BIKE_STAGE_S3
)
FILE_FORMAT = (TYPE = 'PARQUET');
