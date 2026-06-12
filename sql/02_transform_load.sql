-- 02_transform_load.sql
-- loads from staging into the star schema
-- run after 01_create_tables.sql and after raw data is in staging.superstore_raw

-- dim_date
-- generating a full date spine from 2014 to 2018 (superstore data runs 2014-2017,
-- keeping a year buffer so future data doesn't break anything)
INSERT INTO analytics.dim_date (
    date_key, full_date, year, quarter, month, month_name,
    week_of_year, day_of_week, day_name, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT     AS date_key,
    d::DATE                          AS full_date,
    EXTRACT(YEAR    FROM d)::INT     AS year,
    EXTRACT(QUARTER FROM d)::INT     AS quarter,
    EXTRACT(MONTH   FROM d)::INT     AS month,
    TO_CHAR(d, 'Month')              AS month_name,
    EXTRACT(WEEK    FROM d)::INT     AS week_of_year,
    EXTRACT(DOW     FROM d)::INT     AS day_of_week,
    TO_CHAR(d, 'Day')                AS day_name,
    EXTRACT(DOW     FROM d) IN (0,6) AS is_weekend
FROM GENERATE_SERIES('2014-01-01'::DATE, '2018-12-31'::DATE, '1 day'::INTERVAL) d
ON CONFLICT (date_key) DO NOTHING;


-- dim_customer
-- using DISTINCT because the same customer appears on multiple order rows
INSERT INTO analytics.dim_customer (
    customer_id, customer_name, segment, region, state, city
)
SELECT DISTINCT
    customer_id,
    customer_name,
    segment,
    region,
    state,
    city
FROM staging.superstore_raw
ON CONFLICT (customer_id) DO UPDATE SET
    customer_name = EXCLUDED.customer_name,
    segment       = EXCLUDED.segment,
    region        = EXCLUDED.region,
    state         = EXCLUDED.state,
    city          = EXCLUDED.city;


-- dim_product
INSERT INTO analytics.dim_product (
    product_id, product_name, category, sub_category
)
SELECT DISTINCT
    product_id,
    product_name,
    category,
    sub_category
FROM staging.superstore_raw
ON CONFLICT (product_id) DO UPDATE SET
    product_name = EXCLUDED.product_name,
    category     = EXCLUDED.category,
    sub_category = EXCLUDED.sub_category;


-- fact_orders
-- profit_margin computed here once rather than in every downstream viz
-- days_to_ship is just ship_date minus order_date
INSERT INTO analytics.fact_orders (
    order_id, row_id,
    order_date_key, ship_date_key,
    customer_key, product_key,
    ship_mode, quantity, sales, discount, profit,
    profit_margin, days_to_ship
)
SELECT
    r.order_id,
    r.row_id,
    TO_CHAR(r.order_date, 'YYYYMMDD')::INT  AS order_date_key,
    TO_CHAR(r.ship_date,  'YYYYMMDD')::INT  AS ship_date_key,
    c.customer_key,
    p.product_key,
    r.ship_mode,
    r.quantity,
    r.sales,
    r.discount,
    r.profit,
    CASE
        WHEN r.sales = 0 THEN NULL
        ELSE ROUND(r.profit / r.sales, 4)
    END                                     AS profit_margin,
    (r.ship_date - r.order_date)            AS days_to_ship
FROM staging.superstore_raw r
JOIN analytics.dim_customer c USING (customer_id)
JOIN analytics.dim_product  p USING (product_id);


-- quick validation after load
-- row counts should match
SELECT
    (SELECT COUNT(*) FROM staging.superstore_raw) AS staging_rows,
    (SELECT COUNT(*) FROM analytics.fact_orders)  AS fact_rows,
    (SELECT COUNT(*) FROM staging.superstore_raw) =
    (SELECT COUNT(*) FROM analytics.fact_orders)  AS counts_match;

-- check for nulls on key columns
SELECT
    COUNT(*) FILTER (WHERE order_date_key IS NULL) AS null_order_dates,
    COUNT(*) FILTER (WHERE customer_key   IS NULL) AS null_customers,
    COUNT(*) FILTER (WHERE product_key    IS NULL) AS null_products,
    COUNT(*) FILTER (WHERE sales < 0)              AS negative_sales
FROM analytics.fact_orders;

-- sales totals should reconcile between staging and fact
SELECT
    ROUND(SUM(s.sales), 2) AS staging_total,
    ROUND(SUM(f.sales), 2) AS fact_total,
    ROUND(SUM(s.sales) - SUM(f.sales), 2) AS variance
FROM staging.superstore_raw s
CROSS JOIN (SELECT SUM(sales) FROM analytics.fact_orders) f(sales);
