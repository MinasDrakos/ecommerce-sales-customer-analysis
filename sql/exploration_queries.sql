-- =====================================================================
-- Aegean Brew Co. — SQL exploration (SQLite)
-- 12 exploratory questions, from basic aggregation to CTEs and window functions.
-- Each query is followed by its result. Run against data/aegean_brew.db.
-- =====================================================================

-- Reusable trick for the mixed timestamp formats:
-- ISO rows look like '2024-03-05 14:22:00'; the others like '05/03/2024 14:22' (DD/MM/YYYY).
--   CASE WHEN order_ts LIKE '__/__/____%'
--        THEN substr(order_ts,7,4)||'-'||substr(order_ts,4,2)||'-'||substr(order_ts,1,2)
--        ELSE substr(order_ts,1,10) END

-- Q1 Row counts per table, and is customer_id unique?
SELECT 'customers' AS tbl, COUNT(*) FROM customers UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items;
SELECT COUNT(*) AS rows, COUNT(DISTINCT customer_id) AS distinct_ids FROM customers;
-- RESULT:
--   tbl | COUNT(*)
--   customers | 2525
--   products | 20
--   orders | 9974
--   order_items | 20069
--   rows | distinct_ids
--   2525 | 2500

-- Q2 Products and average list price per category
SELECT category, COUNT(*) AS n_products, ROUND(AVG(unit_price), 2) AS avg_price
FROM products GROUP BY category ORDER BY avg_price DESC;
-- RESULT:
--   category | n_products | avg_price
--   Equipment | 6 | 39.83
--   Coffee Beans | 6 | 16.75
--   Accessories | 4 | 15.13
--   Tea | 4 | 10.75

-- Q3 Order status breakdown
SELECT status, COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders GROUP BY status ORDER BY n DESC;
-- RESULT:
--   status | n | pct
--   Delivered | 8259 | 82.8
--   Returned | 890 | 8.9
--   Cancelled | 825 | 8.3

-- Q4 Top 5 products by Delivered revenue (raw data: duplicates/test orders not yet removed)
SELECT p.product_name, p.category,
       SUM(oi.quantity) AS units,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue
FROM order_items oi
JOIN orders o   ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status = 'Delivered'
GROUP BY p.product_id ORDER BY revenue DESC LIMIT 5;
-- RESULT:
--   product_name | category | units | revenue
--   Electric Gooseneck Kettle | Equipment | 701 | 50836.5
--   House Espresso Blend 500g | Coffee Beans | 2601 | 43219.85
--   Brazil Santos 1kg | Coffee Beans | 1302 | 39566.08
--   Manual Grinder | Equipment | 866 | 38754.1
--   Moka Pot 6-cup | Equipment | 1163 | 30731.3

-- Q5 Monthly Delivered revenue (handling mixed timestamp formats)
WITH o AS (
  SELECT order_id, status,
         CASE WHEN order_ts LIKE '__/__/____%'
              THEN substr(order_ts,7,4)||'-'||substr(order_ts,4,2)
              ELSE substr(order_ts,1,7) END AS ym
  FROM orders)
SELECT o.ym, ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue
FROM o JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'Delivered'
GROUP BY o.ym ORDER BY o.ym;
-- RESULT:
--   ym | revenue
--   2024-01 | 1929.95
--   2024-02 | 3436.38
--   2024-03 | 5050.25
--   2024-04 | 4243.13
--   2024-05 | 5327.82
--   2024-06 | 8495.45
--   …
--   2025-10 | 28045.73
--   2025-11 | 40770.07
--   2025-12 | 47620.11

-- Q6 Orders with no matching customer (found: internal test orders)
SELECT o.customer_id, COUNT(*) AS n_orders, GROUP_CONCAT(o.order_id) AS orders
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
GROUP BY o.customer_id;
SELECT oi.* FROM order_items oi WHERE oi.order_id IN
  (SELECT order_id FROM orders WHERE customer_id NOT IN (SELECT customer_id FROM customers));
-- RESULT:
--   customer_id | n_orders | orders
--   0 | 3 | 99001,99002,99003
--   item_id | order_id | product_id | quantity | unit_price | discount
--   900001 | 99001 | 115 | 50 | 79.0 | 0.0
--   900002 | 99002 | 115 | 50 | 79.0 | 0.0
--   900003 | 99003 | 112 | 40 | 49.0 | 0.0

-- Q7 Buyers and average lifetime revenue by acquisition channel (DISTINCT neutralises duplicate customer rows)
WITH cust AS (SELECT DISTINCT customer_id, COALESCE(acquisition_channel, 'Unknown') AS channel FROM customers),
rev AS (
  SELECT o.customer_id, SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
  FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.status = 'Delivered' GROUP BY o.customer_id)
SELECT c.channel, COUNT(*) AS buyers, ROUND(AVG(r.revenue), 2) AS avg_lifetime_revenue
FROM cust c JOIN rev r ON r.customer_id = c.customer_id
GROUP BY c.channel ORDER BY avg_lifetime_revenue DESC;
-- RESULT:
--   channel | buyers | avg_lifetime_revenue
--   Referral | 283 | 300.48
--   Email | 337 | 244.22
--   Unknown | 56 | 208.63
--   Organic Search | 637 | 195.35
--   Paid Search | 357 | 187.34
--   Paid Social | 512 | 139.06

-- Q8 Share of buyers who placed a second order
WITH d AS (
  SELECT customer_id,
         MIN(CASE WHEN order_ts LIKE '__/__/____%'
                  THEN substr(order_ts,7,4)||'-'||substr(order_ts,4,2)||'-'||substr(order_ts,1,2)
                  ELSE substr(order_ts,1,10) END) AS first_order,
         COUNT(*) AS n_delivered
  FROM orders
  WHERE status = 'Delivered' AND customer_id IN (SELECT customer_id FROM customers)
  GROUP BY customer_id)
SELECT COUNT(*) AS buyers,
       SUM(n_delivered >= 2) AS repeat_buyers,
       ROUND(100.0 * SUM(n_delivered >= 2) / COUNT(*), 1) AS repeat_pct
FROM d;
-- RESULT:
--   buyers | repeat_buyers | repeat_pct
--   2182 | 1335 | 61.2

-- Q9 Best-selling product per country (after standardising country names)
WITH cust AS (
  SELECT DISTINCT customer_id,
         CASE UPPER(TRIM(country)) WHEN 'GR' THEN 'Greece' WHEN 'DEUTSCHLAND' THEN 'Germany'
              ELSE UPPER(substr(TRIM(country),1,1)) || LOWER(substr(TRIM(country),2)) END AS country
  FROM customers),
pr AS (
  SELECT c.country, p.product_name,
         SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
  FROM orders o
  JOIN cust c ON c.customer_id = o.customer_id
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN products p ON p.product_id = oi.product_id
  WHERE o.status = 'Delivered'
  GROUP BY c.country, p.product_name),
ranked AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY country ORDER BY revenue DESC) AS rn FROM pr)
SELECT country, product_name, ROUND(revenue, 2) AS revenue FROM ranked WHERE rn = 1 ORDER BY revenue DESC;
-- RESULT:
--   country | product_name | revenue
--   Greece | Electric Gooseneck Kettle | 20946.85
--   Germany | House Espresso Blend 500g | 6195.88
--   Italy | Electric Gooseneck Kettle | 4795.3
--   France | House Espresso Blend 500g | 3798.48
--   Cyprus | Electric Gooseneck Kettle | 3053.35
--   Netherlands | Brazil Santos 1kg | 2875.2
--   Spain | House Espresso Blend 500g | 2426.76
--   Austria | Brazil Santos 1kg | 1912.51

-- Q10 Month-over-month revenue change (LAG)
WITH m AS (
  SELECT CASE WHEN o.order_ts LIKE '__/__/____%'
              THEN substr(o.order_ts,7,4)||'-'||substr(o.order_ts,4,2)
              ELSE substr(o.order_ts,1,7) END AS ym,
         SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
  FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.status = 'Delivered' GROUP BY ym)
SELECT ym, ROUND(revenue, 2) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY ym)) / LAG(revenue) OVER (ORDER BY ym), 1) AS mom_pct
FROM m ORDER BY ym;
-- RESULT:
--   ym | revenue | mom_pct
--   2024-01 | 1929.95 | None
--   2024-02 | 3436.38 | 78.1
--   2024-03 | 5050.25 | 47.0
--   2024-04 | 4243.13 | -16.0
--   2024-05 | 5327.82 | 25.6
--   2024-06 | 8495.45 | 59.5
--   …
--   2025-10 | 28045.73 | 6.1
--   2025-11 | 40770.07 | 45.4
--   2025-12 | 47620.11 | 16.8

-- Q11 Running revenue total for 2025
WITH m AS (
  SELECT CASE WHEN o.order_ts LIKE '__/__/____%'
              THEN substr(o.order_ts,7,4)||'-'||substr(o.order_ts,4,2)
              ELSE substr(o.order_ts,1,7) END AS ym,
         SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
  FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.status = 'Delivered' GROUP BY ym)
SELECT ym, ROUND(revenue, 2) AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY ym), 2) AS running_total
FROM m WHERE ym LIKE '2025-%' ORDER BY ym;
-- RESULT:
--   ym | revenue | running_total
--   2025-01 | 20134.15 | 20134.15
--   2025-02 | 16079.77 | 36213.93
--   2025-03 | 20854.63 | 57068.56
--   2025-04 | 21961.29 | 79029.85
--   2025-05 | 24693.9 | 103723.75
--   2025-06 | 30629.63 | 134353.38
--   2025-07 | 26832.75 | 161186.12
--   2025-08 | 25484.16 | 186670.29
--   2025-09 | 26428.63 | 213098.92
--   2025-10 | 28045.73 | 241144.64
--   2025-11 | 40770.07 | 281914.71
--   2025-12 | 47620.11 | 329534.83

-- Q12 Duplicate order_items rows and the revenue they would add
WITH dup AS (
  SELECT item_id, order_id, product_id, quantity, unit_price, discount, COUNT(*) AS copies
  FROM order_items
  GROUP BY item_id, order_id, product_id, quantity, unit_price, discount
  HAVING COUNT(*) > 1)
SELECT COUNT(*) AS duplicated_lines,
       SUM(copies - 1) AS extra_rows,
       ROUND(SUM((copies - 1) * quantity * unit_price * (1 - discount)), 2) AS inflated_revenue_all_statuses
FROM dup;
-- RESULT:
--   duplicated_lines | extra_rows | inflated_revenue_all_statuses
--   89 | 89 | 2057.38
