import streamlit as st
import altair as alt
import pandas as pd

# ---------------------------------------------------------------------------
# Page config (must be first Streamlit call)
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="Fidely App - Gula Maps",
    page_icon=":material/restaurant:",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DB = "PINNACLE_FINANCIAL_DEMO_33"
SCHEMA = "ANALYTICS_ZONE"
FQ = f"{DB}.{SCHEMA}"

CHART_HEIGHT = 320

# ---------------------------------------------------------------------------
# Snowflake connection - works both locally and inside Snowsight
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Cached data loaders
# ---------------------------------------------------------------------------


@st.cache_data(ttl=600, show_spinner=False)
def load_kpis() -> dict:
    df = run_query(f"""
        SELECT
            COUNT(DISTINCT f.VISIT_KEY)  AS total_visits,
            COUNT(DISTINCT f.USER_KEY)   AS active_users,
            SUM(f.POINTS_EARNED)         AS total_points,
            SUM(f.CASHBACK_AMOUNT)       AS total_cashback,
            COUNT(DISTINCT f.BUSINESS_KEY) AS businesses_visited
        FROM {FQ}.FACT_VISITS f
    """)
    rating = run_query(f"""
        SELECT ROUND(AVG(GOOGLE_RATING), 1) AS avg_rating
        FROM {FQ}.DIM_BUSINESSES
    """)
    total_biz = run_query(f"""
        SELECT COUNT(*) AS cnt FROM {FQ}.DIM_BUSINESSES
    """)
    total_users = run_query(f"""
        SELECT COUNT(*) AS cnt FROM {FQ}.DIM_USERS
    """)
    return {
        "total_visits": int(df["total_visits"].iloc[0]),
        "active_users": int(df["active_users"].iloc[0]),
        "total_points": int(df["total_points"].iloc[0]),
        "total_cashback": float(df["total_cashback"].iloc[0]),
        "businesses_visited": int(df["businesses_visited"].iloc[0]),
        "avg_rating": float(rating["avg_rating"].iloc[0]),
        "total_businesses": int(total_biz["cnt"].iloc[0]),
        "total_users": int(total_users["cnt"].iloc[0]),
    }


@st.cache_data(ttl=600, show_spinner=False)
def load_visits_by_month() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            t.YEAR,
            t.MONTH,
            t.MONTH_NAME,
            COUNT(*) AS visits,
            COUNT(DISTINCT f.USER_KEY) AS unique_users,
            SUM(f.CASHBACK_AMOUNT) AS cashback
        FROM {FQ}.FACT_VISITS f
        JOIN {FQ}.DIM_TIME t ON f.DATE_KEY = t.DATE_KEY
        GROUP BY t.YEAR, t.MONTH, t.MONTH_NAME
        ORDER BY t.YEAR, t.MONTH
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_visits_by_dow() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            t.DAY_OF_WEEK,
            t.DAY_NAME,
            COUNT(*) AS visits,
            t.IS_WEEKEND
        FROM {FQ}.FACT_VISITS f
        JOIN {FQ}.DIM_TIME t ON f.DATE_KEY = t.DATE_KEY
        GROUP BY t.DAY_OF_WEEK, t.DAY_NAME, t.IS_WEEKEND
        ORDER BY t.DAY_OF_WEEK
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_visits_by_hour() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            HOUR(f.VISIT_TIMESTAMP) AS visit_hour,
            COUNT(*) AS visits
        FROM {FQ}.FACT_VISITS f
        GROUP BY visit_hour
        ORDER BY visit_hour
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_loyalty_performance() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            lt.LOYALTY_TYPE_NAME,
            f.VISIT_TYPE,
            COUNT(*) AS visit_count,
            SUM(f.POINTS_EARNED) AS total_points,
            SUM(f.CASHBACK_AMOUNT) AS total_cashback,
            SUM(f.PUNCH_COUNT) AS total_punches
        FROM {FQ}.FACT_VISITS f
        JOIN {FQ}.DIM_LOYALTY_TYPE lt ON f.LOYALTY_TYPE_KEY = lt.LOYALTY_TYPE_KEY
        GROUP BY lt.LOYALTY_TYPE_NAME, f.VISIT_TYPE
        ORDER BY lt.LOYALTY_TYPE_NAME, f.VISIT_TYPE
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_category_breakdown() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            b.CATEGORY,
            COUNT(*) AS visits,
            COUNT(DISTINCT f.USER_KEY) AS unique_users,
            COUNT(DISTINCT f.BUSINESS_KEY) AS business_count,
            SUM(f.POINTS_EARNED) AS total_points,
            SUM(f.CASHBACK_AMOUNT) AS total_cashback
        FROM {FQ}.FACT_VISITS f
        JOIN {FQ}.DIM_BUSINESSES b ON f.BUSINESS_KEY = b.BUSINESS_KEY
        GROUP BY b.CATEGORY
        ORDER BY visits DESC
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_top_merchants(limit: int = 15) -> pd.DataFrame:
    return run_query(f"""
        SELECT
            b.BUSINESS_NAME,
            b.CATEGORY,
            b.NEIGHBORHOOD,
            b.LOYALTY_TYPE,
            b.GOOGLE_RATING,
            COUNT(*) AS total_visits,
            COUNT(DISTINCT f.USER_KEY) AS unique_visitors,
            SUM(f.CASHBACK_AMOUNT) AS cashback_given
        FROM {FQ}.FACT_VISITS f
        JOIN {FQ}.DIM_BUSINESSES b ON f.BUSINESS_KEY = b.BUSINESS_KEY
        GROUP BY b.BUSINESS_NAME, b.CATEGORY, b.NEIGHBORHOOD,
                 b.LOYALTY_TYPE, b.GOOGLE_RATING
        ORDER BY total_visits DESC
        LIMIT {limit}
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_business_map() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            b.BUSINESS_NAME,
            b.CATEGORY,
            b.NEIGHBORHOOD,
            b.LOYALTY_TYPE,
            b.GOOGLE_RATING,
            b.LAT AS latitude,
            b.LNG AS longitude,
            COUNT(f.VISIT_KEY) AS total_visits
        FROM {FQ}.DIM_BUSINESSES b
        LEFT JOIN {FQ}.FACT_VISITS f ON b.BUSINESS_KEY = f.BUSINESS_KEY
        GROUP BY b.BUSINESS_NAME, b.CATEGORY, b.NEIGHBORHOOD,
                 b.LOYALTY_TYPE, b.GOOGLE_RATING, b.LAT, b.LNG
    """)


@st.cache_data(ttl=600, show_spinner=False)
def load_neighborhood_stats() -> pd.DataFrame:
    return run_query(f"""
        SELECT
            b.NEIGHBORHOOD,
            COUNT(DISTINCT b.BUSINESS_KEY) AS businesses,
            COUNT(f.VISIT_KEY) AS visits,
            COUNT(DISTINCT f.USER_KEY) AS unique_users,
            ROUND(AVG(b.GOOGLE_RATING), 1) AS avg_rating
        FROM {FQ}.DIM_BUSINESSES b
        LEFT JOIN {FQ}.FACT_VISITS f ON b.BUSINESS_KEY = f.BUSINESS_KEY
        GROUP BY b.NEIGHBORHOOD
        ORDER BY visits DESC
    """)


# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------
with st.sidebar:
    st.title(":material/restaurant: Fidely App")
    st.caption("Gula Maps - Merida, Yucatan")

    section = st.radio(
        "Navigate",
        options=[
            ":material/monitoring: Overview",
            ":material/schedule: Foot traffic",
            ":material/loyalty: Loyalty programs",
            ":material/storefront: Businesses",
            ":material/map: Map",
        ],
        label_visibility="collapsed",
    )

    st.caption("Data source: ANALYTICS_ZONE (POC synthetic data)")


# ---------------------------------------------------------------------------
# Load all data upfront
# ---------------------------------------------------------------------------
with st.spinner("Loading data from Snowflake..."):
    kpis = load_kpis()

# ---------------------------------------------------------------------------
# Section: Overview
# ---------------------------------------------------------------------------
if "Overview" in section:
    st.title("Fidely overview")
    st.caption("Key metrics across the Gula Maps ecosystem in Merida")

    # KPI row
    with st.container(horizontal=True):
        st.metric("Total visits", f"{kpis['total_visits']:,}", border=True)
        st.metric("Active users", f"{kpis['active_users']:,}",
                   help=f"Out of {kpis['total_users']:,} registered", border=True)
        st.metric("Businesses", f"{kpis['total_businesses']:,}", border=True)
        st.metric("Avg rating", f"{kpis['avg_rating']}", border=True)

    with st.container(horizontal=True):
        st.metric("Points earned", f"{kpis['total_points']:,}", border=True)
        st.metric("Cashback given", f"${kpis['total_cashback']:,.2f}", border=True)

    # Monthly trend
    monthly = load_visits_by_month()

    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Monthly visits")
            month_chart = (
                alt.Chart(monthly)
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("month_name:N", title=None,
                             sort=monthly["month_name"].tolist()),
                    y=alt.Y("visits:Q", title="Visits"),
                    color=alt.Color("month_name:N", legend=None),
                    tooltip=[
                        alt.Tooltip("month_name:N", title="Month"),
                        alt.Tooltip("visits:Q", title="Visits", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(month_chart, use_container_width=True)

    with col2:
        with st.container(border=True):
            st.subheader("Monthly unique users")
            users_chart = (
                alt.Chart(monthly)
                .mark_area(opacity=0.5, line=True)
                .encode(
                    x=alt.X("month_name:N", title=None,
                             sort=monthly["month_name"].tolist()),
                    y=alt.Y("unique_users:Q", title="Unique users",
                             scale=alt.Scale(zero=False)),
                    tooltip=[
                        alt.Tooltip("month_name:N", title="Month"),
                        alt.Tooltip("unique_users:Q", title="Users", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(users_chart, use_container_width=True)

    # Neighborhood stats
    nb = load_neighborhood_stats()
    with st.container(border=True):
        st.subheader("Neighborhoods")
        st.dataframe(
            nb,
            column_config={
                "neighborhood": st.column_config.TextColumn("Neighborhood"),
                "businesses": st.column_config.NumberColumn("Businesses"),
                "visits": st.column_config.NumberColumn("Visits", format="%d"),
                "unique_users": st.column_config.NumberColumn("Unique users"),
                "avg_rating": st.column_config.NumberColumn("Avg rating", format="%.1f"),
            },
            hide_index=True,
            use_container_width=True,
        )


# ---------------------------------------------------------------------------
# Section: Foot traffic
# ---------------------------------------------------------------------------
elif "Foot traffic" in section:
    st.title("Foot traffic analysis")
    st.caption("When do users visit businesses in Merida?")

    dow = load_visits_by_dow()
    hourly = load_visits_by_hour()

    col1, col2 = st.columns(2)

    with col1:
        with st.container(border=True):
            st.subheader("Visits by day of week")
            dow_chart = (
                alt.Chart(dow)
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("day_name:N", title=None,
                             sort=["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
                    y=alt.Y("visits:Q", title="Visits"),
                    color=alt.condition(
                        alt.datum.is_weekend == True,
                        alt.value("#FF6B6B"),
                        alt.value("#4ECDC4"),
                    ),
                    tooltip=[
                        alt.Tooltip("day_name:N", title="Day"),
                        alt.Tooltip("visits:Q", title="Visits", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(dow_chart, use_container_width=True)

    with col2:
        with st.container(border=True):
            st.subheader("Visits by hour of day")
            hour_chart = (
                alt.Chart(hourly)
                .mark_area(
                    opacity=0.6,
                    line=True,
                    interpolate="monotone",
                )
                .encode(
                    x=alt.X("visit_hour:Q", title="Hour of day",
                             scale=alt.Scale(domain=[0, 23])),
                    y=alt.Y("visits:Q", title="Visits"),
                    tooltip=[
                        alt.Tooltip("visit_hour:Q", title="Hour"),
                        alt.Tooltip("visits:Q", title="Visits", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(hour_chart, use_container_width=True)

    # Heatmap: day of week x hour
    with st.container(border=True):
        st.subheader("Traffic heatmap (day x hour)")
        heatmap_data = run_query(f"""
            SELECT
                t.DAY_NAME,
                t.DAY_OF_WEEK,
                HOUR(f.VISIT_TIMESTAMP) AS visit_hour,
                COUNT(*) AS visits
            FROM {FQ}.FACT_VISITS f
            JOIN {FQ}.DIM_TIME t ON f.DATE_KEY = t.DATE_KEY
            GROUP BY t.DAY_NAME, t.DAY_OF_WEEK, visit_hour
            ORDER BY t.DAY_OF_WEEK, visit_hour
        """)
        heatmap = (
            alt.Chart(heatmap_data)
            .mark_rect(cornerRadius=3)
            .encode(
                x=alt.X("visit_hour:O", title="Hour of day"),
                y=alt.Y("day_name:N", title=None,
                         sort=["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
                color=alt.Color("visits:Q", title="Visits",
                                scale=alt.Scale(scheme="orangered")),
                tooltip=[
                    alt.Tooltip("day_name:N", title="Day"),
                    alt.Tooltip("visit_hour:O", title="Hour"),
                    alt.Tooltip("visits:Q", title="Visits", format=","),
                ],
            )
            .properties(height=250)
        )
        st.altair_chart(heatmap, use_container_width=True)


# ---------------------------------------------------------------------------
# Section: Loyalty programs
# ---------------------------------------------------------------------------
elif "Loyalty" in section:
    st.title("Loyalty program performance")
    st.caption("How are the different loyalty programs performing?")

    loyalty = load_loyalty_performance()

    # Summary by loyalty type
    loyalty_summary = (
        loyalty.groupby("loyalty_type_name")
        .agg({
            "visit_count": "sum",
            "total_points": "sum",
            "total_cashback": "sum",
            "total_punches": "sum",
        })
        .reset_index()
    )

    with st.container(horizontal=True):
        for _, row in loyalty_summary.iterrows():
            name = row["loyalty_type_name"]
            st.metric(
                f"{name} visits",
                f"{int(row['visit_count']):,}",
                border=True,
            )

    col1, col2 = st.columns(2)

    with col1:
        with st.container(border=True):
            st.subheader("Visits by loyalty type")
            loy_bar = (
                alt.Chart(loyalty_summary)
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("loyalty_type_name:N", title=None),
                    y=alt.Y("visit_count:Q", title="Visits"),
                    color=alt.Color("loyalty_type_name:N", title=None,
                                    legend=None),
                    tooltip=[
                        alt.Tooltip("loyalty_type_name:N", title="Type"),
                        alt.Tooltip("visit_count:Q", title="Visits", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(loy_bar, use_container_width=True)

    with col2:
        with st.container(border=True):
            st.subheader("Visit type breakdown")
            visit_type_chart = (
                alt.Chart(loyalty)
                .mark_bar()
                .encode(
                    x=alt.X("visit_count:Q", title="Visits", stack="normalize"),
                    y=alt.Y("loyalty_type_name:N", title=None),
                    color=alt.Color("visit_type:N", title="Visit type"),
                    tooltip=[
                        alt.Tooltip("loyalty_type_name:N", title="Loyalty"),
                        alt.Tooltip("visit_type:N", title="Visit type"),
                        alt.Tooltip("visit_count:Q", title="Count", format=","),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(visit_type_chart, use_container_width=True)

    # Cashback detail
    cashback_data = loyalty[loyalty["total_cashback"] > 0]
    if not cashback_data.empty:
        with st.container(border=True):
            st.subheader("Cashback distribution by visit type")
            cb_chart = (
                alt.Chart(cashback_data)
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("visit_type:N", title=None),
                    y=alt.Y("total_cashback:Q", title="Cashback ($)"),
                    color=alt.Color("visit_type:N", legend=None),
                    tooltip=[
                        alt.Tooltip("visit_type:N", title="Type"),
                        alt.Tooltip("total_cashback:Q", title="Cashback",
                                    format="$,.2f"),
                    ],
                )
                .properties(height=280)
            )
            st.altair_chart(cb_chart, use_container_width=True)


# ---------------------------------------------------------------------------
# Section: Businesses
# ---------------------------------------------------------------------------
elif "Businesses" in section:
    st.title("Business directory insights")
    st.caption("Category breakdown and top-performing merchants")

    cat = load_category_breakdown()
    top = load_top_merchants()

    col1, col2 = st.columns(2)

    with col1:
        with st.container(border=True):
            st.subheader("Visits by category")
            cat_chart = (
                alt.Chart(cat)
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("visits:Q", title="Visits"),
                    y=alt.Y("category:N", title=None,
                             sort="-x"),
                    color=alt.Color("category:N", legend=None),
                    tooltip=[
                        alt.Tooltip("category:N", title="Category"),
                        alt.Tooltip("visits:Q", title="Visits", format=","),
                        alt.Tooltip("unique_users:Q", title="Unique users",
                                    format=","),
                        alt.Tooltip("business_count:Q", title="Businesses"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(cat_chart, use_container_width=True)

    with col2:
        with st.container(border=True):
            st.subheader("Cashback by category")
            cash_cat = (
                alt.Chart(cat[cat["total_cashback"] > 0])
                .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
                .encode(
                    x=alt.X("total_cashback:Q", title="Total cashback ($)"),
                    y=alt.Y("category:N", title=None, sort="-x"),
                    color=alt.Color("category:N", legend=None),
                    tooltip=[
                        alt.Tooltip("category:N", title="Category"),
                        alt.Tooltip("total_cashback:Q", title="Cashback",
                                    format="$,.2f"),
                    ],
                )
                .properties(height=CHART_HEIGHT)
            )
            st.altair_chart(cash_cat, use_container_width=True)

    with st.container(border=True):
        st.subheader("Top 15 merchants by visits")
        st.dataframe(
            top,
            column_config={
                "business_name": st.column_config.TextColumn("Business"),
                "category": st.column_config.TextColumn("Category"),
                "neighborhood": st.column_config.TextColumn("Neighborhood"),
                "loyalty_type": st.column_config.TextColumn("Loyalty"),
                "google_rating": st.column_config.NumberColumn(
                    "Rating", format="%.1f"),
                "total_visits": st.column_config.NumberColumn(
                    "Visits", format="%d"),
                "unique_visitors": st.column_config.NumberColumn(
                    "Unique visitors", format="%d"),
                "cashback_given": st.column_config.NumberColumn(
                    "Cashback given", format="$%.2f"),
            },
            hide_index=True,
            use_container_width=True,
        )


# ---------------------------------------------------------------------------
# Section: Map
# ---------------------------------------------------------------------------
elif "Map" in section:
    st.title("Business map - Merida")
    st.caption("All registered businesses on Gula Maps")

    biz_map = load_business_map()

    # Filters
    col_f1, col_f2 = st.columns(2)
    with col_f1:
        cats = ["All"] + sorted(biz_map["category"].unique().tolist())
        sel_cat = st.selectbox("Category", cats)
    with col_f2:
        hoods = ["All"] + sorted(biz_map["neighborhood"].dropna().unique().tolist())
        sel_hood = st.selectbox("Neighborhood", hoods)

    filtered = biz_map.copy()
    if sel_cat != "All":
        filtered = filtered[filtered["category"] == sel_cat]
    if sel_hood != "All":
        filtered = filtered[filtered["neighborhood"] == sel_hood]

    st.map(filtered, latitude="latitude", longitude="longitude", size="total_visits")

    st.caption(f"Showing {len(filtered)} of {len(biz_map)} businesses")

    with st.container(border=True):
        st.subheader("Business details")
        st.dataframe(
            filtered[["business_name", "category", "neighborhood",
                       "loyalty_type", "google_rating", "total_visits"]],
            column_config={
                "business_name": st.column_config.TextColumn("Business"),
                "category": st.column_config.TextColumn("Category"),
                "neighborhood": st.column_config.TextColumn("Neighborhood"),
                "loyalty_type": st.column_config.TextColumn("Loyalty"),
                "google_rating": st.column_config.NumberColumn(
                    "Rating", format="%.1f"),
                "total_visits": st.column_config.NumberColumn(
                    "Visits", format="%d"),
            },
            hide_index=True,
            use_container_width=True,
        )
