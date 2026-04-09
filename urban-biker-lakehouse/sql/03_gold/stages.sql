-- ============================================================================
-- 03_gold/stages.sql
-- Gold layer: internal stage for the Streamlit app files.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE DATABASE URBAN_BIKER_DB_33;
USE SCHEMA GOLD;

CREATE OR REPLACE STAGE STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT   = 'Stage for BiciMAD Streamlit app files';
