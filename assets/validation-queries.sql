-- ============================================================================
-- Pinnacle Financial Services -- Production Data Validation Queries
-- ============================================================================
-- Owner:    David Park, VP of Operations
-- Purpose:  Verify integration correctness across Geneva, NetSuite, Salesforce
-- Usage:    Run daily after ingestion completes (~7:00 AM ET)
--           Schedule via Snowflake Task or run ad-hoc during month-end close
-- Schema:   PINNACLE_FINANCIAL.CURATED (star schema tables)
--           PINNACLE_FINANCIAL.RAW (source landing tables)
-- ============================================================================

USE SCHEMA PINNACLE_FINANCIAL.CURATED;


-- ############################################################################
-- 1. ROW COUNT COMPARISON (Source vs. Snowflake)
-- ############################################################################
-- Compare RAW landing table counts to CURATED table counts.
-- RAW counts should always be >= CURATED (RAW may contain duplicates,
-- historical records, or non-client record types that are filtered out).
-- A CURATED count higher than RAW indicates a transformation bug.
-- ############################################################################

-- 1A. Full row count dashboard across all tables
--     Run this first to get a high-level health check.
SELECT
    'DIM_DATE'           AS TABLE_NAME, COUNT(*) AS CURATED_ROWS FROM CURATED.DIM_DATE
UNION ALL SELECT
    'DIM_CLIENT',        COUNT(*) FROM CURATED.DIM_CLIENT
UNION ALL SELECT
    'DIM_PRODUCT',       COUNT(*) FROM CURATED.DIM_PRODUCT
UNION ALL SELECT
    'DIM_COST_CENTER',   COUNT(*) FROM CURATED.DIM_COST_CENTER
UNION ALL SELECT
    'DIM_GL_ACCOUNT',    COUNT(*) FROM CURATED.DIM_GL_ACCOUNT
UNION ALL SELECT
    'FACT_REVENUE',      COUNT(*) FROM CURATED.FACT_REVENUE
UNION ALL SELECT
    'FACT_EXPENSE',      COUNT(*) FROM CURATED.FACT_EXPENSE
UNION ALL SELECT
    'FACT_BUDGET',       COUNT(*) FROM CURATED.FACT_BUDGET
UNION ALL SELECT
    'FACT_CLIENT_AUM',   COUNT(*) FROM CURATED.FACT_CLIENT_AUM
ORDER BY TABLE_NAME;

-- 1B. Client count: Salesforce RAW vs. CURATED
--     Expect CURATED <= RAW (RAW includes non-client record types).
--     Alert if CURATED > RAW or if delta exceeds 10%.
SELECT
    'Salesforce Accounts (RAW)' AS SOURCE,
    COUNT(*) AS ROW_COUNT
FROM RAW.SALESFORCE_ACCOUNTS
UNION ALL
SELECT
    'DIM_CLIENT (CURATED)',
    COUNT(*)
FROM CURATED.DIM_CLIENT;

-- 1C. Revenue transactions: Geneva RAW vs. CURATED
--     Expect CURATED <= RAW (RAW includes non-fee transaction types).
--     CURATED filters to TRANSACTION_TYPE = 'FEE' and deduplicates.
SELECT
    'Geneva Transactions (RAW)' AS SOURCE,
    COUNT(*) AS ROW_COUNT
FROM RAW.GENEVA_TRANSACTIONS
UNION ALL
SELECT
    'FACT_REVENUE (CURATED)',
    COUNT(*)
FROM CURATED.FACT_REVENUE;

-- 1D. Expense transactions: NetSuite RAW vs. CURATED
--     CURATED filters to expense GL accounts (5000-7999) and excludes voided.
SELECT
    'NetSuite Transaction Lines (RAW)' AS SOURCE,
    COUNT(*) AS ROW_COUNT
FROM RAW.NETSUITE_TRANSACTION_LINES
UNION ALL
SELECT
    'FACT_EXPENSE (CURATED)',
    COUNT(*)
FROM CURATED.FACT_EXPENSE;

-- 1E. Daily row count trend (last 7 days)
--     Detects sudden drops or spikes. A drop > 20% from the 7-day average
--     likely indicates a source system outage or broken extract.
WITH daily_counts AS (
    SELECT
        d.CALENDAR_DATE,
        COUNT(DISTINCT r.REVENUE_KEY) AS REVENUE_ROWS,
        COUNT(DISTINCT e.EXPENSE_KEY) AS EXPENSE_ROWS
    FROM CURATED.DIM_DATE d
    LEFT JOIN CURATED.FACT_REVENUE r ON r.DATE_KEY = d.DATE_KEY
    LEFT JOIN CURATED.FACT_EXPENSE e ON e.DATE_KEY = d.DATE_KEY
    WHERE d.CALENDAR_DATE BETWEEN DATEADD(DAY, -7, CURRENT_DATE()) AND CURRENT_DATE()
    GROUP BY d.CALENDAR_DATE
)
SELECT
    CALENDAR_DATE,
    REVENUE_ROWS,
    EXPENSE_ROWS,
    AVG(REVENUE_ROWS) OVER (ORDER BY CALENDAR_DATE ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS REVENUE_7D_AVG,
    AVG(EXPENSE_ROWS) OVER (ORDER BY CALENDAR_DATE ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS EXPENSE_7D_AVG
FROM daily_counts
ORDER BY CALENDAR_DATE;


-- ############################################################################
-- 2. SUM VALIDATION (Revenue and Expense Totals)
-- ############################################################################
-- Compare dollar totals between RAW and CURATED to catch transformation
-- errors (sign flips, double-counting, dropped records).
-- Tolerance: $1 for daily, $100 for monthly (rounding accumulation).
-- ############################################################################

-- 2A. Revenue total: Geneva RAW vs. CURATED (current month)
--     The two numbers should match within $1.
--     If CURATED > RAW, there is a duplication bug.
--     If CURATED < RAW by more than $1, records are being filtered incorrectly.
SELECT
    'Geneva RAW (current month)' AS SOURCE,
    ROUND(SUM(FEE_AMOUNT), 2) AS TOTAL_REVENUE
FROM RAW.GENEVA_TRANSACTIONS
WHERE TRANSACTION_TYPE = 'FEE'
  AND TRANSACTION_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
UNION ALL
SELECT
    'FACT_REVENUE (current month)',
    ROUND(SUM(REVENUE_AMOUNT), 2)
FROM CURATED.FACT_REVENUE fr
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fr.DATE_KEY
WHERE d.CALENDAR_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE());

-- 2B. Revenue total by month (last 6 months)
--     Use for month-end close reconciliation.
--     Compare against Geneva fee summary report.
SELECT
    d.YEAR_NUMBER,
    d.MONTH_NAME,
    d.MONTH_NUMBER,
    COUNT(*) AS TRANSACTION_COUNT,
    ROUND(SUM(fr.REVENUE_AMOUNT), 2) AS TOTAL_REVENUE,
    ROUND(SUM(fr.AUM_AMOUNT), 2) AS TOTAL_AUM,
    ROUND(AVG(fr.FEE_BASIS_POINTS), 2) AS AVG_FEE_BPS
FROM CURATED.FACT_REVENUE fr
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fr.DATE_KEY
WHERE d.CALENDAR_DATE >= DATEADD(MONTH, -6, DATE_TRUNC('MONTH', CURRENT_DATE()))
GROUP BY d.YEAR_NUMBER, d.MONTH_NAME, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;

-- 2C. Expense total: NetSuite RAW vs. CURATED (current month)
SELECT
    'NetSuite RAW (current month)' AS SOURCE,
    ROUND(SUM(COALESCE(ntl.DEBITAMOUNT, 0) - COALESCE(ntl.CREDITAMOUNT, 0)), 2) AS TOTAL_EXPENSES
FROM RAW.NETSUITE_TRANSACTION_LINES ntl
JOIN RAW.NETSUITE_TRANSACTIONS nt ON nt.ID = ntl.TRANSACTION
JOIN RAW.NETSUITE_ACCOUNTS na ON na.ID = ntl.ACCOUNT
WHERE na.ACCTNUMBER >= '5000' AND na.ACCTNUMBER < '8000'
  AND nt.VOIDED = 'No'
  AND nt.TRANDATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
UNION ALL
SELECT
    'FACT_EXPENSE (current month)',
    ROUND(SUM(EXPENSE_AMOUNT), 2)
FROM CURATED.FACT_EXPENSE fe
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fe.DATE_KEY
WHERE d.CALENDAR_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE());

-- 2D. Expense total by month (last 6 months)
--     Compare against NetSuite P&L report.
SELECT
    d.YEAR_NUMBER,
    d.MONTH_NAME,
    d.MONTH_NUMBER,
    COUNT(*) AS TRANSACTION_COUNT,
    ROUND(SUM(fe.EXPENSE_AMOUNT), 2) AS TOTAL_EXPENSES
FROM CURATED.FACT_EXPENSE fe
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fe.DATE_KEY
WHERE d.CALENDAR_DATE >= DATEADD(MONTH, -6, DATE_TRUNC('MONTH', CURRENT_DATE()))
GROUP BY d.YEAR_NUMBER, d.MONTH_NAME, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;

-- 2E. Profitability sanity check
--     Expense ratio should be 55-75% for Pinnacle.
--     Outside this range indicates a data issue, not a business change.
SELECT
    d.YEAR_NUMBER,
    d.QUARTER_NAME,
    ROUND(SUM(fr.REVENUE_AMOUNT), 2) AS TOTAL_REVENUE,
    ROUND(SUM(fe.EXPENSE_AMOUNT), 2) AS TOTAL_EXPENSES,
    ROUND(SUM(fr.REVENUE_AMOUNT) - SUM(fe.EXPENSE_AMOUNT), 2) AS NET_INCOME,
    ROUND(SUM(fe.EXPENSE_AMOUNT) / NULLIF(SUM(fr.REVENUE_AMOUNT), 0) * 100, 1) AS EXPENSE_RATIO_PCT,
    CASE
        WHEN SUM(fe.EXPENSE_AMOUNT) / NULLIF(SUM(fr.REVENUE_AMOUNT), 0) < 0.55 THEN 'WARNING: Ratio below 55%'
        WHEN SUM(fe.EXPENSE_AMOUNT) / NULLIF(SUM(fr.REVENUE_AMOUNT), 0) > 0.75 THEN 'WARNING: Ratio above 75%'
        ELSE 'OK'
    END AS STATUS
FROM CURATED.FACT_REVENUE fr
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fr.DATE_KEY
LEFT JOIN (
    SELECT DATE_KEY, SUM(EXPENSE_AMOUNT) AS EXPENSE_AMOUNT
    FROM CURATED.FACT_EXPENSE
    GROUP BY DATE_KEY
) fe ON fe.DATE_KEY = d.DATE_KEY
WHERE d.CALENDAR_DATE >= DATEADD(MONTH, -12, CURRENT_DATE())
GROUP BY d.YEAR_NUMBER, d.QUARTER_NAME
ORDER BY d.YEAR_NUMBER, d.QUARTER_NAME;


-- ############################################################################
-- 3. DATE RANGE CHECK (No Missing Days)
-- ############################################################################
-- Verify DIM_DATE has no gaps, and that fact tables have data for every
-- expected business day. Missing days indicate a failed Geneva export
-- or NetSuite sync.
-- ############################################################################

-- 3A. DIM_DATE continuity check
--     Generates all dates in the expected range and finds any missing from DIM_DATE.
--     Result should be 0 rows. Any rows returned are missing dates.
WITH expected_dates AS (
    SELECT DATEADD(DAY, SEQ4(),
        (SELECT MIN(CALENDAR_DATE) FROM CURATED.DIM_DATE)
    ) AS EXPECTED_DATE
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
)
SELECT
    ed.EXPECTED_DATE AS MISSING_DATE,
    DAYNAME(ed.EXPECTED_DATE) AS DAY_NAME
FROM expected_dates ed
LEFT JOIN CURATED.DIM_DATE d ON d.CALENDAR_DATE = ed.EXPECTED_DATE
WHERE d.DATE_KEY IS NULL
  AND ed.EXPECTED_DATE <= (SELECT MAX(CALENDAR_DATE) FROM CURATED.DIM_DATE)
ORDER BY ed.EXPECTED_DATE;

-- 3B. Revenue: business days with no transactions (last 30 days)
--     Expect revenue on every business day (fee accruals run daily).
--     Missing business days likely mean the Geneva extract failed.
SELECT
    d.CALENDAR_DATE,
    d.DAY_NAME,
    'NO REVENUE DATA' AS STATUS
FROM CURATED.DIM_DATE d
LEFT JOIN CURATED.FACT_REVENUE fr ON fr.DATE_KEY = d.DATE_KEY
WHERE d.CALENDAR_DATE BETWEEN DATEADD(DAY, -30, CURRENT_DATE()) AND CURRENT_DATE()
  AND d.IS_BUSINESS_DAY = TRUE
  AND fr.REVENUE_KEY IS NULL
ORDER BY d.CALENDAR_DATE;

-- 3C. Expense: business days with no transactions (last 30 days)
--     Expenses may legitimately have gaps on some days, but more than
--     3 consecutive business days with zero expenses warrants investigation.
WITH expense_days AS (
    SELECT
        d.CALENDAR_DATE,
        d.IS_BUSINESS_DAY,
        CASE WHEN fe.EXPENSE_KEY IS NOT NULL THEN 1 ELSE 0 END AS HAS_DATA
    FROM CURATED.DIM_DATE d
    LEFT JOIN CURATED.FACT_EXPENSE fe ON fe.DATE_KEY = d.DATE_KEY
    WHERE d.CALENDAR_DATE BETWEEN DATEADD(DAY, -30, CURRENT_DATE()) AND CURRENT_DATE()
      AND d.IS_BUSINESS_DAY = TRUE
),
-- Identify consecutive gaps using a running sum technique
gap_groups AS (
    SELECT
        CALENDAR_DATE,
        HAS_DATA,
        SUM(HAS_DATA) OVER (ORDER BY CALENDAR_DATE) AS GROUP_ID
    FROM expense_days
)
SELECT
    MIN(CALENDAR_DATE) AS GAP_START,
    MAX(CALENDAR_DATE) AS GAP_END,
    COUNT(*) AS CONSECUTIVE_MISSING_DAYS,
    CASE WHEN COUNT(*) >= 3 THEN 'ALERT: 3+ consecutive days missing'
         ELSE 'INFO: minor gap'
    END AS STATUS
FROM gap_groups
WHERE HAS_DATA = 0
GROUP BY GROUP_ID
HAVING COUNT(*) >= 1
ORDER BY GAP_START;

-- 3D. Last date with data per fact table
--     Quick check: is today's data loaded? If MAX date is yesterday
--     after 7 AM ET, the pipeline may be stalled.
SELECT
    'FACT_REVENUE' AS TABLE_NAME,
    MAX(d.CALENDAR_DATE) AS LATEST_DATE,
    DATEDIFF(DAY, MAX(d.CALENDAR_DATE), CURRENT_DATE()) AS DAYS_BEHIND
FROM CURATED.FACT_REVENUE fr
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fr.DATE_KEY
UNION ALL
SELECT
    'FACT_EXPENSE',
    MAX(d.CALENDAR_DATE),
    DATEDIFF(DAY, MAX(d.CALENDAR_DATE), CURRENT_DATE())
FROM CURATED.FACT_EXPENSE fe
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = fe.DATE_KEY
UNION ALL
SELECT
    'FACT_CLIENT_AUM',
    MAX(d.CALENDAR_DATE),
    DATEDIFF(DAY, MAX(d.CALENDAR_DATE), CURRENT_DATE())
FROM CURATED.FACT_CLIENT_AUM aum
JOIN CURATED.DIM_DATE d ON d.DATE_KEY = aum.DATE_KEY;


-- ############################################################################
-- 4. REFERENTIAL INTEGRITY (All Foreign Keys Resolve)
-- ############################################################################
-- Snowflake does not enforce FK constraints at write time. These queries
-- catch orphaned records where a fact row references a dimension key that
-- does not exist. Any rows returned indicate a transformation bug or a
-- missing cross-reference mapping.
-- All queries should return 0 rows.
-- ############################################################################

-- 4A. FACT_REVENUE foreign key checks
SELECT 'FACT_REVENUE → DIM_DATE' AS FK_CHECK, COUNT(*) AS ORPHAN_COUNT
FROM CURATED.FACT_REVENUE fr
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_DATE d WHERE d.DATE_KEY = fr.DATE_KEY)
UNION ALL
SELECT 'FACT_REVENUE → DIM_CLIENT', COUNT(*)
FROM CURATED.FACT_REVENUE fr
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_CLIENT c WHERE c.CLIENT_KEY = fr.CLIENT_KEY)
UNION ALL
SELECT 'FACT_REVENUE → DIM_PRODUCT', COUNT(*)
FROM CURATED.FACT_REVENUE fr
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_PRODUCT p WHERE p.PRODUCT_KEY = fr.PRODUCT_KEY)
UNION ALL
SELECT 'FACT_REVENUE → DIM_GL_ACCOUNT', COUNT(*)
FROM CURATED.FACT_REVENUE fr
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_GL_ACCOUNT gl WHERE gl.GL_ACCOUNT_KEY = fr.GL_ACCOUNT_KEY);

-- 4B. FACT_EXPENSE foreign key checks
SELECT 'FACT_EXPENSE → DIM_DATE' AS FK_CHECK, COUNT(*) AS ORPHAN_COUNT
FROM CURATED.FACT_EXPENSE fe
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_DATE d WHERE d.DATE_KEY = fe.DATE_KEY)
UNION ALL
SELECT 'FACT_EXPENSE → DIM_COST_CENTER', COUNT(*)
FROM CURATED.FACT_EXPENSE fe
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_COST_CENTER cc WHERE cc.COST_CENTER_KEY = fe.COST_CENTER_KEY)
UNION ALL
SELECT 'FACT_EXPENSE → DIM_GL_ACCOUNT', COUNT(*)
FROM CURATED.FACT_EXPENSE fe
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_GL_ACCOUNT gl WHERE gl.GL_ACCOUNT_KEY = fe.GL_ACCOUNT_KEY);

-- 4C. FACT_BUDGET foreign key checks
SELECT 'FACT_BUDGET → DIM_DATE' AS FK_CHECK, COUNT(*) AS ORPHAN_COUNT
FROM CURATED.FACT_BUDGET fb
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_DATE d WHERE d.DATE_KEY = fb.DATE_KEY)
UNION ALL
SELECT 'FACT_BUDGET → DIM_GL_ACCOUNT', COUNT(*)
FROM CURATED.FACT_BUDGET fb
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_GL_ACCOUNT gl WHERE gl.GL_ACCOUNT_KEY = fb.GL_ACCOUNT_KEY)
UNION ALL
SELECT 'FACT_BUDGET → DIM_COST_CENTER', COUNT(*)
FROM CURATED.FACT_BUDGET fb
WHERE fb.COST_CENTER_KEY IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM CURATED.DIM_COST_CENTER cc WHERE cc.COST_CENTER_KEY = fb.COST_CENTER_KEY)
UNION ALL
SELECT 'FACT_BUDGET → DIM_PRODUCT', COUNT(*)
FROM CURATED.FACT_BUDGET fb
WHERE fb.PRODUCT_KEY IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM CURATED.DIM_PRODUCT p WHERE p.PRODUCT_KEY = fb.PRODUCT_KEY);

-- 4D. FACT_CLIENT_AUM foreign key checks
SELECT 'FACT_CLIENT_AUM → DIM_DATE' AS FK_CHECK, COUNT(*) AS ORPHAN_COUNT
FROM CURATED.FACT_CLIENT_AUM aum
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_DATE d WHERE d.DATE_KEY = aum.DATE_KEY)
UNION ALL
SELECT 'FACT_CLIENT_AUM → DIM_CLIENT', COUNT(*)
FROM CURATED.FACT_CLIENT_AUM aum
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_CLIENT c WHERE c.CLIENT_KEY = aum.CLIENT_KEY)
UNION ALL
SELECT 'FACT_CLIENT_AUM → DIM_PRODUCT', COUNT(*)
FROM CURATED.FACT_CLIENT_AUM aum
WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_PRODUCT p WHERE p.PRODUCT_KEY = aum.PRODUCT_KEY);

-- 4E. Cross-reference coverage
--     Check that every CURATED dimension key has a mapping in ENTITY_CROSSREF.
--     Missing entries mean new source records that haven't been mapped yet.
SELECT
    'Unmapped Clients (no Geneva ID)' AS CHECK_NAME,
    COUNT(*) AS UNMAPPED_COUNT
FROM CURATED.DIM_CLIENT dc
LEFT JOIN CURATED.ENTITY_CROSSREF xref
    ON xref.CURATED_KEY = dc.CLIENT_KEY AND xref.ENTITY_TYPE = 'CLIENT'
WHERE xref.GENEVA_ID IS NULL
UNION ALL
SELECT
    'Unmapped Clients (no Salesforce ID)',
    COUNT(*)
FROM CURATED.DIM_CLIENT dc
LEFT JOIN CURATED.ENTITY_CROSSREF xref
    ON xref.CURATED_KEY = dc.CLIENT_KEY AND xref.ENTITY_TYPE = 'CLIENT'
WHERE xref.SALESFORCE_ID IS NULL
UNION ALL
SELECT
    'Unverified Crossref Entries',
    COUNT(*)
FROM CURATED.ENTITY_CROSSREF
WHERE VERIFIED = FALSE;


-- ############################################################################
-- 5. DATA FRESHNESS (Last Update Timestamps)
-- ############################################################################
-- Verify that each pipeline stage is running on schedule.
-- Run after expected completion times:
--   Geneva:     7:00 AM ET (daily batch, expect data by 6:15 AM)
--   NetSuite:   Every 4 hrs (6AM, 10AM, 2PM, 6PM, 10PM)
--   Salesforce:  Continuous (CDC, expect < 5 min lag)
-- ############################################################################

-- 5A. RAW table freshness
--     Shows the most recent record loaded into each RAW table.
--     MINUTES_AGO > 60 for CDC tables or > 300 for batch tables = stale.
SELECT
    'GENEVA_TRANSACTIONS' AS RAW_TABLE,
    MAX(_LOADED_AT) AS LAST_LOADED,
    DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()) AS MINUTES_AGO,
    CASE
        WHEN DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()) > 1500 THEN 'STALE (>25 hrs)'
        ELSE 'OK (daily batch)'
    END AS STATUS
FROM RAW.GENEVA_TRANSACTIONS
UNION ALL
SELECT
    'NETSUITE_TRANSACTIONS',
    MAX(_LOADED_AT),
    DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()),
    CASE
        WHEN DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()) > 300 THEN 'STALE (>5 hrs)'
        ELSE 'OK (4-hr sync)'
    END
FROM RAW.NETSUITE_TRANSACTIONS
UNION ALL
SELECT
    'SALESFORCE_ACCOUNTS',
    MAX(_LOADED_AT),
    DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()),
    CASE
        WHEN DATEDIFF(MINUTE, MAX(_LOADED_AT), CURRENT_TIMESTAMP()) > 60 THEN 'STALE (>1 hr)'
        ELSE 'OK (CDC ~5 min)'
    END
FROM RAW.SALESFORCE_ACCOUNTS;

-- 5B. Dynamic Table refresh status
--     Shows when each Dynamic Table last refreshed and whether it is healthy.
--     SUSPENDED or FAILED status requires immediate investigation.
SELECT
    NAME AS DYNAMIC_TABLE,
    SCHEDULING_STATE,
    LAST_COMPLETED_REFRESH_STATE AS LAST_REFRESH_STATUS,
    LAST_COMPLETED_REFRESH_END_TIME AS LAST_REFRESH_TIME,
    DATEDIFF(MINUTE, LAST_COMPLETED_REFRESH_END_TIME, CURRENT_TIMESTAMP()) AS MINUTES_SINCE_REFRESH,
    TARGET_LAG,
    CASE
        WHEN SCHEDULING_STATE != 'ACTIVE' THEN 'ALERT: Not active'
        WHEN LAST_COMPLETED_REFRESH_STATE = 'FAILED' THEN 'ALERT: Last refresh failed'
        WHEN DATEDIFF(MINUTE, LAST_COMPLETED_REFRESH_END_TIME, CURRENT_TIMESTAMP()) > 30
            THEN 'WARNING: Behind target lag'
        ELSE 'OK'
    END AS STATUS
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLES())
WHERE CATALOG_NAME = 'PINNACLE_FINANCIAL'
ORDER BY NAME;

-- 5C. Snowpipe status (Geneva ingestion)
--     Check for load errors in the last 24 hours.
--     Any rows with STATUS = 'LOAD_FAILED' need investigation.
SELECT
    PIPE_NAME,
    FILE_NAME,
    STATUS,
    ROW_COUNT,
    ERROR_COUNT,
    FIRST_ERROR_MESSAGE,
    LAST_LOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'RAW.GENEVA_TRANSACTIONS',
    START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
))
WHERE ERROR_COUNT > 0
ORDER BY LAST_LOAD_TIME DESC;

-- 5D. Connector sync status (NetSuite + Salesforce)
--     Check the last successful sync for each connector.
--     If last sync is older than expected cadence, the connector may be down.
SELECT
    CONNECTOR_NAME,
    LAST_SUCCESSFUL_SYNC,
    DATEDIFF(MINUTE, LAST_SUCCESSFUL_SYNC, CURRENT_TIMESTAMP()) AS MINUTES_SINCE_SYNC,
    SYNC_STATUS,
    CASE
        WHEN SYNC_STATUS != 'SUCCESS' THEN 'ALERT: Sync failed'
        WHEN CONNECTOR_NAME ILIKE '%netsuite%'
            AND DATEDIFF(MINUTE, LAST_SUCCESSFUL_SYNC, CURRENT_TIMESTAMP()) > 300
            THEN 'STALE (>5 hrs, expect 4-hr cadence)'
        WHEN CONNECTOR_NAME ILIKE '%salesforce%'
            AND DATEDIFF(MINUTE, LAST_SUCCESSFUL_SYNC, CURRENT_TIMESTAMP()) > 30
            THEN 'STALE (>30 min, expect near real-time)'
        ELSE 'OK'
    END AS STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.CONNECTOR_HISTORY
WHERE CONNECTOR_NAME ILIKE ANY ('%netsuite%', '%salesforce%')
QUALIFY ROW_NUMBER() OVER (PARTITION BY CONNECTOR_NAME ORDER BY LAST_SUCCESSFUL_SYNC DESC) = 1;

-- 5E. End-to-end latency check
--     Measures time from source system change to CURATED availability.
--     Compare _LOADED_AT (RAW arrival) to CREATED_AT (CURATED write).
SELECT
    'Revenue (Geneva → CURATED)' AS PIPELINE,
    ROUND(AVG(DATEDIFF(MINUTE, gt._LOADED_AT, fr.CREATED_AT)), 1) AS AVG_LATENCY_MIN,
    MAX(DATEDIFF(MINUTE, gt._LOADED_AT, fr.CREATED_AT)) AS MAX_LATENCY_MIN
FROM CURATED.FACT_REVENUE fr
JOIN RAW.GENEVA_TRANSACTIONS gt ON gt.TRANSACTION_ID = fr.TRANSACTION_ID
WHERE fr.CREATED_AT >= DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
UNION ALL
SELECT
    'Expenses (NetSuite → CURATED)',
    ROUND(AVG(DATEDIFF(MINUTE, ntl._LOADED_AT, fe.CREATED_AT)), 1),
    MAX(DATEDIFF(MINUTE, ntl._LOADED_AT, fe.CREATED_AT))
FROM CURATED.FACT_EXPENSE fe
JOIN RAW.NETSUITE_TRANSACTION_LINES ntl
    ON 'NS-' || ntl.TRANID = fe.TRANSACTION_ID
WHERE fe.CREATED_AT >= DATEADD(HOUR, -24, CURRENT_TIMESTAMP());


-- ############################################################################
-- 6. COMBINED HEALTH DASHBOARD
-- ############################################################################
-- Single query that produces a pass/fail summary for all checks.
-- Schedule this as a Snowflake Task running every 30 minutes.
-- Route failures to Slack #data-ops via notification integration.
-- ############################################################################

WITH checks AS (
    -- Check 1: Orphan revenue FKs
    SELECT 'FK: Revenue → Client' AS CHECK_NAME,
           COUNT(*) AS FAIL_COUNT
    FROM CURATED.FACT_REVENUE fr
    WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_CLIENT c WHERE c.CLIENT_KEY = fr.CLIENT_KEY)

    UNION ALL
    SELECT 'FK: Revenue → Product',
           COUNT(*)
    FROM CURATED.FACT_REVENUE fr
    WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_PRODUCT p WHERE p.PRODUCT_KEY = fr.PRODUCT_KEY)

    UNION ALL
    SELECT 'FK: Revenue → Date',
           COUNT(*)
    FROM CURATED.FACT_REVENUE fr
    WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_DATE d WHERE d.DATE_KEY = fr.DATE_KEY)

    UNION ALL
    SELECT 'FK: Expense → Cost Center',
           COUNT(*)
    FROM CURATED.FACT_EXPENSE fe
    WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_COST_CENTER cc WHERE cc.COST_CENTER_KEY = fe.COST_CENTER_KEY)

    UNION ALL
    SELECT 'FK: Expense → GL Account',
           COUNT(*)
    FROM CURATED.FACT_EXPENSE fe
    WHERE NOT EXISTS (SELECT 1 FROM CURATED.DIM_GL_ACCOUNT gl WHERE gl.GL_ACCOUNT_KEY = fe.GL_ACCOUNT_KEY)

    UNION ALL
    -- Check 2: NULL amounts
    SELECT 'NULL: Revenue Amount',
           COUNT(*)
    FROM CURATED.FACT_REVENUE WHERE REVENUE_AMOUNT IS NULL

    UNION ALL
    SELECT 'NULL: Expense Amount',
           COUNT(*)
    FROM CURATED.FACT_EXPENSE WHERE EXPENSE_AMOUNT IS NULL

    UNION ALL
    -- Check 3: Duplicate transactions
    SELECT 'DUP: Revenue Transactions',
           COUNT(*)
    FROM (
        SELECT TRANSACTION_ID
        FROM CURATED.FACT_REVENUE
        GROUP BY TRANSACTION_ID
        HAVING COUNT(*) > 1
    )

    UNION ALL
    SELECT 'DUP: Expense Transactions',
           COUNT(*)
    FROM (
        SELECT TRANSACTION_ID
        FROM CURATED.FACT_EXPENSE
        GROUP BY TRANSACTION_ID
        HAVING COUNT(*) > 1
    )

    UNION ALL
    -- Check 4: Negative amounts (should not exist)
    SELECT 'NEG: Revenue Amount',
           COUNT(*)
    FROM CURATED.FACT_REVENUE WHERE REVENUE_AMOUNT < 0

    UNION ALL
    SELECT 'NEG: Expense Amount',
           COUNT(*)
    FROM CURATED.FACT_EXPENSE WHERE EXPENSE_AMOUNT < 0
)
SELECT
    CHECK_NAME,
    FAIL_COUNT,
    CASE WHEN FAIL_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS,
    CURRENT_TIMESTAMP() AS CHECKED_AT
FROM checks
ORDER BY STATUS DESC, CHECK_NAME;
