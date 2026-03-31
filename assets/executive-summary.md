# Snowflake Financial Analytics -- Executive Summary

**Prepared for:** Margaret Chen, CFO
**From:** Data & Operations Team

---

## What We're Building

A single, secure platform that connects Pinnacle's three core systems -- Geneva (portfolio accounting), NetSuite (general ledger), and Salesforce (client data) -- into one place where anyone on the finance team can ask questions in plain English and get accurate answers in seconds.

Today, getting a simple answer like "What is our profit margin by client segment this quarter?" requires pulling data from multiple systems, reconciling it manually across spreadsheets, and waiting days. With this platform, Margaret or any authorized team member types that question into a chat interface and gets the answer -- with the supporting math visible -- in under five seconds.

The existing Power BI dashboards continue to work. Nothing is being replaced. We're adding a faster, smarter layer on top.

---

## How It Addresses Our Risks

**David's concern: "Can we trust the numbers?"**

Every answer the system produces is backed by a standard SQL query that David's team can inspect, re-run, and verify. There are no black boxes. The system uses a single set of metric definitions (e.g., "profit margin = revenue minus expenses, divided by revenue") that are locked down and versioned. Power BI and the chat interface both read from the same definitions, so numbers always match. Automated checks run every 30 minutes comparing Snowflake's data against our source systems, and alert the team immediately if anything is off.

**Sarah's concern: "Can we prove compliance?"**

Every query, every login, and every data access is logged for 365 days and cannot be modified by anyone -- including system administrators. Client names, tax IDs, and account numbers are automatically masked based on who is looking: executives see anonymized data, compliance sees the full picture. Row-level controls ensure analysts only see clients assigned to them. All of this maps directly to SOC 2 requirements, and Sarah's team has a quarterly review checklist with pre-built reports.

**Business continuity: "What if something breaks?"**

Source data is never modified after it enters the platform -- it is preserved exactly as received. If a calculation error is found, we fix the formula and the system reprocesses automatically. The original data is always available to recover from. Automated monitoring detects pipeline failures, missing data, and anomalies before they reach a dashboard.

---

## Timeline to Value

| Milestone | What It Delivers |
|---|---|
| **POC complete** (now) | Working demo: star schema with realistic data, natural language query interface, sample dashboards. Proves the concept works with Pinnacle's data model. |
| **Phase 1: Foundation** | Snowflake account provisioned, security policies in place, role hierarchy configured. Sarah can review and approve the access control model. |
| **Phase 2: Connect sources** | Geneva, NetSuite, and Salesforce flowing into Snowflake automatically. David's team validates data accuracy against source systems. |
| **Phase 3: Transform & model** | Star schema built, semantic model deployed, metrics locked in. Finance team can start querying real data. |
| **Phase 4: Go live** | Cortex Agent enabled for natural language queries. Power BI migrated to Snowflake. Executives get self-service access. |
| **Phase 5: Operationalize** | Monitoring, alerting, runbooks, and team training complete. First month-end close runs on the new platform in parallel with the old process. |

Month-end close target: from 10 business days down to 3, starting with the first parallel run.

---

## What This Means in Dollars

- **3 FTEs** currently spend 50% of their time on manual data reconciliation. Automated pipelines and checks eliminate most of that work, freeing ~1.5 FTE-equivalents for higher-value analysis.
- **Executives** currently wait days for ad-hoc reports. Self-service answers in seconds means faster decisions and fewer interruptions to the finance team.
- **Compliance risk** from manual regulatory report preparation is reduced by governed, auditable data with a full trail from question to answer to source record.

---

## Next Steps

1. **This week:** Present this POC to the leadership team. Walk through a live demo with 5-7 sample questions that address each stakeholder's priorities.
2. **Decision point:** Go / no-go on proceeding to production integration (Phase 1-2).
3. **If approved:** David's team begins source system connector setup. Sarah reviews and signs off on the security architecture and access control model.
4. **First value milestone:** Real Pinnacle data queryable via natural language, validated against source systems, with full audit trail.
