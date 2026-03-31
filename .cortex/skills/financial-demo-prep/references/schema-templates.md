# Schema Templates for Financial Demo Prep

Reference templates for generating star schema and sample data. Customize names, scale, and values based on the prospect's profile.

## Dimension Tables

### DIM_DATE

```sql
CREATE OR REPLACE TABLE DIM_DATE (
    DATE_KEY INT PRIMARY KEY,
    CALENDAR_DATE DATE NOT NULL,
    DAY_OF_WEEK INT, DAY_NAME VARCHAR(10), DAY_OF_MONTH INT, DAY_OF_YEAR INT,
    WEEK_OF_YEAR INT, MONTH_NUMBER INT, MONTH_NAME VARCHAR(10),
    QUARTER_NUMBER INT, QUARTER_NAME VARCHAR(6),
    YEAR_NUMBER INT, FISCAL_QUARTER INT, FISCAL_YEAR INT,
    IS_MONTH_END BOOLEAN, IS_QUARTER_END BOOLEAN, IS_YEAR_END BOOLEAN,
    IS_BUSINESS_DAY BOOLEAN
);
```

Generate 7 months of dates (current month - 6 through current month). Use a CTE with GENERATOR to populate:

```sql
INSERT INTO DIM_DATE
WITH dates AS (
    SELECT DATEADD(DAY, SEQ4(), DATEADD(MONTH, -6, DATE_TRUNC('MONTH', CURRENT_DATE()))) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 215))
)
SELECT
    ROW_NUMBER() OVER (ORDER BY d) AS DATE_KEY,
    d AS CALENDAR_DATE,
    DAYOFWEEKISO(d), DAYNAME(d), DAY(d), DAYOFYEAR(d),
    WEEKOFYEAR(d), MONTH(d), MONTHNAME(d),
    QUARTER(d), 'Q' || QUARTER(d),
    YEAR(d), QUARTER(d), YEAR(d),
    d = LAST_DAY(d), d = LAST_DAY(d, 'QUARTER'), d = LAST_DAY(d, 'YEAR'),
    DAYOFWEEKISO(d) BETWEEN 1 AND 5
FROM dates WHERE d <= CURRENT_DATE();
```

### DIM_CLIENT

Scale client count to prospect:
- **Small** (<$500M AUM): 8-12 clients
- **Mid** ($500M-$2B): 12-20 clients
- **Large** (>$2B): 20-50 clients

Segments: Individual, Institutional, Family Office. AUM tiers: Platinum (>$50M), Gold ($10M-$50M), Silver (<$10M).

```sql
CREATE OR REPLACE TABLE DIM_CLIENT (
    CLIENT_KEY INT PRIMARY KEY,
    CLIENT_ID VARCHAR(20) NOT NULL,
    CLIENT_NAME VARCHAR(200) NOT NULL,
    CLIENT_SEGMENT VARCHAR(50) NOT NULL,
    RELATIONSHIP_START_DATE DATE,
    RELATIONSHIP_MANAGER VARCHAR(100),
    OFFICE_LOCATION VARCHAR(50),
    AUM_TIER VARCHAR(20),
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### DIM_PRODUCT

Standard financial product set:

```sql
CREATE OR REPLACE TABLE DIM_PRODUCT (
    PRODUCT_KEY INT PRIMARY KEY,
    PRODUCT_ID VARCHAR(20) NOT NULL,
    PRODUCT_NAME VARCHAR(100) NOT NULL,
    PRODUCT_CATEGORY VARCHAR(50) NOT NULL,
    FEE_TYPE VARCHAR(30),
    ASSET_CLASS VARCHAR(50),
    IS_ACTIVE BOOLEAN DEFAULT TRUE
);
```

Categories: Management Fee, Performance Fee, Advisory Fee, Transaction Fee.
Asset classes: Equity, Fixed Income, Alternative, Multi-Asset.

### DIM_EXPENSE_CATEGORY

```sql
CREATE OR REPLACE TABLE DIM_EXPENSE_CATEGORY (
    EXPENSE_CATEGORY_KEY INT PRIMARY KEY,
    EXPENSE_CATEGORY_ID VARCHAR(20) NOT NULL,
    EXPENSE_CATEGORY_NAME VARCHAR(100) NOT NULL,
    EXPENSE_GROUP VARCHAR(50) NOT NULL,
    DEPARTMENT VARCHAR(50),
    IS_ACTIVE BOOLEAN DEFAULT TRUE
);
```

Groups: Compensation, Technology, Professional Services, Occupancy, Marketing, Travel.

### DIM_GL_ACCOUNT

Revenue accounts: 4000-4999. Expense accounts: 5000-7999.

```sql
CREATE OR REPLACE TABLE DIM_GL_ACCOUNT (
    GL_ACCOUNT_KEY INT PRIMARY KEY,
    GL_ACCOUNT_ID VARCHAR(20) NOT NULL,
    GL_ACCOUNT_NAME VARCHAR(100) NOT NULL,
    ACCOUNT_TYPE VARCHAR(30) NOT NULL,
    ACCOUNT_SUBTYPE VARCHAR(50),
    NORMAL_BALANCE VARCHAR(10),
    IS_ACTIVE BOOLEAN DEFAULT TRUE
);
```

### DIM_COST_CENTER

```sql
CREATE OR REPLACE TABLE DIM_COST_CENTER (
    COST_CENTER_KEY INT PRIMARY KEY,
    COST_CENTER_ID VARCHAR(20) NOT NULL,
    COST_CENTER_NAME VARCHAR(100) NOT NULL,
    DEPARTMENT VARCHAR(50),
    OFFICE_LOCATION VARCHAR(50),
    MANAGER VARCHAR(100),
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

## Fact Tables

### FACT_REVENUE

```sql
CREATE OR REPLACE TABLE FACT_REVENUE (
    REVENUE_KEY INT AUTOINCREMENT PRIMARY KEY,
    DATE_KEY INT NOT NULL REFERENCES DIM_DATE(DATE_KEY),
    CLIENT_KEY INT NOT NULL REFERENCES DIM_CLIENT(CLIENT_KEY),
    PRODUCT_KEY INT NOT NULL REFERENCES DIM_PRODUCT(PRODUCT_KEY),
    TRANSACTION_ID VARCHAR(50),
    AUM_AMT DECIMAL(18,2),
    REVENUE_AMT DECIMAL(18,2) NOT NULL,
    FEE_BPS DECIMAL(8,4),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Revenue scaling formula:
- Management fees: AUM * (fee_bps / 10000) / 12 per month
- Typical fee rates: 50-150 bps depending on AUM tier
- Generate ~500-800 rows for 7 months of data

### FACT_EXPENSE

```sql
CREATE OR REPLACE TABLE FACT_EXPENSE (
    EXPENSE_KEY INT AUTOINCREMENT PRIMARY KEY,
    DATE_KEY INT NOT NULL REFERENCES DIM_DATE(DATE_KEY),
    EXPENSE_CATEGORY_KEY INT NOT NULL REFERENCES DIM_EXPENSE_CATEGORY(EXPENSE_CATEGORY_KEY),
    TRANSACTION_ID VARCHAR(50),
    EXPENSE_AMT DECIMAL(18,2) NOT NULL,
    VENDOR_NAME VARCHAR(200),
    DESCRIPTION VARCHAR(500),
    PAYMENT_STATUS VARCHAR(20),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Expense scaling: total expenses ~ 60-70% of total revenue.
- Compensation: ~60% of expenses
- Technology: ~15%
- Professional Services: ~10%
- Occupancy: ~8%
- Marketing: ~5%
- Travel: ~2%

Generate ~250-400 rows across all categories.

## Semantic View Template

Key syntax rules for `CREATE OR REPLACE SEMANTIC VIEW`:
- Scoped metrics use `TABLE_ALIAS.METRIC_NAME AS expression`
- Cross-table derived metrics are unscoped: `METRIC_NAME AS t1.metric - t2.metric`
- Disambiguate shared column names with `table_alias.COLUMN_NAME`
- COMMENT goes after METRICS section
- `AI_SQL_GENERATION 'text'` and `AI_QUESTION_CATEGORIZATION 'text'` are bare keywords at the end (no equals, no block wrapper)
- Always use `NULLIF(divisor, 0)` for ratio metrics

## Agent Spec Template

```json
{
  "models": {"orchestration": "auto"},
  "orchestration": {"budget": {"seconds": 900, "tokens": 400000}},
  "instructions": {
    "orchestration": "You are a financial analyst for [COMPANY]. Answer questions about revenue, expenses, profitability, and client analytics. Use the query_financials tool for all data questions. If asked about topics outside financial analytics, politely explain your scope.",
    "response": "Format currency with $ and commas. Round percentages to 1 decimal. Always specify the time period in your response. Add caveats when data is sample/demo data."
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "query_financials",
        "description": "Query [COMPANY] financial data including revenue by client/product, expenses by category/department, profitability metrics, and AUM analytics."
      }
    }
  ],
  "tool_resources": {
    "query_financials": {
      "execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": ""},
      "semantic_view": "[DB].[SCHEMA].[SV_NAME]"
    }
  }
}
```
