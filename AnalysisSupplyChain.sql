DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id       INTEGER PRIMARY KEY,
    customer_city     TEXT,
    customer_state    TEXT,
    customer_country  TEXT,
    customer_zipcode  TEXT,
    customer_segment  TEXT
);

CREATE TABLE products (
    product_id        INTEGER PRIMARY KEY,
    product_name      TEXT,
    product_price     NUMERIC,
    product_status    INTEGER,
    category_id       INTEGER,
    category_name     TEXT,
    department_id     INTEGER,
    department_name   TEXT
);

CREATE TABLE orders (
    order_id                     INTEGER PRIMARY KEY,
    customer_id                  INTEGER REFERENCES customers(customer_id),
    order_date                   TIMESTAMP,
    shipping_date                TIMESTAMP,
    days_for_shipping_real       INTEGER,
    days_for_shipment_scheduled  INTEGER,
    delivery_status              TEXT,
    late_delivery_risk           INTEGER,
    shipping_mode                TEXT,
    order_status                 TEXT,
    market                       TEXT,
    order_region                 TEXT,
    order_state                  TEXT,
    order_city                   TEXT,
    order_country                TEXT,
    latitude                     NUMERIC,
    longitude                    NUMERIC
);

CREATE TABLE order_items (
    order_item_id       INTEGER PRIMARY KEY,
    order_id            INTEGER REFERENCES orders(order_id),
    product_id          INTEGER REFERENCES products(product_id),
    quantity             INTEGER,
    discount             NUMERIC,
    discount_rate        NUMERIC,
    unit_price           NUMERIC,
    profit_ratio         NUMERIC,
    sales                NUMERIC,
    order_item_total     NUMERIC,
    order_profit         NUMERIC,
    benefit_per_order    NUMERIC,
    sales_per_customer   NUMERIC
);

SELECT
  (SELECT COUNT(*) FROM customers)   AS customers_count,
  (SELECT COUNT(*) FROM products)    AS products_count,
  (SELECT COUNT(*) FROM orders)      AS orders_count,
  (SELECT COUNT(*) FROM order_items) AS order_items_count;

-- 1. Overall on-time delivery rate 
SELECT
COUNT(*) AS total_orders,
SUM(CASE WHEN late_delivery_risk = 0 
    THEN 1 ELSE 0 END)
	AS on_time_orders,
    ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM orders;

-- 2. On-time rate by shipping mode 
SELECT shipping_mode, COUNT(*) AS total_orders,
  ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM orders 
GROUP BY shipping_mode 
ORDER BY on_time_pct;

-- 3. On-time rate by region 
SELECT order_region, COUNT(*) AS total_orders,
  ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) 
  AS on_time_pct
FROM orders 
GROUP BY order_region 
ORDER BY on_time_pct;

-- 4. True average delay (only among late orders)
SELECT
  shipping_mode,
  ROUND(AVG(days_for_shipping_real - days_for_shipment_scheduled), 2) AS avg_delay_days_when_late
FROM orders
WHERE days_for_shipping_real > days_for_shipment_scheduled
GROUP BY shipping_mode
ORDER BY avg_delay_days_when_late DESC;

-- 5. Delivery performance trend over time (month-over-month)
SELECT
  DATE_TRUNC('month', order_date) AS month,
  COUNT(*) AS total_orders,
  ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM orders
GROUP BY month
ORDER BY month;

--6. Market-level performance (higher grouping than region)
SELECT market, COUNT(*) AS total_orders,
  ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM orders 
GROUP BY market 
ORDER BY on_time_pct;

--7. Total sales, profit, and profit margin overall
SELECT
  ROUND(SUM(sales), 2) AS total_sales,
  ROUND(SUM(order_profit), 2) AS total_profit,
  ROUND(100.0 * SUM(order_profit) / NULLIF(SUM(sales), 0), 2) AS profit_margin_pct
FROM order_items;

--8. Profit impact of late vs. on-time orders — ties delivery performance directly to money
SELECT
  o.late_delivery_risk,
  COUNT(*) AS total_order_items,
  ROUND(SUM(oi.order_profit), 2) AS total_profit,
  ROUND(AVG(oi.order_profit), 2) AS avg_profit_per_item
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY o.late_delivery_risk;

--9. Cost vs. speed tradeoff by shipping mode
SELECT
  o.shipping_mode,
  ROUND(AVG(oi.sales), 2) AS avg_sales_per_item,
  ROUND(100.0 * SUM(CASE WHEN o.late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY o.shipping_mode
ORDER BY on_time_pct;

--10. Top 10 highest-loss orders (negative profit)
SELECT order_id, product_id, sales, order_profit
FROM order_items
ORDER BY order_profit ASC
LIMIT 10;

--11. % of orders that are loss-making, by category
SELECT
  p.category_name,
  COUNT(*) AS total_items,
  SUM(CASE WHEN oi.order_profit < 0 THEN 1 ELSE 0 END) AS loss_making_items,
  ROUND(100.0 * SUM(CASE WHEN oi.order_profit < 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS loss_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category_name
ORDER BY loss_pct DESC
LIMIT 10;

--12. Best-selling product categories by revenue
SELECT p.category_name, ROUND(SUM(oi.sales), 2) AS total_sales, COUNT(*) AS total_items_sold
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category_name
ORDER BY total_sales DESC
LIMIT 10;

--13. Categories with worst on-time delivery — root-cause drill-down
SELECT
  p.category_name,
  COUNT(*) AS total_items,
  ROUND(100.0 * SUM(CASE WHEN o.late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category_name
ORDER BY on_time_pct
LIMIT 10;

--14. Average discount rate by category (are discounts hurting margin?)
SELECT
  p.category_name,
  ROUND(AVG(oi.discount_rate) * 100, 2) AS avg_discount_pct,
  ROUND(AVG(oi.profit_ratio) * 100, 2) AS avg_profit_ratio_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category_name
ORDER BY avg_discount_pct DESC
LIMIT 10;

--15. Customer segment performance (Consumer/Corporate/Home Office)
SELECT
  c.customer_segment,
  COUNT(DISTINCT o.order_id) AS total_orders,
  ROUND(100.0 * SUM(CASE WHEN o.late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct,
  ROUND(SUM(oi.sales), 2) AS total_sales
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_segment
ORDER BY total_sales DESC;

--16. Top 10 customers by total sales (potential VIP/at-risk customers)
SELECT
  c.customer_id, c.customer_city, c.customer_state,
  ROUND(SUM(oi.sales), 2) AS total_sales,
  ROUND(100.0 * SUM(CASE WHEN o.late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_city, c.customer_state
ORDER BY total_sales DESC
LIMIT 10;

--17. Order status distribution (includes fraud/cancellation categories)
SELECT order_status, COUNT(*) AS total_orders,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

--18. Suspected fraud orders — do they also have high late delivery risk?
SELECT
  order_status,
  COUNT(*) AS total_orders,
  ROUND(100.0 * SUM(late_delivery_risk) / COUNT(*), 2) AS late_risk_pct
FROM orders
WHERE order_status IN ('SUSPECTED_FRAUD', 'COMPLETE', 'CANCELED')
GROUP BY order_status;

--19. Rank shipping modes by on-time % within each market (using window function)
SELECT market, shipping_mode, on_time_pct,
RANK() OVER (PARTITION BY market ORDER BY on_time_pct DESC) AS rank_in_market
FROM (SELECT market, shipping_mode,
    ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
  FROM orders
  GROUP BY market, shipping_mode
) sub
ORDER BY market, rank_in_market;

--20. Month-over-month change in on-time % (using LAG window function)
SELECT month, on_time_pct,
  ROUND(on_time_pct - LAG(on_time_pct) OVER (ORDER BY month), 2) AS change_vs_prev_month
FROM (SELECT DATE_TRUNC('month', order_date) AS month,
    ROUND(100.0 * SUM(CASE WHEN late_delivery_risk = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct
    FROM orders
    GROUP BY DATE_TRUNC('month', order_date)
) monthly
ORDER BY month;

--Some more queries

SELECT
  p.product_name,
  p.category_name,
  COUNT(*) AS times_sold,
  ROUND(AVG(oi.sales), 2) AS avg_sales,
  ROUND(AVG(oi.order_profit), 2) AS avg_profit,
  ROUND(SUM(oi.order_profit), 2) AS total_profit
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
WHERE oi.product_id = 1351
GROUP BY p.product_name, p.category_name;


SELECT order_id, sales, discount, discount_rate, order_profit
FROM order_items
WHERE product_id = 1351 AND order_profit < 0
ORDER BY order_profit ASC;


SELECT
  CASE WHEN order_profit < 0 THEN 'Loss' ELSE 'Profit' END AS outcome,
  COUNT(*) AS num_orders,
  ROUND(AVG(discount_rate) * 100, 2) AS avg_discount_pct,
  ROUND(AVG(order_profit), 2) AS avg_profit
FROM order_items
WHERE product_id = 1351
GROUP BY CASE WHEN order_profit < 0 THEN 'Loss' ELSE 'Profit' END;