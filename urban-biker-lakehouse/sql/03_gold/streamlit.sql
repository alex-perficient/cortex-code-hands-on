-- ============================================================================
-- 03_gold/streamlit.sql
-- Gold layer: Streamlit in Snowflake (SiS) application.
-- NOTE: Before running this, upload streamlit_app.py and environment.yml
--       to @URBAN_BIKER_DB_33.GOLD.STREAMLIT_STAGE using PUT commands.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA GOLD;

CREATE OR REPLACE STREAMLIT BICIMAD_DASHBOARD
    ROOT_LOCATION   = '@URBAN_BIKER_DB_33.GOLD.STREAMLIT_STAGE'
    MAIN_FILE       = 'streamlit_app.py'
    QUERY_WAREHOUSE = 'COCO_HOL_WH'
    COMMENT         = 'Madrid bike-sharing network dashboard from the Urban Biker Lakehouse'
    TITLE           = 'BiciMAD Dashboard';
