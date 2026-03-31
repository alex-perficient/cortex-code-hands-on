# Pinnacle Financial Services -- Security Architecture Document

**Classification:** Internal -- Restricted
**Audience:** David Park (VP Operations), Sarah Martinez (Head of Compliance)
**Companion:** `security-architecture.md` (Mermaid diagrams), `integration-guide.md` (technical details)

---

## Executive Summary

This document defines the security architecture for Pinnacle Financial's Snowflake deployment, addressing two primary stakeholder concerns: David Park's requirement for data accuracy and trustworthiness, and Sarah Martinez's requirement for SOC 2 compliance, audit trails, and regulatory reporting controls. Every control maps to a specific Snowflake feature and a SOC 2 Trust Services Criterion.

The architecture enforces defense in depth: SSO with MFA at the perimeter, role-based access control with least-privilege functional roles, dynamic data masking for PII, row-level security for client data segmentation, and AI-specific guardrails that ensure Cortex Analyst produces governed, explainable SQL. All activity is logged immutably in ACCOUNT_USAGE with 365-day retention.

---

## 1. Authentication & Authorization

### 1.1 SSO Integration

Pinnacle's corporate identity provider (Azure AD or Okta) is the single source of truth for user identity. No local Snowflake passwords for human users.

| Component | Snowflake Feature | Configuration | SOC 2 |
|---|---|---|---|
| Federated login | SAML 2.0 integration | `ALTER ACCOUNT SET SAML_IDENTITY_PROVIDER = '{...}';` | CC6.1 |
| Multi-factor auth | MFA enforcement | `ALTER ACCOUNT SET REQUIRE_MFA = TRUE;` Applied via authentication policy to all human roles. | CC6.1 |
| User provisioning | SCIM 2.0 | Auto-sync users and groups from IdP. Deprovisioned IdP users are immediately disabled in Snowflake. | CC6.2 |
| Service accounts | Key-pair authentication | RSA 2048-bit key pairs for Power BI and API integrations. No passwords, keys rotated quarterly. | CC6.1 |
| Network perimeter | Network policies | IP allowlist: NY HQ (`10.1.0.0/16`), Boston (`10.2.0.0/16`), SF (`10.3.0.0/16`), VPN (`172.16.0.0/12`). All other IPs blocked. | CC6.1 |
| Session control | Session policies | Idle timeout: 30 minutes. Max session: 8 hours. No client-side result caching for PII-bearing queries. | CC6.1 |

**Implementation SQL:**

```sql
-- Authentication policy: enforce MFA for all human users
CREATE OR REPLACE AUTHENTICATION POLICY PINNACLE_HUMAN_AUTH_POLICY
  MFA_AUTHENTICATION_METHODS = ('TOTP')
  CLIENT_TYPES = ('SNOWFLAKE_UI', 'SNOWSIGHT')
  SECURITY_INTEGRATIONS = ('PINNACLE_SAML_INTEGRATION');

-- Network policy: restrict to office and VPN IPs
CREATE OR REPLACE NETWORK POLICY PINNACLE_NETWORK_POLICY
  ALLOWED_IP_LIST = ('10.1.0.0/16', '10.2.0.0/16', '10.3.0.0/16', '172.16.0.0/12')
  COMMENT = 'SOC 2 CC6.1: Restrict access to Pinnacle office and VPN networks';

ALTER ACCOUNT SET NETWORK_POLICY = PINNACLE_NETWORK_POLICY;

-- Session policy: idle timeout 30 min, max 8 hrs
CREATE OR REPLACE SESSION POLICY PINNACLE_SESSION_POLICY
  SESSION_IDLE_TIMEOUT_MINS = 30
  SESSION_UI_IDLE_TIMEOUT_MINS = 30
  COMMENT = 'SOC 2 CC6.1: Automatic session termination';
```

### 1.2 Role-Based Access Control (RBAC)

Five functional roles follow least-privilege principles. No user operates under ACCOUNTADMIN or SYSADMIN for daily work.

```
ACCOUNTADMIN          (break-glass only, 2 designated admins)
    └── SECURITYADMIN  (role/grant management, Sarah Martinez)
        └── SYSADMIN   (object ownership, David Park for DDL)
            ├── PINNACLE_OPS_RL        (David Park -- full data, full PII)
            │   ├── PINNACLE_EXECUTIVE_RL  (Margaret Chen -- analytics only, PII masked)
            │   └── PINNACLE_ANALYST_RL    (Finance team -- curated+analytics, PII masked)
            │       └── PINNACLE_SERVICE_RL (Power BI, API -- analytics only, PII masked)
            └── PINNACLE_COMPLIANCE_RL (Sarah Martinez -- full data, audit logs, full PII)
```

**Role-to-Data Access Matrix:**

| Schema / Object | EXECUTIVE | OPS | COMPLIANCE | ANALYST | SERVICE |
|---|---|---|---|---|---|
| RAW schema | -- | READ | READ | -- | -- |
| CURATED schema | -- | READ | READ | READ | -- |
| ANALYTICS schema | READ | READ | READ | READ | READ |
| Semantic View | READ | READ | READ | READ | READ |
| Cortex Agent | USAGE | USAGE | USAGE | USAGE | -- |
| Client PII columns | MASKED | FULL | FULL | MASKED | MASKED |
| Audit / Access History | -- | -- | READ | -- | -- |
| Query History | -- | READ | READ | -- | -- |

**Implementation SQL:**

```sql
-- Create functional roles
CREATE ROLE IF NOT EXISTS PINNACLE_OPS_RL;
CREATE ROLE IF NOT EXISTS PINNACLE_EXECUTIVE_RL;
CREATE ROLE IF NOT EXISTS PINNACLE_COMPLIANCE_RL;
CREATE ROLE IF NOT EXISTS PINNACLE_ANALYST_RL;
CREATE ROLE IF NOT EXISTS PINNACLE_SERVICE_RL;

-- Role hierarchy
GRANT ROLE PINNACLE_OPS_RL TO ROLE SYSADMIN;
GRANT ROLE PINNACLE_COMPLIANCE_RL TO ROLE SYSADMIN;
GRANT ROLE PINNACLE_EXECUTIVE_RL TO ROLE PINNACLE_OPS_RL;
GRANT ROLE PINNACLE_ANALYST_RL TO ROLE PINNACLE_OPS_RL;
GRANT ROLE PINNACLE_SERVICE_RL TO ROLE PINNACLE_ANALYST_RL;

-- Schema grants (ANALYTICS)
GRANT USAGE ON DATABASE PINNACLE_FINANCIAL TO ROLE PINNACLE_ANALYST_RL;
GRANT USAGE ON SCHEMA PINNACLE_FINANCIAL.ANALYTICS TO ROLE PINNACLE_ANALYST_RL;
GRANT SELECT ON ALL TABLES IN SCHEMA PINNACLE_FINANCIAL.ANALYTICS TO ROLE PINNACLE_ANALYST_RL;
GRANT SELECT ON ALL VIEWS IN SCHEMA PINNACLE_FINANCIAL.ANALYTICS TO ROLE PINNACLE_ANALYST_RL;

-- RAW + CURATED only for OPS and COMPLIANCE
GRANT USAGE ON SCHEMA PINNACLE_FINANCIAL.RAW TO ROLE PINNACLE_OPS_RL;
GRANT SELECT ON ALL TABLES IN SCHEMA PINNACLE_FINANCIAL.RAW TO ROLE PINNACLE_OPS_RL;
GRANT USAGE ON SCHEMA PINNACLE_FINANCIAL.RAW TO ROLE PINNACLE_COMPLIANCE_RL;
GRANT SELECT ON ALL TABLES IN SCHEMA PINNACLE_FINANCIAL.RAW TO ROLE PINNACLE_COMPLIANCE_RL;

-- Audit access for COMPLIANCE only
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE PINNACLE_COMPLIANCE_RL;
```

### 1.3 Row-Level Security for Client Data

Relationship managers see only their assigned clients. Office managers see clients in their office. Executives and compliance see all clients.

**Snowflake Feature:** Row Access Policy

```sql
-- Mapping table: which users can see which clients
CREATE OR REPLACE TABLE CURATED.CLIENT_ACCESS_MAP (
    USER_EMAIL       VARCHAR(200),
    ALLOWED_ROLE     VARCHAR(50),     -- Role that grants access
    OFFICE_LOCATION  VARCHAR(50),     -- NULL = all offices
    CLIENT_KEY       INT              -- NULL = all clients in office
);

-- Row access policy on DIM_CLIENT
CREATE OR REPLACE ROW ACCESS POLICY CURATED.CLIENT_ROW_POLICY
AS (CLIENT_KEY INT, OFFICE_LOCATION VARCHAR) RETURNS BOOLEAN ->
  -- Compliance and Ops see everything
  CURRENT_ROLE() IN ('PINNACLE_COMPLIANCE_RL', 'PINNACLE_OPS_RL')
  OR
  -- Executives see everything
  CURRENT_ROLE() = 'PINNACLE_EXECUTIVE_RL'
  OR
  -- Analysts see clients mapped to them or their office
  EXISTS (
    SELECT 1 FROM CURATED.CLIENT_ACCESS_MAP cam
    WHERE cam.USER_EMAIL = CURRENT_USER()
      AND (cam.CLIENT_KEY = CLIENT_KEY OR cam.OFFICE_LOCATION = OFFICE_LOCATION)
  );

-- Apply to DIM_CLIENT
ALTER TABLE CURATED.DIM_CLIENT ADD ROW ACCESS POLICY CURATED.CLIENT_ROW_POLICY
  ON (CLIENT_KEY, OFFICE_LOCATION);

-- Apply to FACT_REVENUE (via client key)
-- Revenue rows are filtered based on whether the user can see the client
CREATE OR REPLACE ROW ACCESS POLICY CURATED.REVENUE_ROW_POLICY
AS (CLIENT_KEY INT) RETURNS BOOLEAN ->
  CURRENT_ROLE() IN ('PINNACLE_COMPLIANCE_RL', 'PINNACLE_OPS_RL', 'PINNACLE_EXECUTIVE_RL')
  OR
  EXISTS (
    SELECT 1 FROM CURATED.CLIENT_ACCESS_MAP cam
    WHERE cam.USER_EMAIL = CURRENT_USER()
      AND cam.CLIENT_KEY = CLIENT_KEY
  );

ALTER TABLE CURATED.FACT_REVENUE ADD ROW ACCESS POLICY CURATED.REVENUE_ROW_POLICY
  ON (CLIENT_KEY);
```

**SOC 2 Control:** CC6.5 -- restricts data access to authorized personnel based on business need.

---

## 2. Data Protection

### 2.1 Encryption

| Layer | Method | Snowflake Feature | Detail |
|---|---|---|---|
| At rest | AES-256 | Automatic, always-on | All data, metadata, and temporary files encrypted. Keys managed by Snowflake's hierarchical key model (account key > table key > micro-partition key). |
| In transit | TLS 1.2+ | Automatic, always-on | All client-to-Snowflake and Snowflake-internal communication encrypted. Minimum TLS 1.2 enforced. |
| Key management | Tri-Secret Secure (optional) | Customer-managed key wrapping | Customer provides a KMS key (AWS KMS, Azure Key Vault) that wraps Snowflake's account key. Pinnacle controls key revocation. |
| End-to-end | Snowflake-managed | No user action required | Data is never decrypted outside Snowflake's secure compute environment. Query results transmitted over TLS. |

**SOC 2 Control:** CC6.7 -- encryption protects data confidentiality during transmission and storage.

**For David:** Data is encrypted at every layer automatically. Tri-Secret Secure is available if Pinnacle requires custody of encryption keys for regulatory reasons. There is no unencrypted data path.

### 2.2 Dynamic Data Masking for PII

PII fields are masked in real time based on the querying role. The underlying data is never modified -- masking is applied at query time.

**Snowflake Feature:** Dynamic Data Masking Policies

| PII Field | Full Access Roles | Masked Output (all other roles) | Policy |
|---|---|---|---|
| `CLIENT_NAME` | OPS, COMPLIANCE | `J*** D**` (first initial + asterisks) | `PINNACLE_NAME_MASK` |
| `TAX_ID` / `SSN` | COMPLIANCE only | `***-**-1234` (last 4 digits) | `PINNACLE_SSN_MASK` |
| `ACCOUNT_NUMBER` | OPS, COMPLIANCE | `****4567` (last 4 digits) | `PINNACLE_ACCT_MASK` |
| `EMAIL` | OPS, COMPLIANCE | `a***@***.com` (first char + domain masked) | `PINNACLE_EMAIL_MASK` |
| `PHONE` | OPS, COMPLIANCE | `***-***-5678` (last 4 digits) | `PINNACLE_PHONE_MASK` |

**Implementation SQL:**

```sql
-- Name masking: show first initial + asterisks
CREATE OR REPLACE MASKING POLICY PINNACLE_NAME_MASK AS (val VARCHAR)
RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() IN ('PINNACLE_OPS_RL', 'PINNACLE_COMPLIANCE_RL') THEN val
    WHEN val IS NULL THEN NULL
    ELSE LEFT(val, 1) || REGEXP_REPLACE(SUBSTR(val, 2), '[A-Za-z]', '*')
  END;

-- SSN masking: show last 4 digits only
CREATE OR REPLACE MASKING POLICY PINNACLE_SSN_MASK AS (val VARCHAR)
RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() = 'PINNACLE_COMPLIANCE_RL' THEN val
    WHEN val IS NULL THEN NULL
    ELSE '***-**-' || RIGHT(REPLACE(val, '-', ''), 4)
  END;

-- Account number masking: show last 4 digits
CREATE OR REPLACE MASKING POLICY PINNACLE_ACCT_MASK AS (val VARCHAR)
RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() IN ('PINNACLE_OPS_RL', 'PINNACLE_COMPLIANCE_RL') THEN val
    WHEN val IS NULL THEN NULL
    ELSE REPEAT('*', GREATEST(LENGTH(val) - 4, 0)) || RIGHT(val, 4)
  END;

-- Email masking: first char + masked domain
CREATE OR REPLACE MASKING POLICY PINNACLE_EMAIL_MASK AS (val VARCHAR)
RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() IN ('PINNACLE_OPS_RL', 'PINNACLE_COMPLIANCE_RL') THEN val
    WHEN val IS NULL THEN NULL
    ELSE LEFT(val, 1) || '***@***.com'
  END;

-- Apply policies to columns
ALTER TABLE CURATED.DIM_CLIENT MODIFY COLUMN CLIENT_NAME
  SET MASKING POLICY PINNACLE_NAME_MASK;
-- (Repeat for other PII columns on applicable tables)
```

**SOC 2 Control:** CC6.5 -- restricts access to sensitive data based on role.

### 2.3 Column-Level Security for Sensitive Fields

Beyond masking, certain columns are fully hidden from roles that have no business need.

**Snowflake Feature:** Tag-based column security + projection policies

| Column Category | Tagged With | Visible To | Hidden From |
|---|---|---|---|
| PII identifiers (SSN, Tax ID) | `PINNACLE.TAGS.SENSITIVITY = 'RESTRICTED'` | COMPLIANCE | All other roles |
| Financial amounts (revenue, AUM) | `PINNACLE.TAGS.SENSITIVITY = 'CONFIDENTIAL'` | OPS, COMPLIANCE, EXECUTIVE, ANALYST | SERVICE (aggregates only via Semantic View) |
| Audit metadata (_LOADED_AT, _SOURCE_FILE) | `PINNACLE.TAGS.SENSITIVITY = 'INTERNAL'` | OPS, COMPLIANCE | EXECUTIVE, ANALYST, SERVICE |

**Implementation SQL:**

```sql
-- Create tag for sensitivity classification
CREATE OR REPLACE TAG PINNACLE_FINANCIAL.TAGS.SENSITIVITY
  ALLOWED_VALUES = 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
  COMMENT = 'Data sensitivity classification per Pinnacle data governance policy';

-- Tag PII columns
ALTER TABLE CURATED.DIM_CLIENT MODIFY COLUMN CLIENT_NAME
  SET TAG PINNACLE_FINANCIAL.TAGS.SENSITIVITY = 'CONFIDENTIAL';

-- Tag restricted columns (if they exist in future tables)
-- ALTER TABLE CURATED.DIM_CLIENT MODIFY COLUMN TAX_ID
--   SET TAG PINNACLE_FINANCIAL.TAGS.SENSITIVITY = 'RESTRICTED';

-- Projection policy: prevent SERVICE role from reading raw financial amounts
CREATE OR REPLACE PROJECTION POLICY PINNACLE_FINANCIAL_PROJECTION
AS () RETURNS PROJECTION_CONSTRAINT ->
  CASE
    WHEN CURRENT_ROLE() = 'PINNACLE_SERVICE_RL' THEN PROJECTION_CONSTRAINT(PREVENT => TRUE)
    ELSE PROJECTION_CONSTRAINT(PREVENT => FALSE)
  END;
```

**For David:** These controls are enforced at the Snowflake engine level. No amount of SQL creativity can bypass them -- a masked column returns masked data regardless of the query structure. The Semantic View adds a further abstraction layer: even if underlying columns are accessible, the Semantic View only exposes the columns and metrics it explicitly defines.

---

## 3. Audit & Compliance

### 3.1 Query History Retention

**Snowflake Feature:** ACCOUNT_USAGE.QUERY_HISTORY (365-day retention, immutable)

Every SQL statement executed against the Pinnacle database is logged with:

| Field | Description | Use Case |
|---|---|---|
| `QUERY_TEXT` | Full SQL statement | Reproduce any result; verify AI-generated SQL |
| `USER_NAME` | Who ran it | Attribution for audit |
| `ROLE_NAME` | Which role was active | Verify least-privilege compliance |
| `WAREHOUSE_NAME` | Compute resource used | Cost attribution |
| `EXECUTION_STATUS` | Success / failure | Detect unauthorized access attempts |
| `ROWS_PRODUCED` | Result row count | Detect bulk data exfiltration |
| `START_TIME` / `END_TIME` | Timestamps | Timeline reconstruction for investigations |
| `QUERY_TAG` | Custom metadata | Tag Cortex Analyst queries for AI audit trail |

**For Sarah:** This is immutable -- no user, including ACCOUNTADMIN, can delete or modify query history. It is retained for 365 days automatically. For longer retention (SEC requires 5-7 years for certain records), Snowflake data can be exported to an external archive.

**Compliance query example:**

```sql
-- All queries against client PII in the last 30 days
SELECT
    USER_NAME,
    ROLE_NAME,
    QUERY_TEXT,
    START_TIME,
    ROWS_PRODUCED
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
  AND (QUERY_TEXT ILIKE '%DIM_CLIENT%' OR QUERY_TEXT ILIKE '%CLIENT_NAME%')
  AND EXECUTION_STATUS = 'SUCCESS'
ORDER BY START_TIME DESC;
```

### 3.2 Access Logging

**Snowflake Feature:** ACCOUNT_USAGE.ACCESS_HISTORY (365-day retention)

Column-level access tracking: every time a user reads a column, Snowflake logs which columns were accessed, from which tables, and which columns appeared in the query result.

| Audit View | What It Tracks | Retention | SOC 2 |
|---|---|---|---|
| `LOGIN_HISTORY` | All authentication attempts (success + failure), IP address, client type | 365 days | CC7.2 |
| `QUERY_HISTORY` | Every SQL executed, user, role, warehouse, duration, rows | 365 days | CC7.2 |
| `ACCESS_HISTORY` | Table and column-level reads, who accessed what and when | 365 days | CC7.2 |
| `GRANTS_TO_ROLES` | All permission changes, role assignments, policy modifications | 365 days | CC6.2 |
| `SESSIONS` | Session start/end, IP, authentication method, client | 365 days | CC7.2 |
| `DATA_TRANSFER_HISTORY` | Data exports, cross-region/cross-cloud transfers | 365 days | CC6.7 |

**Alerting configuration:**

```sql
-- Alert: Failed login spike (>5 failures in 10 minutes)
CREATE OR REPLACE ALERT PINNACLE_FAILED_LOGIN_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
    WHERE IS_SUCCESS = 'NO'
      AND EVENT_TIMESTAMP >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
    HAVING COUNT(*) > 5
  ))
  THEN
    CALL SYSTEM$SEND_EMAIL(
      'PINNACLE_SECURITY_NOTIFICATIONS',
      'security@pinnaclefinancial.com',
      'ALERT: Failed login spike detected',
      'More than 5 failed login attempts in the last 10 minutes. Review LOGIN_HISTORY immediately.'
    );

-- Alert: Off-hours data access (outside 6 AM - 10 PM ET on weekdays)
CREATE OR REPLACE ALERT PINNACLE_OFFHOURS_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '30 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -30, CURRENT_TIMESTAMP())
      AND DATABASE_NAME = 'PINNACLE_FINANCIAL'
      AND (HOUR(CONVERT_TIMEZONE('America/New_York', START_TIME)) NOT BETWEEN 6 AND 22
           OR DAYOFWEEKISO(START_TIME) > 5)
      AND ROLE_NAME NOT IN ('PINNACLE_SERVICE_RL')  -- exclude scheduled jobs
  ))
  THEN
    CALL SYSTEM$SEND_EMAIL(
      'PINNACLE_SECURITY_NOTIFICATIONS',
      'security@pinnaclefinancial.com',
      'ALERT: Off-hours data access detected',
      'A user accessed Pinnacle Financial data outside normal business hours. Review QUERY_HISTORY.'
    );

-- Alert: Bulk data export (>10,000 rows in a single query by non-service role)
CREATE OR REPLACE ALERT PINNACLE_BULK_EXPORT_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -15, CURRENT_TIMESTAMP())
      AND DATABASE_NAME = 'PINNACLE_FINANCIAL'
      AND ROWS_PRODUCED > 10000
      AND ROLE_NAME NOT IN ('PINNACLE_SERVICE_RL', 'PINNACLE_OPS_RL')
  ))
  THEN
    CALL SYSTEM$SEND_EMAIL(
      'PINNACLE_SECURITY_NOTIFICATIONS',
      'security@pinnaclefinancial.com',
      'ALERT: Bulk data export detected',
      'A query returned >10,000 rows from a non-service role. Possible data exfiltration. Review QUERY_HISTORY.'
    );
```

### 3.3 SOC 2 Type II Mapping

Complete mapping of SOC 2 Trust Services Criteria to Snowflake controls:

| SOC 2 Control | Category | Snowflake Implementation | Evidence Source |
|---|---|---|---|
| **CC1.1** | Control Environment | Documented security architecture (this document), role definitions | This document |
| **CC2.1** | Information & Communication | Security policies communicated via IdP group assignments, role-based access | SCIM provisioning logs |
| **CC3.1** | Risk Assessment | Quarterly access review, sensitivity classification tags | ACCESS_HISTORY, tag audit |
| **CC5.1** | Control Activities | Masking policies, row access policies, network policies | Policy DDL + POLICY_REFERENCES view |
| **CC6.1** | Logical Access Controls | MFA, network policies, session policies, SAML SSO | LOGIN_HISTORY, SESSIONS |
| **CC6.2** | Access Provisioning | SCIM auto-provisioning, SECURITYADMIN manages grants | GRANTS_TO_ROLES, SCIM logs |
| **CC6.3** | Privileged Access Mgmt | ACCOUNTADMIN restricted to break-glass, logged | QUERY_HISTORY (filter ROLE_NAME = 'ACCOUNTADMIN') |
| **CC6.5** | Data Protection | Dynamic masking, row access policies, column tags | POLICY_REFERENCES, TAG_REFERENCES |
| **CC6.6** | Access Removal | SCIM deprovisioning, IdP-driven | SCIM sync logs, LOGIN_HISTORY (disabled users) |
| **CC6.7** | Transmission Security | TLS 1.2+ for all connections, AES-256 at rest | Snowflake infrastructure (no user config) |
| **CC7.1** | Change Detection | Dynamic Table lineage, schema change tracking | ACCOUNT_USAGE schema change views |
| **CC7.2** | Security Monitoring | LOGIN_HISTORY, QUERY_HISTORY, ACCESS_HISTORY, alerts | ACCOUNT_USAGE (365-day immutable retention) |
| **CC7.3** | Evaluation of Events | Alert rules for failed logins, bulk exports, off-hours access | Alert configurations (Section 3.2) |
| **CC8.1** | Incident Response | Automated alerts, escalation to security@pinnaclefinancial.com | Alert history, email logs |

**Quarterly Evidence Package for Sarah:**

```sql
-- 1. Active users and roles (who has access to what)
SELECT
    u.NAME AS USER_NAME,
    u.EMAIL,
    u.DISABLED,
    u.LAST_SUCCESS_LOGIN,
    LISTAGG(DISTINCT gr.ROLE, ', ') AS ASSIGNED_ROLES
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS u
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS gr ON gr.GRANTEE_NAME = u.NAME
WHERE u.DELETED_ON IS NULL
GROUP BY u.NAME, u.EMAIL, u.DISABLED, u.LAST_SUCCESS_LOGIN
ORDER BY u.LAST_SUCCESS_LOGIN DESC;

-- 2. Privilege escalation events (any ACCOUNTADMIN usage)
SELECT USER_NAME, ROLE_NAME, QUERY_TEXT, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE ROLE_NAME = 'ACCOUNTADMIN'
  AND START_TIME >= DATEADD(DAY, -90, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;

-- 3. Policy coverage: which tables have masking and row access policies
SELECT *
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'PINNACLE_FINANCIAL.CURATED.DIM_CLIENT'
));

-- 4. Failed login attempts summary
SELECT
    DATE_TRUNC('DAY', EVENT_TIMESTAMP) AS DAY,
    COUNT(*) AS FAILED_LOGINS,
    COUNT(DISTINCT USER_NAME) AS DISTINCT_USERS,
    LISTAGG(DISTINCT CLIENT_IP, ', ') AS SOURCE_IPS
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE IS_SUCCESS = 'NO'
  AND EVENT_TIMESTAMP >= DATEADD(DAY, -90, CURRENT_TIMESTAMP())
GROUP BY DAY
ORDER BY DAY DESC;
```

### 3.4 Regulatory Reporting Controls

| Regulation | Requirement | Snowflake Control |
|---|---|---|
| **SEC Rule 17a-4** | Records retention (5-7 years) | ACCOUNT_USAGE (365 days native). For longer retention: scheduled export of QUERY_HISTORY and ACCESS_HISTORY to a Snowflake archival schema with 7-year Time Travel. |
| **SEC Form ADV** | Client AUM and fee disclosures | FACT_CLIENT_AUM and FACT_REVENUE provide source data. Semantic View metrics ensure consistent calculation. |
| **SEC Form 13F** | Quarterly holdings report | RAW.GENEVA_POSITIONS provides authoritative holdings data. Row access policies ensure only authorized users can access. |
| **SOX (if applicable)** | Financial reporting controls | Immutable RAW schema (append-only), Dynamic Table lineage, query history for every number in the P&L. |
| **GDPR / CCPA** | PII protection, right to erasure | Dynamic masking for routine access. For erasure requests: DELETE from RAW + CURATED with audit trail, then `ALTER TABLE ... RECLUSTER` to purge from micro-partitions. |

---

## 4. AI Governance

### 4.1 Cortex Analyst Guardrails

Cortex Analyst generates SQL from natural language queries. Without guardrails, it could produce queries that return sensitive data, perform unauthorized aggregations, or generate incorrect results. The Semantic View controls what Cortex Analyst can and cannot do.

**Guardrail 1: Scope restriction via Semantic View**

The Semantic View is the only data source Cortex Analyst can query. It explicitly defines which tables, columns, and metrics are available. Anything not in the Semantic View is invisible to the AI.

| What's In Scope | What's Out of Scope |
|---|---|
| Revenue by client, product, time | Individual security positions |
| Expense by category, department | Trade execution details |
| Client segment, AUM tier, office | Client SSN, tax ID, email, phone |
| Profitability metrics (margin, ratio) | Raw Geneva/NetSuite/Salesforce data |
| Budget vs actual comparisons | Compliance violation records |

**Guardrail 2: AI_QUESTION_CATEGORIZATION**

Built into the Semantic View DDL -- tells Cortex Analyst to reject questions it cannot safely answer:

```
AI_QUESTION_CATEGORIZATION
  'This model covers Pinnacle Financial analytics only.
   IN SCOPE: Revenue, expenses, profitability, AUM, client segments, fee rates.
   OUT OF SCOPE: Individual trades, client PII, compliance violations, market data,
   investment performance attribution, regulatory filings.
   If the question is out of scope, explain what data is available instead of guessing.'
```

**Guardrail 3: AI_SQL_GENERATION rules**

Built into the Semantic View DDL -- forces safe SQL patterns:

```
AI_SQL_GENERATION
  'RULES:
   1. ROUND all currency to 2 decimal places, percentages to 1.
   2. Always use NULLIF(denominator, 0) for division.
   3. Default time scope: most recent complete month if not specified.
   4. Never use SELECT * -- always specify columns explicitly.
   5. Never generate DDL, DML, or DCL (only SELECT queries).
   6. Always include a time dimension (month, quarter, year) for financial metrics.
   7. Cap result sets at 1000 rows with LIMIT unless user specifies otherwise.'
```

**Guardrail 4: Masking policies apply to AI queries**

Cortex Analyst executes SQL under the user's active role. If Margaret Chen (EXECUTIVE role) asks "Show me client names and revenue," CLIENT_NAME comes back masked because her role has the masking policy applied. The AI does not bypass masking.

### 4.2 SQL Approval Workflows

**For David:** Every answer from Cortex Analyst is backed by a SQL query that can be inspected.

| Control | Implementation | Detail |
|---|---|---|
| SQL visibility | Snowflake Intelligence UI | Every answer includes a "Show SQL" button. The generated SQL is displayed alongside the result. |
| Query tagging | `QUERY_TAG` metadata | All Cortex Analyst queries are auto-tagged with `CORTEX_ANALYST` in QUERY_HISTORY. Sarah can filter audit logs to AI-generated queries only. |
| No write access | Semantic View is read-only | Cortex Analyst can only generate SELECT statements. It has no ability to INSERT, UPDATE, DELETE, CREATE, or DROP anything. |
| Result validation | Human-in-the-loop | For month-end close or regulatory reports, the workflow is: (1) ask Cortex Analyst, (2) review the generated SQL, (3) cross-check against Geneva/NetSuite source reports, (4) approve for use. |

**Audit query for AI-generated SQL:**

```sql
-- All Cortex Analyst queries in the last 7 days
SELECT
    USER_NAME,
    ROLE_NAME,
    QUERY_TEXT,
    ROWS_PRODUCED,
    START_TIME,
    TOTAL_ELAPSED_TIME / 1000 AS DURATION_SEC
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TAG ILIKE '%CORTEX_ANALYST%'
  AND START_TIME >= DATEADD(DAY, -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

### 4.3 Explainability Requirements

Every AI-generated answer must be traceable to its source data. This is non-negotiable for financial analytics at Pinnacle.

| Requirement | How Snowflake Meets It |
|---|---|
| **SQL transparency** | Cortex Analyst always produces standard SQL. No opaque model outputs -- the SQL is the explanation. David can read, modify, and re-run any generated query. |
| **Data lineage** | ACCESS_HISTORY records exactly which tables and columns were read for each query. Combined with the Semantic View definition, this creates a full chain: question → SQL → tables → columns → source system. |
| **Metric definitions** | The Semantic View's METRICS section defines every calculation (e.g., `PROFIT_MARGIN = (revenue - expenses) / revenue * 100`). These are documented, versioned, and auditable. No hidden formulas. |
| **Deterministic results** | The same question with the same data returns the same SQL and the same result. Cortex Analyst is not generative in the result -- it generates SQL, which Snowflake executes deterministically. |
| **Error acknowledgment** | AI_QUESTION_CATEGORIZATION instructs the agent to say "I don't have that data" rather than hallucinate an answer. |

**For David:** This is not a black box. Every number traces back to a SQL query, which traces back to specific table columns, which trace back to Geneva, NetSuite, or Salesforce records. The chain is fully auditable and reproducible.

**For Sarah:** Every AI interaction is logged in QUERY_HISTORY with the `CORTEX_ANALYST` tag. You can audit exactly what was asked, what SQL was generated, what data was accessed, and who asked it -- for the last 365 days.

---

## Appendix: Implementation Checklist

| # | Task | Owner | SOC 2 Control | Status |
|---|---|---|---|---|
| 1 | Configure SAML 2.0 integration with corporate IdP | IT / Snowflake Admin | CC6.1 | |
| 2 | Enable MFA enforcement via authentication policy | Snowflake Admin | CC6.1 | |
| 3 | Configure SCIM provisioning for user sync | IT / IdP Admin | CC6.2 | |
| 4 | Create and apply network policy (office + VPN IPs) | Snowflake Admin | CC6.1 | |
| 5 | Create session policy (30-min idle, 8-hr max) | Snowflake Admin | CC6.1 | |
| 6 | Create functional roles and role hierarchy | Snowflake Admin | CC6.2 | |
| 7 | Apply schema-level grants per role matrix | Snowflake Admin | CC6.5 | |
| 8 | Create and apply masking policies for PII columns | Data Engineer | CC6.5 | |
| 9 | Create and apply row access policy for client data | Data Engineer | CC6.5 | |
| 10 | Create sensitivity tags and apply to columns | Data Engineer | CC6.5 | |
| 11 | Configure security alerts (failed login, bulk export, off-hours) | Snowflake Admin | CC7.3, CC8.1 | |
| 12 | Configure AI_SQL_GENERATION and AI_QUESTION_CATEGORIZATION in Semantic View | Data Engineer | AI Governance | |
| 13 | Validate masking: test each role sees correct masking level | QA / David Park | CC6.5 | |
| 14 | Validate row access: test analyst sees only assigned clients | QA / David Park | CC6.5 | |
| 15 | Generate quarterly evidence package and review with Sarah | Compliance | CC3.1 | |
| 16 | Document audit log export process for 5-year SEC retention | Compliance / IT | SEC 17a-4 | |
| 17 | Key-pair auth setup for Power BI and API service accounts | IT | CC6.1 | |
| 18 | Security architecture review sign-off | David Park, Sarah Martinez | CC1.1 | |
