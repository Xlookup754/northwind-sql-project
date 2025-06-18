-- Create a new schema for the analysis and switch to it
CREATE SCHEMA northwind_traders;
USE northwind_traders;

----------------------------------------------------------------------------------------
--  ANALYSIS 1: Top 5 Customers by Total Revenue & Their % Contribution
-- Goal: Identify which customers generate the most revenue and how much of total revenue
-- they contribute. Helps target key clients and maintain relationships.
----------------------------------------------------------------------------------------
WITH CTE AS (
    SELECT 
        o.customerID,  
        SUM(od.unitPrice * od.quantity) AS total_revenue 
    FROM order_details od 
    INNER JOIN orders o ON od.orderID = o.orderID
    GROUP BY o.customerID 
)
SELECT 
    customerID, 
    total_revenue, 
    SUM(total_revenue) OVER () AS grand_total, 
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS percentage
FROM CTE
ORDER BY total_revenue DESC 
LIMIT 5;

----------------------------------------------------------------------------------------
--  ANALYSIS 2: Top Product Revenue Consistency Over Time (Rolling Average)
-- Goal: Determine the product with the highest average revenue per order and analyze how
-- consistent its monthly performance is. Useful for inventory and forecasting.
----------------------------------------------------------------------------------------
WITH CTE_product_year AS (
    SELECT 
        p.productID,
        p.categoryID, 
        od.unitPrice, 
        od.quantity, 
        od.discount, 
        o.orderID, 
        o.orderDate
    FROM products p 
    INNER JOIN order_details od ON p.productID = od.productID
    INNER JOIN orders o ON od.orderID = o.orderID
),
SUM_REVENUE AS (
    SELECT 
        productID,
        categoryID, 
        orderID, 
        MONTH(orderDate) AS month_order,
        SUM(unitPrice * quantity) AS revenue_per_product 
    FROM CTE_product_year
    GROUP BY productID, categoryID, orderID, MONTH(orderDate)
),
RANKED_PRODUCTS AS (
    SELECT 
        productID,
        AVG(revenue_per_product) AS avg_revenue
    FROM SUM_REVENUE
    GROUP BY productID
    ORDER BY avg_revenue DESC
    LIMIT 1
)
SELECT 
    sr.productID,
    sr.categoryID, 
    sr.month_order, 
    sr.orderID, 
    sr.revenue_per_product,
    ROUND(
        AVG(sr.revenue_per_product) OVER (
            PARTITION BY sr.productID 
            ORDER BY sr.month_order 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2
    ) AS running_avg_revenue
FROM SUM_REVENUE sr
JOIN RANKED_PRODUCTS rp ON sr.productID = rp.productID
ORDER BY sr.month_order, sr.orderID;

----------------------------------------------------------------------------------------
--  ANALYSIS 3: Top Employees by Revenue & Avg Order Size
-- Goal: Measure which employees manage the most revenue and their average order size.
-- Helpful for performance reviews or incentives.
----------------------------------------------------------------------------------------
WITH employees AS (
    SELECT 
        e.employeeName, 
        p.productID, 
        p.unitPrice, 
        od.quantity,  
        od.discount, 
        o.customerID, 
        o.orderID,
        p.quantityPerUnit
    FROM employees e
    INNER JOIN orders o ON e.employeeID = o.employeeID 
    INNER JOIN order_details od ON od.orderID = o.orderID
    INNER JOIN products p ON p.productID = od.productID
),
parsed_employees AS (
    SELECT 
        employeeName,
        customerID,
        orderID,
        productID,
        unitPrice,
        quantity,
        discount,
        quantityPerUnit,
        -- Estimate number of units per package for better granularity
        CASE 
            WHEN quantityPerUnit LIKE '%x%' THEN
                CAST(SUBSTRING_INDEX(quantityPerUnit, ' ', 1) AS UNSIGNED) *
                CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(quantityPerUnit, 'x', -1), ' ', 1) AS UNSIGNED)
            ELSE
                CAST(SUBSTRING_INDEX(quantityPerUnit, ' ', 1) AS UNSIGNED)
        END AS units_per_package,
        SUBSTRING_INDEX(quantityPerUnit, ' ', -1) AS unit_description
    FROM employees
),
employee_summary AS (
    SELECT 
        employeeName,
        customerID,
        unit_description,
        SUM(unitPrice * quantity) AS total_revenue,
        ROUND(AVG(quantity), 2) AS avg_quantity_per_order,
        ROUND(AVG(quantity * units_per_package), 2) AS approx_total_units_per_order
    FROM parsed_employees
    GROUP BY employeeName, customerID, unit_description
)
SELECT *
FROM employee_summary
ORDER BY total_revenue DESC
LIMIT 5;

----------------------------------------------------------------------------------------
--  ANALYSIS 4: Reorder Behavior - Are Customers Reordering the Same Products?
-- Goal: See which products are frequently reordered by the same customers.
-- Useful for identifying recurring demand and setting up auto-reorder options.
----------------------------------------------------------------------------------------
WITH cte AS (
    SELECT 
        c.customerID, 
        od.orderID, 
        od.productID, 
        o.orderDate
    FROM customers c
    INNER JOIN orders o ON c.customerID = o.customerID
    INNER JOIN order_details od ON od.orderID = o.orderID
),
reorder AS (
    SELECT 
        customerID, 
        productID,
        COUNT(DISTINCT orderID) AS num_orders
    FROM cte
    GROUP BY customerID, productID
    HAVING COUNT(DISTINCT orderID) > 1
)
SELECT 
    productID, 
    COUNT(*) AS number_of_customers_who_reordered, 
    SUM(num_orders) AS total_times_product_was_reordered
FROM reorder
GROUP BY productID
ORDER BY total_times_product_was_reordered DESC
LIMIT 5;

----------------------------------------------------------------------------------------
-- 🌍 ANALYSIS 5: Top Countries by Total Profit
-- Goal: Identify geographic areas generating the most revenue. Helps inform expansion or
-- marketing focus.
----------------------------------------------------------------------------------------
WITH cte AS (
    SELECT 
        c.customerID, 
        c.country, 
        od.unitPrice, 
        od.quantity,
        od.discount
    FROM customers c 
    INNER JOIN orders o ON o.customerID = c.customerID
    INNER JOIN order_details od ON o.orderID = od.orderID
)
SELECT 
    country, 
    ROUND(SUM(unitPrice * quantity * (1 - discount)), 2) AS total_revenue
FROM cte
GROUP BY country
ORDER BY total_revenue DESC
LIMIT 10;

----------------------------------------------------------------------------------------
--  ANALYSIS 6: Shipping Efficiency by Shipper
-- Goal: Compare average delivery times across shipping providers.
-- Helps in negotiating contracts or identifying delays.
----------------------------------------------------------------------------------------
WITH cte AS (
    SELECT 
        orderID, 
        customerID, 
        shipperID, 
        DATEDIFF(shippedDate, orderDate) AS shipping_days
    FROM orders
)
SELECT 
    shipperID, 
    AVG(shipping_days) AS avg_shipping_time
FROM cte
GROUP BY shipperID;

----------------------------------------------------------------------------------------
--  ANALYSIS 7: Are Discounted Orders Less Profitable?
-- Goal: Calculate how much revenue is lost due to discounts and whether discounting
-- strategies are cost-effective.
----------------------------------------------------------------------------------------
WITH cte AS (
    SELECT 
        orderID,
        ROUND(SUM(unitPrice * quantity * (1 - discount)), 2) AS discounted_revenue,
        ROUND(SUM(unitPrice * quantity), 2) AS total_revenue
    FROM order_details
    GROUP BY orderID
)
SELECT 
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(SUM(discounted_revenue), 2) AS discounted_revenue,
    ROUND(SUM(total_revenue) - SUM(discounted_revenue), 2) AS revenue_lost_to_discounts,
    ROUND((SUM(total_revenue) - SUM(discounted_revenue)) * 100.0 / SUM(total_revenue), 2) AS discount_impact_percent
FROM cte;

----------------------------------------------------------------------------------------
--  ANALYSIS 8: Customer Churn Risk Based on Inactivity
-- Goal: Identify customers who haven't ordered in a long time (180+ days) and may be at
-- risk of churn. Can be used for re-engagement campaigns.
----------------------------------------------------------------------------------------
SELECT 
    customerID,
    CURRENT_DATE() AS today,
    MAX(orderDate) AS last_order_date,
    DATEDIFF(CURRENT_DATE(), MAX(orderDate)) AS days_since_last_order,
    CASE 
        WHEN DATEDIFF(CURRENT_DATE(), MAX(orderDate)) > 180 THEN 'churn risk'
        ELSE 'active'
    END AS status
FROM orders
GROUP BY customerID;
