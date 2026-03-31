# Streamlit on Snowsight — Complete Development & Deployment Guide

> **Scope**: This guide covers everything needed to build, test, and deploy a
> Streamlit application that runs **both locally on your PC and inside Snowsight**
> (Streamlit in Snowflake). It documents every pitfall encountered during the
> development of the Pinnacle Financial Analytics dashboard and how to avoid them.

---

## A. Features of This Dashboard

This Streamlit dashboard connects to Snowflake and visualizes financial data from
`PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS`. It provides:

| # | Widget | Description |
|---|--------|-------------|
| 1 | **Total Revenue KPI** | Aggregated revenue with month-over-month % change |
| 2 | **Total Expenses KPI** | Aggregated expenses with MoM % change (inverse color) |
| 3 | **Net Income KPI** | Revenue minus expenses with profit margin % |
| 4 | **Active Clients KPI** | Count of active clients with total AUM |
| 5 | **Monthly P&L Trend** | Multi-line chart (Revenue, Expenses, Net Income over time) |
| 6 | **Revenue by Client Segment** | Bar chart — Institutional, Family Office, Individual |
| 7 | **Revenue by Product Category** | Bar chart — Performance Fee, Management Fee, Advisory Fee |
| 8 | **Top 10 Expense Categories** | Horizontal bar chart of largest expense categories |
| 9 | **Client Profitability Table** | Data table with client name, segment, AUM, revenue, BPS |
| 10 | **Sidebar Segment Filter** | Filters the segment bar chart and client table |
| 11 | **Refresh Button** | Clears `st.cache_data` and reruns the app |

### Data Sources (8 tables)

- `FACT_REVENUE` — revenue transactions (534 rows)
- `FACT_EXPENSE` — expense transactions (284 rows)
- `DIM_DATE` — calendar dimension (215 rows)
- `DIM_CLIENT` — client dimension (12 rows)
- `DIM_PRODUCT` — product dimension (8 rows)
- `DIM_EXPENSE_CATEGORY` — expense categories (14 rows)
- `DIM_COST_CENTER` — cost centers (14 rows)
- `DIM_GL_ACCOUNT` — general ledger accounts (18 rows)

---

## B. Setting Up Your Local Development Environment

This section covers how to configure **Visual Studio Code** (or any editor) with
Cortex Code CLI and Snowflake CLI so you can develop and deploy from your PC.

### B.1 Install the Snowflake CLI

```bash
# Windows (using pip)
pip install snowflake-cli

# Verify installation
snow --version
```

### B.2 Configure a Snowflake Connection

Create or edit `~/.snowflake/connections.toml` (on Windows: `%USERPROFILE%\.snowflake\connections.toml`):

```toml
[COCO_HOL_ACCOUNT]
account = "WGPAPYX-COCO_HOL_ACCOUNT"
user = "COCO_HOL_USER_33"
authenticator = "externalbrowser"
role = "COCO_HOL_RL"
warehouse = "COCO_HOL_WH"
database = "PINNACLE_FINANCIAL_DEMO_33"
schema = "FINANCE_ANALYTICS"
```

> **Tip — `externalbrowser` authenticator**: This opens your default browser for
> SSO login. It works well on local dev machines. For CI/CD pipelines, use
> `snowflake_jwt` (key-pair) or `username_password` instead.

Test your connection:

```bash
snow connection test -c COCO_HOL_ACCOUNT
```

You should see `Status: OK`.

### B.3 Set Up Cortex Code in VS Code

1. Install the **Cortex Code** extension from the VS Code marketplace (or use the
   CLI directly in the integrated terminal).
2. Set your active connection so Cortex Code can query Snowflake:
   ```bash
   cortex connections set COCO_HOL_ACCOUNT
   ```
3. Useful Cortex CLI commands for development:
   ```bash
   # Search for Snowflake objects (tables, views, etc.)
   cortex search object "FACT_REVENUE"

   # Search Snowflake documentation
   cortex search docs "streamlit deploy"

   # Check available packages before adding them to environment.yml
   cortex search object "packages" --types=table,view
   ```

### B.4 Configure Local Streamlit Credentials

Streamlit locally uses `.streamlit/secrets.toml` to connect to Snowflake.
Copy the example and fill in your values:

```bash
cp .streamlit/secrets.toml.example .streamlit/secrets.toml
```

The file should look like:

```toml
[connections.snowflake]
account = "WGPAPYX-COCO_HOL_ACCOUNT"
host = "WGPAPYX-COCO_HOL_ACCOUNT.snowflakecomputing.com"
user = "COCO_HOL_USER_33"
authenticator = "externalbrowser"
warehouse = "COCO_HOL_WH"
database = "PINNACLE_FINANCIAL_DEMO_33"
schema = "FINANCE_ANALYTICS"
role = "COCO_HOL_RL"
```

> **IMPORTANT**: Add `.streamlit/secrets.toml` to `.gitignore`. Never commit credentials.

### B.5 Install Local Python Dependencies

```bash
# Using pip
pip install -e .

# Or install directly from pyproject.toml dependencies
pip install "altair==5.5.0" "pandas==2.2.3" "snowflake-snowpark-python>=1.48.0" "streamlit>=1.52.0,<=1.52.2"
```

---

## C. How to Check Which Packages Are Available in Snowsight

This is **the most common source of deployment failures**. Snowsight runs inside
Snowflake's sandboxed environment and can only use packages from Snowflake's
curated Anaconda channel — not the full PyPI registry.

### C.1 Query the Package Catalog

Run this SQL in a Snowsight worksheet or via the CLI. You **must** qualify the
`information_schema.packages` view with a database name, otherwise you get
"Cannot perform SELECT — this session does not have a current database":

```sql
-- List all available Python packages (and their latest versions)
SELECT PACKAGE_NAME, MAX(VERSION) AS LATEST_VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
GROUP BY PACKAGE_NAME
ORDER BY PACKAGE_NAME;
```

> **Pitfall encountered**: Running `SELECT * FROM information_schema.packages`
> without a database prefix fails. Always use `<DATABASE>.information_schema.packages`.

### C.2 Check a Specific Package and Version

```sql
-- Is streamlit 1.54.0 available? (Answer: No, max is 1.52.2)
SELECT PACKAGE_NAME, VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
  AND PACKAGE_NAME = 'streamlit'
ORDER BY VERSION DESC;

-- Check multiple packages at once
SELECT PACKAGE_NAME, MAX(VERSION) AS LATEST_VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
  AND PACKAGE_NAME IN ('streamlit', 'altair', 'pandas', 'snowflake-snowpark-python')
GROUP BY PACKAGE_NAME
ORDER BY PACKAGE_NAME;
```

### C.3 Package Pinning Rules

| File | Purpose | Version Syntax | Example |
|------|---------|----------------|---------|
| `environment.yml` | Snowsight (Anaconda channel) | Single `=` | `streamlit=1.52.2` |
| `pyproject.toml` | Local dev (PyPI) | PEP 440 ranges | `streamlit>=1.52.0,<=1.52.2` |

**Key rule**: The versions in both files must be compatible. Pin `environment.yml`
to exact versions you verified exist in the Anaconda channel. Use the same or
compatible ranges in `pyproject.toml`.

### C.4 Verified Package Versions (as of March 2026)

| Package | Snowsight Max Version | PyPI Latest |
|---------|----------------------|-------------|
| streamlit | 1.52.2 | 1.54+ |
| altair | 5.5.0 | 5.5+ |
| pandas | 2.2.3 | 2.2+ |
| snowflake-snowpark-python | 1.48.0 | 1.48+ |

> **Pitfall encountered**: `pyproject.toml` originally had `streamlit>=1.54.0`,
> which is not available in Snowflake's Anaconda channel. This caused deployment
> to work locally but fail in Snowsight.

---

## D. Project Structure and File Reference

```
streamlit-app/
  streamlit_app.py        # Main application (dual-environment: local + Snowsight)
  snowflake.yml           # Snowflake CLI deployment descriptor (definition v2)
  environment.yml         # Anaconda packages for Snowsight runtime
  pyproject.toml          # Local development dependencies (PyPI)
  DEPLOYMENT_GUIDE.md     # This file
  .streamlit/
    secrets.toml          # Local Snowflake credentials (DO NOT commit)
    secrets.toml.example  # Template for secrets.toml
```

### D.1 `snowflake.yml` — Deployment Descriptor

```yaml
definition_version: '2'
entities:
  pinnacle_financial_dashboard:
    type: streamlit
    identifier:
      name: PINNACLE_FINANCIAL_DASHBOARD
    title: "Pinnacle Financial Analytics"
    query_warehouse: COCO_HOL_WH
    main_file: streamlit_app.py
    artifacts:
      - streamlit_app.py
      - environment.yml
```

**Critical fields and pitfalls**:

| Field | Required | Pitfall |
|-------|----------|---------|
| `definition_version` | Yes | Must be `'2'` (quoted string). |
| `artifacts` | Yes | **Must list every file to upload.** Omitting this causes `'NoneType' object is not iterable` error during deploy. |
| `main_file` | Yes | Must match the actual filename of your Streamlit entry point. |
| `query_warehouse` | Yes | The warehouse the app uses to run queries. Must exist and be accessible by the deploying role. |
| `environment_file` | N/A | **Not a valid field** in definition v2. The CLI auto-detects `environment.yml` from the artifacts list. Using this field causes: `Extra inputs are not permitted`. |
| `pages_dir` | Optional | Only include if you have a `pages/` directory. Referencing a nonexistent directory causes errors. |

### D.2 `environment.yml` — Snowsight Package Dependencies

```yaml
name: sf_env
channels:
  - snowflake
dependencies:
  - streamlit=1.52.2
  - altair=5.5.0
  - pandas=2.2.3
  - snowflake-snowpark-python=1.48.0
```

**Rules**:
- Channel must be `snowflake` (not `conda-forge` or `defaults`).
- Use single `=` for pinning (Conda syntax, not pip).
- Only list packages you verified exist via `information_schema.packages`.

### D.3 `pyproject.toml` — Local Development Dependencies

```toml
[project]
name = "pinnacle-financial-dashboard"
version = "1.0.0"
description = "Pinnacle Financial Analytics Dashboard"
requires-python = ">=3.11"
dependencies = [
    "altair>=5.5.0,<=5.5.0",
    "pandas>=2.2.3,<=2.2.3",
    "snowflake-snowpark-python>=1.48.0",
    "streamlit>=1.52.0,<=1.52.2",
]
```

**Key differences from `environment.yml`**:
- Uses `snowflake-snowpark-python` (not `snowflake-connector-python`) — the
  Snowpark SDK includes the connector and is required for `get_active_session()`.
- Version ranges use PEP 440 syntax (`>=`, `<=`).
- Constrain upper bounds to match what Snowsight supports, so local dev and
  Snowsight behave identically.

---

## E. Writing Dual-Environment Code (Local + Snowsight)

The biggest challenge is that **Snowsight and local Streamlit use different
connection mechanisms**. The pattern below handles both transparently.

### E.1 The Problem

| Environment | Connection Method | Query Method |
|-------------|-------------------|--------------|
| **Local** | `st.connection("snowflake")` | `conn.query(sql, ttl=600)` |
| **Snowsight** | `get_active_session()` | `session.sql(sql).to_pandas()` |

`st.connection("snowflake")` does **not** work inside Snowsight. It throws an
exception because Snowsight manages the session internally.

### E.2 The Solution — Environment Detection Pattern

```python
import streamlit as st
import pandas as pd

DB = "PINNACLE_FINANCIAL_DEMO_33"
SCHEMA = "FINANCE_ANALYTICS"

def _is_running_in_snowsight() -> bool:
    """Return True when the app is running inside Snowflake (Snowsight)."""
    try:
        from snowflake.snowpark.context import get_active_session
        get_active_session()
        return True
    except Exception:
        return False

IS_SNOWSIGHT = _is_running_in_snowsight()

if IS_SNOWSIGHT:
    from snowflake.snowpark.context import get_active_session
    session = get_active_session()
else:
    def _get_local_connection():
        try:
            return st.connection("snowflake")
        except Exception as exc:
            st.error(f"Could not connect to Snowflake: {exc}")
            st.stop()
    conn = _get_local_connection()

def run_query(sql: str) -> pd.DataFrame:
    """Run SQL and return a DataFrame — works in both environments."""
    if IS_SNOWSIGHT:
        df = session.sql(sql).to_pandas()
    else:
        df = conn.query(sql, ttl=600)
    df.columns = df.columns.str.lower()
    return df
```

### E.3 Why This Works

1. `_is_running_in_snowsight()` tries to import and call `get_active_session()`.
   Inside Snowsight this succeeds; locally it raises an exception (no active session).
2. The `run_query()` function is the **single entry point** for all SQL. Every
   data loader calls it, so the environment branching is in one place.
3. `df.columns.str.lower()` normalizes column names — Snowflake returns
   UPPER_CASE by default, but Streamlit widgets expect lower_case.

### E.4 Caching

`@st.cache_data(ttl=600)` works in both environments. Apply it to every data
loader function:

```python
@st.cache_data(ttl=600)
def load_kpi_revenue() -> pd.DataFrame:
    return run_query(f"SELECT ... FROM {DB}.{SCHEMA}.FACT_REVENUE ...")
```

### E.5 Fully Qualified Table References

Always use `{DB}.{SCHEMA}.TABLE_NAME` in SQL queries. Inside Snowsight, the
session database/schema context may not match what you expect. Fully qualifying
avoids "Object does not exist" errors.

---

## F. Step-by-Step Deployment to Snowsight

### Step 1 — Verify Snowflake connection

```bash
snow connection test -c COCO_HOL_ACCOUNT
```

Expected: `Status: OK`

### Step 2 — Verify packages are available

```sql
SELECT PACKAGE_NAME, MAX(VERSION) AS LATEST_VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
  AND PACKAGE_NAME IN ('streamlit', 'altair', 'pandas', 'snowflake-snowpark-python')
GROUP BY PACKAGE_NAME;
```

Cross-reference the results with your `environment.yml` versions.

### Step 3 — Validate data exists

```sql
SELECT 'FACT_REVENUE' AS tbl, COUNT(*) AS cnt FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE
UNION ALL
SELECT 'FACT_EXPENSE', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_EXPENSE
UNION ALL
SELECT 'DIM_DATE', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_DATE
UNION ALL
SELECT 'DIM_CLIENT', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_CLIENT
UNION ALL
SELECT 'DIM_PRODUCT', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_PRODUCT
UNION ALL
SELECT 'DIM_EXPENSE_CATEGORY', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_EXPENSE_CATEGORY;
```

All tables should return rows > 0.

### Step 4 — Generate a template to validate structure (optional)

If this is your first Streamlit project, generate a template to compare against:

```bash
snow init my_test_project --template example_streamlit --no-interactive
```

Compare its `snowflake.yml` with yours. Delete the test project after.

### Step 5 — Deploy

From the `streamlit-app/` directory:

```bash
snow streamlit deploy -c COCO_HOL_ACCOUNT --database PINNACLE_FINANCIAL_DEMO_33 --schema FINANCE_ANALYTICS --replace
```

Use `--replace` to overwrite an existing app with the same name.

### Step 6 — Open in Snowsight

Navigate to **Snowsight > Projects > Streamlit** and open **PINNACLE_FINANCIAL_DASHBOARD**.

Or use the URL printed by the deploy command.

---

## G. Verification Tests

### G.1 Local Tests (outside Snowsight)

Run from the `streamlit-app/` directory.

**T1 — App starts without errors**
```bash
streamlit run streamlit_app.py
```
Expected: Browser opens at `localhost:8501` with no error banners.

**T2 — KPI cards render**
Check all four KPI cards display values (not `None` or blank).

**T3 — P&L chart shows 3 lines**
The Monthly P&L Trend chart should show Revenue (blue), Expenses (red), and
Net Income (green dashed).

**T4 — Segment filter works**
- Select "Institutional" from the sidebar.
- The "Revenue by Client Segment" bar chart should show only the Institutional bar.
- The Client Profitability table should show only Institutional clients.
- Select "All" — all segments and clients return.

**T5 — Refresh button clears cache**
Click the "Refresh data" button. The page should reload and re-query Snowflake.

**T6 — No console errors**
Check the terminal running Streamlit for Python tracebacks or warnings.

---

### G.2 Snowsight Tests (inside Snowflake)

**T7 — App loads in Snowsight**
Open the deployed Streamlit app in Snowsight. It should render the full dashboard
without "Could not connect" or import errors.

**T8 — Verify session detection**
The app should detect it is running inside Snowsight and use
`get_active_session()` instead of `st.connection("snowflake")`.
Indicator: no "Could not connect to Snowflake" error banner.

**T9 — KPI values match direct SQL**
Run this query in a Snowsight worksheet and compare to the dashboard:

```sql
SELECT
    (SELECT SUM(REVENUE_AMOUNT) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE) AS total_revenue,
    (SELECT SUM(EXPENSE_AMOUNT) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_EXPENSE) AS total_expenses,
    (SELECT SUM(REVENUE_AMOUNT) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE)
      - (SELECT SUM(EXPENSE_AMOUNT) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_EXPENSE) AS net_income,
    (SELECT COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_CLIENT WHERE IS_ACTIVE = TRUE) AS active_clients;
```

**T10 — Charts render correctly**
All four Altair charts should render inside the Snowsight iframe:
- Monthly P&L Trend (line chart)
- Revenue by Client Segment (bar chart)
- Revenue by Product Category (bar chart)
- Top 10 Expense Categories (horizontal bar chart)

**T11 — Sidebar filter works in Snowsight**
Same as T4 — verify the segment filter updates charts and table inside Snowsight.

**T12 — Refresh button works in Snowsight**
Click "Refresh data" — the app should rerun without errors.

---

### G.3 Data Validation Queries

Run these independently to confirm the underlying data is correct.

**Revenue by segment totals**
```sql
SELECT c.CLIENT_SEGMENT, ROUND(SUM(r.REVENUE_AMOUNT), 0) AS REVENUE
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE r
JOIN PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_CLIENT c ON r.CLIENT_KEY = c.CLIENT_KEY
GROUP BY c.CLIENT_SEGMENT
ORDER BY REVENUE DESC;
```

**Monthly P&L data**
```sql
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER,
       SUM(r.REVENUE_AMOUNT) AS revenue
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE r
JOIN PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_DATE d ON r.DATE_KEY = d.DATE_KEY
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;
```

**Top expenses**
```sql
SELECT ec.EXPENSE_CATEGORY_NAME, ROUND(SUM(e.EXPENSE_AMOUNT), 0) AS AMOUNT
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_EXPENSE e
JOIN PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_EXPENSE_CATEGORY ec
  ON e.EXPENSE_CATEGORY_KEY = ec.EXPENSE_CATEGORY_KEY
GROUP BY ec.EXPENSE_CATEGORY_NAME
ORDER BY AMOUNT DESC
LIMIT 10;
```

---

## H. Common Pitfalls & Troubleshooting

These are the actual issues encountered during development of this project,
documented so you can avoid them in future Streamlit-on-Snowsight projects.

### H.1 Deployment Errors

| # | Problem | Error Message | Root Cause | Fix |
|---|---------|---------------|------------|-----|
| 1 | `snowflake.yml` missing `artifacts` | `'NoneType' object is not iterable` | CLI v3.10.1 requires an explicit `artifacts` list. Without it, the bundle step gets `None` and crashes. | Add `artifacts:` listing every file to upload (at minimum: `streamlit_app.py`, `environment.yml`). |
| 2 | `environment_file` in `snowflake.yml` | `Extra inputs are not permitted. You provided field 'entities...environment_file'` | `environment_file` is not a valid field in definition v2. The CLI auto-detects `environment.yml` from the artifacts list. | Remove the `environment_file` key. List `environment.yml` under `artifacts` instead. |
| 3 | `pages_dir` references missing directory | Deploy error or empty pages | If you declare `pages_dir: pages` but have no `pages/` folder, the CLI fails. | Only include `pages_dir` if the directory exists. |
| 4 | Package not available on Snowflake channel | Deploy succeeds but app crashes with `ModuleNotFoundError` | `environment.yml` lists a package or version not in Snowflake's Anaconda channel. | Query `information_schema.packages` first (see Section C). |

### H.2 Runtime Errors

| # | Problem | Error Message | Root Cause | Fix |
|---|---------|---------------|------------|-----|
| 5 | `st.connection("snowflake")` fails in Snowsight | `Could not connect to Snowflake` or similar | Snowsight provides its own session; `st.connection()` is for local use only. | Use the dual-environment pattern from Section E. |
| 6 | SQL returns no data / "Object does not exist" | `Object 'TABLE_NAME' does not exist` | Session database/schema context in Snowsight may differ from what you expect. | Always use fully qualified names: `DB.SCHEMA.TABLE`. |
| 7 | `information_schema.packages` query fails | `Cannot perform SELECT. This session does not have a current database.` | The `information_schema` view must be qualified with a database name. | Use `YOUR_DB.information_schema.packages`. |
| 8 | Column name mismatch | KeyError accessing DataFrame columns | Snowflake returns UPPER_CASE column names; your code expects lower_case. | Add `df.columns = df.columns.str.lower()` after every query. |

### H.3 Local Development Errors

| # | Problem | Root Cause | Fix |
|---|---------|------------|-----|
| 9 | App crashes on startup locally | Missing `.streamlit/secrets.toml` | Copy `secrets.toml.example` to `secrets.toml` and fill credentials. |
| 10 | `ImportError: snowflake.snowpark` | `snowflake-connector-python` installed instead of `snowflake-snowpark-python` | Replace with `pip install snowflake-snowpark-python`. The Snowpark SDK includes the connector. |
| 11 | Charts look different locally vs Snowsight | Different Altair versions | Pin the exact same version in both `pyproject.toml` and `environment.yml`. |

---

## I. Checklist — Before Every Deployment

Use this checklist before running `snow streamlit deploy`:

- [ ] **Packages verified**: All packages in `environment.yml` exist in
      `information_schema.packages` at the pinned versions
- [ ] **Versions aligned**: `pyproject.toml` ranges are compatible with
      `environment.yml` pins
- [ ] **`snowflake.yml` has `artifacts`**: Lists `streamlit_app.py` and
      `environment.yml` (and any other files like `pages/`, `common/`)
- [ ] **No invalid fields in `snowflake.yml`**: No `environment_file`,
      no `runtime_name`, no `pages_dir` pointing to a missing directory
- [ ] **Dual-environment code**: `run_query()` uses `session.sql()` in
      Snowsight and `conn.query()` locally
- [ ] **Fully qualified SQL**: All table references use `DB.SCHEMA.TABLE`
- [ ] **Column normalization**: `df.columns.str.lower()` after every query
- [ ] **Connection test passes**: `snow connection test -c <CONNECTION>`
- [ ] **Data tables have rows**: Verified with COUNT(*) queries
- [ ] **SQL compiles**: Tested key queries with `only_compile=true` or in a
      Snowsight worksheet
- [ ] **`.streamlit/secrets.toml` is in `.gitignore`**

---

## J. Quick Reference — Useful Commands

### Snowflake CLI

```bash
# Test connection
snow connection test -c COCO_HOL_ACCOUNT

# Deploy (first time)
snow streamlit deploy -c COCO_HOL_ACCOUNT --database DB --schema SCHEMA

# Redeploy (overwrite existing)
snow streamlit deploy -c COCO_HOL_ACCOUNT --database DB --schema SCHEMA --replace

# Generate a Streamlit template to compare project structure
snow init my_test_project --template example_streamlit --no-interactive

# Check CLI version (relevant for snowflake.yml schema compatibility)
snow --version
```

### Cortex Code CLI (in VS Code terminal)

```bash
# Set active Snowflake connection for Cortex Code
cortex connections set COCO_HOL_ACCOUNT

# List available connections
cortex connections list

# Search for Snowflake objects
cortex search object "FACT_REVENUE"

# Search Snowflake documentation
cortex search docs "streamlit environment.yml"
```

### SQL — Package Discovery

```sql
-- All available Python packages
SELECT PACKAGE_NAME, MAX(VERSION) AS LATEST_VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
GROUP BY PACKAGE_NAME
ORDER BY PACKAGE_NAME;

-- Search for a specific package
SELECT PACKAGE_NAME, VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
  AND PACKAGE_NAME ILIKE '%streamlit%'
ORDER BY VERSION DESC;

-- Verify your exact dependencies
SELECT PACKAGE_NAME, MAX(VERSION) AS LATEST_VERSION
FROM COCO_HOL_DB.INFORMATION_SCHEMA.PACKAGES
WHERE LANGUAGE = 'python'
  AND PACKAGE_NAME IN ('streamlit', 'altair', 'pandas', 'snowflake-snowpark-python')
GROUP BY PACKAGE_NAME;
```

### Local Development

```bash
# Run locally
streamlit run streamlit_app.py

# Install local dependencies
pip install -e .
```
