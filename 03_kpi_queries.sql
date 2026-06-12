-- 03_kpi_queries.sql
-- analytical views that Power BI connects to
-- each view maps to one dashboard page or one set of related visuals

-- monthly revenue trend
CREATE OR REPLACE VIEW analytics.v_monthly_revenue AS
SELECT
    d.year,
    d.month,
    d.month_name,
    ROUND(SUM(f.sales),  2)                  AS total_sales,
    ROUND(SUM(f.profit), 2)                  AS total_profit,
    ROUND(AVG(f.profit_margin) * 100, 2)     AS avg_margin_pct,
    COUNT(DISTINCT f.order_id)               AS order_count,
    SUM(f.quantity)                          AS units_sold
FROM analytics.fact_orders f
JOIN analytics.dim_date d ON f.order_date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- regional sales breakdown
CREATE OR REPLACE VIEW analytics.v_regional_sales AS
SELECT
    c.region,
    c.state,
    ROUND(SUM(f.sales),  2)                                          AS total_sales,
    ROUND(SUM(f.profit), 2)                                          AS total_profit,
    ROUND(SUM(f.profit) / NULLIF(SUM(f.sales), 0) * 100, 2)         AS margin_pct,
    COUNT(DISTINCT c.customer_key)                                   AS unique_customers,
    COUNT(DISTINCT f.order_id)                                       AS order_count
FROM analytics.fact_orders f
JOIN analytics.dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.region, c.state
ORDER BY total_sales DESC;


-- product performance
CREATE OR REPLACE VIEW analytics.v_product_performance AS
SELECT
    p.category,
    p.sub_category,
    p.product_name,
    ROUND(SUM(f.sales),  2)                                          AS total_sales,
    ROUND(SUM(f.profit), 2)                                          AS total_profit,
    ROUND(SUM(f.profit) / NULLIF(SUM(f.sales), 0) * 100, 2)         AS margin_pct,
    SUM(f.quantity)                                                  AS units_sold,
    COUNT(DISTINCT f.order_id)                                       AS order_count,
    ROUND(AVG(f.discount) * 100, 2)                                  AS avg_discount_pct
FROM analytics.fact_orders f
JOIN analytics.dim_product p ON f.product_key = p.product_key
GROUP BY p.category, p.sub_category, p.product_name
ORDER BY total_sales DESC;


-- customer segment analysis
CREATE OR REPLACE VIEW analytics.v_segment_analysis AS
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_key)                                   AS customer_count,
    ROUND(SUM(f.sales),  2)                                          AS total_sales,
    ROUND(SUM(f.profit), 2)                                          AS total_profit,
    ROUND(SUM(f.sales) / COUNT(DISTINCT c.customer_key), 2)          AS avg_sales_per_customer,
    ROUND(AVG(f.discount) * 100, 2)                                  AS avg_discount_pct,
    COUNT(DISTINCT f.order_id)                                       AS order_count,
    ROUND(
        COUNT(DISTINCT f.order_id)::NUMERIC / COUNT(DISTINCT c.customer_key), 2
    )                                                                AS avg_orders_per_customer
FROM analytics.fact_orders f
JOIN analytics.dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.segment
ORDER BY total_sales DESC;


-- shipping performance by mode
CREATE OR REPLACE VIEW analytics.v_shipping_performance AS
SELECT
    f.ship_mode,
    COUNT(*)                                                         AS total_orders,
    ROUND(AVG(f.days_to_ship), 2)                                    AS avg_days_to_ship,
    MIN(f.days_to_ship)                                              AS min_days,
    MAX(f.days_to_ship)                                              AS max_days,
    COUNT(*) FILTER (WHERE f.days_to_ship <= 2)                      AS shipped_within_2_days,
    ROUND(
        COUNT(*) FILTER (WHERE f.days_to_ship <= 2)::NUMERIC
        / COUNT(*) * 100, 2
    )                                                                AS pct_within_2_days,
    ROUND(SUM(f.sales), 2)                                           AS total_sales
FROM analytics.fact_orders f
WHERE f.days_to_ship IS NOT NULL
GROUP BY f.ship_mode
ORDER BY total_orders DESC;


-- year over year comparison
CREATE OR REPLACE VIEW analytics.v_yoy_comparison AS
SELECT
    d.year,
    d.month,
    ROUND(SUM(f.sales), 2)   AS sales,
    ROUND(SUM(f.profit), 2)  AS profit,
    LAG(ROUND(SUM(f.sales), 2))
        OVER (PARTITION BY d.month ORDER BY d.year) AS prev_year_sales,
    LAG(ROUND(SUM(f.profit), 2))
        OVER (PARTITION BY d.month ORDER BY d.year) AS prev_year_profit,
    ROUND(
        (SUM(f.sales) - LAG(SUM(f.sales)) OVER (PARTITION BY d.month ORDER BY d.year))
        / NULLIF(LAG(SUM(f.sales)) OVER (PARTITION BY d.month ORDER BY d.year), 0) * 100, 2
    ) AS yoy_sales_growth_pct
FROM analytics.fact_orders f
JOIN analytics.dim_date d ON f.order_date_key = d.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;


-- discount impact
-- standardized bucketing so all reports use the same definition
-- NULL check included as a safeguard in case discount data quality changes
-- "No Discount" only counts rows where discount is explicitly 0
CREATE OR REPLACE VIEW analytics.v_discount_impact AS
SELECT
    CASE
        WHEN f.discount IS NULL THEN 'Unknown'
        WHEN f.discount = 0     THEN 'No Discount'
        WHEN f.discount < 0.10  THEN '0-10%'
        WHEN f.discount < 0.20  THEN '10-20%'
        WHEN f.discount < 0.30  THEN '20-30%'
        ELSE '30%+'
    END                                         AS discount_bucket,
    COUNT(*)                                    AS order_lines,
    ROUND(SUM(f.sales), 2)                      AS total_sales,
    ROUND(AVG(f.profit_margin) * 100, 2)        AS avg_margin_pct,
    ROUND(AVG(f.discount) * 100, 2)             AS avg_actual_discount_pct
FROM analytics.fact_orders f
GROUP BY discount_bucket
ORDER BY avg_actual_discount_pct;
