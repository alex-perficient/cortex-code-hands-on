"""
My Usage Dashboard - Personal Resource Monitoring

Monitors compute credits, Cortex AI usage, warehouse consumption,
storage, query performance, login activity, and object inventory
for any selected user.
"""

import pandas as pd
import altair as alt
import streamlit as st

st.set_page_config(
    page_title="My usage dashboard",
    page_icon=":material/monitoring:",
    layout="wide",
)

# =============================================================================
# Constants
# =============================================================================

CHART_HEIGHT = 320
DEFAULT_USER = "COCO_HOL_USER_33"

# =============================================================================
# Snowflake connection — works both locally and inside Snowsight
# =============================================================================


def _is_running_in_snowsight() -> bool:
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
    if IS_SNOWSIGHT:
        df = session.sql(sql).to_pandas()
    else:
        df = conn.query(sql, ttl=600)
    df.columns = df.columns.str.lower()
    return df


# =============================================================================
# Sidebar — user selector
# =============================================================================


@st.cache_data(ttl=600, show_spinner=False)
def load_user_list():
    df = run_query("""
        SELECT name
        FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
        WHERE name LIKE 'COCO_HOL_USER_%'
          AND deleted_on IS NULL
        ORDER BY name
    """)
    return df["name"].tolist()


with st.sidebar:
    st.markdown("## :material/settings: Settings")
    user_list = load_user_list()
    default_idx = user_list.index(DEFAULT_USER) if DEFAULT_USER in user_list else 0
    selected_user = st.selectbox(
        "Select user",
        options=user_list,
        index=default_idx,
    )
    st.divider()
    if st.button(":material/restart_alt: Refresh data", use_container_width=True):
        st.cache_data.clear()
        st.rerun()


def _user_suffix(user: str) -> str:
    """Extract numeric suffix from username, e.g. 'COCO_HOL_USER_33' -> '33'."""
    return user.rsplit("_", 1)[-1]


# =============================================================================
# Data loaders (cached, parameterised by user)
# =============================================================================


@st.cache_data(ttl=600, show_spinner=False)
def load_credit_summary(user: str):
    return run_query(f"""
        SELECT
            ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS total_compute_credits,
            ROUND(COALESCE(SUM(credits_used_query_acceleration), 0), 4) AS total_qas_credits,
            COUNT(DISTINCT query_id) AS total_queries,
            COUNT(DISTINCT warehouse_name) AS warehouses_used
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND user_name = '{user}'
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_cortex_summary(user: str):
    return run_query(f"""
        SELECT
            ROUND(COALESCE(SUM(credits), 0), 4) AS total_cortex_credits,
            COALESCE(SUM(request_count), 0) AS total_requests,
            COUNT(DISTINCT DATE(start_time)) AS active_days
        FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND username = '{user}'
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_wow_comparison(user: str):
    return run_query(f"""
        WITH current_week AS (
            SELECT ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
            WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
              AND user_name = '{user}'
        ),
        previous_week AS (
            SELECT ROUND(COALESCE(SUM(credits_attributed_compute), 0), 4) AS credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
            WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
              AND start_time < DATEADD(DAY, -7, CURRENT_DATE())
              AND user_name = '{user}'
        )
        SELECT
            c.credits AS current_week_credits,
            p.credits AS previous_week_credits,
            ROUND(c.credits - p.credits, 4) AS change,
            CASE WHEN p.credits > 0
                 THEN ROUND(((c.credits - p.credits) / p.credits) * 100, 2)
                 ELSE NULL END AS pct_change
        FROM current_week c, previous_week p
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_daily_credits(user: str):
    return run_query(f"""
        SELECT
            DATE(start_time) AS usage_date,
            ROUND(SUM(credits_attributed_compute), 4) AS daily_compute_credits,
            ROUND(SUM(COALESCE(credits_used_query_acceleration, 0)), 4) AS daily_qas_credits,
            COUNT(DISTINCT query_id) AS daily_query_count
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND user_name = '{user}'
        GROUP BY DATE(start_time)
        ORDER BY usage_date
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_warehouse_credits(user: str):
    return run_query(f"""
        SELECT
            warehouse_name,
            ROUND(SUM(credits_attributed_compute), 4) AS total_credits,
            COUNT(DISTINCT query_id) AS query_count,
            ROUND(AVG(credits_attributed_compute), 6) AS avg_credits_per_query
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND user_name = '{user}'
        GROUP BY warehouse_name
        ORDER BY total_credits DESC
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_top_queries(user: str):
    return run_query(f"""
        SELECT
            query_id,
            warehouse_name,
            ROUND(credits_attributed_compute, 6) AS credits_compute,
            ROUND(COALESCE(credits_used_query_acceleration, 0), 6) AS credits_qas,
            start_time
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND user_name = '{user}'
          AND credits_attributed_compute > 0
        ORDER BY credits_attributed_compute DESC
        LIMIT 15
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_cortex_daily(user: str):
    return run_query(f"""
        SELECT
            DATE(start_time) AS usage_date,
            ROUND(SUM(credits), 4) AS daily_credits,
            SUM(request_count) AS daily_requests
        FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
        WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
          AND username = '{user}'
        GROUP BY DATE(start_time)
        ORDER BY usage_date
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_query_types(user: str):
    return run_query(f"""
        SELECT
            query_type,
            COUNT(*) AS execution_count,
            ROUND(AVG(total_elapsed_time) / 1000, 2) AS avg_duration_sec,
            ROUND(MAX(total_elapsed_time) / 1000, 2) AS max_duration_sec,
            ROUND(AVG(bytes_scanned) / (1024*1024), 2) AS avg_mb_scanned
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
        WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
          AND user_name = '{user}'
        GROUP BY query_type
        ORDER BY execution_count DESC
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_storage(user_suffix: str):
    return run_query(f"""
        SELECT
            database_name,
            ROUND(AVG(average_database_bytes) / (1024*1024*1024), 4) AS avg_storage_gb,
            ROUND(AVG(average_failsafe_bytes) / (1024*1024*1024), 4) AS avg_failsafe_gb,
            ROUND(AVG(average_database_bytes + average_failsafe_bytes
                      + COALESCE(average_hybrid_table_storage_bytes, 0))
                  / (1024*1024*1024), 4) AS total_avg_gb
        FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
        WHERE usage_date >= DATEADD(DAY, -30, CURRENT_DATE())
          AND (database_name LIKE '%_{user_suffix}' OR database_name LIKE '%_{user_suffix}_%')
        GROUP BY database_name
        ORDER BY total_avg_gb DESC
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_login_history(user: str):
    return run_query(f"""
        SELECT
            DATE(event_timestamp) AS login_date,
            COUNT(*) AS login_count,
            COUNT_IF(is_success = 'YES') AS successful_logins,
            COUNT_IF(is_success = 'NO') AS failed_logins
        FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
        WHERE event_timestamp >= DATEADD(DAY, -7, CURRENT_DATE())
          AND user_name = '{user}'
        GROUP BY DATE(event_timestamp)
        ORDER BY login_date
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_object_inventory(user: str):
    return run_query(f"""
        WITH classified AS (
            SELECT
                CASE
                    WHEN query_type = 'CREATE_TABLE' THEN 'TABLE'
                    WHEN query_type = 'CREATE_TABLE_AS_SELECT' THEN 'TABLE (CTAS)'
                    WHEN query_type = 'CREATE_VIEW' THEN 'VIEW'
                    WHEN query_type = 'CREATE_SEMANTIC_VIEW' THEN 'SEMANTIC VIEW'
                    WHEN query_type = 'CREATE_ICEBERG_TABLE' THEN 'ICEBERG TABLE'
                    WHEN query_type = 'CREATE_STREAM' THEN 'STREAM'
                    WHEN query_type = 'CREATE_TASK' THEN 'TASK'
                    WHEN query_type = 'CREATE_ROLE' THEN 'ROLE'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%STREAMLIT%' THEN 'STREAMLIT APP'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%AGENT%' THEN 'AGENT'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%NOTEBOOK%' THEN 'NOTEBOOK'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%DASHBOARD%' THEN 'DASHBOARD'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%STAGE%' THEN 'STAGE'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%DATABASE%' THEN 'DATABASE'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%SCHEMA%' THEN 'SCHEMA'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%PROCEDURE%' THEN 'PROCEDURE'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%FUNCTION%' THEN 'FUNCTION'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%FILE FORMAT%' THEN 'FILE FORMAT'
                    WHEN query_type = 'CREATE' AND UPPER(query_text) LIKE '%WORKSPACE%' THEN 'WORKSPACE'
                    ELSE 'OTHER'
                END AS object_type,
                query_hash
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
            WHERE user_name = '{user}'
              AND query_type LIKE 'CREATE%'
              AND execution_status = 'SUCCESS'
              AND start_time >= DATEADD(DAY, -90, CURRENT_DATE())
        )
        SELECT object_type, COUNT(DISTINCT query_hash) AS objects_created
        FROM classified
        GROUP BY object_type
        ORDER BY objects_created DESC
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_current_objects(user_suffix: str):
    return run_query(f"""
        SELECT 'TABLE' AS object_type, COUNT(*) AS object_count
        FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
        WHERE deleted IS NULL
          AND table_type = 'BASE TABLE'
          AND (table_catalog LIKE '%_{user_suffix}' OR table_catalog LIKE '%_{user_suffix}_%')
        UNION ALL
        SELECT 'VIEW', COUNT(*)
        FROM SNOWFLAKE.ACCOUNT_USAGE.VIEWS
        WHERE deleted IS NULL
          AND (table_catalog LIKE '%_{user_suffix}' OR table_catalog LIKE '%_{user_suffix}_%')
        UNION ALL
        SELECT 'FUNCTION', COUNT(*)
        FROM SNOWFLAKE.ACCOUNT_USAGE.FUNCTIONS
        WHERE deleted IS NULL
          AND (function_catalog LIKE '%_{user_suffix}' OR function_catalog LIKE '%_{user_suffix}_%')
        UNION ALL
        SELECT 'PROCEDURE', COUNT(*)
        FROM SNOWFLAKE.ACCOUNT_USAGE.PROCEDURES
        WHERE deleted IS NULL
          AND (procedure_catalog LIKE '%_{user_suffix}' OR procedure_catalog LIKE '%_{user_suffix}_%')
        UNION ALL
        SELECT 'STAGE', COUNT(*)
        FROM SNOWFLAKE.ACCOUNT_USAGE.STAGES
        WHERE deleted IS NULL
          AND (stage_catalog LIKE '%_{user_suffix}' OR stage_catalog LIKE '%_{user_suffix}_%')
        UNION ALL
        SELECT 'SEMANTIC VIEW', COUNT(*)
        FROM SNOWFLAKE.ACCOUNT_USAGE.SEMANTIC_VIEWS
        WHERE deleted IS NULL
          AND (semantic_view_database_name LIKE '%_{user_suffix}' OR semantic_view_database_name LIKE '%_{user_suffix}_%')
        ORDER BY object_count DESC
    """)


# =============================================================================
# Page header
# =============================================================================

st.markdown("# :material/monitoring: My usage dashboard")
st.caption(
    f":material/person: **{selected_user}**  |  Last 30 days  |  :material/cloud: Powered by Snowflake"
)

# =============================================================================
# KPI row
# =============================================================================

with st.spinner("Loading summary..."):
    credit_summary = load_credit_summary(selected_user)
    cortex_summary = load_cortex_summary(selected_user)
    wow = load_wow_comparison(selected_user)

total_compute = float(credit_summary["total_compute_credits"].iloc[0] or 0)
total_qas = float(credit_summary["total_qas_credits"].iloc[0] or 0)
total_queries = int(credit_summary["total_queries"].iloc[0] or 0)
wh_used = int(credit_summary["warehouses_used"].iloc[0] or 0)

cortex_credits = float(cortex_summary["total_cortex_credits"].iloc[0] or 0)
cortex_requests = int(cortex_summary["total_requests"].iloc[0] or 0)

wow_change = float(wow["change"].iloc[0] or 0)
wow_pct = wow["pct_change"].iloc[0]
wow_delta = f"{wow_pct}%" if wow_pct is not None and str(wow_pct) != "None" else "N/A"

with st.container(horizontal=True):
    st.metric("Compute credits (30d)", f"{total_compute:,.4f}", delta=f"{wow_delta} WoW", border=True)
    st.metric("Cortex AI credits (30d)", f"{cortex_credits:,.4f}", border=True)
    st.metric("Total queries (30d)", f"{total_queries:,}", border=True)
    st.metric("Warehouses used", f"{wh_used}", border=True)
    st.metric("Cortex requests", f"{cortex_requests:,}", border=True)

# =============================================================================
# Row 1: Daily credits trend + Credits by warehouse
# =============================================================================

col1, col2 = st.columns(2)

with col1:
    with st.container(border=True):
        st.markdown("**:material/show_chart: Daily compute credits**")
        daily_df = load_daily_credits(selected_user)
        if daily_df.empty:
            st.info("No compute credit data found for the last 30 days.")
        else:
            chart = (
                alt.Chart(daily_df)
                .mark_area(opacity=0.4, line=True)
                .encode(
                    x=alt.X("usage_date:T", title=None),
                    y=alt.Y("daily_compute_credits:Q", title="Credits"),
                    tooltip=[
                        alt.Tooltip("usage_date:T", title="Date", format="%Y-%m-%d"),
                        alt.Tooltip("daily_compute_credits:Q", title="Credits", format=",.4f"),
                        alt.Tooltip("daily_query_count:Q", title="Queries"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
                .interactive()
            )
            st.altair_chart(chart, use_container_width=True)

with col2:
    with st.container(border=True):
        st.markdown("**:material/database: Credits by warehouse**")
        wh_df = load_warehouse_credits(selected_user)
        if wh_df.empty:
            st.info("No warehouse credit data found.")
        else:
            bar = (
                alt.Chart(wh_df)
                .mark_bar()
                .encode(
                    x=alt.X("total_credits:Q", title="Credits"),
                    y=alt.Y("warehouse_name:N", title=None, sort="-x"),
                    color=alt.Color("warehouse_name:N", legend=None),
                    tooltip=[
                        alt.Tooltip("warehouse_name:N", title="Warehouse"),
                        alt.Tooltip("total_credits:Q", title="Credits", format=",.4f"),
                        alt.Tooltip("query_count:Q", title="Queries"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(bar, use_container_width=True)

# =============================================================================
# Row 2: Cortex AI trend + Query types breakdown
# =============================================================================

col3, col4 = st.columns(2)

with col3:
    with st.container(border=True):
        st.markdown("**:material/smart_toy: Cortex Analyst daily usage**")
        cortex_df = load_cortex_daily(selected_user)
        if cortex_df.empty:
            st.info("No Cortex Analyst usage found for the last 30 days.")
        else:
            area = (
                alt.Chart(cortex_df)
                .mark_area(opacity=0.3, color="#6C63FF", line=True)
                .encode(
                    x=alt.X("usage_date:T", title=None),
                    y=alt.Y("daily_credits:Q", title="Credits"),
                    tooltip=[
                        alt.Tooltip("usage_date:T", title="Date", format="%Y-%m-%d"),
                        alt.Tooltip("daily_credits:Q", title="Credits", format=",.4f"),
                        alt.Tooltip("daily_requests:Q", title="Requests"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
                .interactive()
            )
            st.altair_chart(area, use_container_width=True)

with col4:
    with st.container(border=True):
        st.markdown("**:material/query_stats: Query types (last 7 days)**")
        qt_df = load_query_types(selected_user)
        if qt_df.empty:
            st.info("No query history found.")
        else:
            pie = (
                alt.Chart(qt_df)
                .mark_arc(innerRadius=50)
                .encode(
                    theta=alt.Theta("execution_count:Q"),
                    color=alt.Color("query_type:N", legend=alt.Legend(orient="bottom", columns=3)),
                    tooltip=[
                        alt.Tooltip("query_type:N", title="Type"),
                        alt.Tooltip("execution_count:Q", title="Count"),
                        alt.Tooltip("avg_duration_sec:Q", title="Avg duration (s)"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(pie, use_container_width=True)

# =============================================================================
# Row 3: Object inventory (full width)
# =============================================================================

with st.container(border=True):
    st.markdown("**:material/inventory_2: Objects created (last 90 days)**")
    inv_df = load_object_inventory(selected_user)
    suffix = _user_suffix(selected_user)
    if inv_df.empty:
        st.info("No objects created by this user in the last 90 days.")
    else:
        total_objects = int(inv_df["objects_created"].sum())
        top_types = inv_df.head(5)

        with st.container(horizontal=True):
            st.metric("Total objects created", f"{total_objects:,}", border=True)
            for _, row in top_types.iterrows():
                st.metric(row["object_type"], int(row["objects_created"]), border=True)

        inv_bar = (
            alt.Chart(inv_df)
            .mark_bar()
            .encode(
                x=alt.X("objects_created:Q", title="Count"),
                y=alt.Y("object_type:N", title=None, sort="-x"),
                color=alt.Color("object_type:N", legend=None),
                tooltip=[
                    alt.Tooltip("object_type:N", title="Object type"),
                    alt.Tooltip("objects_created:Q", title="Count"),
                ],
            )
            .properties(height=max(len(inv_df) * 30, 200))
        )
        st.altair_chart(inv_bar, use_container_width=True)

# =============================================================================
# Row 3b: Current live objects in user databases (full width)
# =============================================================================

with st.container(border=True):
    st.markdown(f"**:material/check_circle: Current objects in databases matching _{suffix}**")
    cur_df = load_current_objects(suffix)
    cur_df = cur_df[cur_df["object_count"] > 0]
    if cur_df.empty:
        st.info(f"No current objects found in databases matching suffix _{suffix}.")
    else:
        total_current = int(cur_df["object_count"].sum())

        with st.container(horizontal=True):
            st.metric("Total live objects", f"{total_current:,}", border=True)
            for _, row in cur_df.iterrows():
                st.metric(row["object_type"], int(row["object_count"]), border=True)

        cur_bar = (
            alt.Chart(cur_df)
            .mark_bar(color="#4CAF50")
            .encode(
                x=alt.X("object_count:Q", title="Count"),
                y=alt.Y("object_type:N", title=None, sort="-x"),
                tooltip=[
                    alt.Tooltip("object_type:N", title="Object type"),
                    alt.Tooltip("object_count:Q", title="Count"),
                ],
            )
            .properties(height=max(len(cur_df) * 35, 150))
        )
        st.altair_chart(cur_bar, use_container_width=True)
    st.caption("Based on ACCOUNT_USAGE catalog views. Only includes objects in user-specific databases.")

# =============================================================================
# Row 4: Storage + Login history
# =============================================================================

col5, col6 = st.columns(2)

with col5:
    with st.container(border=True):
        st.markdown("**:material/storage: Database storage**")
        storage_df = load_storage(suffix)
        if storage_df.empty:
            st.info(f"No storage data found for databases matching suffix _{suffix}.")
        else:
            st.dataframe(
                storage_df,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "database_name": st.column_config.TextColumn("Database"),
                    "avg_storage_gb": st.column_config.NumberColumn("Storage (GB)", format="%.4f"),
                    "avg_failsafe_gb": st.column_config.NumberColumn("Failsafe (GB)", format="%.4f"),
                    "total_avg_gb": st.column_config.NumberColumn("Total (GB)", format="%.4f"),
                },
            )

with col6:
    with st.container(border=True):
        st.markdown("**:material/login: Login activity (last 7 days)**")
        login_df = load_login_history(selected_user)
        if login_df.empty:
            st.info("No login history found.")
        else:
            login_melted = login_df.melt(
                id_vars=["login_date"],
                value_vars=["successful_logins", "failed_logins"],
                var_name="status",
                value_name="count",
            )
            login_chart = (
                alt.Chart(login_melted)
                .mark_bar()
                .encode(
                    x=alt.X("login_date:T", title=None),
                    y=alt.Y("count:Q", title="Logins"),
                    color=alt.Color(
                        "status:N",
                        scale=alt.Scale(
                            domain=["successful_logins", "failed_logins"],
                            range=["#4CAF50", "#F44336"],
                        ),
                        legend=alt.Legend(orient="bottom"),
                    ),
                    tooltip=[
                        alt.Tooltip("login_date:T", title="Date", format="%Y-%m-%d"),
                        alt.Tooltip("status:N", title="Status"),
                        alt.Tooltip("count:Q", title="Count"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(login_chart, use_container_width=True)

# =============================================================================
# Row 5: Top expensive queries (full width)
# =============================================================================

with st.container(border=True):
    st.markdown("**:material/paid: Top 15 most expensive queries (last 30 days)**")
    top_df = load_top_queries(selected_user)
    if top_df.empty:
        st.info("No queries with compute credits found.")
    else:
        st.dataframe(
            top_df,
            use_container_width=True,
            hide_index=True,
            column_config={
                "query_id": st.column_config.TextColumn("Query ID"),
                "warehouse_name": st.column_config.TextColumn("Warehouse"),
                "credits_compute": st.column_config.NumberColumn("Compute credits", format="%.6f"),
                "credits_qas": st.column_config.NumberColumn("QAS credits", format="%.6f"),
                "start_time": st.column_config.DatetimeColumn("Start time", format="YYYY-MM-DD HH:mm"),
            },
        )
