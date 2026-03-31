# Pinnacle Financial Services -- SOC 2 Compliance Checklist

**Owner:** Sarah Martinez, Head of Compliance
**Reviewer:** David Park, VP of Operations
**Scope:** Snowflake platform hosting Pinnacle Financial analytics (PINNACLE_FINANCIAL database)
**Standard:** SOC 2 Type II -- Trust Services Criteria (2017)

---

## CC6.1 -- Logical Access Controls

*The entity implements logical access security software, infrastructure, and architectures over protected information assets to protect them from security events.*

| # | Requirement | Snowflake Feature | Implementation | Evidence Source | Status |
|---|---|---|---|---|---|
| 6.1.1 | Network perimeter restricts access to authorized locations | Network Policy | IP allowlist limited to NY HQ (`10.1.0.0/16`), Boston (`10.2.0.0/16`), SF (`10.3.0.0/16`), VPN (`172.16.0.0/12`). All other IPs blocked at connection time. | `SHOW NETWORK POLICIES;` `DESCRIBE NETWORK POLICY PINNACLE_NETWORK_POLICY;` | |
| 6.1.2 | Connections encrypted in transit | TLS 1.2+ (automatic) | All client-to-Snowflake connections enforce minimum TLS 1.2. No configuration required -- enforced by platform. Certificate pinning available for JDBC/ODBC drivers. | Snowflake SOC 2 report (platform-level control) | |
| 6.1.3 | Data encrypted at rest | AES-256 (automatic) | All data, metadata, and temporary files encrypted via hierarchical key model (account key > table key > micro-partition key). Keys rotated automatically. | Snowflake SOC 2 report (platform-level control) | |
| 6.1.4 | Customer-managed encryption keys available | Tri-Secret Secure | Optional: Pinnacle provides a KMS key (AWS KMS) that wraps Snowflake's account master key. Pinnacle can revoke access by disabling the KMS key. | `SHOW PARAMETERS LIKE '%ENCRYPTION%' IN ACCOUNT;` | |
| 6.1.5 | Session controls limit exposure | Session Policy | Idle timeout: 30 minutes. Max session: 8 hours. Applied to all users. Prevents unattended terminal access. | `SHOW SESSION POLICIES;` `DESCRIBE SESSION POLICY PINNACLE_SESSION_POLICY;` | |
| 6.1.6 | Failed login attempts are limited | Authentication Policy | Account lockout after 5 consecutive failed attempts. Lockout duration: 15 minutes. Applies to all non-SSO authentication. | `SHOW AUTHENTICATION POLICIES;` LOGIN_HISTORY (filter IS_SUCCESS = 'NO') | |
| 6.1.7 | Service accounts use non-password auth | Key-Pair Authentication | Power BI and API service accounts use RSA 2048-bit key pairs. No passwords stored or transmitted. Keys rotated quarterly. | `DESCRIBE USER SVC_POWERBI;` (check RSA_PUBLIC_KEY is set) | |

**Validation Query:**
```sql
-- Verify network policy is applied to account
SELECT SYSTEM$ALLOWLISTED_IPS() AS ALLOWED_IPS;

-- Verify session policy exists and is configured
SHOW SESSION POLICIES;

-- Verify no users have password-only auth (all should be SSO or key-pair)
SELECT NAME, HAS_PASSWORD, HAS_RSA_PUBLIC_KEY,
       EXT_AUTHN_DUO, DISABLED
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE DELETED_ON IS NULL
ORDER BY NAME;
```

---

## CC6.2 -- Authentication

*Prior to issuing system credentials and granting system access, the entity registers and authorizes new internal and external users. For those users whose access is no longer required, the entity removes credentials and access.*

| # | Requirement | Snowflake Feature | Implementation | Evidence Source | Status |
|---|---|---|---|---|---|
| 6.2.1 | Centralized identity management | SAML 2.0 SSO | All human users authenticate via corporate IdP (Azure AD / Okta). No local Snowflake passwords for human accounts. | `SHOW SECURITY INTEGRATIONS;` `DESCRIBE SECURITY INTEGRATION PINNACLE_SAML_INTEGRATION;` | |
| 6.2.2 | Multi-factor authentication enforced | MFA via Authentication Policy | TOTP-based MFA required for all human users on Snowsight and Snowflake UI clients. Enforced at policy level, not optional per user. | `SHOW AUTHENTICATION POLICIES;` LOGIN_HISTORY (check `SECOND_AUTHENTICATION_FACTOR` column) | |
| 6.2.3 | Automated user provisioning | SCIM 2.0 | Users and groups synced automatically from IdP. New hires provisioned within minutes of IdP group assignment. No manual Snowflake user creation. | SCIM integration logs in IdP admin console | |
| 6.2.4 | Automated deprovisioning on termination | SCIM 2.0 | When a user is disabled or removed in the IdP, SCIM immediately disables the Snowflake user. The user cannot authenticate. | `SELECT NAME, DISABLED, LAST_SUCCESS_LOGIN FROM SNOWFLAKE.ACCOUNT_USAGE.USERS WHERE DISABLED = 'true';` | |
| 6.2.5 | Access provisioning requires approval | IdP group-based role assignment | Role assignment is controlled by IdP group membership. Adding a user to the "Pinnacle Analysts" IdP group grants PINNACLE_ANALYST role via SCIM. Group changes require manager approval in IdP workflow. | IdP audit logs (group membership changes) | |
| 6.2.6 | Periodic access review | GRANTS_TO_USERS + GRANTS_TO_ROLES | Quarterly review: Sarah Martinez reviews all role assignments. Compare active users/roles against HR active employee list. Revoke stale access. | Quarterly access review report (see query below) | |
| 6.2.7 | Privileged account inventory | ACCOUNTADMIN usage tracking | Only 2 designated admins have ACCOUNTADMIN. All ACCOUNTADMIN usage logged and triggers an alert. Quarterly review confirms no unauthorized grants. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE ROLE_NAME = 'ACCOUNTADMIN';` | |

**Validation Query:**
```sql
-- Quarterly access review: all users, their roles, and last login
SELECT
    u.NAME AS USER_NAME,
    u.EMAIL,
    u.DISABLED,
    u.LAST_SUCCESS_LOGIN,
    u.CREATED_ON,
    LISTAGG(DISTINCT gtu.ROLE, ', ') WITHIN GROUP (ORDER BY gtu.ROLE) AS ROLES
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS u
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS gtu
    ON gtu.GRANTEE_NAME = u.NAME
    AND gtu.DELETED_ON IS NULL
WHERE u.DELETED_ON IS NULL
GROUP BY u.NAME, u.EMAIL, u.DISABLED, u.LAST_SUCCESS_LOGIN, u.CREATED_ON
ORDER BY u.LAST_SUCCESS_LOGIN DESC NULLS LAST;

-- Users who haven't logged in for 90+ days (candidates for deprovisioning)
SELECT NAME, EMAIL, LAST_SUCCESS_LOGIN,
       DATEDIFF(DAY, LAST_SUCCESS_LOGIN, CURRENT_TIMESTAMP()) AS DAYS_INACTIVE
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE DELETED_ON IS NULL
  AND DISABLED = 'false'
  AND (LAST_SUCCESS_LOGIN IS NULL
       OR DATEDIFF(DAY, LAST_SUCCESS_LOGIN, CURRENT_TIMESTAMP()) > 90)
ORDER BY DAYS_INACTIVE DESC;

-- All ACCOUNTADMIN role grants (should be exactly 2)
SELECT GRANTEE_NAME, ROLE, GRANTED_ON, GRANTED_BY
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
WHERE ROLE = 'ACCOUNTADMIN'
  AND DELETED_ON IS NULL;
```

---

## CC6.3 -- Authorization

*The entity authorizes, modifies, or removes access to data, software, functions, and other protected information assets based on roles, responsibilities, or the system design and changes, giving consideration to the concepts of least privilege and segregation of duties.*

| # | Requirement | Snowflake Feature | Implementation | Evidence Source | Status |
|---|---|---|---|---|---|
| 6.3.1 | Role-based access control | RBAC (roles + grants) | 5 functional roles: PINNACLE_DATA_ENG (write), PINNACLE_ANALYST (read), PINNACLE_VIEWER (dashboards), PINNACLE_COMPLIANCE (audit), PINNACLE_ADMIN (management). Users inherit permissions from their assigned role only. | `SHOW ROLES;` `SHOW GRANTS TO ROLE PINNACLE_ANALYST;` | |
| 6.3.2 | Least privilege enforced | Schema-level grants | VIEWER cannot access RAW or CURATED. ANALYST cannot write. DATA_ENG cannot access audit logs. Each role has minimum permissions for its function. | `SHOW GRANTS TO ROLE PINNACLE_VIEWER;` (verify no RAW/CURATED access) | |
| 6.3.3 | Segregation of duties | Role hierarchy separation | Compliance role is independent from data engineering. DATA_ENG cannot read audit logs. COMPLIANCE cannot modify data. Prevents self-audit. | Role hierarchy in `role-hierarchy.md` | |
| 6.3.4 | PII access restricted by role | Dynamic Data Masking | 5 masking policies (name, SSN, account number, email, phone). Only COMPLIANCE sees full SSN. Only COMPLIANCE and DATA_ENG see full client names. All others see masked values. | `SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_DOMAIN => 'TABLE', REF_ENTITY_NAME => 'PINNACLE_FINANCIAL.CURATED.DIM_CLIENT'));` | |
| 6.3.5 | Row-level data segmentation | Row Access Policy | Analysts see only clients assigned to them or their office. Executives, compliance, and data engineering see all clients. Enforced at query time by Snowflake engine. | `DESCRIBE ROW ACCESS POLICY CURATED.CLIENT_ROW_POLICY;` | |
| 6.3.6 | Sensitive columns hidden from unauthorized roles | Projection Policy + Tags | Columns tagged RESTRICTED (TAX_ID) hidden from all roles except COMPLIANCE. Financial amounts hidden from VIEWER (accessible only via Semantic View metrics). | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES WHERE TAG_NAME = 'SENSITIVITY';` | |
| 6.3.7 | Access changes are auditable | GRANTS_TO_ROLES history | Every GRANT and REVOKE is logged with timestamp, grantor, grantee, privilege, and object. 365-day retention. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES WHERE CREATED_ON >= DATEADD(DAY, -90, CURRENT_TIMESTAMP()) ORDER BY CREATED_ON DESC;` | |
| 6.3.8 | Service accounts have minimal access | PINNACLE_VIEWER role | Power BI and API service accounts assigned VIEWER role: read-only on ANALYTICS schema views, no RAW/CURATED access, PII masked, no DDL/DML. | `SHOW GRANTS TO ROLE PINNACLE_VIEWER;` | |

**Validation Query:**
```sql
-- Verify masking policies are applied to all PII columns
SELECT
    POLICY_NAME,
    REF_ENTITY_NAME AS TABLE_NAME,
    REF_COLUMN_NAME AS COLUMN_NAME,
    POLICY_KIND
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'PINNACLE_FINANCIAL.CURATED.DIM_CLIENT'
))
WHERE POLICY_KIND = 'MASKING_POLICY';

-- Verify row access policy is applied
SELECT
    POLICY_NAME,
    REF_ENTITY_NAME AS TABLE_NAME,
    POLICY_KIND
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'PINNACLE_FINANCIAL.CURATED.DIM_CLIENT'
))
WHERE POLICY_KIND = 'ROW_ACCESS_POLICY';

-- Test masking: run as ANALYST and verify CLIENT_NAME is masked
-- (manual test during quarterly review)
USE ROLE PINNACLE_ANALYST;
SELECT CLIENT_KEY, CLIENT_NAME, AUM_TIER
FROM PINNACLE_FINANCIAL.CURATED.DIM_CLIENT
LIMIT 5;
-- Expected: CLIENT_NAME shows "J*** D**" pattern
```

---

## CC7.1 -- System Monitoring

*The entity monitors system components and the operation of those components for anomalies that are indicative of malicious acts, natural disasters, and errors affecting the entity's ability to meet its objectives; anomalies are analyzed to determine whether they represent security events.*

| # | Requirement | Snowflake Feature | Implementation | Evidence Source | Status |
|---|---|---|---|---|---|
| 7.1.1 | All authentication attempts logged | LOGIN_HISTORY | Every login attempt (success and failure) recorded with timestamp, user, IP address, client type, authentication method, error code. 365-day immutable retention. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY ORDER BY EVENT_TIMESTAMP DESC LIMIT 100;` | |
| 7.1.2 | All queries logged | QUERY_HISTORY | Every SQL statement recorded with user, role, warehouse, execution status, duration, rows produced, query text. 365-day retention. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE DATABASE_NAME = 'PINNACLE_FINANCIAL' ORDER BY START_TIME DESC LIMIT 100;` | |
| 7.1.3 | Column-level access tracked | ACCESS_HISTORY | Every table and column read is recorded: which user, which role, which columns were accessed, which columns appeared in the result. 365-day retention. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY WHERE QUERY_START_TIME >= DATEADD(DAY, -7, CURRENT_TIMESTAMP()) ORDER BY QUERY_START_TIME DESC;` | |
| 7.1.4 | Permission changes tracked | GRANTS_TO_ROLES / GRANTS_TO_USERS | Every GRANT and REVOKE logged with grantor, grantee, privilege, object, timestamp. Detects unauthorized privilege escalation. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES WHERE CREATED_ON >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());` | |
| 7.1.5 | Data transfer activity tracked | DATA_TRANSFER_HISTORY | Cross-region and cross-cloud data transfers logged. Detects unauthorized data movement outside Pinnacle's Snowflake account. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_TRANSFER_HISTORY ORDER BY START_TIME DESC;` | |
| 7.1.6 | Schema changes tracked | QUERY_HISTORY (DDL filter) | All CREATE, ALTER, DROP statements logged in QUERY_HISTORY. Filter by `QUERY_TYPE` to identify schema modifications. | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE QUERY_TYPE IN ('CREATE_TABLE', 'ALTER_TABLE_MODIFY_COLUMN', 'DROP') AND DATABASE_NAME = 'PINNACLE_FINANCIAL';` | |
| 7.1.7 | Pipeline health monitored | Dynamic Table status + Snowpipe COPY_HISTORY | Dynamic Table refresh failures logged. Snowpipe load errors recorded per file. Scheduled monitoring task checks every 30 minutes. | `SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLES());` `SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(...));` | |
| 7.1.8 | Audit logs immutable | ACCOUNT_USAGE (system-managed) | Audit views are read-only. No user -- including ACCOUNTADMIN -- can modify, delete, or truncate audit records. Retention is 365 days, system-enforced. | Snowflake platform guarantee (documented in SOC 2 report) | |

**Validation Query:**
```sql
-- Monitoring coverage: confirm all audit views are accessible to COMPLIANCE
USE ROLE PINNACLE_COMPLIANCE;

-- Should return data (not permission error)
SELECT COUNT(*) AS LOGIN_EVENTS FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE EVENT_TIMESTAMP >= DATEADD(DAY, -1, CURRENT_TIMESTAMP());

SELECT COUNT(*) AS QUERIES FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(DAY, -1, CURRENT_TIMESTAMP());

SELECT COUNT(*) AS ACCESS_EVENTS FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE QUERY_START_TIME >= DATEADD(DAY, -1, CURRENT_TIMESTAMP());

SELECT COUNT(*) AS GRANT_EVENTS FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE CREATED_ON >= DATEADD(DAY, -30, CURRENT_TIMESTAMP());
```

---

## CC7.2 -- Anomaly Detection

*The entity monitors system components for anomalies indicative of malicious acts and takes action when anomalies are detected.*

| # | Requirement | Snowflake Feature | Implementation | Evidence Source | Status |
|---|---|---|---|---|---|
| 7.2.1 | Failed login spike detection | Snowflake Alert | Alert fires when >5 failed logins occur within 10 minutes. Sends email to security@pinnaclefinancial.com. Detects brute-force or credential stuffing attempts. | `SHOW ALERTS LIKE 'PINNACLE_FAILED_LOGIN%';` Alert history in ALERT_HISTORY view. | |
| 7.2.2 | Privilege escalation detection | Snowflake Alert | Alert fires on any ACCOUNTADMIN usage. Quarterly review confirms only break-glass usage. Any unexpected ACCOUNTADMIN query triggers immediate investigation. | `SHOW ALERTS LIKE 'PINNACLE_PRIV_ESCALATION%';` QUERY_HISTORY filtered by ROLE_NAME. | |
| 7.2.3 | Off-hours access detection | Snowflake Alert | Alert fires when data is accessed outside 6 AM-10 PM ET on weekdays. Service account queries excluded (scheduled jobs). Detects unauthorized after-hours access. | `SHOW ALERTS LIKE 'PINNACLE_OFFHOURS%';` | |
| 7.2.4 | Bulk data export detection | Snowflake Alert | Alert fires when a non-service, non-ops role query returns >10,000 rows. Detects potential data exfiltration. Threshold tunable based on normal usage patterns. | `SHOW ALERTS LIKE 'PINNACLE_BULK_EXPORT%';` | |
| 7.2.5 | Row count anomaly detection | Scheduled Task | Daily task compares fact table row counts to 7-day rolling average. Alert if delta >20%. Detects source system outages, broken pipelines, or data corruption. | `validation-queries.sql` query 1E | |
| 7.2.6 | Revenue total anomaly detection | Scheduled Task | Daily task compares revenue totals to prior day and same day prior month. Alert if delta >50%. Detects fee calculation errors, duplicate transactions, or missing data. | `validation-queries.sql` query 2E | |
| 7.2.7 | Data freshness monitoring | Scheduled Task | Every 30 minutes: check RAW table timestamps, Dynamic Table refresh status, connector sync status. Alert if any source exceeds staleness threshold. | `validation-queries.sql` section 5 | |
| 7.2.8 | AI query anomaly tracking | QUERY_HISTORY + QUERY_TAG | All Cortex Analyst queries tagged. Monthly review of AI-generated queries: volume, users, topics. Detect misuse patterns (e.g., repeated PII probing, out-of-scope questions). | `SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE QUERY_TAG ILIKE '%CORTEX%' ORDER BY START_TIME DESC;` | |

**Alert Implementation:**
```sql
-- 7.2.1: Failed login spike (>5 in 10 minutes)
CREATE OR REPLACE ALERT PINNACLE_FAILED_LOGIN_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
    WHERE IS_SUCCESS = 'NO'
      AND EVENT_TIMESTAMP >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
    HAVING COUNT(*) > 5
  ))
  THEN CALL SYSTEM$SEND_EMAIL('PINNACLE_SECURITY_NOTIFICATIONS',
    'security@pinnaclefinancial.com',
    'ALERT: Failed login spike',
    'More than 5 failed logins in 10 minutes. Investigate LOGIN_HISTORY.');

-- 7.2.2: Privilege escalation (any ACCOUNTADMIN query)
CREATE OR REPLACE ALERT PINNACLE_PRIV_ESCALATION_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE ROLE_NAME = 'ACCOUNTADMIN'
      AND START_TIME >= DATEADD(MINUTE, -5, CURRENT_TIMESTAMP())
  ))
  THEN CALL SYSTEM$SEND_EMAIL('PINNACLE_SECURITY_NOTIFICATIONS',
    'security@pinnaclefinancial.com',
    'ALERT: ACCOUNTADMIN usage detected',
    'A query was executed with ACCOUNTADMIN role. Verify this was authorized break-glass usage.');

-- 7.2.3: Off-hours access (outside 6AM-10PM ET weekdays)
CREATE OR REPLACE ALERT PINNACLE_OFFHOURS_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '30 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -30, CURRENT_TIMESTAMP())
      AND DATABASE_NAME = 'PINNACLE_FINANCIAL'
      AND ROLE_NAME NOT IN ('PINNACLE_SERVICE_RL')
      AND (HOUR(CONVERT_TIMEZONE('America/New_York', START_TIME)) NOT BETWEEN 6 AND 22
           OR DAYOFWEEKISO(START_TIME) > 5)
  ))
  THEN CALL SYSTEM$SEND_EMAIL('PINNACLE_SECURITY_NOTIFICATIONS',
    'security@pinnaclefinancial.com',
    'ALERT: Off-hours data access',
    'Pinnacle Financial data accessed outside business hours. Review QUERY_HISTORY.');

-- 7.2.4: Bulk data export (>10K rows by non-service role)
CREATE OR REPLACE ALERT PINNACLE_BULK_EXPORT_ALERT
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -15, CURRENT_TIMESTAMP())
      AND DATABASE_NAME = 'PINNACLE_FINANCIAL'
      AND ROWS_PRODUCED > 10000
      AND ROLE_NAME NOT IN ('PINNACLE_SERVICE_RL', 'PINNACLE_DATA_ENG')
  ))
  THEN CALL SYSTEM$SEND_EMAIL('PINNACLE_SECURITY_NOTIFICATIONS',
    'security@pinnaclefinancial.com',
    'ALERT: Bulk data export detected',
    'Query returned >10,000 rows. Possible data exfiltration. Review QUERY_HISTORY.');
```

---

## Quarterly Review Checklist

For Sarah Martinez to execute every quarter:

| # | Review Item | Query / Method | Sign-off |
|---|---|---|---|
| 1 | All active users have valid IdP accounts | Compare USERS view against HR active employee list | |
| 2 | No users inactive >90 days remain enabled | CC6.2 validation query (inactive users) | |
| 3 | ACCOUNTADMIN granted to exactly 2 users | CC6.2 validation query (ACCOUNTADMIN grants) | |
| 4 | No ACCOUNTADMIN usage outside break-glass | CC7.2 QUERY_HISTORY filter for ACCOUNTADMIN | |
| 5 | Masking policies applied to all PII columns | CC6.3 validation query (policy references) | |
| 6 | Row access policy active on client tables | CC6.3 validation query (row access policy) | |
| 7 | Network policy restricts to approved IPs | CC6.1 validation query (allowlisted IPs) | |
| 8 | All security alerts active and firing | `SHOW ALERTS;` verify all 4 alerts are STARTED | |
| 9 | No unauthorized privilege grants in period | GRANTS_TO_ROLES filtered to last 90 days | |
| 10 | AI query volume and patterns are normal | QUERY_HISTORY filtered by CORTEX_ANALYST tag | |

**Sign-off:**

```
Reviewed by: _________________________ Date: _________
Sarah Martinez, Head of Compliance

Reviewed by: _________________________ Date: _________
David Park, VP of Operations
```
