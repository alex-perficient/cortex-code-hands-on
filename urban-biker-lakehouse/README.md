# Urban-Biker Lakehouse

Medallion-architecture data lakehouse on Snowflake for analyzing **BiciMAD** (Madrid's public bike-sharing network). Ingests real-time station data from the CityBikes API, transforms it through Bronze/Silver/Gold layers, and serves a Streamlit dashboard.

## Architecture

```
CityBikes API (bicimad)
        |
        v
  extract_data.py        --> Parquet file (local)
        |
        v
      AWS S3              --> s3://citybikes-stg/citybikes_parquet/
        |
        v
  ┌─── TASK_HOURLY_INGESTION (CRON 0 * * * * UTC) ───┐
  │                                                   │
  │  COPY INTO (S3 Stage) --> RAW.BIKE_STATIONS_RAW   │  (Bronze)
  │        |                                          │
  │        v                                          │
  │  SP_CLEAN_BIKE_STATIONS --> SILVER.BIKE_STATIONS  │  (Silver)
  │   (MERGE procedure)                               │
  └───────────────────────────────────────────────────┘
        |
        v
  Dynamic Tables (1h lag) --> GOLD.DT_NETWORK_SUMMARY          (Gold)
                              GOLD.DT_STATION_HOURLY_METRICS
        |
        v
  Streamlit in Snowflake  --> GOLD.BICIMAD_DASHBOARD
```

## Project Structure

```
urban-biker-lakehouse/
├── app/
│   ├── streamlit_app.py            # Streamlit dashboard (runs in Snowflake SiS)
│   └── environment.yml             # Conda env for Streamlit in Snowflake
├── scripts/
│   ├── extract_data.py             # CityBikes API -> Parquet -> S3
│   ├── load_data.py                # S3 stage -> RAW table via COPY INTO
│   └── generate_keypair.py         # RSA key pair for Snowflake auth
└── sql/
    ├── run_all.sql                 # Step-by-step orchestration guide
    ├── 00_setup.sql                # Database + schema creation
    ├── 01_raw/
    │   ├── tables.sql              # BIKE_STATIONS_RAW table
    │   └── stages.sql              # Internal + S3 external stages, COPY INTO
    ├── 02_silver/
    │   ├── tables.sql              # BIKE_STATIONS table (typed columns)
    │   └── procedures.sql          # SP_CLEAN_BIKE_STATIONS (MERGE)
    ├── 03_gold/
    │   ├── dynamic_tables.sql      # DT_NETWORK_SUMMARY, DT_STATION_HOURLY_METRICS
    │   ├── stages.sql              # STREAMLIT_STAGE (for app files)
    │   └── streamlit.sql           # BICIMAD_DASHBOARD definition
    └── 04_automation/
        └── tasks.sql               # TASK_HOURLY_INGESTION (scheduled COPY + SP)
```

## Snowflake Objects

| Schema | Object | Type |
|--------|--------|------|
| RAW | BIKE_STATIONS_RAW | Table |
| RAW | CITYBIKES_STG | Internal Stage |
| RAW | BIKE_STAGE_S3 | External Stage (S3) |
| SILVER | BIKE_STATIONS | Table |
| SILVER | SP_CLEAN_BIKE_STATIONS | Stored Procedure |
| GOLD | DT_NETWORK_SUMMARY | Dynamic Table (1h lag) |
| GOLD | DT_STATION_HOURLY_METRICS | Dynamic Table (1h lag) |
| GOLD | STREAMLIT_STAGE | Internal Stage |
| GOLD | BICIMAD_DASHBOARD | Streamlit App |
| RAW | TASK_HOURLY_INGESTION | Task (hourly CRON) |

## Data Layers

**Bronze (RAW)** - Raw VARIANT data loaded from Parquet files via S3 external stage. Each row contains the full JSON record per station plus file metadata and ingestion timestamp.

**Silver (SILVER)** - Cleaned and typed station data. The `SP_CLEAN_BIKE_STATIONS` stored procedure performs a MERGE that extracts fields from the VARIANT column, filters invalid records (null coordinates, zero slots), and trims addresses.

**Gold (GOLD)** - Two dynamic tables auto-refresh every hour:
- `DT_NETWORK_SUMMARY`: Network-level aggregates per snapshot (total/online stations, free bikes, occupancy %).
- `DT_STATION_HOURLY_METRICS`: Station-level hourly averages (free bikes, empty slots, occupancy %) with coordinates for mapping.

## Dashboard

The Streamlit app (`GOLD.BICIMAD_DASHBOARD`) runs natively in Snowflake and provides:
- KPI cards (total stations, online stations, free bikes, empty slots, occupancy %)
- PyDeck map of stations colored by occupancy (green/orange/red)
- Top 10 / Bottom 10 stations by occupancy (bar charts)
- Network occupancy time series (requires multiple extraction snapshots)
- Raw data explorer

## Completed Steps

- [x] **Fase 0 - Initial Setup**: Repository and dev environment configured.
- [x] **Fase 1 - Extraction & Landing (Bronze)**: API extraction script (`extract_data.py`), S3 upload, Snowflake external stage, raw table, first data load via `COPY INTO`.
- [x] **Fase 2 - Transformation (Silver/Gold)**: `SP_CLEAN_BIKE_STATIONS` stored procedure (MERGE from RAW to SILVER), Dynamic Tables for network and station-level hourly aggregates.
- [x] **Fase 3 - Visualization & Deployment**: Streamlit dashboard developed and deployed to Snowflake (SiS) with PyDeck maps, KPIs, and charts.

## Future Steps - ETL Automation

The Snowflake-side pipeline is now automated: `TASK_HOURLY_INGESTION` runs every hour, executing `COPY INTO` from S3 and calling `SP_CLEAN_BIKE_STATIONS`. Gold Dynamic Tables auto-refresh from Silver. The only manual step remaining is running `extract_data.py` to push new snapshots to S3.

Completed:

- [x] **Snowflake Task for hourly ingestion + Silver refresh**: `RAW.TASK_HOURLY_INGESTION` runs `COPY INTO` from S3 and calls `SP_CLEAN_BIKE_STATIONS` every hour on a CRON schedule.

Remaining:

- [ ] **Scheduled extraction with external orchestration**: Automate `extract_data.py` on a schedule (e.g., cron job, AWS Lambda, or GitHub Actions) to continuously fetch snapshots from the CityBikes API and push to S3.
- [ ] **Alerts and monitoring**: Add Snowflake Alerts to detect pipeline failures (e.g., no new data in X hours, SP execution errors) and notify via email or webhook.
- [ ] **Git Integration for Streamlit deployment**: Connect the repository to Snowflake Git Integration so app updates deploy automatically on push.
