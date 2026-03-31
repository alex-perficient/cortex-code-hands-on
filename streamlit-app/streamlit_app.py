import streamlit as st
import altair as alt
import pandas as pd

# ---------------------------------------------------------------------------
# Page config (must be first Streamlit call)
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="Pinnacle Financial Analytics",
    page_icon=":material/monitoring:",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Snowflake connection
# ---------------------------------------------------------------------------
DB = "PINNACLE_FINANCIAL_DEMO_33"
SCHEMA = "FINANCE_ANALYTICS"


def get_snowflake_connection():
    """Return a Snowflake connection, or show an error and stop."""
    try:
        return st.connection("snowflake")
    except Exception as exc:
        st.error(f"Could not connect to Snowflake: {exc}")
        st.stop()


conn = get_snowflake_connection()


def run_query(sql: str) -> pd.DataFrame:
    """Run *sql* via the cached Snowflake connection and lower-case columns."""
    df = conn.query(sql, ttl=600)
    df.columns = df.columns.str.lower()
    return df


# ---------------------------------------------------------------------------
# Data loaders — one per dashboard widget
# ---------------------------------------------------------------------------
@st.cache_data(ttl=600)
def load_kpi_revenue() -> pd.DataFrame:
    return run_query(f"""
        WITH monthly AS (
            SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, SUM(r.REVENUE_AMOUNT) AS rev
            FROM {DB}.{SCHEMA}.FACT_REVENUE r
            JOIN {DB}.{SCHEMA}.DIM_DATE d ON r.DATE_KEY = d.DATE_KEY
            GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
        ), ranked AS (
            SELECT rev, ROW_NUMBER() OVER (ORDER BY YEAR_NUMBER DESC, MONTH_NUMBER DESC) AS rn
            FROM monthly
        )
        SELECT
            (SELECT TO_VARCHAR(SUM(REVENUE_AMOUNT), '$999,999,999')
             FROM {DB}.{SCHEMA}.FACT_REVENUE) AS VALUE,
            CONCAT(
                CASE WHEN (SELECT rev FROM ranked WHERE rn = 1) >= (SELECT rev FROM ranked WHERE rn = 2) THEN '+' ELSE '' END,
                ROUND(((SELECT rev FROM ranked WHERE rn = 1) - (SELECT rev FROM ranked WHERE rn = 2))
                      / (SELECT rev FROM ranked WHERE rn = 2) * 100, 1),
                '% MoM'
            ) AS DIFF
    """)


@st.cache_data(ttl=600)
def load_kpi_expenses() -> pd.DataFrame:
    return run_query(f"""
        WITH monthly AS (
            SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, SUM(e.EXPENSE_AMOUNT) AS exp
            FROM {DB}.{SCHEMA}.FACT_EXPENSE e
            JOIN {DB}.{SCHEMA}.DIM_DATE d ON e.DATE_KEY = d.DATE_KEY
            GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
        ), ranked AS (
            SELECT exp, ROW_NUMBER() OVER (ORDER BY YEAR_NUMBER DESC, MONTH_NUMBER DESC) AS rn
            FROM monthly
        )
        SELECT
            (SELECT TO_VARCHAR(SUM(EXPENSE_AMOUNT), '$999,999,999')
             FROM {DB}.{SCHEMA}.FACT_EXPENSE) AS VALUE,
            CONCAT(
                CASE WHEN (SELECT exp FROM ranked WHERE rn = 1) >= (SELECT exp FROM ranked WHERE rn = 2) THEN '+' ELSE '' END,
                ROUND(((SELECT exp FROM ranked WHERE rn = 1) - (SELECT exp FROM ranked WHERE rn = 2))
                      / (SELECT exp FROM ranked WHERE rn = 2) * 100, 1),
                '% MoM'
            ) AS DIFF
    """)


@st.cache_data(ttl=600)
def load_kpi_net_income() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            TO_VARCHAR(
                (SELECT SUM(REVENUE_AMOUNT) FROM {DB}.{SCHEMA}.FACT_REVENUE)
                - (SELECT SUM(EXPENSE_AMOUNT) FROM {DB}.{SCHEMA}.FACT_EXPENSE),
                '$999,999,999'
            ) AS VALUE,
            CONCAT(
                ROUND(
                    ((SELECT SUM(REVENUE_AMOUNT) FROM {DB}.{SCHEMA}.FACT_REVENUE)
                     - (SELECT SUM(EXPENSE_AMOUNT) FROM {DB}.{SCHEMA}.FACT_EXPENSE))
                    / (SELECT SUM(REVENUE_AMOUNT) FROM {DB}.{SCHEMA}.FACT_REVENUE) * 100,
                    1
                ),
                '% margin'
            ) AS DIFF
    """)


@st.cache_data(ttl=600)
def load_kpi_clients() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            (SELECT COUNT(*) FROM {DB}.{SCHEMA}.DIM_CLIENT WHERE IS_ACTIVE = TRUE)::VARCHAR AS VALUE,
            CONCAT('$', TO_VARCHAR(ROUND(SUM(r.AUM_AMOUNT) / 1e9, 1)), 'B AUM') AS DIFF
        FROM {DB}.{SCHEMA}.FACT_REVENUE r
    """)


@st.cache_data(ttl=600)
def load_pl_trend() -> pd.DataFrame:
    return run_query(f"""
        WITH monthly_rev AS (
            SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, SUM(r.REVENUE_AMOUNT) AS amount
            FROM {DB}.{SCHEMA}.FACT_REVENUE r
            JOIN {DB}.{SCHEMA}.DIM_DATE d ON r.DATE_KEY = d.DATE_KEY
            GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
        ), monthly_exp AS (
            SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, SUM(e.EXPENSE_AMOUNT) AS amount
            FROM {DB}.{SCHEMA}.FACT_EXPENSE e
            JOIN {DB}.{SCHEMA}.DIM_DATE d ON e.DATE_KEY = d.DATE_KEY
            GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
        ), combined AS (
            SELECT
                r.YEAR_NUMBER,
                r.MONTH_NUMBER,
                r.YEAR_NUMBER::VARCHAR || '-' || LPAD(r.MONTH_NUMBER::VARCHAR, 2, '0') || '-01' AS MONTH,
                r.amount AS REVENUE,
                COALESCE(x.amount, 0) AS EXPENSES,
                r.amount - COALESCE(x.amount, 0) AS NET_INCOME
            FROM monthly_rev r
            LEFT JOIN monthly_exp x ON r.YEAR_NUMBER = x.YEAR_NUMBER AND r.MONTH_NUMBER = x.MONTH_NUMBER
        )
        SELECT MONTH, 'Revenue' AS METRIC, REVENUE AS AMOUNT FROM combined
        UNION ALL
        SELECT MONTH, 'Expenses' AS METRIC, EXPENSES AS AMOUNT FROM combined
        UNION ALL
        SELECT MONTH, 'Net Income' AS METRIC, NET_INCOME AS AMOUNT FROM combined
        ORDER BY MONTH, METRIC
    """)


@st.cache_data(ttl=600)
def load_revenue_by_segment() -> pd.DataFrame:
    return run_query(f"""
        SELECT c.CLIENT_SEGMENT AS SEGMENT, ROUND(SUM(r.REVENUE_AMOUNT), 0) AS REVENUE
        FROM {DB}.{SCHEMA}.FACT_REVENUE r
        JOIN {DB}.{SCHEMA}.DIM_CLIENT c ON r.CLIENT_KEY = c.CLIENT_KEY
        GROUP BY c.CLIENT_SEGMENT
        ORDER BY REVENUE DESC
    """)


@st.cache_data(ttl=600)
def load_revenue_by_product() -> pd.DataFrame:
    return run_query(f"""
        SELECT p.PRODUCT_CATEGORY AS CATEGORY, ROUND(SUM(r.REVENUE_AMOUNT), 0) AS REVENUE,
               ROUND(AVG(r.FEE_BASIS_POINTS), 1) AS AVG_BPS
        FROM {DB}.{SCHEMA}.FACT_REVENUE r
        JOIN {DB}.{SCHEMA}.DIM_PRODUCT p ON r.PRODUCT_KEY = p.PRODUCT_KEY
        GROUP BY p.PRODUCT_CATEGORY
        ORDER BY REVENUE DESC
    """)


@st.cache_data(ttl=600)
def load_top_expenses() -> pd.DataFrame:
    return run_query(f"""
        SELECT ec.EXPENSE_CATEGORY_NAME AS CATEGORY, ROUND(SUM(e.EXPENSE_AMOUNT), 0) AS AMOUNT
        FROM {DB}.{SCHEMA}.FACT_EXPENSE e
        JOIN {DB}.{SCHEMA}.DIM_EXPENSE_CATEGORY ec ON e.EXPENSE_CATEGORY_KEY = ec.EXPENSE_CATEGORY_KEY
        GROUP BY ec.EXPENSE_CATEGORY_NAME
        ORDER BY AMOUNT DESC
        LIMIT 10
    """)


@st.cache_data(ttl=600)
def load_client_profitability() -> pd.DataFrame:
    return run_query(f"""
        SELECT c.CLIENT_NAME, c.CLIENT_SEGMENT, c.AUM_TIER,
               ROUND(SUM(r.REVENUE_AMOUNT), 0) AS TOTAL_REVENUE,
               ROUND(SUM(r.AUM_AMOUNT) / 1e6, 1) AS AUM_MILLIONS,
               ROUND(AVG(r.FEE_BASIS_POINTS), 1) AS AVG_BPS
        FROM {DB}.{SCHEMA}.FACT_REVENUE r
        JOIN {DB}.{SCHEMA}.DIM_CLIENT c ON r.CLIENT_KEY = c.CLIENT_KEY
        GROUP BY c.CLIENT_NAME, c.CLIENT_SEGMENT, c.AUM_TIER
        ORDER BY SUM(r.REVENUE_AMOUNT) DESC
    """)


# ---------------------------------------------------------------------------
# Load all data
# ---------------------------------------------------------------------------
kpi_rev = load_kpi_revenue()
kpi_exp = load_kpi_expenses()
kpi_ni = load_kpi_net_income()
kpi_cli = load_kpi_clients()
df_pl = load_pl_trend()
df_segment = load_revenue_by_segment()
df_product = load_revenue_by_product()
df_expenses = load_top_expenses()
df_clients = load_client_profitability()

# ---------------------------------------------------------------------------
# Sidebar — Client Segment filter
# ---------------------------------------------------------------------------
with st.sidebar:
    st.header("Filters")
    segments = ["All"] + sorted(df_segment["segment"].unique().tolist())
    selected_segment = st.selectbox("Client Segment", segments)

# Apply filter
if selected_segment != "All":
    df_segment_filtered = df_segment[df_segment["segment"] == selected_segment]
    df_clients_filtered = df_clients[df_clients["client_segment"] == selected_segment]
else:
    df_segment_filtered = df_segment
    df_clients_filtered = df_clients

# ---------------------------------------------------------------------------
# Page header
# ---------------------------------------------------------------------------
header_left, header_right = st.columns([8, 4])
with header_left:
    st.title("Pinnacle Financial Analytics")
with header_right:
    st.markdown("")  # spacer
    if st.button("↻ Refresh data", type="tertiary"):
        st.cache_data.clear()
        st.rerun()

# ---------------------------------------------------------------------------
# Highlight banner
# ---------------------------------------------------------------------------
st.info(
    "Net income trending upward — January posted the strongest margin "
    "at +56% on $2.1M revenue",
    icon=":material/trending_up:",
)

# ---------------------------------------------------------------------------
# Row 1 — KPI Scorecards
# ---------------------------------------------------------------------------
with st.container(horizontal=True):
    st.metric(
        label="Total Revenue",
        value=kpi_rev["value"].iloc[0],
        delta=kpi_rev["diff"].iloc[0],
        help="Jul 2025 – Jan 2026",
        border=True,
    )
    st.metric(
        label="Total Expenses",
        value=kpi_exp["value"].iloc[0],
        delta=kpi_exp["diff"].iloc[0],
        delta_color="inverse",
        help="Jul 2025 – Jan 2026",
        border=True,
    )
    st.metric(
        label="Net Income",
        value=kpi_ni["value"].iloc[0],
        delta=kpi_ni["diff"].iloc[0],
        help="Profit Margin",
        border=True,
    )
    st.metric(
        label="Active Clients",
        value=kpi_cli["value"].iloc[0],
        delta=kpi_cli["diff"].iloc[0],
        help="Total Assets Under Management",
        border=True,
    )

# ---------------------------------------------------------------------------
# Row 2 — P&L Trend (2/3) + Revenue by Segment (1/3)
# ---------------------------------------------------------------------------
col_pl, col_seg = st.columns([2, 1])

with col_pl:
    with st.container(border=True):
        st.subheader("Monthly P&L Trend")

        color_scale = alt.Scale(
            domain=["Revenue", "Expenses", "Net Income"],
            range=["#2E86C1", "#E74C3C", "#27AE60"],
        )
        stroke_dash_scale = alt.Scale(
            domain=["Revenue", "Expenses", "Net Income"],
            range=[[0], [0], [4, 4]],
        )

        pl_chart = (
            alt.Chart(df_pl)
            .mark_line(point=True)
            .encode(
                x=alt.X("month:T", title="Month", axis=alt.Axis(format="%b %Y")),
                y=alt.Y("amount:Q", title="Amount ($)", axis=alt.Axis(format="$,.0f")),
                color=alt.Color("metric:N", title="Metric", scale=color_scale),
                strokeDash=alt.StrokeDash(
                    "metric:N", scale=stroke_dash_scale, legend=None
                ),
                tooltip=[
                    alt.Tooltip("month:T", title="Month", format="%b %Y"),
                    alt.Tooltip("metric:N", title="Metric"),
                    alt.Tooltip("amount:Q", title="Amount", format="$,.0f"),
                ],
            )
            .properties(height=350)
        )
        st.altair_chart(pl_chart, use_container_width=True)

with col_seg:
    with st.container(border=True):
        st.subheader("Revenue by Client Segment")

        seg_color_scale = alt.Scale(
            domain=["Institutional", "Family Office", "Individual"],
            range=["#2E86C1", "#F39C12", "#27AE60"],
        )

        seg_chart = (
            alt.Chart(df_segment_filtered)
            .mark_bar()
            .encode(
                x=alt.X("segment:N", title="Client Segment", sort="-y"),
                y=alt.Y("revenue:Q", title="Revenue ($)", axis=alt.Axis(format="$,.0f")),
                color=alt.Color("segment:N", scale=seg_color_scale, legend=None),
                tooltip=[
                    alt.Tooltip("segment:N", title="Segment"),
                    alt.Tooltip("revenue:Q", title="Revenue", format="$,.0f"),
                ],
            )
            .properties(height=350)
        )
        st.altair_chart(seg_chart, use_container_width=True)

# ---------------------------------------------------------------------------
# Row 3 — Revenue by Product (1/2) + Top Expenses (1/2)
# ---------------------------------------------------------------------------
col_prod, col_exp = st.columns(2)

with col_prod:
    with st.container(border=True):
        st.subheader("Revenue by Product Category")

        prod_color_scale = alt.Scale(
            domain=["Performance Fee", "Management Fee", "Advisory Fee"],
            range=["#8E44AD", "#2E86C1", "#16A085"],
        )

        prod_chart = (
            alt.Chart(df_product)
            .mark_bar()
            .encode(
                x=alt.X("category:N", title="Product Category", sort="-y"),
                y=alt.Y("revenue:Q", title="Revenue ($)", axis=alt.Axis(format="$,.0f")),
                color=alt.Color("category:N", scale=prod_color_scale, legend=None),
                tooltip=[
                    alt.Tooltip("category:N", title="Category"),
                    alt.Tooltip("revenue:Q", title="Revenue", format="$,.0f"),
                    alt.Tooltip("avg_bps:Q", title="Avg Basis Points"),
                ],
            )
            .properties(height=350)
        )
        st.altair_chart(prod_chart, use_container_width=True)

with col_exp:
    with st.container(border=True):
        st.subheader("Top 10 Expense Categories")

        exp_chart = (
            alt.Chart(df_expenses)
            .mark_bar(color="#E74C3C")
            .encode(
                y=alt.Y("category:N", title="Expense Category", sort="-x"),
                x=alt.X("amount:Q", title="Amount ($)", axis=alt.Axis(format="$,.0f")),
                tooltip=[
                    alt.Tooltip("category:N", title="Category"),
                    alt.Tooltip("amount:Q", title="Amount", format="$,.0f"),
                ],
            )
            .properties(height=350)
        )
        st.altair_chart(exp_chart, use_container_width=True)

# ---------------------------------------------------------------------------
# Row 4 — Client Profitability table
# ---------------------------------------------------------------------------
with st.container(border=True):
    st.subheader("Client Profitability")
    st.dataframe(
        df_clients_filtered,
        column_config={
            "client_name": st.column_config.TextColumn("Client Name"),
            "client_segment": st.column_config.TextColumn("Segment"),
            "aum_tier": st.column_config.TextColumn("AUM Tier"),
            "total_revenue": st.column_config.NumberColumn(
                "Total Revenue", format="$%d"
            ),
            "aum_millions": st.column_config.NumberColumn(
                "AUM (Millions)", format="%.1f"
            ),
            "avg_bps": st.column_config.NumberColumn(
                "Avg BPS", format="%.1f"
            ),
        },
        hide_index=True,
        use_container_width=True,
    )
