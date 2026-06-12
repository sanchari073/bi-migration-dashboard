# DAX measures — Superstore Power BI migration

These are the Power BI measures that replace the Tableau calculated fields.
Where there's a direct Tableau equivalent, I've noted what changed and why.

---

## Base measures

```dax
Total Sales =
    SUM(fact_orders[sales])

Total Profit =
    SUM(fact_orders[profit])

-- using DIVIDE instead of division so it returns 0 on blank rather than erroring
Profit Margin % =
    DIVIDE(
        SUM(fact_orders[profit]),
        SUM(fact_orders[sales]),
        0
    ) * 100

-- distinct count of order_id, not row count -- one order can have multiple line items
Order Count =
    DISTINCTCOUNT(fact_orders[order_id])

Units Sold =
    SUM(fact_orders[quantity])

Avg Order Value =
    DIVIDE([Total Sales], [Order Count], 0)
```

---

## Time intelligence

These replace Tableau's LOOKUP and WINDOW_SUM table calculations.
The big advantage is these work correctly across any filter context
without needing to specify partition dimensions manually.

```dax
Sales PY =
    CALCULATE(
        [Total Sales],
        SAMEPERIODLASTYEAR(dim_date[full_date])
    )

YoY Sales Growth % =
    DIVIDE(
        [Total Sales] - [Sales PY],
        [Sales PY],
        BLANK()
    ) * 100

Sales MTD =
    CALCULATE(
        [Total Sales],
        DATESMTD(dim_date[full_date])
    )

Sales QTD =
    CALCULATE(
        [Total Sales],
        DATESQTD(dim_date[full_date])
    )

Sales YTD =
    CALCULATE(
        [Total Sales],
        DATESYTD(dim_date[full_date])
    )

-- 3 month rolling average -- useful for smoothing out weekly noise in trend lines
Sales 3M Rolling Avg =
    AVERAGEX(
        DATESINPERIOD(
            dim_date[full_date],
            LASTDATE(dim_date[full_date]),
            -3,
            MONTH
        ),
        CALCULATE([Total Sales])
    )
```

---

## Segment and category

```dax
-- keeps segment filter when other slicers are active
Segment Sales =
    CALCULATE(
        [Total Sales],
        ALLEXCEPT(dim_customer, dim_customer[segment])
    )

-- for bar chart labels showing each category's share of total
Sales % of Total =
    DIVIDE(
        [Total Sales],
        CALCULATE([Total Sales], ALL(fact_orders)),
        0
    ) * 100

-- for conditional formatting -- highlights loss-making products red
Is Loss Making =
    IF([Total Profit] < 0, 1, 0)

Category Sales Rank =
    RANKX(
        ALL(dim_product[category]),
        [Total Sales],
        ,
        DESC,
        DENSE
    )
```

---

## Discount analysis

```dax
Avg Discount % =
    AVERAGE(fact_orders[discount]) * 100

Sales With Discount =
    CALCULATE(
        [Total Sales],
        fact_orders[discount] > 0
    )

Sales Without Discount =
    CALCULATE(
        [Total Sales],
        fact_orders[discount] = 0
    )

Margin With Discount =
    CALCULATE(
        [Profit Margin %],
        fact_orders[discount] > 0
    )

Margin Without Discount =
    CALCULATE(
        [Profit Margin %],
        fact_orders[discount] = 0
    )

-- how much does discounting hurt margin? negative number = discounts are costing margin
Discount Margin Impact =
    [Margin With Discount] - [Margin Without Discount]
```

---

## Shipping

```dax
Avg Days to Ship =
    AVERAGE(fact_orders[days_to_ship])

On Time Ship Rate =
    DIVIDE(
        COUNTROWS(FILTER(fact_orders, fact_orders[days_to_ship] <= 2)),
        [Order Count],
        0
    ) * 100
```

---

## Tableau to Power BI translation notes

| Tableau calc | Power BI equivalent | what changed |
|---|---|---|
| `WINDOW_SUM(SUM([Sales]))` | `CALCULATE([Total Sales], ALL(...))` | more explicit filter scope |
| `DATETRUNC('month', [Order Date])` | `dim_date[month]` | comes from date dim, no inline calc needed |
| `LOOKUP(SUM([Sales]), -1)` | `Sales PY` with `SAMEPERIODLASTYEAR` | proper time intelligence |
| `RUNNING_AVG(AVG([Discount]))` | `Sales 3M Rolling Avg` | `DATESINPERIOD` replaces the window |
| NULL discount handling | explicit `discount = 0` filter | handled in SQL view, not DAX |

The last row in the translation table is worth noting — the NULL discount handling is
done in SQL in `v_discount_impact` rather than in DAX. This keeps the bucketing logic
in one place and means the Power BI measures don't need to replicate it.
