"""
BiciMAD Urban Biker Dashboard
Streamlit app that visualizes Madrid's bike-sharing network
from the Gold layer of the Urban Biker Lakehouse.
"""

import streamlit as st
import pandas as pd
import pydeck as pdk
from snowflake.snowpark.context import get_active_session

# ---------------------------------------------------------------------------
# Snowpark session (provided automatically by Streamlit in Snowflake)
# ---------------------------------------------------------------------------
session = get_active_session()

# ---------------------------------------------------------------------------
# Data loading (cached)
# ---------------------------------------------------------------------------
@st.cache_data(ttl=300)
def load_network_summary():
    return session.sql(
        "SELECT * FROM DT_NETWORK_SUMMARY ORDER BY EXTRACTION_AT DESC"
    ).to_pandas()


@st.cache_data(ttl=300)
def load_station_metrics():
    return session.sql(
        """
        SELECT *
        FROM DT_STATION_HOURLY_METRICS
        ORDER BY HOUR_BUCKET DESC, STATION_NAME
        """
    ).to_pandas()


# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="BiciMAD Dashboard",
    page_icon="\U0001F6B2",
    layout="wide",
)

st.title("BiciMAD - Madrid Bike-Sharing Dashboard")
st.caption("Gold-layer data from the Urban Biker Lakehouse")

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
try:
    df_network = load_network_summary()
    df_stations = load_station_metrics()
except Exception as e:
    st.error(f"Could not connect to Snowflake: {e}")
    st.stop()

# ---------------------------------------------------------------------------
# KPI cards
# ---------------------------------------------------------------------------
latest = df_network.iloc[0]

st.subheader("Network Overview")
k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Total Stations", int(latest["TOTAL_STATIONS"]))
k2.metric("Online Stations", int(latest["ONLINE_STATIONS"]))
k3.metric("Free Bikes", f"{int(latest['TOTAL_FREE_BIKES']):,}")
k4.metric("Empty Slots", f"{int(latest['TOTAL_EMPTY_SLOTS']):,}")
k5.metric("Occupancy", f"{latest['NETWORK_OCCUPANCY_PCT']:.1f}%")

st.divider()

# ---------------------------------------------------------------------------
# Map: stations colored by occupancy (green / yellow / red)
# ---------------------------------------------------------------------------
st.subheader("Station Map - Availability")

# Use the latest hour bucket for the map
latest_bucket = df_stations["HOUR_BUCKET"].max()
df_map = df_stations[df_stations["HOUR_BUCKET"] == latest_bucket].copy()


def availability_color(occ_pct):
    """Return [R, G, B, A] based on occupancy percentage."""
    if occ_pct >= 60:
        return [34, 139, 34, 180]   # green  - high availability
    elif occ_pct >= 30:
        return [255, 165, 0, 180]   # orange - moderate
    else:
        return [220, 20, 60, 180]   # red    - low availability


df_map["color"] = df_map["AVG_OCCUPANCY_PCT"].apply(availability_color)
df_map["radius"] = df_map["AVG_TOTAL_SLOTS"].apply(lambda s: max(float(s) * 3, 30))

map_layer = pdk.Layer(
    "ScatterplotLayer",
    data=df_map,
    get_position=["LONGITUDE", "LATITUDE"],
    get_radius="radius",
    get_fill_color="color",
    pickable=True,
)

tooltip = {
    "html": (
        "<b>{STATION_NAME}</b><br/>"
        "Bikes: {AVG_FREE_BIKES}<br/>"
        "Empty slots: {AVG_EMPTY_SLOTS}<br/>"
        "Occupancy: {AVG_OCCUPANCY_PCT}%"
    ),
    "style": {"backgroundColor": "#333", "color": "white"},
}

view_state = pdk.ViewState(
    latitude=40.42,
    longitude=-3.70,
    zoom=12,
    pitch=0,
)

st.pydeck_chart(pdk.Deck(layers=[map_layer], initial_view_state=view_state, tooltip=tooltip))

col_legend1, col_legend2, col_legend3 = st.columns(3)
col_legend1.markdown(":green_circle: **High availability** (>=60%)")
col_legend2.markdown(":orange_circle: **Moderate** (30-60%)")
col_legend3.markdown(":red_circle: **Low availability** (<30%)")

st.divider()

# ---------------------------------------------------------------------------
# Bar chart: Top 10 stations by occupancy
# ---------------------------------------------------------------------------
st.subheader("Top 10 Stations by Occupancy")

df_top10 = (
    df_map.nlargest(10, "AVG_OCCUPANCY_PCT")[["STATION_NAME", "AVG_OCCUPANCY_PCT"]]
    .set_index("STATION_NAME")
)
st.bar_chart(df_top10)

st.divider()

# ---------------------------------------------------------------------------
# Bottom 10: stations with lowest availability
# ---------------------------------------------------------------------------
st.subheader("Bottom 10 Stations - Lowest Availability")

df_bottom10 = (
    df_map.nsmallest(10, "AVG_OCCUPANCY_PCT")[["STATION_NAME", "AVG_OCCUPANCY_PCT"]]
    .set_index("STATION_NAME")
)
st.bar_chart(df_bottom10)

st.divider()

# ---------------------------------------------------------------------------
# Time series (only meaningful with multiple extractions)
# ---------------------------------------------------------------------------
st.subheader("Network Occupancy Over Time")

if len(df_network) > 1:
    df_ts = df_network[["EXTRACTION_AT", "NETWORK_OCCUPANCY_PCT"]].copy()
    df_ts = df_ts.set_index("EXTRACTION_AT").sort_index()
    st.line_chart(df_ts)
else:
    st.info(
        "Only one extraction snapshot available. "
        "Run extract_data.py multiple times to see trends over time."
    )

# ---------------------------------------------------------------------------
# Raw data expander
# ---------------------------------------------------------------------------
with st.expander("View raw station data"):
    st.dataframe(
        df_map[
            [
                "STATION_NAME",
                "ADDRESS",
                "AVG_FREE_BIKES",
                "AVG_EMPTY_SLOTS",
                "AVG_TOTAL_SLOTS",
                "AVG_OCCUPANCY_PCT",
            ]
        ].sort_values("STATION_NAME"),
        use_container_width=True,
    )

st.caption("Data sourced from CityBikes API (BiciMAD) via the Urban Biker Lakehouse")
