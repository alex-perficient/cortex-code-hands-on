# Pinnacle Financial Services -- Documentation Index

**Project:** Snowflake Financial Analytics POC
**Database:** `PINNACLE_FINANCIAL_DEMO_33`
**Last Updated:** March 2026

---

## 1. Architecture Overview

| Document | Description | Audience |
|---|---|---|
| [System Architecture Diagram](assets/architecture-diagram.md) | Mermaid diagram: data sources, ingestion layer, Snowflake platform (RAW/CURATED/ANALYTICS), Cortex AI layer, consumption layer. Includes data latency annotations and design decisions. | David Park, all technical |
| [System Architecture (ASCII)](assets/architecture-diagram%20(ASCII%20version).txt) | Plain-text version of the architecture diagram for embedding in emails, tickets, or terminals. | All |
| [Security Architecture Diagram](assets/security-architecture.md) | Mermaid diagram: authentication flow (SSO/MFA/SCIM), role hierarchy (RBAC), data masking policies (PII), audit logging. SOC 2 control IDs annotated on each component. | David Park, Sarah Martinez |
| [Role Hierarchy Diagram](assets/role-hierarchy.md) | Mermaid diagram: ACCOUNTADMIN through functional roles. Includes access matrix, sensitive column visibility per role, and full GRANT SQL implementation. | David Park, Sarah Martinez |

---

## 2. Integration Guide

| Document | Description | Audience |
|---|---|---|
| [Technical Integration Guide](assets/integration-guide.md) | Complete production integration plan: executive summary, prerequisites, per-source-system connection details (Geneva/NetSuite/Salesforce), transformation logic (RAW to CURATED mappings), refresh schedules, error handling, and implementation timeline. | David Park, data engineering |
| [Data Mapping Document](assets/data-mapping.md) | Column-level mapping from source systems to Snowflake: Salesforce to DIM_CLIENT (10 columns), Geneva to FACT_REVENUE (10 columns), NetSuite to FACT_EXPENSE (9 columns). Includes join logic SQL, cross-reference key resolution, and validation rules per table. | Data engineering, QA |
| [Validation Queries](assets/validation-queries.sql) | 23 executable SQL queries for production data validation: row count comparison, sum validation, date range checks, referential integrity, data freshness, and a combined health dashboard. Ready to schedule as Snowflake Tasks. | David Park, data engineering |

---

## 3. Security & Compliance

| Document | Description | Audience |
|---|---|---|
| [Security Architecture Document](assets/security-document.md) | Comprehensive security architecture: authentication and authorization (SSO, RBAC, row-level security with SQL), data protection (encryption, dynamic masking, column-level security with SQL), audit and compliance (query history, access logging, SOC 2 Type II mapping, regulatory controls), and AI governance (Cortex Analyst guardrails, SQL approval workflows, explainability). Includes implementation checklist. | David Park, Sarah Martinez |
| [SOC 2 Compliance Checklist](assets/soc2-checklist.md) | Control-by-control mapping: CC6.1 (logical access, 7 items), CC6.2 (authentication, 7 items), CC6.3 (authorization, 8 items), CC7.1 (monitoring, 8 items), CC7.2 (anomaly detection, 8 items). Each item has Snowflake feature, implementation detail, evidence source, and status column. Includes alert SQL and quarterly review checklist with sign-off lines. | Sarah Martinez, auditors |
| [Role Hierarchy Diagram](assets/role-hierarchy.md) | Access control model with implementation SQL. (Also listed under Architecture.) | David Park, Sarah Martinez |

---

## 4. Operations

| Document | Description | Audience |
|---|---|---|
| [Validation Queries](assets/validation-queries.sql) | Production monitoring queries. Section 6 (combined health dashboard) is designed to run as a scheduled Snowflake Task every 30 minutes. (Also listed under Integration.) | Data engineering, on-call |
| Runbook: Ingestion Failures | *Placeholder -- to be created during Phase 5 (Operationalize).* Covers: Geneva SFTP file missing, NetSuite connector failure, Salesforce CDC lag, Snowpipe load errors. Response procedures and escalation paths. | Data engineering, on-call |
| Runbook: Transformation Failures | *Placeholder -- to be created during Phase 5 (Operationalize).* Covers: Dynamic Table refresh failure, cross-reference key miss, row count anomaly, revenue sum anomaly. Debugging steps and rollback procedures. | Data engineering, on-call |
| Runbook: Security Incidents | *Placeholder -- to be created during Phase 5 (Operationalize).* Covers: failed login spike response, privilege escalation investigation, off-hours access triage, bulk export review. Escalation to Sarah Martinez for compliance events. | Security, Sarah Martinez |
| Monitoring Dashboard Spec | *Placeholder -- to be created during Phase 5 (Operationalize).* Snowflake Task definitions for the 7 automated checks defined in `validation-queries.sql` Section 6. Alert routing to email and Slack #data-ops. | Data engineering |

---

## 5. Reference Materials

| Document | Description | Audience |
|---|---|---|
| [Executive Summary for CFO](assets/executive-summary.md) | 1-page non-technical summary for Margaret Chen. Covers architecture in business terms, risk mitigation (David's and Sarah's concerns), timeline to value, ROI indicators, and next steps. | Margaret Chen, executive team |
| [Customer Brief](assets/customer-brief.md) | Pinnacle Financial company background: $2B AUM, 50K client accounts, $25M revenue, 150 employees. Current tech stack, pain points, POC requirements (P0/P1/P2), stakeholder profiles, and timeline. | All |
| [Discovery Notes](assets/discovery-notes.md) | Notes from stakeholder discovery sessions. | All |

---

## Document Dependency Map

```
customer-brief.md (company context)
    │
    ├── architecture-diagram.md (system design)
    │       └── integration-guide.md (how to build it)
    │               ├── data-mapping.md (column-level detail)
    │               └── validation-queries.sql (how to verify it)
    │
    ├── security-architecture.md (security design)
    │       ├── security-document.md (full security spec)
    │       ├── role-hierarchy.md (access control)
    │       └── soc2-checklist.md (compliance evidence)
    │
    ├── Runbooks & Monitoring (operational -- placeholder)
    │
    └── executive-summary.md (CFO-facing, draws from all above)
```
