-- ============================================================================
-- 00_setup.sql
-- Creates the database, schemas, and sets the execution context.
-- ============================================================================

USE ROLE COCO_HOL_RL;
USE WAREHOUSE COCO_HOL_WH;

CREATE OR REPLACE DATABASE URBAN_BIKER_DB_33;

CREATE OR REPLACE SCHEMA URBAN_BIKER_DB_33.RAW;
CREATE OR REPLACE SCHEMA URBAN_BIKER_DB_33.SILVER;
CREATE OR REPLACE SCHEMA URBAN_BIKER_DB_33.GOLD;
