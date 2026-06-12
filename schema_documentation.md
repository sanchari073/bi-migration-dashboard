# Data model — Superstore BI

## Why star schema instead of flat table

The original Tableau dashboards all pointed at the same flat CSV. That was fine for
three workbooks but meant any schema change had to be replicated manually across all
of them, KPI definitions drifted over time, and there was no date table so time
intelligence calculations broke at quarter boundaries.

Moving to a star schema solves all of this at the source:

- `profit_margin` and `days_to_ship` computed once at load time, same number everywhere
- Date dimension means Power BI time intelligence (MTD, YTD, SAMEPERIODLASTYEAR) just works
- Surrogate keys decouple the fact table from natural keys
- Single source of truth for every KPI

---

## Tables

**fact_orders** — one row per order line item

| column | type | notes |
|---|---|---|
| order_line_key | int | PK, auto-increment |
| order_id | varchar | natural key from source |
| order_date_key | int | FK → dim_date, YYYYMMDD format |
| ship_date_key | int | FK → dim_date (inactive relationship) |
| customer_key | int | FK → dim_customer |
| product_key | int | FK → dim_product |
| ship_mode | varchar | Standard Class, Second Class, etc |
| quantity | int | units ordered |
| sales | decimal | revenue |
| discount | decimal | 0.0 to 1.0 range |
| profit | decimal | can be negative |
| profit_margin | decimal | profit/sales, computed on load |
| days_to_ship | int | ship_date minus order_date, computed on load |

**dim_date** — one row per calendar day, 2014-2018

| column | type | notes |
|---|---|---|
| date_key | int | PK, YYYYMMDD integer |
| full_date | date | actual date value |
| year | int | |
| quarter | int | 1-4 |
| month | int | 1-12 |
| month_name | varchar | January, February, etc |
| week_of_year | int | ISO week number |
| day_of_week | int | 0=Sunday, 6=Saturday |
| day_name | varchar | Monday, Tuesday, etc |
| is_weekend | boolean | |

**dim_customer** — one row per unique customer

| column | type | notes |
|---|---|---|
| customer_key | int | PK, surrogate key |
| customer_id | varchar | natural key from source, unique |
| customer_name | varchar | |
| segment | varchar | Consumer, Corporate, Home Office |
| region | varchar | East, West, Central, South |
| state | varchar | |
| city | varchar | |

**dim_product** — one row per unique product

| column | type | notes |
|---|---|---|
| product_key | int | PK, surrogate key |
| product_id | varchar | natural key from source, unique |
| product_name | varchar | |
| category | varchar | Furniture, Office Supplies, Technology |
| sub_category | varchar | Chairs, Binders, Phones, etc |

---

## Relationships in Power BI

| from | to | join column | cardinality | active |
|---|---|---|---|---|
| fact_orders[order_date_key] | dim_date[date_key] | date key | Many:1 | yes |
| fact_orders[ship_date_key] | dim_date[date_key] | date key | Many:1 | no |
| fact_orders[customer_key] | dim_customer[customer_key] | surrogate key | Many:1 | yes |
| fact_orders[product_key] | dim_product[product_key] | surrogate key | Many:1 | yes |

The ship_date relationship to dim_date is set to inactive because Power BI
doesn't allow two active relationships between the same tables. To use it
in shipping analysis measures, activate it with USERELATIONSHIP():

```dax
Sales by Ship Date =
    CALCULATE(
        [Total Sales],
        USERELATIONSHIP(fact_orders[ship_date_key], dim_date[date_key])
    )
```

---

## Power Query load steps

**fact_orders:**
- order_line_key, customer_key, product_key → Int64
- order_date_key, ship_date_key → Int64
- sales, profit, profit_margin, discount → Decimal
- remove rows where sales is null

**dim_date:**
- mark as Date Table in Power BI (this is what enables MTD/YTD/etc)
- set full_date as the marked date column

**dim_customer and dim_product:**
- no transforms needed, types come through correctly from SQL
