/* ============================================================================
   Class 07 + Class 08  —  Combined Demo
   Topics : Indexes | Views | Window Functions
   Database: BikeStores
   ============================================================================
   Run each block one at a time (select + F5) so students see one idea per run.
   For the index part, turn ON the actual execution plan (Ctrl + M) BEFORE
   running -- the whole lesson is visible in the plan, not in the result grid.
   ========================================================================== */

USE BikeStores;
GO

/* ============================================================================
   PART 1 — INDEXES
   ----------------------------------------------------------------------------
   An index is a sorted lookup structure (B-tree) that lets SQL Server jump
   straight to the rows it needs instead of reading the whole table.

   Book analogy:
     No index -> read every page to find a topic   (TABLE / INDEX SCAN)
     Index    -> check the index at the back, jump straight to the page (SEEK)

   Two kinds:
     CLUSTERED     -> defines the PHYSICAL sort order of the table.
                      The table IS the index. Only ONE per table.
                      A PRIMARY KEY creates one automatically.
     NON-CLUSTERED -> a separate structure holding the key + a pointer back
                      to the row. Many per table.

   A table with no clustered index is a HEAP -- rows sit in no particular order.

   The trade-off: indexes make reads faster but INSERT/UPDATE/DELETE slower,
   because every index must also be maintained. Index for real query patterns,
   not "just in case".
   ========================================================================== */

-- 1.1 Start with a HEAP (no index at all)
DROP TABLE IF EXISTS production.parts;
CREATE TABLE production.parts (
    part_id   INT IDENTITY(1,1),
    part_name VARCHAR(100) NOT NULL
);

INSERT INTO production.parts (part_name)
VALUES ('Frame'), ('Head Tube'), ('Handlebar Grip'), ('Shock Absorber'), ('Fork');

-- 5 rows -> the plan shows a Table Scan, and that is perfectly fine.
-- On tiny tables a scan is CHEAPER than an index. Indexes only pay off at scale.
SELECT part_id, part_name FROM production.parts WHERE part_id = 5;

-- 1.2 Make it big enough for indexes to matter (~500,000 rows)
--     Adjust 100000 up or down depending on how much class time you have.
;WITH base AS (
    SELECT part_name
    FROM (VALUES ('Frame'),('Head Tube'),('Handlebar Grip'),
                 ('Shock Absorber'),('Fork')) AS p(part_name)
),
nums AS (
    SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO production.parts (part_name)
SELECT CONCAT(b.part_name, '_', n.n)
FROM nums n CROSS JOIN base b;

SELECT COUNT(*) AS row_count FROM production.parts;

-- 1.3 Measure BEFORE indexing. STATISTICS IO prints how many pages were read.
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM production.parts WHERE part_id = 312938;
-- Plan: Table Scan. Logical reads = thousands of pages to find ONE row.

-- 1.4 Add a CLUSTERED index -> the table gets physically sorted by part_id
CREATE CLUSTERED INDEX ix_parts_part_id ON production.parts (part_id);

SELECT * FROM production.parts WHERE part_id = 312938;
-- Plan: Clustered Index Seek. Logical reads drop to a handful of pages.
-- THIS is the moment to point at the plan and the read counts side by side.

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- 1.5 NON-CLUSTERED index on a foreign key column
--     FK columns are the single most commonly forgotten index.
SELECT * FROM sales.orders WHERE customer_id = 259;   -- scan first

DROP INDEX IF EXISTS ix_orders_customer_id ON sales.orders;
CREATE NONCLUSTERED INDEX ix_orders_customer_id ON sales.orders (customer_id);

SELECT * FROM sales.orders WHERE customer_id = 259;   -- now a seek

-- 1.6 COMPOSITE index -> KEY ORDER MATTERS (the "leftmost prefix" rule)
DROP INDEX IF EXISTS ix_customers_name ON sales.customers;
CREATE NONCLUSTERED INDEX ix_customers_name
ON sales.customers (last_name, first_name);

-- USED: the filter starts with the leading column
SELECT customer_id, first_name, last_name FROM sales.customers
WHERE last_name = 'Berg' AND first_name = 'Monika';

-- USED: the leading column alone is still enough
SELECT customer_id, last_name FROM sales.customers WHERE last_name = 'Berg';

-- NOT USED (scan): this skips the leading column
SELECT customer_id, first_name FROM sales.customers WHERE first_name = 'Monika';
-- Index (last_name, first_name) is like a phone book sorted by surname.
-- You cannot use it to find everyone whose first name is "Monika".

-- 1.7 An OR against an unindexed column pushes the optimizer back to a scan
SELECT customer_id, first_name, last_name FROM sales.customers
WHERE (last_name = 'Berg' AND first_name = 'Monika')
   OR city = 'Atwater';        -- city is in no index -> scan

-- 1.8 COVERING index -> INCLUDE extra columns so the query never touches the
--     table at all (the "Key Lookup" operator disappears from the plan)
DROP INDEX IF EXISTS ix_customers_city_covering ON sales.customers;
CREATE NONCLUSTERED INDEX ix_customers_city_covering
ON sales.customers (city)
INCLUDE (first_name, last_name, email);

SELECT first_name, last_name, email FROM sales.customers WHERE city = 'Atwater';
-- Key columns  -> used for searching and sorting
-- INCLUDE cols -> just carried along so they can be returned

-- 1.9 UNIQUE index -> an index that also enforces a rule
--     (this is exactly how UNIQUE and PRIMARY KEY work underneath)
DROP INDEX IF EXISTS ux_parts_part_name ON production.parts;
CREATE UNIQUE NONCLUSTERED INDEX ux_parts_part_name ON production.parts (part_name);
INSERT INTO production.parts (part_name) VALUES ('Frame');   -- duplicate -> error

-- 1.10 FILTERED index -> index only the rows you actually query.
--      Smaller index, cheaper to maintain.
DROP INDEX IF EXISTS ix_orders_pending ON sales.orders;
CREATE NONCLUSTERED INDEX ix_orders_pending
ON sales.orders (order_date)
WHERE order_status = 1;

SELECT order_id, order_date FROM sales.orders
WHERE order_status = 1 AND order_date > '2017-01-01';

-- 1.11 Inspect the indexes a table already has
SELECT i.name AS index_name,
       i.type_desc,
       i.is_unique,
       i.has_filter,
       COL_NAME(ic.object_id, ic.column_id) AS column_name,
       ic.key_ordinal,
       ic.is_included_column
FROM sys.indexes i
JOIN sys.index_columns ic
     ON ic.object_id = i.object_id AND ic.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('sales.customers')
ORDER BY i.name, ic.is_included_column, ic.key_ordinal;

/*  WHEN TO INDEX                          WHEN NOT TO
    - columns in WHERE / JOIN / ORDER BY   - very small tables
    - foreign key columns                  - columns with few distinct values
    - high-selectivity columns               (e.g. a Yes/No flag)
    - columns used by frequent queries     - write-heavy, rarely-read tables
                                           - columns you never filter on      */


/* ============================================================================
   PART 2 — VIEWS
   ----------------------------------------------------------------------------
   A view is a SAVED QUERY that you can treat like a table.
   It stores NO data -- the underlying query runs every time you select from it.

     CREATE VIEW schema.view_name AS <query>;

   Why views:
     - Hide complexity : users select from one name instead of a 4-table join
     - Security        : expose only certain columns/rows, not the base table
     - Consistency     : one definition of "net sales" reused everywhere
     - Stability       : change the internals without breaking reports

   Naming convention: prefix with vw_ so nobody mistakes it for a table.

   Types:
   Normal View:
   It is stored as a query. So that we can just run it when needed.

   Materialized View: 
   It stores the table as view and give little fast result becuse table alreadye exist. The data will be automatically updated with
   "with check option"
   ========================================================================== */

-- 2.1 The query we keep rewriting
SELECT p.product_name, b.brand_name, p.list_price
FROM production.products p
JOIN production.brands b ON b.brand_id = p.brand_id;

-- 2.2 Save it once as a view
DROP VIEW IF EXISTS production.vw_product_info;
GO
CREATE VIEW production.vw_product_info
AS
SELECT p.product_id, p.product_name, b.brand_name, p.list_price
FROM production.products p
JOIN production.brands b ON b.brand_id = p.brand_id;
GO

-- Now it behaves like a table: filter it, join it, aggregate it
SELECT * FROM production.vw_product_info WHERE brand_name = 'Trek';

SELECT brand_name, COUNT(*) AS products, AVG(list_price) AS avg_price
FROM production.vw_product_info
GROUP BY brand_name;

-- 2.3 View with an explicit column list -> names are defined on the view, so
--     the inner query does not need an alias for every expression
DROP VIEW IF EXISTS sales.vw_staff_sales;
GO
CREATE VIEW sales.vw_staff_sales (first_name, last_name, order_year, amount)
AS
SELECT s.first_name,
       s.last_name,
       YEAR(o.order_date),
       SUM(i.list_price * i.quantity)
FROM sales.order_items i
JOIN sales.orders o ON o.order_id = i.order_id
JOIN sales.staffs s ON s.staff_id = o.staff_id
GROUP BY s.first_name, s.last_name, YEAR(o.order_date);
GO

SELECT * FROM sales.vw_staff_sales ORDER BY order_year, amount DESC;

-- 2.4 A view we will reuse in Part 3 -- monthly net sales per brand
DROP VIEW IF EXISTS sales.vw_netsales_brands;
GO
CREATE VIEW sales.vw_netsales_brands
AS
SELECT b.brand_name,
       YEAR(o.order_date)  AS [year],
       MONTH(o.order_date) AS [month],
       CONVERT(DECIMAL(10,0),
               SUM(i.list_price * i.quantity * (1 - i.discount))) AS net_sales
FROM sales.orders o
JOIN sales.order_items i   ON i.order_id   = o.order_id
JOIN production.products p ON p.product_id = i.product_id
JOIN production.brands b   ON b.brand_id   = p.brand_id
GROUP BY b.brand_name, YEAR(o.order_date), MONTH(o.order_date);
GO

SELECT * FROM sales.vw_netsales_brands ORDER BY [year], [month], brand_name;

-- 2.5 Rules and gotchas
--   * No ORDER BY inside a view definition (unless paired with TOP) -- a view
--     is an unordered set. Sort in the OUTER query instead.
--   * A simple single-table view IS updatable: INSERT/UPDATE/DELETE pass
--     through to the base table. Views with JOIN, GROUP BY, DISTINCT or
--     aggregates are NOT updatable.
--   * WITH CHECK OPTION blocks writes that would make a row vanish from the view.
DROP VIEW IF EXISTS sales.vw_ny_customers;
GO
CREATE VIEW sales.vw_ny_customers
AS
SELECT customer_id, first_name, last_name, state
FROM sales.customers
WHERE state = 'NY'
WITH CHECK OPTION;
GO
-- This fails: 'CA' would no longer satisfy the view's WHERE clause
UPDATE sales.vw_ny_customers SET state = 'CA' WHERE customer_id = 1;

-- 2.6 Read and change a view definition
SELECT OBJECT_DEFINITION(OBJECT_ID('production.vw_product_info')) AS definition;
SELECT name, create_date, modify_date FROM sys.views ORDER BY name;
GO
-- ALTER VIEW replaces the body but keeps permissions (safer than DROP + CREATE)
ALTER VIEW production.vw_product_info
AS
SELECT p.product_id, p.product_name, b.brand_name, p.list_price, p.model_year
FROM production.products p
JOIN production.brands b ON b.brand_id = p.brand_id;
GO

-- 2.7 INDEXED VIEW (SQL Server's "materialized view")
--     A unique clustered index on a view makes the result physically stored
--     and kept in sync automatically. Requires WITH SCHEMABINDING, two-part
--     object names, COUNT_BIG(*), and no outer joins or sub-queries.
DROP VIEW IF EXISTS sales.vw_order_counts;
GO
CREATE VIEW sales.vw_order_counts
WITH SCHEMABINDING
AS
SELECT customer_id, COUNT_BIG(*) AS order_count
FROM sales.orders
GROUP BY customer_id;
GO
CREATE UNIQUE CLUSTERED INDEX ix_vw_order_counts
ON sales.vw_order_counts (customer_id);
GO
SELECT * FROM sales.vw_order_counts ORDER BY order_count DESC;
-- Reads are now pre-computed; the cost moves to every write on sales.orders.


/* ============================================================================
   PART 3 — WINDOW FUNCTIONS
   ----------------------------------------------------------------------------
   A window function calculates across a set of rows RELATED to the current
   row -- and still returns ONE ROW PER INPUT ROW.

     GROUP BY -> collapses many rows into one   (detail is LOST)
     OVER()   -> keeps every row and adds the calculation beside it

   Syntax:
     function() OVER (
         [PARTITION BY ...]   -- restart the calculation per group
         [ORDER BY     ...]   -- order inside the window (needed for ranking)
         [frame]              -- ROWS/RANGE BETWEEN ... (running totals)
     )

   Ranking      : ROW_NUMBER, RANK, DENSE_RANK, NTILE
   Aggregate    : SUM, AVG, COUNT, MIN, MAX ... OVER()
   Offset/value : LAG, LEAD, FIRST_VALUE, LAST_VALUE
   ========================================================================== */

-- 3.1 GROUP BY vs OVER() -- run both and compare the row counts
SELECT category_id, AVG(list_price) AS avg_price
FROM production.products
GROUP BY category_id;                       -- 7 rows, product detail is gone

SELECT product_name, category_id, list_price,
       AVG(list_price) OVER (PARTITION BY category_id) AS avg_price_in_category,
       list_price - AVG(list_price) OVER (PARTITION BY category_id) AS diff_from_avg
FROM production.products;                   -- every product + its category avg
-- No GROUP BY needed, and each row can be compared against its own group.

-- 3.2 ROW_NUMBER -> a plain 1,2,3 with no gaps and no ties
SELECT ROW_NUMBER() OVER (ORDER BY first_name) AS row_num,
       first_name, last_name, city
FROM sales.customers;

-- 3.3 PARTITION BY -> the numbering RESTARTS for each group
SELECT ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY list_price DESC) AS rn,
       category_id, product_name, list_price
FROM production.products;
-- Filtering rn <= 3 gives the classic "top N per group" -- but a window
-- function cannot go in WHERE, so wrap it in a CTE (next demo).

-- 3.4 Top 3 most expensive products per category
WITH cte_ranked AS (
    SELECT product_name, category_id, list_price,
           ROW_NUMBER() OVER (PARTITION BY category_id
                              ORDER BY list_price DESC) AS rn
    FROM production.products
)
SELECT * FROM cte_ranked WHERE rn <= 3 ORDER BY category_id, rn;
-- WHY the CTE: SELECT runs AFTER WHERE, so the alias rn does not exist yet
-- when WHERE is evaluated. The CTE turns it into a real column first.

-- 3.5 ROW_NUMBER vs RANK vs DENSE_RANK -- the tie behaviour is the whole point
SELECT product_name, list_price,
       ROW_NUMBER() OVER (ORDER BY list_price DESC) AS row_number,
       RANK()       OVER (ORDER BY list_price DESC) AS rank_with_gaps,
       DENSE_RANK() OVER (ORDER BY list_price DESC) AS dense_rank_no_gaps,
       NTILE(4)     OVER (ORDER BY list_price DESC) AS price_quartile
FROM production.products;
/*  Prices 100, 90, 90, 80 produce:
      ROW_NUMBER  1, 2, 3, 4   -> always unique, ties broken arbitrarily
      RANK        1, 2, 2, 4   -> ties share a rank, then SKIPS 3
      DENSE_RANK  1, 2, 2, 3   -> ties share a rank, no gap
      NTILE(4)                 -> splits the rows into 4 equal buckets       */

-- 3.6 Practical use: find and delete duplicates with ROW_NUMBER
--     Work on a COPY so the real table stays intact.
DROP TABLE IF EXISTS sales.customers_dup;
SELECT * INTO sales.customers_dup FROM sales.customers;

-- Number the rows inside each duplicate-name group; row 1 is the keeper
WITH cte_dupes AS (
    SELECT customer_id,
           ROW_NUMBER() OVER (PARTITION BY first_name, last_name
                              ORDER BY customer_id) AS rn
    FROM sales.customers_dup
)
SELECT * FROM cte_dupes WHERE rn > 1;      -- always inspect before deleting

-- Deleting THROUGH the CTE removes those rows from the base table
WITH cte_dupes AS (
    SELECT customer_id,
           ROW_NUMBER() OVER (PARTITION BY first_name, last_name
                              ORDER BY customer_id) AS rn
    FROM sales.customers_dup
)
DELETE FROM cte_dupes WHERE rn > 1;
-- DELETE FROM cte_name works because the CTE is an updatable view over a
-- single table. If the CTE has joins, use DELETE ... WHERE id IN (SELECT ...).

-- 3.7 Running total and share of total -> an aggregate OVER with ORDER BY
SELECT [month],
       SUM(net_sales) AS net_sales,
       SUM(SUM(net_sales)) OVER (ORDER BY [month]
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
       SUM(SUM(net_sales)) OVER ()                             AS year_total,
       CONVERT(DECIMAL(5,2),
           100.0 * SUM(net_sales) / SUM(SUM(net_sales)) OVER ()) AS pct_of_year
FROM sales.vw_netsales_brands
WHERE [year] = 2017
GROUP BY [month]
ORDER BY [month];
-- OVER() with no ORDER BY -> the whole result set (grand total)
-- OVER(ORDER BY ...)      -> everything up to the current row (running total)

-- 3.8 LAG / LEAD -> reach into the PREVIOUS or NEXT row
--     LAG(column, offset, default_if_missing)
WITH cte_monthly AS (
    SELECT [month], SUM(net_sales) AS net_sales
    FROM sales.vw_netsales_brands
    WHERE [year] = 2017
    GROUP BY [month]
)
SELECT [month],
       net_sales,
       LAG(net_sales, 1, 0)  OVER (ORDER BY [month]) AS previous_month,
       LEAD(net_sales, 1, 0) OVER (ORDER BY [month]) AS next_month,
       net_sales - LAG(net_sales, 1, 0) OVER (ORDER BY [month]) AS mom_change
FROM cte_monthly
ORDER BY [month];
-- Month-over-month growth in one pass. Without LAG this needs a self-join.

-- 3.9 FIRST_VALUE / LAST_VALUE -> the best and worst in each partition
SELECT category_id, product_name, list_price,
       FIRST_VALUE(product_name) OVER (PARTITION BY category_id
                                       ORDER BY list_price DESC) AS most_expensive,
       LAST_VALUE(product_name)  OVER (PARTITION BY category_id
                                       ORDER BY list_price DESC
             ROWS BETWEEN UNBOUNDED PRECEDING
                      AND UNBOUNDED FOLLOWING) AS cheapest
FROM production.products;
-- LAST_VALUE needs the explicit full frame. The default frame stops at the
-- CURRENT ROW, so without it LAST_VALUE just repeats the current row.

-- 3.10 Views + window functions together: rank brands within each year
SELECT [year], brand_name,
       SUM(net_sales) AS net_sales,
       DENSE_RANK() OVER (PARTITION BY [year]
                          ORDER BY SUM(net_sales) DESC) AS brand_rank
FROM sales.vw_netsales_brands
GROUP BY [year], brand_name
ORDER BY [year], brand_rank;
-- Window functions run AFTER GROUP BY, which is why SUM() is legal inside OVER().


/* ============================================================================
   CLEANUP — drop everything this file created
   ========================================================================== */
DROP INDEX IF EXISTS ix_orders_customer_id      ON sales.orders;
DROP INDEX IF EXISTS ix_orders_pending          ON sales.orders;
DROP INDEX IF EXISTS ix_customers_name          ON sales.customers;
DROP INDEX IF EXISTS ix_customers_city_covering ON sales.customers;
DROP TABLE IF EXISTS production.parts;
DROP TABLE IF EXISTS sales.customers_dup;
GO
DROP VIEW IF EXISTS sales.vw_order_counts;
DROP VIEW IF EXISTS sales.vw_ny_customers;
DROP VIEW IF EXISTS sales.vw_staff_sales;
DROP VIEW IF EXISTS sales.vw_netsales_brands;
DROP VIEW IF EXISTS production.vw_product_info;
GO

/* ============================================================================
   PRACTICE QUESTIONS
   ============================================================================

   INDEXES
   1. Filter sales.order_items by product_id with the execution plan turned on.
      Note the operator and the logical reads, add a non-clustered index, run it
      again, and write down both numbers.
   2. Most reports filter sales.orders by (store_id, order_date). Create the
      composite index. Which column should lead, and why?
   3. Using your index from Q2, show one query that CAN use it and one that
      cannot. Explain both with the leftmost-prefix rule.
   4. A report selects order_id, order_date and order_status filtered by
      store_id. Build a covering index so the plan has no Key Lookup.
   5. In your own words: why can adding an index to a write-heavy table make
      the application slower overall?
   6. List every index on sales.orders with its type and key columns using
      sys.indexes and sys.index_columns.
   7. Only about 2% of orders have order_status = 3. Write a filtered index for
      those rows and explain why it beats a full index on order_status.

   VIEWS
   8. Create production.vw_stock_summary showing product_name, store_name and
      quantity by joining production.stocks, production.products and sales.stores.
   9. Create sales.vw_order_summary with order_id, customer full name, order
      date, item count and order total. Then find the 10 largest orders from it.
   10. Put an ORDER BY inside a view definition. What error appears, and where
       does the sorting actually belong?
   11. Try to UPDATE a quantity through your Q8 view. Does it work? Why or why not?
   12. Create a view exposing only customers from Texas WITH CHECK OPTION, then
       attempt to insert a California customer through it. Explain the result.
   13. Use ALTER VIEW to add list_price to your Q8 view. Why is ALTER VIEW
       preferred over DROP + CREATE in production?

   WINDOW FUNCTIONS
   14. For every product show its list_price, the average price of its brand,
       and how far above/below that average it sits -- without using GROUP BY.
   15. Rank staff by total sales within each year using DENSE_RANK, then return
       only the #1 performer per year.
   16. For each customer, number their orders 1, 2, 3... by order_date, then
       return only each customer's FIRST order.
   17. Build a running total of daily sales for 2018, ordered by date.
   18. Use LAG to show each customer's previous order date and the number of
       days between their orders (hint: DATEDIFF).
   19. Split products into 4 price quartiles with NTILE(4) and show the minimum
       and maximum price in each quartile.
   20. Explain the difference between RANK() and DENSE_RANK() when three
       products share the same price. Prove it with a query.

   MIXED
   21. Create a view of monthly net sales per store, query it with LAG to get
       month-over-month growth, and index the base-table columns the view
       joins on. Compare the plan before and after the index.

   ========================================================================== */
