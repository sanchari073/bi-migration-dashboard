-- 01_create_tables.sql
-- sets up the staging table (raw ingest) and the star schema
-- run this first before anything else
-- postgres syntax, should work on snowflake too with minor tweaks

-- staging schema -- just dumps the raw CSV as-is
CREATE SCHEMA IF NOT EXISTS staging;

CREATE TABLE IF NOT EXISTS staging.superstore_raw (
    row_id          INT,
    order_id        VARCHAR(20),
    order_date      DATE,
    ship_date       DATE,
    ship_mode       VARCHAR(30),
    customer_id     VARCHAR(20),
    customer_name   VARCHAR(100),
    segment         VARCHAR(20),
    country         VARCHAR(50),
    city            VARCHAR(100),
    state           VARCHAR(50),
    postal_code     VARCHAR(10),
    region          VARCHAR(20),
    product_id      VARCHAR(20),
    category        VARCHAR(50),
    sub_category    VARCHAR(50),
    product_name    VARCHAR(200),
    sales           DECIMAL(12, 4),
    quantity        INT,
    discount        DECIMAL(5, 4),
    profit          DECIMAL(12, 4)
);

-- analytics schema -- cleaned and modeled, this is what Power BI connects to
CREATE SCHEMA IF NOT EXISTS analytics;

-- date dimension
-- using an integer key (YYYYMMDD) instead of a date type -- faster joins
CREATE TABLE IF NOT EXISTS analytics.dim_date (
    date_key        INT PRIMARY KEY,
    full_date       DATE,
    year            INT,
    quarter         INT,
    month           INT,
    month_name      VARCHAR(10),
    week_of_year    INT,
    day_of_week     INT,
    day_name        VARCHAR(10),
    is_weekend      BOOLEAN
);

-- customer dimension
CREATE TABLE IF NOT EXISTS analytics.dim_customer (
    customer_key    SERIAL PRIMARY KEY,
    customer_id     VARCHAR(20) UNIQUE,
    customer_name   VARCHAR(100),
    segment         VARCHAR(20),
    region          VARCHAR(20),
    state           VARCHAR(50),
    city            VARCHAR(100)
);

-- product dimension
CREATE TABLE IF NOT EXISTS analytics.dim_product (
    product_key     SERIAL PRIMARY KEY,
    product_id      VARCHAR(20) UNIQUE,
    product_name    VARCHAR(200),
    category        VARCHAR(50),
    sub_category    VARCHAR(50)
);

-- fact table
-- profit_margin and days_to_ship are computed on load so they're consistent
-- across every report rather than each viz calculating them independently
CREATE TABLE IF NOT EXISTS analytics.fact_orders (
    order_line_key  SERIAL PRIMARY KEY,
    order_id        VARCHAR(20),
    row_id          INT,
    order_date_key  INT REFERENCES analytics.dim_date(date_key),
    ship_date_key   INT REFERENCES analytics.dim_date(date_key),
    customer_key    INT REFERENCES analytics.dim_customer(customer_key),
    product_key     INT REFERENCES analytics.dim_product(product_key),
    ship_mode       VARCHAR(30),
    quantity        INT,
    sales           DECIMAL(12, 4),
    discount        DECIMAL(5, 4),
    profit          DECIMAL(12, 4),
    profit_margin   DECIMAL(8, 4),
    days_to_ship    INT
);
