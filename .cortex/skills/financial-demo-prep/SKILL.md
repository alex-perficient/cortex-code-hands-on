---
name: financial-demo-prep
description: "Prepare financial analytics POC demos end-to-end. Use when: setting up a new financial demo, creating sample data for a prospect, building a financial analytics POC. Triggers: financial demo, POC prep, demo prep, financial POC, prospect demo, create financial demo."
---

# Financial Demo Prep

Automates financial analytics POC preparation: requirements, sample data, semantic view, Cortex Agent, and presentation script.

## Prerequisites

- Snowflake connection with CREATE DATABASE, CREATE TABLE, CREATE SEMANTIC VIEW, CREATE AGENT privileges
- Customer brief or discovery notes (company name, AUM, pain points, stakeholders)

## Step 1: Gather Requirements

**Ask** the user (or extract from a customer brief):

1. Company name and type (asset manager, RIA, bank, insurance)
2. AUM or revenue scale (e.g., $500M AUM)
3. Approximate number of clients
4. Office locations
5. Top 2-3 pain points (e.g., slow month-end close, no self-service reporting)
6. Key stakeholders and roles (CFO, VP Ops, Compliance)
7. Target database name (e.g., ACME_FINANCIAL_DEMO)

**Confirm** by summarizing: company profile, database name, pain points addressed, and what will be built (star schema, semantic view, Cortex Agent, presentation script).

⚠️ **STOP** - Wait for user confirmation before proceeding.

## Step 2: Generate Schema & Sample Data

**Load** `references/schema-templates.md` for base DDL and data patterns.

**Create** database, schema, and tables:

```sql
CREATE DATABASE IF NOT EXISTS <DB_NAME>;
CREATE SCHEMA IF NOT EXISTS <DB_NAME>.FINANCE_ANALYTICS;
```

**Dimension tables:** DIM_DATE (7 months), DIM_CLIENT (scaled to AUM), DIM_PRODUCT, DIM_EXPENSE_CATEGORY, DIM_GL_ACCOUNT, DIM_COST_CENTER.

**Fact tables:** FACT_REVENUE (fee transactions), FACT_EXPENSE (expense transactions).

**Generate sample data** with realistic values:
- Client names appropriate to company type
- Revenue scaled to AUM (management fees = 50-150 bps)
- Expense mix: compensation ~60%, technology ~15%, other ~25%
- Monthly seasonality and business-day patterns

**Verify** row counts:

```sql
SELECT 'DIM_CLIENT' AS TBL, COUNT(*) AS ROWS FROM DIM_CLIENT
UNION ALL SELECT 'FACT_REVENUE', COUNT(*) FROM FACT_REVENUE
UNION ALL SELECT 'FACT_EXPENSE', COUNT(*) FROM FACT_EXPENSE;
```

⚠️ **STOP** - Present data summary. Confirm data looks realistic before proceeding.

## Step 3: Create Semantic View

**Create** with `CREATE OR REPLACE SEMANTIC VIEW <DB_NAME>.FINANCE_ANALYTICS.<SV_NAME>`:
- All tables with PRIMARY KEY, SYNONYMS, COMMENT (include row counts)
- RELATIONSHIPS between facts and dimensions
- FACTS for numeric measures (REVENUE_AMT, AUM_AMT, FEE_BPS, EXPENSE_AMT)
- DIMENSIONS for all analytical attributes
- Scoped METRICS per table (e.g., `REVENUE.TOTAL_REVENUE AS SUM(...)`)
- Unscoped cross-table metrics (e.g., `NET_INCOME AS revenue.total_revenue - expenses.total_expenses`)

**Required metrics:** TOTAL_REVENUE, TOTAL_AUM, AVG_FEE_RATE, REVENUE_PER_CLIENT, TOTAL_EXPENSES, NET_INCOME, PROFIT_MARGIN, EXPENSE_RATIO.

**Add AI instructions** tailored to pain points:
- `AI_SQL_GENERATION` - rounding, time filters, NULLIF for division, P&L structure
- `AI_QUESTION_CATEGORIZATION` - data sensitivity, out-of-scope topics

**Verify:** `DESCRIBE SEMANTIC VIEW ...;` - target 350+ properties.

**Syntax reminders:**
- Scoped metrics: `TABLE_ALIAS.METRIC_NAME AS expr`
- Unscoped derived: `METRIC_NAME AS t1.metric - t2.metric`
- AI instructions are bare keywords: `AI_SQL_GENERATION 'text'` (no equals, no block wrapper)
- Use `CREATE OR REPLACE` (ALTER ADD TABLE not supported)

## Step 4: Create Cortex Agent

**Create** AGENTS schema and agent:

```sql
CREATE SCHEMA IF NOT EXISTS <DB_NAME>.AGENTS;

CREATE OR REPLACE CORTEX AGENT <DB_NAME>.AGENTS.<AGENT_NAME>
FROM SPECIFICATION $spec$
{
  "models": {"orchestration": "auto"},
  "orchestration": {"budget": {"seconds": 900, "tokens": 400000}},
  "instructions": {
    "orchestration": "<customize: scope and data description>",
    "response": "<customize: formatting, rounding, caveats>"
  },
  "tools": [{
    "tool_spec": {
      "type": "cortex_analyst_text_to_sql",
      "name": "query_financials",
      "description": "<customize: financial data available>"
    }
  }],
  "tool_resources": {
    "query_financials": {
      "execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": ""},
      "semantic_view": "<DB_NAME>.FINANCE_ANALYTICS.<SV_NAME>"
    }
  }
}
$spec$;
```

**Verify:** `SHOW AGENTS IN SCHEMA <DB_NAME>.AGENTS;`

**Enable in Snowflake Intelligence:**

```sql
GRANT USAGE ON DATABASE <DB_NAME> TO ROLE <USER_ROLE>;
GRANT USAGE ON SCHEMA <DB_NAME>.AGENTS TO ROLE <USER_ROLE>;
GRANT USAGE ON AGENT <DB_NAME>.AGENTS.<AGENT_NAME> TO ROLE <USER_ROLE>;
```

**Test** with: "What is total revenue by client segment?"

## Step 5: Generate Presentation Script

**Generate talking points** per stakeholder from Step 1. Template per role:
- **CFO:** Pain: slow reporting. Query: "Profit margin by quarter?" Point: "Ask in plain English, get answers in seconds."
- **VP Ops:** Pain: data accuracy. Query: "Revenue by client and product last month?" Point: "Every answer traces to governed SQL."
- **Compliance:** Pain: audit trail. Query: "Total expenses by category this year?" Point: "Full audit trail, role-based access, SOC 2."

**Create demo script** with 5-7 questions ordered for impact:
1. Simple aggregation (builds confidence)
2. Multi-dimension analysis (shows power)
3. Profitability metric (addresses pain point)
4. Time comparison (shows trends)
5. Edge case with guardrail (shows safety)

⚠️ **STOP** - Get approval on presentation script before finalizing.

## Step 6: Validate End-to-End

**Checklist:**
- [ ] Tables exist with realistic data
- [ ] Semantic view: 350+ properties
- [ ] Agent responds to natural language questions correctly
- [ ] Guardrails reject out-of-scope questions
- [ ] All demo script queries return expected results

**On failure:** Return to the relevant step. Maximum 3 retries per step.

**On success:** Present summary with database name, semantic view, agent, row counts, property count, and demo query count. Recommend next steps: test in Snowflake Intelligence UI, share access, rehearse demo.

## Stopping Points

- ⚠️ After Step 1: Confirm requirements
- ⚠️ After Step 2: Verify sample data
- ⚠️ After Step 5: Approve presentation script

## Output

1. Snowflake database with star schema and sample data
2. Semantic view with dimensions, metrics, and AI guardrails
3. Cortex Agent enabled in Snowflake Intelligence
4. Presentation script with stakeholder talking points and demo queries
