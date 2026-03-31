# Pinnacle Financial Services -- Data Mapping Document

**Purpose:** Column-level mapping from source systems to Snowflake CURATED tables.
**Companion to:** `integration-guide.md` (see Section 5 for transformation logic overview)

---

## 1. Client Master Data: Salesforce --> DIM_CLIENT

### Source Tables

| RAW Table | Source Object | Refresh | Notes |
|---|---|---|---|
| `RAW.SALESFORCE_ACCOUNTS` | `Account` | CDC (~5 min) | Primary client record |
| `RAW.SALESFORCE_FINANCIAL_ACCOUNTS` | `Financial_Account__c` | CDC (~5 min) | Investment accounts with AUM, strategy |
| `RAW.SALESFORCE_USERS` | `User` | Daily full sync | Relationship manager lookup |

### Column Mapping

| Target Column | Type | Source Table | Source Column | Transform | Notes |
|---|---|---|---|---|---|
| `CLIENT_KEY` | `INT PK` | -- | -- | `ROW_NUMBER() OVER (ORDER BY a.Id)` | Generated surrogate key. Stable ordering by Salesforce ID. |
| `CLIENT_ID` | `VARCHAR(20)` | `SALESFORCE_ACCOUNTS` | `Account_Number__c` | Direct map. If NULL, use `'SF-' \|\| LEFT(a.Id, 15)` | Business identifier. Prefer custom account number field. |
| `CLIENT_NAME` | `VARCHAR(200)` | `SALESFORCE_ACCOUNTS` | `Name` | `TRIM(a.Name)` | Full legal name of client or entity. |
| `CLIENT_SEGMENT` | `VARCHAR(50)` | `SALESFORCE_ACCOUNTS` | `Type` | `CASE a.Type WHEN 'Individual' THEN 'Individual' WHEN 'Institution' THEN 'Institutional' WHEN 'Family Office' THEN 'Family Office' ELSE 'Other' END` | Normalize Salesforce picklist values to Pinnacle segments. |
| `RELATIONSHIP_START_DATE` | `DATE` | `SALESFORCE_ACCOUNTS` | `CreatedDate` | `a.CreatedDate::DATE` | Account creation date as proxy for relationship start. Override with custom field if available. |
| `RELATIONSHIP_MANAGER` | `VARCHAR(100)` | `SALESFORCE_USERS` | `Name` | `JOIN SALESFORCE_USERS u ON a.OwnerId = u.Id` then `u.Name` | Account owner = relationship manager. |
| `OFFICE_LOCATION` | `VARCHAR(50)` | `SALESFORCE_ACCOUNTS` | `BillingCity` | `CASE WHEN a.BillingCity ILIKE '%new york%' THEN 'New York' WHEN a.BillingCity ILIKE '%boston%' THEN 'Boston' WHEN a.BillingCity ILIKE '%san fran%' THEN 'San Francisco' ELSE a.BillingCity END` | Normalize city names to Pinnacle office locations. |
| `AUM_TIER` | `VARCHAR(20)` | `SALESFORCE_FINANCIAL_ACCOUNTS` | `Total_AUM__c` | `CASE WHEN client_aum > 50000000 THEN 'Platinum' WHEN client_aum > 10000000 THEN 'Gold' ELSE 'Silver' END` where `client_aum = SUM(fa.Total_AUM__c)` grouped by Account | Derived from aggregated AUM across all financial accounts for the client. |
| `IS_ACTIVE` | `BOOLEAN` | `SALESFORCE_ACCOUNTS` | `IsActive__c` or `Status__c` | `COALESCE(a.IsActive__c, a.Status__c = 'Active', TRUE)` | Check custom active flag first, then status picklist, default TRUE. |
| `CREATED_AT` | `TIMESTAMP_NTZ` | -- | -- | `CURRENT_TIMESTAMP()` | Snowflake record creation time. |

### Join Logic

```sql
-- DIM_CLIENT Dynamic Table (simplified)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.ID) AS CLIENT_KEY,
    COALESCE(a.ACCOUNT_NUMBER__C, 'SF-' || LEFT(a.ID, 15)) AS CLIENT_ID,
    TRIM(a.NAME) AS CLIENT_NAME,
    CASE a.TYPE
        WHEN 'Individual' THEN 'Individual'
        WHEN 'Institution' THEN 'Institutional'
        WHEN 'Family Office' THEN 'Family Office'
        ELSE 'Other'
    END AS CLIENT_SEGMENT,
    a.CREATEDDATE::DATE AS RELATIONSHIP_START_DATE,
    u.NAME AS RELATIONSHIP_MANAGER,
    CASE
        WHEN a.BILLINGCITY ILIKE '%new york%' THEN 'New York'
        WHEN a.BILLINGCITY ILIKE '%boston%' THEN 'Boston'
        WHEN a.BILLINGCITY ILIKE '%san fran%' THEN 'San Francisco'
        ELSE a.BILLINGCITY
    END AS OFFICE_LOCATION,
    CASE
        WHEN SUM(fa.TOTAL_AUM__C) > 50000000 THEN 'Platinum'
        WHEN SUM(fa.TOTAL_AUM__C) > 10000000 THEN 'Gold'
        ELSE 'Silver'
    END AS AUM_TIER,
    COALESCE(a.ISACTIVE__C, TRUE) AS IS_ACTIVE,
    CURRENT_TIMESTAMP() AS CREATED_AT
FROM RAW.SALESFORCE_ACCOUNTS a
LEFT JOIN RAW.SALESFORCE_USERS u ON a.OWNERID = u.ID
LEFT JOIN RAW.SALESFORCE_FINANCIAL_ACCOUNTS fa ON fa.ACCOUNT__C = a.ID
WHERE a.RECORDTYPEID IN (<client_record_type_ids>)  -- Filter to client records only
GROUP BY a.ID, a.ACCOUNT_NUMBER__C, a.NAME, a.TYPE, a.CREATEDDATE,
         u.NAME, a.BILLINGCITY, a.ISACTIVE__C;
```

### Validation Rules

| Check | SQL | Expected |
|---|---|---|
| No NULL client names | `SELECT COUNT(*) FROM CURATED.DIM_CLIENT WHERE CLIENT_NAME IS NULL` | 0 |
| Valid segments only | `SELECT DISTINCT CLIENT_SEGMENT FROM CURATED.DIM_CLIENT` | Individual, Institutional, Family Office, Other |
| Valid AUM tiers | `SELECT DISTINCT AUM_TIER FROM CURATED.DIM_CLIENT` | Platinum, Gold, Silver |
| Row count vs Salesforce | `SELECT COUNT(*) FROM CURATED.DIM_CLIENT` vs Salesforce Account report | Match within 1% (excludes non-client record types) |
| No duplicate CLIENT_ID | `SELECT CLIENT_ID, COUNT(*) FROM CURATED.DIM_CLIENT GROUP BY 1 HAVING COUNT(*) > 1` | 0 rows |

---

## 2. Revenue Data: Geneva --> FACT_REVENUE

### Source Tables

| RAW Table | Source File | Refresh | Notes |
|---|---|---|---|
| `RAW.GENEVA_TRANSACTIONS` | Geneva fee transaction export | Daily batch 6 AM ET | Fee accrual and payment events |
| `RAW.GENEVA_NAV` | Geneva NAV/valuation export | Daily batch 6 AM ET | AUM at time of fee calculation |
| `RAW.GENEVA_FEE_SCHEDULES` | Geneva fee schedule export | Daily batch (full replace) | Fee rates by account and product |
| `CURATED.DIM_DATE` | -- | Generated | Date dimension lookup |
| `CURATED.DIM_CLIENT` | -- | Dynamic Table | Client dimension lookup (via ENTITY_CROSSREF) |
| `CURATED.DIM_PRODUCT` | -- | Dynamic Table | Product dimension lookup (via ENTITY_CROSSREF) |
| `CURATED.DIM_GL_ACCOUNT` | -- | Dynamic Table | GL account lookup |
| `CURATED.ENTITY_CROSSREF` | -- | Dynamic Table | Geneva-to-Snowflake key resolution |

### Column Mapping

| Target Column | Type | Source Table | Source Column | Transform | Notes |
|---|---|---|---|---|---|
| `REVENUE_KEY` | `INT PK AUTO` | -- | -- | `AUTOINCREMENT` | System-generated surrogate key. |
| `DATE_KEY` | `INT FK` | `GENEVA_TRANSACTIONS` | `transaction_date` | `JOIN DIM_DATE d ON d.CALENDAR_DATE = gt.TRANSACTION_DATE::DATE` then `d.DATE_KEY` | Resolve calendar date to date dimension key. |
| `CLIENT_KEY` | `INT FK` | `GENEVA_TRANSACTIONS` | `account_id` | `JOIN ENTITY_CROSSREF xref ON xref.GENEVA_ID = gt.ACCOUNT_ID AND xref.ENTITY_TYPE = 'CLIENT'` then `xref.CURATED_KEY` | Resolve Geneva account to DIM_CLIENT via cross-reference table. |
| `PRODUCT_KEY` | `INT FK` | `GENEVA_TRANSACTIONS` | `strategy_id` | `JOIN ENTITY_CROSSREF xref ON xref.GENEVA_ID = gt.STRATEGY_ID AND xref.ENTITY_TYPE = 'PRODUCT'` then `xref.CURATED_KEY` | Resolve Geneva strategy to DIM_PRODUCT via cross-reference table. |
| `GL_ACCOUNT_KEY` | `INT FK` | `GENEVA_FEE_SCHEDULES` | `fee_type` | `CASE fs.FEE_TYPE WHEN 'Management' THEN gl_key_4010 WHEN 'Performance' THEN gl_key_4020 WHEN 'Advisory' THEN gl_key_4030 WHEN 'Transaction' THEN gl_key_4040 END` | Map fee type to GL revenue account. Join to DIM_GL_ACCOUNT on GL_ACCOUNT_ID. |
| `TRANSACTION_ID` | `VARCHAR(50)` | `GENEVA_TRANSACTIONS` | `transaction_id` | `gt.TRANSACTION_ID` | Direct map. Unique per Geneva fee event. Used for deduplication. |
| `AUM_AMOUNT` | `DECIMAL(18,2)` | `GENEVA_NAV` | `market_value` | `JOIN GENEVA_NAV nav ON nav.ACCOUNT_ID = gt.ACCOUNT_ID AND nav.VALUATION_DATE = gt.TRANSACTION_DATE` then `nav.MARKET_VALUE` | AUM at time of fee calculation. Join on account + date. |
| `REVENUE_AMOUNT` | `DECIMAL(18,2)` | `GENEVA_TRANSACTIONS` | `fee_amount` | `ROUND(gt.FEE_AMOUNT, 2)`. Validate: should approximate `AUM_AMOUNT * FEE_BASIS_POINTS / 10000 / 12` | Fee revenue in dollars. Round to 2 decimal places. Cross-check against computed value. |
| `FEE_BASIS_POINTS` | `DECIMAL(8,4)` | `GENEVA_FEE_SCHEDULES` | `fee_rate_bps` | `JOIN GENEVA_FEE_SCHEDULES fs ON fs.ACCOUNT_ID = gt.ACCOUNT_ID AND fs.STRATEGY_ID = gt.STRATEGY_ID` then `fs.FEE_RATE_BPS` | Fee rate from schedule. If multiple schedules match, use the one with the latest `effective_date <= transaction_date`. |
| `TRANSACTION_COUNT` | `INT` | -- | -- | `1` | Default 1 per transaction row. Aggregation metric. |
| `CREATED_AT` | `TIMESTAMP_NTZ` | -- | -- | `CURRENT_TIMESTAMP()` | Snowflake record creation time. |

### Join Logic

```sql
-- FACT_REVENUE Dynamic Table (simplified)
SELECT
    d.DATE_KEY,
    xref_client.CURATED_KEY AS CLIENT_KEY,
    xref_product.CURATED_KEY AS PRODUCT_KEY,
    gl.GL_ACCOUNT_KEY,
    gt.TRANSACTION_ID,
    nav.MARKET_VALUE AS AUM_AMOUNT,
    ROUND(gt.FEE_AMOUNT, 2) AS REVENUE_AMOUNT,
    fs.FEE_RATE_BPS AS FEE_BASIS_POINTS,
    1 AS TRANSACTION_COUNT,
    CURRENT_TIMESTAMP() AS CREATED_AT
FROM RAW.GENEVA_TRANSACTIONS gt
-- Date resolution
JOIN CURATED.DIM_DATE d
    ON d.CALENDAR_DATE = gt.TRANSACTION_DATE::DATE
-- Client resolution (Geneva account → DIM_CLIENT)
JOIN CURATED.ENTITY_CROSSREF xref_client
    ON xref_client.GENEVA_ID = gt.ACCOUNT_ID
    AND xref_client.ENTITY_TYPE = 'CLIENT'
-- Product resolution (Geneva strategy → DIM_PRODUCT)
JOIN CURATED.ENTITY_CROSSREF xref_product
    ON xref_product.GENEVA_ID = gt.STRATEGY_ID
    AND xref_product.ENTITY_TYPE = 'PRODUCT'
-- AUM at time of fee
LEFT JOIN RAW.GENEVA_NAV nav
    ON nav.ACCOUNT_ID = gt.ACCOUNT_ID
    AND nav.VALUATION_DATE = gt.TRANSACTION_DATE
-- Fee rate from schedule
LEFT JOIN RAW.GENEVA_FEE_SCHEDULES fs
    ON fs.ACCOUNT_ID = gt.ACCOUNT_ID
    AND fs.STRATEGY_ID = gt.STRATEGY_ID
    AND fs.EFFECTIVE_DATE = (
        SELECT MAX(fs2.EFFECTIVE_DATE)
        FROM RAW.GENEVA_FEE_SCHEDULES fs2
        WHERE fs2.ACCOUNT_ID = gt.ACCOUNT_ID
          AND fs2.STRATEGY_ID = gt.STRATEGY_ID
          AND fs2.EFFECTIVE_DATE <= gt.TRANSACTION_DATE
    )
-- GL account from fee type
JOIN CURATED.DIM_GL_ACCOUNT gl
    ON gl.GL_ACCOUNT_ID = CASE fs.FEE_TYPE
        WHEN 'Management'  THEN '4010'
        WHEN 'Performance' THEN '4020'
        WHEN 'Advisory'    THEN '4030'
        WHEN 'Transaction' THEN '4040'
    END
WHERE gt.TRANSACTION_TYPE = 'FEE'  -- Filter to fee events only
QUALIFY ROW_NUMBER() OVER (PARTITION BY gt.TRANSACTION_ID ORDER BY gt._LOADED_AT DESC) = 1;
    -- Deduplicate: keep latest load if reprocessed
```

### Validation Rules

| Check | SQL | Expected |
|---|---|---|
| No orphan dates | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE DATE_KEY NOT IN (SELECT DATE_KEY FROM CURATED.DIM_DATE)` | 0 |
| No orphan clients | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE CLIENT_KEY NOT IN (SELECT CLIENT_KEY FROM CURATED.DIM_CLIENT)` | 0 |
| No NULL revenue | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE REVENUE_AMOUNT IS NULL` | 0 |
| Revenue positive | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE REVENUE_AMOUNT < 0` | 0 (fees should not be negative; refunds go through a separate process) |
| No duplicate txns | `SELECT TRANSACTION_ID, COUNT(*) FROM CURATED.FACT_REVENUE GROUP BY 1 HAVING COUNT(*) > 1` | 0 rows |
| Daily total vs Geneva | `SELECT SUM(REVENUE_AMOUNT) FROM CURATED.FACT_REVENUE WHERE DATE_KEY = <today>` vs Geneva fee report | Match within $1 |
| Fee rate sanity | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE FEE_BASIS_POINTS < 0 OR FEE_BASIS_POINTS > 500` | 0 (rates above 500 bps are unrealistic for Pinnacle) |
| AUM vs revenue consistency | `SELECT COUNT(*) FROM CURATED.FACT_REVENUE WHERE ABS(REVENUE_AMOUNT - (AUM_AMOUNT * FEE_BASIS_POINTS / 10000 / 12)) > 100` | 0 (tolerance: $100 rounding difference) |

---

## 3. Expense Data: NetSuite --> FACT_EXPENSE

### Source Tables

| RAW Table | Source Object | Refresh | Notes |
|---|---|---|---|
| `RAW.NETSUITE_TRANSACTIONS` | `transaction` | Incremental (4-hour CDC) | GL journal entries, invoices, payments |
| `RAW.NETSUITE_TRANSACTION_LINES` | `transactionline` | Incremental (4-hour CDC) | Line-level detail: amount, account, department |
| `RAW.NETSUITE_VENDORS` | `vendor` | Full sync (4-hour) | Vendor/payee reference |
| `CURATED.DIM_DATE` | -- | Generated | Date dimension lookup |
| `CURATED.DIM_COST_CENTER` | -- | Dynamic Table | Cost center lookup (from NetSuite departments) |
| `CURATED.DIM_GL_ACCOUNT` | -- | Dynamic Table | GL account lookup |

### Column Mapping

| Target Column | Type | Source Table | Source Column | Transform | Notes |
|---|---|---|---|---|---|
| `EXPENSE_KEY` | `INT PK AUTO` | -- | -- | `AUTOINCREMENT` | System-generated surrogate key. |
| `DATE_KEY` | `INT FK` | `NETSUITE_TRANSACTIONS` | `trandate` | `JOIN DIM_DATE d ON d.CALENDAR_DATE = nt.TRANDATE::DATE` then `d.DATE_KEY` | Transaction date to date dimension. |
| `COST_CENTER_KEY` | `INT FK` | `NETSUITE_TRANSACTION_LINES` | `department` | `JOIN DIM_COST_CENTER cc ON cc.COST_CENTER_ID = 'CC-' \|\| LPAD(ntl.DEPARTMENT, 3, '0')` then `cc.COST_CENTER_KEY` | Map NetSuite department internal ID to DIM_COST_CENTER. ID format: `CC-` + zero-padded department ID. |
| `GL_ACCOUNT_KEY` | `INT FK` | `NETSUITE_TRANSACTION_LINES` | `account` | `JOIN DIM_GL_ACCOUNT gl ON gl.GL_ACCOUNT_ID = na.ACCTNUMBER` via `JOIN NETSUITE_ACCOUNTS na ON na.ID = ntl.ACCOUNT` | Resolve line-level account to DIM_GL_ACCOUNT. Two-hop join: line → NetSuite account → DIM_GL_ACCOUNT. |
| `TRANSACTION_ID` | `VARCHAR(50)` | `NETSUITE_TRANSACTIONS` | `tranid` | `'NS-' \|\| nt.TRANID` | Prefix with `NS-` to namespace. NetSuite `tranid` is the user-visible document number. |
| `EXPENSE_AMOUNT` | `DECIMAL(18,2)` | `NETSUITE_TRANSACTION_LINES` | `debitamount` / `creditamount` | `ROUND(COALESCE(ntl.DEBITAMOUNT, 0) - COALESCE(ntl.CREDITAMOUNT, 0), 2)` | Expense = debit - credit for expense accounts (normal balance is debit). Positive = expense incurred. |
| `VENDOR_NAME` | `VARCHAR(200)` | `NETSUITE_VENDORS` | `companyname` | `JOIN NETSUITE_VENDORS v ON v.ID = nt.ENTITY` then `v.COMPANYNAME` | Vendor lookup from transaction entity. NULL for non-vendor transactions (payroll, accruals). |
| `DESCRIPTION` | `VARCHAR(500)` | `NETSUITE_TRANSACTION_LINES` | `memo` | `COALESCE(ntl.MEMO, nt.MEMO, 'No description')` | Line-level memo preferred. Fall back to header memo. |
| `PAYMENT_STATUS` | `VARCHAR(20)` | `NETSUITE_TRANSACTIONS` | `status` | `CASE nt.STATUS WHEN 'Paid In Full' THEN 'Paid' WHEN 'Open' THEN 'Pending' WHEN 'Pending Approval' THEN 'Pending' ELSE 'Accrued' END` | Normalize NetSuite statuses to Pinnacle terms: Paid, Pending, Accrued. |
| `CREATED_AT` | `TIMESTAMP_NTZ` | -- | -- | `CURRENT_TIMESTAMP()` | Snowflake record creation time. |

### Join Logic

```sql
-- FACT_EXPENSE Dynamic Table (simplified)
SELECT
    d.DATE_KEY,
    cc.COST_CENTER_KEY,
    gl.GL_ACCOUNT_KEY,
    'NS-' || nt.TRANID AS TRANSACTION_ID,
    ROUND(COALESCE(ntl.DEBITAMOUNT, 0) - COALESCE(ntl.CREDITAMOUNT, 0), 2) AS EXPENSE_AMOUNT,
    v.COMPANYNAME AS VENDOR_NAME,
    COALESCE(ntl.MEMO, nt.MEMO, 'No description') AS DESCRIPTION,
    CASE nt.STATUS
        WHEN 'Paid In Full'      THEN 'Paid'
        WHEN 'Open'              THEN 'Pending'
        WHEN 'Pending Approval'  THEN 'Pending'
        ELSE 'Accrued'
    END AS PAYMENT_STATUS,
    CURRENT_TIMESTAMP() AS CREATED_AT
FROM RAW.NETSUITE_TRANSACTION_LINES ntl
-- Header join
JOIN RAW.NETSUITE_TRANSACTIONS nt
    ON nt.ID = ntl.TRANSACTION
-- Date resolution
JOIN CURATED.DIM_DATE d
    ON d.CALENDAR_DATE = nt.TRANDATE::DATE
-- GL account resolution (two-hop: line account ID → NetSuite account → DIM_GL_ACCOUNT)
JOIN RAW.NETSUITE_ACCOUNTS na
    ON na.ID = ntl.ACCOUNT
JOIN CURATED.DIM_GL_ACCOUNT gl
    ON gl.GL_ACCOUNT_ID = na.ACCTNUMBER
-- Cost center resolution
LEFT JOIN CURATED.DIM_COST_CENTER cc
    ON cc.COST_CENTER_ID = 'CC-' || LPAD(ntl.DEPARTMENT::VARCHAR, 3, '0')
-- Vendor lookup
LEFT JOIN RAW.NETSUITE_VENDORS v
    ON v.ID = nt.ENTITY
-- Filter to expense accounts only (5xxx-7xxx)
WHERE na.ACCTNUMBER >= '5000' AND na.ACCTNUMBER < '8000'
  -- Exclude voided/reversed transactions
  AND nt.VOIDED = 'No'
  -- Deduplicate on reprocessing
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY nt.TRANID, ntl.LINE_SEQUENCE
    ORDER BY ntl._LOADED_AT DESC
) = 1;
```

### Validation Rules

| Check | SQL | Expected |
|---|---|---|
| No orphan dates | `SELECT COUNT(*) FROM CURATED.FACT_EXPENSE WHERE DATE_KEY NOT IN (SELECT DATE_KEY FROM CURATED.DIM_DATE)` | 0 |
| No NULL expense amt | `SELECT COUNT(*) FROM CURATED.FACT_EXPENSE WHERE EXPENSE_AMOUNT IS NULL` | 0 |
| Expense positive | `SELECT COUNT(*) FROM CURATED.FACT_EXPENSE WHERE EXPENSE_AMOUNT < 0` | 0 (credits/refunds should net, not go negative) |
| Valid payment status | `SELECT DISTINCT PAYMENT_STATUS FROM CURATED.FACT_EXPENSE` | Paid, Pending, Accrued |
| GL accounts in range | `SELECT COUNT(*) FROM CURATED.FACT_EXPENSE fe JOIN CURATED.DIM_GL_ACCOUNT gl ON fe.GL_ACCOUNT_KEY = gl.GL_ACCOUNT_KEY WHERE gl.GL_ACCOUNT_ID < '5000' OR gl.GL_ACCOUNT_ID >= '8000'` | 0 |
| No duplicate lines | `SELECT TRANSACTION_ID, COUNT(*) FROM CURATED.FACT_EXPENSE GROUP BY 1 HAVING COUNT(*) > (SELECT MAX(line_count) FROM ...)` | Investigate any txn with more lines than expected |
| Monthly total vs NetSuite | `SELECT SUM(EXPENSE_AMOUNT) FROM CURATED.FACT_EXPENSE WHERE DATE_KEY BETWEEN <month_start> AND <month_end>` vs NetSuite P&L report | Match within $10 |
| Expense ratio sanity | `Total expenses / total revenue` | Between 0.55 and 0.75 (Pinnacle target: ~65%) |

---

## Appendix: Cross-Reference Key Resolution

All three mappings above depend on `CURATED.ENTITY_CROSSREF` to resolve source system IDs to Snowflake surrogate keys.

### ENTITY_CROSSREF Structure

| Column | Type | Description |
|---|---|---|
| `CROSSREF_KEY` | `INT PK` | Surrogate key |
| `ENTITY_TYPE` | `VARCHAR(20)` | `CLIENT`, `PRODUCT`, `GL_ACCOUNT`, `COST_CENTER` |
| `GENEVA_ID` | `VARCHAR(50)` | Geneva account_id or strategy_id (NULL if no Geneva record) |
| `NETSUITE_ID` | `VARCHAR(50)` | NetSuite internal ID (NULL if no NetSuite record) |
| `SALESFORCE_ID` | `VARCHAR(50)` | Salesforce 18-char record ID (NULL if no Salesforce record) |
| `CURATED_KEY` | `INT` | FK to the corresponding DIM table (DIM_CLIENT.CLIENT_KEY, etc.) |
| `MATCH_METHOD` | `VARCHAR(20)` | `MANUAL`, `NAME_MATCH`, `ID_MATCH` -- how the mapping was established |
| `VERIFIED` | `BOOLEAN` | TRUE if manually verified by Operations team |
| `LAST_UPDATED` | `TIMESTAMP_NTZ` | Last modification timestamp |

### Initial Seeding Process

1. Export client list from all three systems (Geneva accounts, NetSuite customers, Salesforce accounts)
2. Match on business identifiers (account numbers, tax IDs) where available -- tag as `ID_MATCH`
3. Fuzzy match on name + city for remaining records -- tag as `NAME_MATCH`
4. Operations team reviews all `NAME_MATCH` entries and sets `VERIFIED = TRUE` or corrects
5. Unmatched records flagged for manual resolution before go-live

### Ongoing Maintenance

- New Salesforce accounts: automatically create `ENTITY_CROSSREF` entry with `SALESFORCE_ID` populated, others NULL
- New Geneva accounts: matching Dynamic Table proposes `CURATED_KEY` based on name similarity, routes to review queue
- Quarterly full reconciliation: compare all three source system counts against ENTITY_CROSSREF coverage
