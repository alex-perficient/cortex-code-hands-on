-- ============================================================
-- STEP 10: Data Quality — Data Metric Functions (DMFs)
-- Crea DMFs custom y adjunta built-in + custom a Bronze, Silver y Gold
-- Schedule: TRIGGER_ON_CHANGES (se evaluan cuando la tabla cambia)
-- ============================================================

USE DATABASE URBAN_BIKER_DB_33;
USE WAREHOUSE COCO_HOL_WH;

-- ============================================================
-- 10.1  DMFs CUSTOM — Bronze (RAW)
-- ============================================================

-- Cuenta registros con RAW_DATA NULL (archivos corruptos o vacios)
CREATE OR REPLACE DATA METRIC FUNCTION RAW.DMF_NULL_VARIANT_COUNT(
    ARG_T TABLE(RAW_DATA VARIANT)
)
RETURNS NUMBER
COMMENT = 'Counts NULL VARIANT values in RAW_DATA — indicates corrupt or empty records.'
AS
$$
    SELECT COUNT(*) FROM ARG_T WHERE RAW_DATA IS NULL
$$;

-- Cuenta filas duplicadas por combinacion RAW_DATA + FILENAME
CREATE OR REPLACE DATA METRIC FUNCTION RAW.DMF_DUPLICATE_RAW_COUNT(
    ARG_T TABLE(RAW_DATA VARIANT, FILENAME VARCHAR, INGESTION_TIME TIMESTAMP_NTZ)
)
RETURNS NUMBER
COMMENT = 'Counts duplicate rows by RAW_DATA+FILENAME — detects repeated COPY INTO loads.'
AS
$$
    SELECT COUNT(*) - COUNT(DISTINCT RAW_DATA || '|' || FILENAME)
    FROM ARG_T
$$;

-- ============================================================
-- 10.2  SCHEDULE — Activar evaluacion automatica por tabla
-- ============================================================

ALTER TABLE RAW.BIKE_STATIONS_RAW
    SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER TABLE SILVER.BIKE_STATIONS
    SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER DYNAMIC TABLE GOLD.DT_NETWORK_SUMMARY
    SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

-- ============================================================
-- 10.3  ADJUNTAR DMFs — Bronze (RAW.BIKE_STATIONS_RAW)
-- ============================================================

-- Nulls en RAW_DATA (VARIANT — requiere DMF custom)
ALTER TABLE RAW.BIKE_STATIONS_RAW
    ADD DATA METRIC FUNCTION RAW.DMF_NULL_VARIANT_COUNT ON (RAW_DATA);

-- Nulls en FILENAME
ALTER TABLE RAW.BIKE_STATIONS_RAW
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (FILENAME);

-- Duplicados por RAW_DATA + FILENAME
ALTER TABLE RAW.BIKE_STATIONS_RAW
    ADD DATA METRIC FUNCTION RAW.DMF_DUPLICATE_RAW_COUNT ON (RAW_DATA, FILENAME, INGESTION_TIME);

-- ============================================================
-- 10.4  ADJUNTAR DMFs — Silver (SILVER.BIKE_STATIONS)
-- ============================================================

-- Nulls en columnas criticas
ALTER TABLE SILVER.BIKE_STATIONS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (STATION_ID);

ALTER TABLE SILVER.BIKE_STATIONS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (LATITUDE);

ALTER TABLE SILVER.BIKE_STATIONS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (LONGITUDE);

-- Duplicados en STATION_ID
-- NOTA: DUPLICATE_COUNT > 0 es ESPERADO aqui porque la tabla contiene multiples
-- snapshots temporales (mismo station_id con distintos extraction_at).
-- La unicidad real es (STATION_ID, EXTRACTION_AT), protegida por QUALIFY en el SP.
-- Este metric sirve como baseline: un aumento subito indica cargas duplicadas.
ALTER TABLE SILVER.BIKE_STATIONS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (STATION_ID);

-- ============================================================
-- 10.5  ADJUNTAR DMFs — Gold (GOLD.DT_NETWORK_SUMMARY)
-- ============================================================

-- Nulls en metricas agregadas
ALTER DYNAMIC TABLE GOLD.DT_NETWORK_SUMMARY
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (TOTAL_STATIONS);

ALTER DYNAMIC TABLE GOLD.DT_NETWORK_SUMMARY
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (NETWORK_OCCUPANCY_PCT);

-- ============================================================
-- NOTA: SNOWFLAKE.CORE.FRESHNESS solo acepta TIMESTAMP_LTZ.
-- Nuestras columnas usan TIMESTAMP_NTZ, por lo que no es compatible.
-- La frescura se valida indirectamente:
--   - El Task TASK_HOURLY_INGESTION corre cada hora
--   - Si falla, TASK_HISTORY lo registra con estado FAILED
--   - Las Dynamic Tables de Gold tienen TARGET_LAG = '1 hour'
-- ============================================================

-- ============================================================
-- 10.6  VERIFICAR DMFs ADJUNTAS (ejecutar para confirmar)
-- ============================================================

-- Ver DMFs adjuntas a Bronze:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
--     REF_ENTITY_NAME => 'URBAN_BIKER_DB_33.RAW.BIKE_STATIONS_RAW',
--     REF_ENTITY_DOMAIN => 'TABLE'));

-- Ver DMFs adjuntas a Silver:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
--     REF_ENTITY_NAME => 'URBAN_BIKER_DB_33.SILVER.BIKE_STATIONS',
--     REF_ENTITY_DOMAIN => 'TABLE'));

-- Ver DMFs adjuntas a Gold:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
--     REF_ENTITY_NAME => 'URBAN_BIKER_DB_33.GOLD.DT_NETWORK_SUMMARY',
--     REF_ENTITY_DOMAIN => 'TABLE'));

-- ============================================================
-- 10.7  EJECUTAR DMFs MANUALMENTE (para validar resultados)
-- ============================================================

-- Bronze: nulls en VARIANT
-- SELECT RAW.DMF_NULL_VARIANT_COUNT(SELECT RAW_DATA FROM RAW.BIKE_STATIONS_RAW);

-- Bronze: duplicados
-- SELECT RAW.DMF_DUPLICATE_RAW_COUNT(SELECT RAW_DATA, FILENAME, INGESTION_TIME FROM RAW.BIKE_STATIONS_RAW);

-- Silver: nulls en columnas criticas
-- SELECT SNOWFLAKE.CORE.NULL_COUNT(SELECT STATION_ID FROM SILVER.BIKE_STATIONS);
-- SELECT SNOWFLAKE.CORE.NULL_COUNT(SELECT LATITUDE FROM SILVER.BIKE_STATIONS);

-- Silver: duplicados en STATION_ID (esperado > 0 por multiples snapshots)
-- SELECT SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT STATION_ID FROM SILVER.BIKE_STATIONS);
