-- =============================================================================
-- My Usage Dashboard - SQL Queries
-- Description: All queries used by the Streamlit monitoring dashboard.
--              In the dashboard, the user is selected dynamically via a
--              sidebar selectbox. Below, 'COCO_HOL_USER_33' is used as
--              example; replace with any valid username.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. USER LIST (for the sidebar selector)
-- ---------------------------------------------------------------------------
SELECT name
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE name LIKE 'COCO_HOL_USER_%'
  AND deleted_on IS NULL
ORDER BY name;


-- ---------------------------------------------------------------------------
-- 1. OVERALL CREDIT SUMMARY (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS total_compute_credits,
    ROUND(COALESCE(SUM(credits_used_query_acceleration), 0), 4) AS total_qas_credits,
    COUNT(DISTINCT query_id) AS total_queries,
    COUNT(DISTINCT warehouse_name) AS warehouses_used
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33';


-- ---------------------------------------------------------------------------
-- 2. CORTEX ANALYST CREDITS (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    ROUND(COALESCE(SUM(credits), 0), 4) AS total_cortex_credits,
    COALESCE(SUM(request_count), 0) AS total_requests,
    COUNT(DISTINCT DATE(start_time)) AS active_days
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND username = 'COCO_HOL_USER_33';


-- ---------------------------------------------------------------------------
-- 3. WEEK-OVER-WEEK COMPARISON
-- ---------------------------------------------------------------------------
WITH current_week AS (
    SELECT ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
    WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
      AND user_name = 'COCO_HOL_USER_33'
),
previous_week AS (
    SELECT ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
    WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
      AND start_time < DATEADD(DAY, -7, CURRENT_DATE())
      AND user_name = 'COCO_HOL_USER_33'
)
SELECT
    c.credits AS current_week_credits,
    p.credits AS previous_week_credits,
    ROUND(c.credits - p.credits, 4) AS change,
    CASE WHEN p.credits > 0
         THEN ROUND(((c.credits - p.credits) / p.credits) * 100, 2)
         ELSE NULL END AS pct_change
FROM current_week c, previous_week p;


-- ---------------------------------------------------------------------------
-- 4. DAILY COMPUTE CREDITS TREND (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    DATE(start_time) AS usage_date,
    ROUND(SUM(credits_attributed_compute), 4) AS daily_compute_credits,
    ROUND(SUM(COALESCE(credits_used_query_acceleration, 0)), 4) AS daily_qas_credits,
    COUNT(DISTINCT query_id) AS daily_query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33'
GROUP BY DATE(start_time)
ORDER BY usage_date;


-- ---------------------------------------------------------------------------
-- 5. CREDITS BY WAREHOUSE (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    warehouse_name,
    ROUND(SUM(credits_attributed_compute), 4) AS total_credits,
    COUNT(DISTINCT query_id) AS query_count,
    ROUND(AVG(credits_attributed_compute), 6) AS avg_credits_per_query
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33'
GROUP BY warehouse_name
ORDER BY total_credits DESC;


-- ---------------------------------------------------------------------------
-- 6. CORTEX ANALYST DAILY TREND (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    DATE(start_time) AS usage_date,
    ROUND(SUM(credits), 4) AS daily_credits,
    SUM(request_count) AS daily_requests
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND username = 'COCO_HOL_USER_33'
GROUP BY DATE(start_time)
ORDER BY usage_date;


-- ---------------------------------------------------------------------------
-- 7. QUERY TYPES BREAKDOWN (last 7 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    query_type,
    COUNT(*) AS execution_count,
    ROUND(AVG(total_elapsed_time) / 1000, 2) AS avg_duration_sec,
    ROUND(MAX(total_elapsed_time) / 1000, 2) AS max_duration_sec,
    ROUND(AVG(bytes_scanned) / (1024*1024), 2) AS avg_mb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33'
GROUP BY query_type
ORDER BY execution_count DESC;


-- ---------------------------------------------------------------------------
-- 8. OBJECT INVENTORY - Objects created (last 90 days, filtered by user)
-- ---------------------------------------------------------------------------
-- Classifies CREATE statements from QUERY_HISTORY into object types
-- and counts distinct objects (by query_hash) to avoid duplicates from
-- repeated CREATE OR REPLACE / CREATE IF NOT EXISTS statements.
WITH classified AS (
    SELECT
        CASE
            WHEN query_type = 'CREATE_TABLE' THEN 'TABLE'
            WHEN query_type = 'CREATE_TABLE_AS_SELECT' THEN 'TABLE (CTAS)'
            WHEN query_type = 'CREATE_VIEW' THEN 'VIEW'
            WHEN query_type = 'CREATE_SEMANTIC_VIEW' THEN 'SEMANTIC VIEW'
            WHEN query_type = 'CREATE_ICEBERG_TABLE' THEN 'ICEBERG TABLE'
            WHEN query_type = 'CREATE_STREAM' THEN 'STREAM'
            WHEN query_type = 'CREATE_TASK' THEN 'TASK'
            WHEN query_type = 'CREATE_ROLE' THEN 'ROLE'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%STREAMLIT%' THEN 'STREAMLIT APP'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%AGENT%' THEN 'AGENT'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%NOTEBOOK%' THEN 'NOTEBOOK'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%DASHBOARD%' THEN 'DASHBOARD'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%STAGE%' THEN 'STAGE'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%DATABASE%' THEN 'DATABASE'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%SCHEMA%' THEN 'SCHEMA'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%PROCEDURE%' THEN 'PROCEDURE'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%FUNCTION%' THEN 'FUNCTION'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%FILE FORMAT%' THEN 'FILE FORMAT'
            WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%WORKSPACE%' THEN 'WORKSPACE'
            ELSE 'OTHER'
        END AS object_type,
        query_hash
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE user_name = 'COCO_HOL_USER_33'
      AND query_type LIKE 'CREATE%'
      AND execution_status = 'SUCCESS'
      AND start_time >= DATEADD(DAY, -90, CURRENT_DATE())
)
SELECT object_type, COUNT(DISTINCT query_hash) AS objects_created
FROM classified
GROUP BY object_type
ORDER BY objects_created DESC;


-- ---------------------------------------------------------------------------
-- 9. STORAGE USAGE FOR USER DATABASES (databases with user suffix)
-- ---------------------------------------------------------------------------
-- Replace '_33' with the user's numeric suffix
-- 9a. CURRENT LIVE OBJECTS in user databases (not deleted)
-- ---------------------------------------------------------------------------
SELECT 'TABLE' AS object_type, COUNT(*) AS object_count
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE deleted IS NULL
  AND table_type = 'BASE TABLE'
  AND (table_catalog LIKE '%_33' OR table_catalog LIKE '%_33_%')
UNION ALL
SELECT 'VIEW', COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.VIEWS
WHERE deleted IS NULL
  AND (table_catalog LIKE '%_33' OR table_catalog LIKE '%_33_%')
UNION ALL
SELECT 'FUNCTION', COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.FUNCTIONS
WHERE deleted IS NULL
  AND (function_catalog LIKE '%_33' OR function_catalog LIKE '%_33_%')
UNION ALL
SELECT 'PROCEDURE', COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.PROCEDURES
WHERE deleted IS NULL
  AND (procedure_catalog LIKE '%_33' OR procedure_catalog LIKE '%_33_%')
UNION ALL
SELECT 'STAGE', COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.STAGES
WHERE deleted IS NULL
  AND (stage_catalog LIKE '%_33' OR stage_catalog LIKE '%_33_%')
UNION ALL
SELECT 'SEMANTIC VIEW', COUNT(*)
FROM SNOWFLAKE.ACCOUNT_USAGE.SEMANTIC_VIEWS
WHERE deleted IS NULL
  AND (semantic_view_database_name LIKE '%_33' OR semantic_view_database_name LIKE '%_33_%')
ORDER BY object_count DESC;


-- ---------------------------------------------------------------------------
-- 9b. STORAGE USAGE FOR USER DATABASES (databases with user suffix)
-- ---------------------------------------------------------------------------
SELECT
    database_name,
    ROUND(AVG(average_database_bytes) / (1024*1024*1024), 4) AS avg_storage_gb,
    ROUND(AVG(average_failsafe_bytes) / (1024*1024*1024), 4) AS avg_failsafe_gb,
    ROUND(AVG(average_database_bytes + average_failsafe_bytes
              + COALESCE(average_hybrid_table_storage_bytes, 0))
          / (1024*1024*1024), 4) AS total_avg_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE usage_date >= DATEADD(DAY, -30, CURRENT_DATE())
  AND (database_name LIKE '%_33' OR database_name LIKE '%_33_%')
GROUP BY database_name
ORDER BY total_avg_gb DESC;


-- ---------------------------------------------------------------------------
-- 10. LOGIN HISTORY (last 7 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    DATE(event_timestamp) AS login_date,
    COUNT(*) AS login_count,
    COUNT_IF(is_success = 'YES') AS successful_logins,
    COUNT_IF(is_success = 'NO') AS failed_logins
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE event_timestamp >= DATEADD(DAY, -7, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33'
GROUP BY DATE(event_timestamp)
ORDER BY login_date;


-- ---------------------------------------------------------------------------
-- 11. TOP 15 MOST EXPENSIVE QUERIES (last 30 days, filtered by user)
-- ---------------------------------------------------------------------------
SELECT
    query_id,
    warehouse_name,
    ROUND(credits_attributed_compute, 6) AS credits_compute,
    ROUND(COALESCE(credits_used_query_acceleration, 0), 6) AS credits_qas,
    start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
  AND user_name = 'COCO_HOL_USER_33'
  AND credits_attributed_compute > 0
ORDER BY credits_attributed_compute DESC
LIMIT 15;
