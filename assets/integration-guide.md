# Pinnacle Financial Services -- Technical Integration Guide

**Document Owner:** David Park, VP of Operations
**Status:** Draft -- Pending POC Go/No-Go Decision
**Scope:** Production integration of Geneva, NetSuite, and Salesforce into Snowflake

---

## 1. Executive Summary

This guide describes how Pinnacle Financial will connect its three core systems -- Advent Geneva (portfolio accounting), NetSuite (general ledger), and Salesforce Financial Services Cloud (CRM) -- into Snowflake to replace the current SQL Server warehouse and manual reconciliation workflows. The integration uses Snowflake-native connectors where possible (NetSuite, Salesforce) and a scheduled SFTP extract for Geneva, landing data into a three-layer architecture (RAW, CURATED, ANALYTICS) that feeds both the existing Power BI dashboards and the new Snowflake Intelligence natural language interface. End-to-end latency from source change to executive query ranges from 20 minutes (Salesforce) to 50 minutes (Geneva), compared to the current multi-day manual process. The architecture is SOC 2 compliant with full audit logging, role-based access control, and PII masking -- no data leaves Snowflake's encrypted environment.

---

## 2. Technical Overview

### Architecture Layers

```
SOURCE SYSTEMS          INGESTION              SNOWFLAKE                    CONSUMERS
─────────────          ─────────              ─────────                    ─────────
Geneva ──────► SFTP + Snowpipe ──► RAW ──► CURATED ──► ANALYTICS ──► Power BI
NetSuite ────► Native Connector ──►  │     (Dynamic    (Semantic       Snowflake
Salesforce ──► Native CDC ─────────►  │      Tables)     View)          Intelligence
                                                                        REST API
```

### Design Principles

1. **No data modification at ingestion** -- RAW schema is append-only and immutable. Source records are never altered after landing.
2. **Incremental everywhere** -- Dynamic Tables use incremental refresh. Full reloads are reserved for schema changes or disaster recovery.
3. **Single source of truth** -- The Semantic View in ANALYTICS is the only sanctioned query layer. Power BI and Snowflake Intelligence both read from it.
4. **Native connectors first** -- Avoid third-party ETL tools where Snowflake provides a native option. Reduces licensing cost, maintenance burden, and latency.

### Target Database Layout

```
PINNACLE_FINANCIAL/
├── RAW/
│   ├── GENEVA_*          (raw portfolio extracts)
│   ├── NETSUITE_*        (raw GL tables)
│   └── SALESFORCE_*      (raw CRM objects)
├── CURATED/
│   ├── DIM_DATE
│   ├── DIM_CLIENT
│   ├── DIM_PRODUCT
│   ├── DIM_COST_CENTER
│   ├── DIM_GL_ACCOUNT
│   ├── FACT_REVENUE
│   ├── FACT_EXPENSE
│   ├── FACT_BUDGET
│   └── FACT_CLIENT_AUM
├── ANALYTICS/
│   └── PINNACLE_FINANCIAL_SV    (Semantic View)
└── AGENTS/
    └── PINNACLE_FINANCIAL_AGENT (Cortex Agent)
```

---

## 3. Prerequisites & Requirements

### Snowflake Account

| Requirement | Detail |
|---|---|
| Edition | Enterprise (required for masking policies, Dynamic Tables) |
| Cloud / Region | AWS us-east-1 (closest to NY HQ) |
| Warehouses | `INGESTION_WH` (X-Small, auto-suspend 60s), `ANALYTICS_WH` (Small, auto-suspend 120s), `CORTEX_WH` (Small, for AI workloads) |
| Storage integration | AWS S3 bucket for Geneva SFTP staging |
| Network policy | IP allowlist: NY, BOS, SF office CIDRs + VPN range |

### Source System Access

| System | Access Required | Owner |
|---|---|---|
| Geneva | SFTP export credentials, scheduled job configuration, read access to portfolio/transaction/NAV datasets | Geneva admin (Operations team) |
| NetSuite | API access via SuiteAnalytics Connect or REST Web Services, OAuth 2.0 client credentials, read-only role on GL, AP/AR, and revenue tables | NetSuite admin (Finance team) |
| Salesforce | Connected App with OAuth 2.0, API-enabled user with read access to Account, Contact, Opportunity, AUM custom objects, Change Data Capture enabled | Salesforce admin (IT team) |

### Personnel

| Role | Responsibility | Estimated Effort |
|---|---|---|
| Snowflake Admin | Account setup, network policies, warehouse config, role hierarchy | Ongoing |
| Data Engineer | Connector setup, Dynamic Table DDL, testing, monitoring | Primary effort during build |
| Geneva Admin | Configure SFTP export jobs, validate extract completeness | Setup + validation |
| NetSuite Admin | Create API integration, grant read-only role | Setup only |
| Salesforce Admin | Create Connected App, enable CDC on required objects | Setup only |
| David Park (VP Ops) | Technical review, UAT sign-off | Checkpoints |
| Sarah Martinez (Compliance) | Validate audit trail, approve masking policies | Checkpoints |

---

## 4. Integration Details by Source System

### 4A. Advent Geneva --> Snowflake (Portfolio Data)

**Connection Method:** Scheduled SFTP extract + Snowflake external stage + Snowpipe

Geneva's export capabilities are batch-oriented. This is standard practice for portfolio accounting systems -- real-time streaming is neither supported nor necessary for NAV and position data that settles on a T+1 basis.

**Architecture:**

```
Geneva ──► SFTP Server ──► S3 Staging Bucket ──► Snowpipe ──► RAW.GENEVA_*
               │
          Scheduled export
          Daily 6:00 AM ET
```

**Tables to Sync:**

| Geneva Export | RAW Landing Table | Description | Row Volume (est.) |
|---|---|---|---|
| Portfolio Positions | `RAW.GENEVA_POSITIONS` | End-of-day holdings by account, security, quantity, market value | ~500K/day |
| Transactions | `RAW.GENEVA_TRANSACTIONS` | Buys, sells, dividends, corporate actions | ~5K/day |
| NAV / Valuations | `RAW.GENEVA_NAV` | Daily NAV per portfolio | ~200/day |
| Account Master | `RAW.GENEVA_ACCOUNTS` | Account metadata, strategy, benchmark | ~50K total (full) |
| Security Master | `RAW.GENEVA_SECURITIES` | Security reference data (CUSIP, ISIN, asset class) | ~10K total (full) |
| Fee Schedule | `RAW.GENEVA_FEE_SCHEDULES` | Fee rates by account, tier, product | ~500 total (full) |

**Refresh Strategy:**

| Table | Strategy | Rationale |
|---|---|---|
| Positions, Transactions, NAV | Incremental append | New records daily. Deduplicate on `TRANSACTION_ID` or `POSITION_DATE + ACCOUNT_ID`. |
| Account Master, Security Master | Full replace daily | Small reference tables. Full snapshot ensures deletions/corrections are captured. |
| Fee Schedule | Full replace daily | Small table, changes infrequently but must be accurate. |

**Expected Latency:**
- Geneva export completes: ~6:00-6:10 AM ET
- S3 upload via SFTP: ~2 minutes
- Snowpipe auto-ingest: ~3 minutes
- **Total: ~15 minutes from export start to RAW availability**

**Configuration Steps:**

1. Create external stage pointing to S3 bucket:
   ```sql
   CREATE OR REPLACE STAGE RAW.GENEVA_STAGE
     URL = 's3://pinnacle-geneva-exports/'
     STORAGE_INTEGRATION = PINNACLE_S3_INTEGRATION
     FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"'
                    SKIP_HEADER = 1 NULL_IF = ('', 'NULL'));
   ```

2. Create RAW landing tables matching Geneva export schemas (one per export file).

3. Create Snowpipe for each table:
   ```sql
   CREATE OR REPLACE PIPE RAW.GENEVA_POSITIONS_PIPE
     AUTO_INGEST = TRUE AS
     COPY INTO RAW.GENEVA_POSITIONS
     FROM @RAW.GENEVA_STAGE/positions/;
   ```

4. Configure S3 event notification to trigger Snowpipe on new file arrival.

5. Schedule Geneva export job to write to SFTP at 6:00 AM ET daily.

---

### 4B. NetSuite --> Snowflake (GL Data)

**Connection Method:** Snowflake Connector for NetSuite (native)

Snowflake's native connector for NetSuite uses SuiteAnalytics Connect to replicate tables directly into Snowflake without middleware. It handles schema detection, incremental sync, and error retry automatically.

**Architecture:**

```
NetSuite ──► Snowflake Connector for NetSuite ──► RAW.NETSUITE_*
                    │
               API sync
               Every 4 hours
```

**Tables to Sync:**

| NetSuite Table | RAW Landing Table | Description | Row Volume (est.) |
|---|---|---|---|
| `transaction` | `RAW.NETSUITE_TRANSACTIONS` | All GL journal entries, invoices, payments | ~2K/day |
| `transactionline` | `RAW.NETSUITE_TRANSACTION_LINES` | Line-level detail for each transaction | ~10K/day |
| `account` | `RAW.NETSUITE_ACCOUNTS` | Chart of accounts (GL account master) | ~500 total |
| `accountingperiod` | `RAW.NETSUITE_PERIODS` | Fiscal periods, open/close status | ~60 total |
| `department` | `RAW.NETSUITE_DEPARTMENTS` | Department / cost center master | ~50 total |
| `vendor` | `RAW.NETSUITE_VENDORS` | Vendor master for AP | ~500 total |
| `subsidiary` | `RAW.NETSUITE_SUBSIDIARIES` | Legal entity structure | ~5 total |
| `budgets` | `RAW.NETSUITE_BUDGETS` | Annual budget by account, department, period | ~5K total |

**Refresh Strategy:**

| Table | Strategy | Rationale |
|---|---|---|
| `transaction`, `transactionline` | Incremental (CDC via `lastmodifieddate`) | High volume, append-heavy. Connector tracks watermark automatically. |
| `account`, `department`, `vendor`, `subsidiary` | Full sync every 4 hours | Small reference tables. Full sync ensures corrections and deletions propagate. |
| `accountingperiod` | Full sync every 4 hours | Must reflect period open/close status changes for month-end close. |
| `budgets` | Full sync every 4 hours | Low volume, changes during budget season only. |

**Expected Latency:**
- Connector sync cycle: every 4 hours (configurable down to 1 hour)
- Sync duration for incremental tables: ~10-15 minutes
- Sync duration for full reference tables: ~5 minutes
- **Total: ~30 minutes from NetSuite change to RAW availability (worst case within sync window)**

**Configuration Steps:**

1. In NetSuite: create an integration record and issue OAuth 2.0 client credentials. Assign a read-only role with access to GL, AP/AR, and budget tables.

2. In Snowflake: create the connector:
   ```sql
   CREATE OR REPLACE SECRET RAW.NETSUITE_OAUTH_SECRET
     TYPE = GENERIC_STRING
     SECRET_STRING = '<oauth_token>';

   -- Connector setup via Snowsight UI:
   -- Connections > + Connector > NetSuite
   -- Provide: Account ID, Consumer Key/Secret, Token Key/Secret
   -- Select tables, set sync frequency to 4 hours
   -- Target schema: RAW
   ```

3. Validate initial sync completes and row counts match NetSuite saved searches.

---

### 4C. Salesforce --> Snowflake (Client Data)

**Connection Method:** Snowflake Connector for Salesforce (native, CDC-enabled)

Salesforce's connector leverages Change Data Capture (CDC) to stream changes into Snowflake in near real-time. This is critical for client data -- when a relationship manager updates a client record in Salesforce, the change should be queryable within minutes.

**Architecture:**

```
Salesforce ──► Snowflake Connector for Salesforce ──► RAW.SALESFORCE_*
                    │
               CDC stream
               Near real-time (~5 min)
```

**Tables to Sync:**

| Salesforce Object | RAW Landing Table | Description | Row Volume (est.) |
|---|---|---|---|
| `Account` | `RAW.SALESFORCE_ACCOUNTS` | Client accounts (firms, trusts, individuals) | ~50K total |
| `Contact` | `RAW.SALESFORCE_CONTACTS` | Individual contacts linked to accounts | ~80K total |
| `Opportunity` | `RAW.SALESFORCE_OPPORTUNITIES` | Sales pipeline, new client onboarding | ~5K total |
| `Financial_Account__c` | `RAW.SALESFORCE_FINANCIAL_ACCOUNTS` | Investment accounts with AUM, strategy, benchmark | ~100K total |
| `AUM_Snapshot__c` | `RAW.SALESFORCE_AUM_SNAPSHOTS` | Monthly AUM snapshots per client/product | ~600K total |
| `Task` / `Event` | `RAW.SALESFORCE_ACTIVITIES` | Client interactions, meeting notes | ~200K total |
| `User` | `RAW.SALESFORCE_USERS` | Relationship manager / advisor records | ~200 total |

**Refresh Strategy:**

| Table | Strategy | Rationale |
|---|---|---|
| `Account`, `Contact`, `Financial_Account__c` | CDC (near real-time) | Core client data -- must reflect updates quickly for accurate reporting. |
| `AUM_Snapshot__c` | CDC (near real-time) | AUM changes drive revenue calculations. |
| `Opportunity` | CDC (near real-time) | Pipeline visibility for leadership. |
| `Task`, `Event` | Incremental (hourly batch) | High volume, lower urgency. Hourly is sufficient for analytics. |
| `User` | Full sync daily | Small reference table. Changes infrequently. |

**Expected Latency:**
- CDC event propagation: ~2-3 minutes
- Snowflake connector processing: ~2 minutes
- **Total: ~5 minutes from Salesforce save to RAW availability**

**Configuration Steps:**

1. In Salesforce: create a Connected App with OAuth 2.0 (Web Server flow). Enable CDC on Account, Contact, Financial_Account__c, AUM_Snapshot__c, and Opportunity objects.

2. In Snowflake: create the connector:
   ```sql
   -- Connector setup via Snowsight UI:
   -- Connections > + Connector > Salesforce
   -- Provide: Instance URL, Client ID/Secret, Refresh Token
   -- Select objects, enable CDC for real-time tables
   -- Set batch tables (Task, Event) to hourly
   -- Target schema: RAW
   ```

3. Validate initial sync. Confirm row counts match Salesforce report builder totals.

---

## 5. Data Transformation Logic

Transformations are implemented as **Dynamic Tables** in the CURATED schema. Dynamic Tables handle scheduling, dependency ordering, and incremental refresh automatically -- no orchestration tool required.

### RAW --> CURATED Mappings

#### DIM_CLIENT
```
Source: RAW.SALESFORCE_ACCOUNTS + RAW.SALESFORCE_FINANCIAL_ACCOUNTS
Logic:
  - Join Account to Financial_Account__c on AccountId
  - Derive CLIENT_SEGMENT from Account.Type (Individual, Institutional, Family Office)
  - Derive AUM_TIER from total AUM: Platinum (>$50M), Gold ($10M-$50M), Silver (<$10M)
  - Map Account.Owner to RELATIONSHIP_MANAGER via RAW.SALESFORCE_USERS
  - Map Account.BillingCity to OFFICE_LOCATION (NY, BOS, SF)
  - Filter: IS_ACTIVE = Account.IsActive (exclude closed accounts)
Refresh: Incremental via CDC, ~10 min target lag
```

#### DIM_PRODUCT
```
Source: RAW.GENEVA_FEE_SCHEDULES + RAW.NETSUITE_ACCOUNTS (revenue accounts only)
Logic:
  - Geneva fee schedules define products (strategies/funds)
  - Map to GL revenue account via fee type
  - Derive PRODUCT_CATEGORY from fee structure (Management, Performance, Advisory, Transaction)
  - Derive ASSET_CLASS from Geneva strategy metadata
Refresh: Daily (reference data, low change frequency)
```

#### DIM_DATE
```
Source: Generated (no external source)
Logic:
  - Generate via GENERATOR() CTE for the required date range
  - Compute all calendar and fiscal attributes
  - Fiscal year = calendar year for Pinnacle (Jan-Dec)
Refresh: Monthly (extend range as needed)
```

#### DIM_COST_CENTER
```
Source: RAW.NETSUITE_DEPARTMENTS
Logic:
  - Map NetSuite department to cost center
  - Derive EXPENSE_CATEGORY from department classification
  - Map department.location to OFFICE_LOCATION
Refresh: Daily (reference data)
```

#### DIM_GL_ACCOUNT
```
Source: RAW.NETSUITE_ACCOUNTS
Logic:
  - Filter to active accounts
  - Derive ACCOUNT_TYPE from account number range (4xxx = Revenue, 5xxx-7xxx = Expense)
  - Map NORMAL_BALANCE from account type (Credit for revenue, Debit for expense)
Refresh: Daily (reference data)
```

#### FACT_REVENUE
```
Source: RAW.GENEVA_TRANSACTIONS + RAW.GENEVA_NAV + RAW.GENEVA_FEE_SCHEDULES
Logic:
  - Join transactions (fee events) to NAV (AUM at time of fee) on date + account
  - Look up fee rate from fee schedule by account + product
  - Compute REVENUE_AMOUNT = AUM_AMOUNT * FEE_BASIS_POINTS / 10000 / 12
  - Resolve CLIENT_KEY via Geneva account -> Salesforce account mapping
  - Resolve PRODUCT_KEY via Geneva strategy -> DIM_PRODUCT
  - Resolve DATE_KEY via transaction date -> DIM_DATE
  - Deduplicate on TRANSACTION_ID
Refresh: Incremental, ~10 min target lag
```

#### FACT_EXPENSE
```
Source: RAW.NETSUITE_TRANSACTIONS + RAW.NETSUITE_TRANSACTION_LINES
Logic:
  - Filter to expense transactions (GL account 5xxx-7xxx)
  - Join transaction to lines for amount, department, vendor
  - Resolve COST_CENTER_KEY via department -> DIM_COST_CENTER
  - Resolve GL_ACCOUNT_KEY via account -> DIM_GL_ACCOUNT
  - Resolve DATE_KEY via transaction date -> DIM_DATE
  - Map PAYMENT_STATUS from NetSuite transaction status
Refresh: Incremental, ~10 min target lag
```

#### FACT_BUDGET
```
Source: RAW.NETSUITE_BUDGETS
Logic:
  - Map budget lines to DIM_GL_ACCOUNT, DIM_COST_CENTER, DIM_PRODUCT
  - Derive BUDGET_TYPE from GL account type (Revenue vs Expense)
  - Resolve DATE_KEY from accounting period -> DIM_DATE (period start)
Refresh: Daily (budgets change infrequently)
```

#### FACT_CLIENT_AUM
```
Source: RAW.SALESFORCE_AUM_SNAPSHOTS + RAW.GENEVA_NAV
Logic:
  - Primary: Geneva NAV provides authoritative AUM by account + date
  - Secondary: Salesforce AUM snapshots for client-level rollup validation
  - Compute AUM_CHANGE = current - prior period
  - Derive NET_FLOWS from Geneva cash transaction types (deposits, withdrawals)
  - Derive MARKET_CHANGE = AUM_CHANGE - NET_FLOWS
  - Resolve CLIENT_KEY, PRODUCT_KEY, DATE_KEY
Refresh: Incremental, ~10 min target lag
```

### Cross-System Key Resolution

The critical integration challenge is mapping entities across Geneva, NetSuite, and Salesforce. A mapping table in CURATED resolves this:

```
CURATED.ENTITY_CROSSREF
─────────────────────────────────────────────────────────
CROSSREF_KEY    INT PRIMARY KEY
ENTITY_TYPE     VARCHAR(20)     -- 'CLIENT', 'PRODUCT', 'ACCOUNT'
GENEVA_ID       VARCHAR(50)     -- Geneva account/strategy ID
NETSUITE_ID     VARCHAR(50)     -- NetSuite internal ID
SALESFORCE_ID   VARCHAR(50)     -- Salesforce record ID (18-char)
CURATED_KEY     INT             -- FK to the corresponding DIM table
─────────────────────────────────────────────────────────
```

This table is initially seeded manually during implementation and maintained via a matching Dynamic Table that proposes new mappings based on name/ID similarity for human review.

---

## 6. Refresh Schedules

### Ingestion (Source --> RAW)

| Source | Schedule | Method | Window |
|---|---|---|---|
| Geneva | Daily 6:00 AM ET | SFTP + Snowpipe | 6:00-6:15 AM |
| NetSuite | Every 4 hours (6AM, 10AM, 2PM, 6PM, 10PM) | Native connector | ~15 min per cycle |
| Salesforce (CDC tables) | Continuous | Native connector CDC | Near real-time |
| Salesforce (batch tables) | Hourly | Native connector batch | ~5 min per cycle |

### Transformation (RAW --> CURATED)

| Dynamic Table | Target Lag | Depends On |
|---|---|---|
| DIM_DATE | Manual refresh (monthly) | None |
| DIM_CLIENT | 10 minutes | SALESFORCE_ACCOUNTS, SALESFORCE_FINANCIAL_ACCOUNTS, SALESFORCE_USERS |
| DIM_PRODUCT | 24 hours | GENEVA_FEE_SCHEDULES, NETSUITE_ACCOUNTS |
| DIM_COST_CENTER | 24 hours | NETSUITE_DEPARTMENTS |
| DIM_GL_ACCOUNT | 24 hours | NETSUITE_ACCOUNTS |
| ENTITY_CROSSREF | 24 hours | All RAW tables (matching logic) |
| FACT_REVENUE | 10 minutes | GENEVA_TRANSACTIONS, GENEVA_NAV, DIM_DATE, DIM_CLIENT, DIM_PRODUCT |
| FACT_EXPENSE | 10 minutes | NETSUITE_TRANSACTIONS, NETSUITE_TRANSACTION_LINES, DIM_COST_CENTER, DIM_GL_ACCOUNT |
| FACT_BUDGET | 24 hours | NETSUITE_BUDGETS, DIM_GL_ACCOUNT, DIM_COST_CENTER |
| FACT_CLIENT_AUM | 10 minutes | GENEVA_NAV, SALESFORCE_AUM_SNAPSHOTS, DIM_CLIENT, DIM_PRODUCT |

### Consumption (CURATED --> ANALYTICS)

| Object | Target Lag | Notes |
|---|---|---|
| Semantic View | 5 minutes | References CURATED tables directly; lag is additive to CURATED lag |
| Cortex Agent | Real-time | Queries Semantic View on demand, no separate refresh |

### End-to-End Latency by Data Domain

| Domain | Source | Worst-Case Latency | Typical Latency |
|---|---|---|---|
| Client data (AUM, segment) | Salesforce CDC | ~20 minutes | ~15 minutes |
| Revenue / fees | Geneva batch | ~50 minutes (after 6AM export) | ~30 minutes |
| Expenses / GL | NetSuite 4-hour | ~50 minutes (within sync window) | ~30 minutes |
| Budgets | NetSuite 4-hour | ~4.5 hours (next sync + transform) | ~30 minutes |

---

## 7. Error Handling & Monitoring

### Ingestion Errors

| Error Type | Detection | Response | Alert Recipient |
|---|---|---|---|
| Geneva SFTP file missing | Snowflake task checks S3 for expected file by 6:30 AM | Retry SFTP connection. If absent by 7:00 AM, alert Operations. | David Park, Geneva admin |
| Geneva file corrupt / schema drift | Snowpipe COPY_HISTORY shows LOAD_FAILED | Quarantine file to `RAW.GENEVA_ERRORS`. Parse error details. Alert for manual review. | Data Engineer |
| NetSuite connector sync failure | Connector status in Snowsight shows ERROR | Automatic retry (3 attempts). If persistent, check NetSuite API limits and credentials. | Data Engineer, NetSuite admin |
| Salesforce CDC lag > 15 min | Monitor SALESFORCE connector lag metric | Check Salesforce API rate limits. Verify Connected App is active. | Data Engineer, SF admin |
| Duplicate records in RAW | MERGE or QUALIFY dedup in Dynamic Table | Dynamic Tables handle dedup in transformation. Log duplicate counts for monitoring. | Automated (no alert unless spike) |

### Transformation Errors

| Error Type | Detection | Response |
|---|---|---|
| Dynamic Table refresh failure | `SHOW DYNAMIC TABLES` shows SUSPENDED or FAILED | Check DYNAMIC_TABLE_REFRESH_HISTORY for error. Common causes: upstream table dropped, column renamed, warehouse suspended. |
| Cross-reference key miss | ENTITY_CROSSREF has NULL CURATED_KEY | Route to manual mapping queue. Revenue/expense records with unmapped keys land in a staging table pending resolution. |
| Data quality: row count anomaly | Scheduled task compares today's row count to 7-day rolling average | Alert if delta > 20%. Likely cause: source system outage or Geneva export misconfiguration. |
| Data quality: revenue sum anomaly | Compare daily revenue total to prior day and prior month same day | Alert if delta > 50%. Likely cause: fee schedule change, duplicate transactions, or missing accounts. |

### Monitoring Dashboard

Create a Snowflake task-based monitoring pipeline:

```
CHECK FREQUENCY: Every 30 minutes
─────────────────────────────────────────────────────
CHECK                         THRESHOLD     ACTION
─────────────────────────────────────────────────────
Geneva file arrived today?    By 6:30 AM    Alert Ops
NetSuite last sync age        < 5 hours     Alert Eng
Salesforce CDC lag             < 15 min      Alert Eng
Dynamic Table failures         = 0           Alert Eng
RAW row count vs yesterday    +/- 20%       Alert Eng
FACT_REVENUE daily total      +/- 50%       Alert Ops
Unmapped crossref keys        = 0           Alert Eng
─────────────────────────────────────────────────────
```

Alert channels: Snowflake notifications --> email (immediate) + Slack #data-ops channel.

### Disaster Recovery

| Scenario | Recovery Method | RTO |
|---|---|---|
| RAW table corrupted | Time Travel (UNDROP or AT/BEFORE) -- 90-day retention | < 1 hour |
| CURATED table incorrect | Suspend Dynamic Table, fix logic, resume -- automatic full refresh | < 2 hours |
| Source connector credential expiry | Rotate credentials in source system, update Snowflake secret | < 30 minutes |
| Full account recovery | Snowflake replication to secondary region (if configured) | < 4 hours |

---

## 8. Timeline & Milestones

### Phase 1: Foundation

| Step | Description | Dependencies |
|---|---|---|
| 1.1 | Snowflake account provisioning (Enterprise, us-east-1) | Procurement approval |
| 1.2 | Network policy, role hierarchy, warehouse setup | 1.1 |
| 1.3 | S3 staging bucket + storage integration for Geneva | AWS admin, 1.1 |
| 1.4 | Create RAW schema and all landing tables | 1.2 |
| 1.5 | Configure masking policies and row access policies | Sarah Martinez sign-off, 1.2 |

### Phase 2: Connector Setup

| Step | Description | Dependencies |
|---|---|---|
| 2.1 | Geneva: configure SFTP export, create Snowpipe, validate first load | Geneva admin, 1.3, 1.4 |
| 2.2 | NetSuite: create integration record, deploy native connector, validate initial sync | NetSuite admin, 1.4 |
| 2.3 | Salesforce: create Connected App, enable CDC, deploy native connector, validate initial sync | SF admin, 1.4 |
| 2.4 | Validate RAW row counts against source systems | 2.1, 2.2, 2.3 |

### Phase 3: Transformation Layer

| Step | Description | Dependencies |
|---|---|---|
| 3.1 | Build ENTITY_CROSSREF mapping table (manual seed + matching logic) | 2.4 |
| 3.2 | Create all DIM Dynamic Tables in CURATED | 2.4, 3.1 |
| 3.3 | Create all FACT Dynamic Tables in CURATED | 3.2 |
| 3.4 | Validate CURATED data quality: reconcile totals against source systems | 3.3 |
| 3.5 | David Park UAT review of CURATED layer | 3.4 |

### Phase 4: Analytics & AI Layer

| Step | Description | Dependencies |
|---|---|---|
| 4.1 | Create Semantic View in ANALYTICS (port POC model to production tables) | 3.5 |
| 4.2 | Create Cortex Agent in AGENTS schema | 4.1 |
| 4.3 | Grant roles and enable Snowflake Intelligence access | 4.2 |
| 4.4 | Migrate Power BI connections from SQL Server to Snowflake | 4.1 |
| 4.5 | End-to-end validation: NL queries return correct, governed answers | 4.3, 4.4 |

### Phase 5: Operationalize

| Step | Description | Dependencies |
|---|---|---|
| 5.1 | Deploy monitoring tasks and alert notifications | 4.5 |
| 5.2 | Document runbooks for each error scenario | 5.1 |
| 5.3 | Train finance team on Snowflake Intelligence | 4.5 |
| 5.4 | Parallel run: SQL Server + Snowflake side-by-side for 1 month-end close | 4.5 |
| 5.5 | Sarah Martinez compliance review and sign-off | 5.4 |
| 5.6 | Decommission SQL Server reads (keep as backup for 90 days) | 5.5 |

### Go-Live Criteria

- [ ] All three source connectors running on schedule with zero failures for 5 consecutive days
- [ ] CURATED totals reconcile to source systems within $100 tolerance
- [ ] Semantic View describes successfully with 350+ properties
- [ ] Cortex Agent answers 10 standard test queries correctly
- [ ] Masking policies verified: analysts see masked PII, compliance sees full
- [ ] Monitoring alerts fire correctly on simulated failures
- [ ] One complete month-end close executed on Snowflake in parallel with SQL Server
- [ ] Sarah Martinez sign-off on audit trail and governance
- [ ] David Park sign-off on data accuracy and technical architecture
