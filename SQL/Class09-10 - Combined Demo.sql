/* ============================================================================
   Class 09 + Class 10  —  Combined Demo  (final file of Section 1)
   Topics : DML (INSERT/UPDATE/DELETE) | MERGE | Transactions & TRY..CATCH
            PIVOT / UNPIVOT | Variables & Control Flow | Stored Procedures
            + PART 7: topics not covered anywhere else in Section 1
   Database: BikeStores
   ============================================================================
   Run each block one at a time (select + F5) so students see one idea per run.
   Everything created here is dropped again in the CLEANUP block at the end.

   Version note: DROP ... IF EXISTS needs SQL Server 2016+, and STRING_AGG in
   demo 4.6 needs 2017+. On older versions use IF OBJECT_ID(...) IS NOT NULL
   and FOR XML PATH instead.
   ========================================================================== */

USE BikeStores;
GO

/* ============================================================================
   PART 1 — DML : INSERT, UPDATE, DELETE
   ----------------------------------------------------------------------------
   DDL = defines structure   (CREATE, ALTER, DROP, TRUNCATE)
   DML = changes data        (INSERT, UPDATE, DELETE, MERGE)
   DQL = reads data          (SELECT)

   THE GOLDEN RULE: write the WHERE clause as a SELECT first, look at the rows,
   and only then turn it into an UPDATE or DELETE. There is no Ctrl+Z in SQL.
   ========================================================================== */

-- Work on our own table so the sample database stays clean
DROP TABLE IF EXISTS sales.demo_categories;
CREATE TABLE sales.demo_categories (
    category_id   INT IDENTITY(1,1) PRIMARY KEY,
    category_name VARCHAR(255) NOT NULL,
    amount        DECIMAL(10,2) DEFAULT 0,
    created_at    DATETIME DEFAULT GETDATE()   -- audit column, filled by SQL Server
);

-- 1.1 INSERT one row -> columns we skip take their DEFAULT
INSERT INTO sales.demo_categories (category_name, amount)
VALUES ('Children Bicycles', 15000);

-- 1.2 INSERT many rows in ONE statement (one round trip, much faster)
INSERT INTO sales.demo_categories (category_name, amount)
VALUES ('Comfort Bicycles',    25000),
       ('Cruisers Bicycles',   13000),
       ('Cyclocross Bicycles', 10000);

SELECT * FROM sales.demo_categories;

-- 1.3 IDENTITY columns are generated for you -- do not supply them.
--     If you really must, unlock the column first:
INSERT INTO sales.demo_categories (category_id, category_name) VALUES (99, 'Fails');
SET IDENTITY_INSERT sales.demo_categories ON;
INSERT INTO sales.demo_categories (category_id, category_name) VALUES (99, 'Forced');
SET IDENTITY_INSERT sales.demo_categories OFF;   -- ALWAYS turn it back off

-- 1.4 OUTPUT clause -> returns the rows the statement actually touched.
--     Two virtual tables are available: inserted and deleted.
INSERT INTO sales.demo_categories (category_name, amount)
OUTPUT inserted.category_id, inserted.category_name, inserted.created_at
VALUES ('Electric Bikes', 30000);
-- Perfect for grabbing a new identity value without a second query.

-- 1.5 INSERT INTO ... SELECT -> load a table from a query
DROP TABLE IF EXISTS sales.ny_customers;
CREATE TABLE sales.ny_customers (
    customer_id   INT PRIMARY KEY,
    customer_name VARCHAR(255)
);

INSERT INTO sales.ny_customers (customer_id, customer_name)
SELECT customer_id, first_name + ' ' + last_name
FROM sales.customers
WHERE state = 'NY';

SELECT * FROM sales.ny_customers;

-- 1.6 SELECT ... INTO -> creates the table AND loads it in one shot.
--     Handy for a quick backup before a risky UPDATE. Copies no keys/indexes.
DROP TABLE IF EXISTS sales.demo_categories_backup;
SELECT * INTO sales.demo_categories_backup FROM sales.demo_categories;

-- 1.7 UPDATE -- verify with SELECT first
SELECT * FROM sales.demo_categories WHERE category_id IN (2, 3);   -- step 1: look

UPDATE sales.demo_categories
SET amount     = amount * 1.10,
    created_at = GETDATE()
OUTPUT deleted.amount AS old_amount, inserted.amount AS new_amount
WHERE category_id IN (2, 3);                                       -- step 2: change

-- 1.8 UPDATE ... FROM ... JOIN -> set values from ANOTHER table (T-SQL feature)
UPDATE c
SET c.amount = t.total_sales
FROM sales.demo_categories c
JOIN (
    SELECT p.category_id,
           SUM(oi.quantity * oi.list_price) AS total_sales
    FROM production.products p
    JOIN sales.order_items oi ON oi.product_id = p.product_id
    GROUP BY p.category_id
) t ON t.category_id = c.category_id;

SELECT * FROM sales.demo_categories;

-- 1.9 An UPDATE with NO WHERE hits EVERY row. Demonstrate deliberately, then
--     restore from the backup made in 1.6.
UPDATE sales.demo_categories SET amount = 0;
SELECT * FROM sales.demo_categories;      -- all zeros

TRUNCATE TABLE sales.demo_categories;
SET IDENTITY_INSERT sales.demo_categories ON;
INSERT INTO sales.demo_categories (category_id, category_name, amount, created_at)
SELECT category_id, category_name, amount, created_at FROM sales.demo_categories_backup;
SET IDENTITY_INSERT sales.demo_categories OFF;

-- 1.10 DELETE -- row-by-row, logged, and it can be filtered
DELETE FROM sales.demo_categories
OUTPUT deleted.category_id, deleted.category_name
WHERE category_name = 'Forced';

DELETE TOP (2) FROM sales.demo_categories;   -- TOP works here too (no ORDER BY!)

/*  DELETE vs TRUNCATE vs DROP -- a classic interview question
    ---------------------------------------------------------------------------
                  DELETE              TRUNCATE            DROP
    Type          DML                 DDL                 DDL
    WHERE         yes                 no (all rows)       n/a
    Speed         slow (per row)      very fast (pages)   fast
    IDENTITY      keeps counter       RESETS to seed      gone
    Triggers      fires them          does NOT fire       n/a
    Rollback      yes                 yes (in a txn)      yes (in a txn)
    Structure     table remains       table remains       table is GONE       */

/* ============================================================================
   PART 2 — MERGE  (the "UPSERT")
   ----------------------------------------------------------------------------
   Synchronises a TARGET table with a SOURCE table in ONE statement.
   This is the core of every incremental ETL load a data engineer writes.

     MERGE target USING source ON (join condition)
     WHEN MATCHED              THEN UPDATE ...   -- row in both
     WHEN NOT MATCHED BY TARGET THEN INSERT ...  -- new in source
     WHEN NOT MATCHED BY SOURCE THEN DELETE;     -- gone from source
   ========================================================================== */

DROP TABLE IF EXISTS sales.category;
DROP TABLE IF EXISTS sales.category_staging;

CREATE TABLE sales.category (            -- TARGET: yesterday's data
    category_id   INT PRIMARY KEY,
    category_name VARCHAR(255) NOT NULL,
    amount        DECIMAL(10,2)
);
INSERT INTO sales.category VALUES
    (1,'Children Bicycles',15000), (2,'Comfort Bicycles',25000),
    (3,'Cruisers Bicycles',13000), (4,'Cyclocross Bicycles',10000);

CREATE TABLE sales.category_staging (    -- SOURCE: today's feed
    category_id   INT PRIMARY KEY,
    category_name VARCHAR(255) NOT NULL,
    amount        DECIMAL(10,2)
);
INSERT INTO sales.category_staging VALUES
    (1,'Children Bicycles',15000),      -- unchanged
    (3,'Cruisers Bicycles',13000),      -- unchanged
    (4,'Cyclocross Bicycles',20000),    -- amount CHANGED -> update
    (5,'Electric Bikes',10000),         -- NEW           -> insert
    (6,'Mountain Bikes',10000);         -- NEW           -> insert
-- category_id 2 is missing from the source                -> delete

-- $action tells you what MERGE did to each row -- great for teaching
MERGE sales.category AS t
USING sales.category_staging AS s
    ON s.category_id = t.category_id
WHEN MATCHED THEN
    UPDATE SET t.category_name = s.category_name,
               t.amount        = s.amount
WHEN NOT MATCHED BY TARGET THEN
    INSERT (category_id, category_name, amount)
    VALUES (s.category_id, s.category_name, s.amount)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE
OUTPUT $action, inserted.category_id, inserted.category_name, deleted.category_id;

SELECT * FROM sales.category ORDER BY category_id;
-- Tip: add "AND t.amount <> s.amount" to WHEN MATCHED so unchanged rows are
-- skipped instead of pointlessly rewritten.


/* ============================================================================
   PART 3 — TRANSACTIONS & ERROR HANDLING
   ----------------------------------------------------------------------------
   A transaction groups statements into ONE all-or-nothing unit of work.

     ACID:  Atomicity   all or nothing
            Consistency constraints hold before and after
            Isolation   concurrent transactions do not corrupt each other
            Durability  once committed, it survives a crash

     BEGIN TRANSACTION  -> start
     COMMIT             -> make it permanent
     ROLLBACK           -> undo everything since BEGIN
   ========================================================================== */

DROP TABLE IF EXISTS sales.invoice_items;
DROP TABLE IF EXISTS sales.invoices;

CREATE TABLE sales.invoices (
    invoice_id  INT IDENTITY PRIMARY KEY,
    customer_id INT NOT NULL,
    total       DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0)
);
CREATE TABLE sales.invoice_items (
    item_id    INT,
    invoice_id INT NOT NULL,
    item_name  VARCHAR(100) NOT NULL,
    amount     DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    tax        DECIMAL(4,2)  NOT NULL CHECK (tax >= 0),
    PRIMARY KEY (item_id, invoice_id),
    FOREIGN KEY (invoice_id) REFERENCES sales.invoices (invoice_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- 3.1 A successful transaction: header + lines + total, or nothing at all
BEGIN TRANSACTION;
    INSERT INTO sales.invoices (customer_id, total) VALUES (100, 0);
    DECLARE @invoice_id INT = SCOPE_IDENTITY();   -- id of the row just inserted

    INSERT INTO sales.invoice_items (item_id, invoice_id, item_name, amount, tax)
    VALUES (10, @invoice_id, 'Keyboard', 70, 0.08),
           (20, @invoice_id, 'Mouse',    50, 0.08);

    UPDATE sales.invoices
    SET total = (SELECT SUM(amount * (1 + tax))
                 FROM sales.invoice_items WHERE invoice_id = @invoice_id)
    WHERE invoice_id = @invoice_id;
COMMIT;

SELECT * FROM sales.invoices;
SELECT * FROM sales.invoice_items;

-- 3.2 ROLLBACK -> the escape hatch. Nothing below survives.
BEGIN TRANSACTION;
    DELETE FROM sales.invoices;          -- looks catastrophic...
    SELECT COUNT(*) AS rows_inside_txn FROM sales.invoices;   -- 0
ROLLBACK;
SELECT COUNT(*) AS rows_after_rollback FROM sales.invoices;   -- back to 1
-- Habit worth teaching: BEGIN TRAN -> run the DELETE -> check -> COMMIT or ROLLBACK.

-- 3.3 TRY...CATCH -> catch the error instead of leaving a half-finished write
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO sales.invoices (customer_id, total) VALUES (200, 500);
        INSERT INTO sales.invoices (customer_id, total) VALUES (201, -999);  -- CHECK fails
    COMMIT;
    PRINT 'Committed';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;          -- undo the first INSERT too
    SELECT ERROR_NUMBER()  AS error_number,
           ERROR_MESSAGE() AS error_message,
           ERROR_LINE()    AS error_line,
           ERROR_SEVERITY() AS severity;
    PRINT 'Rolled back -- neither row was saved';
END CATCH;

SELECT * FROM sales.invoices;      -- customer 200 is NOT here: atomicity

-- 3.4 THROW -> raise your own error, so callers can react to bad input
BEGIN TRY
    DECLARE @qty INT = -5;
    IF @qty < 0 THROW 50001, 'Quantity cannot be negative.', 1;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
-- @@TRANCOUNT = how many transactions are open. Always check it in CATCH.


/* ============================================================================
   PART 4 — PIVOT & UNPIVOT
   ----------------------------------------------------------------------------
   PIVOT   turns ROWS into COLUMNS (long -> wide). Reports, Excel-style output.
   UNPIVOT turns COLUMNS into ROWS (wide -> long). Normalising a messy feed.

   PIVOT always needs three things:
     1. an aggregate      (COUNT / SUM / AVG ...)
     2. FOR <column>      the column whose VALUES become new column headers
     3. IN (...)          the list of those values, hard-coded in [brackets]
   ========================================================================== */

-- 4.1 The "long" starting point
SELECT c.category_name, COUNT(p.product_id) AS product_count
FROM production.categories c
JOIN production.products p ON p.category_id = c.category_id
GROUP BY c.category_name;

-- 4.2 Same data pivoted into one wide row
SELECT * FROM (
    SELECT c.category_name, p.product_id
    FROM production.products p
    JOIN production.categories c ON c.category_id = p.category_id
) AS src
PIVOT (
    COUNT(product_id)
    FOR category_name IN ([Children Bicycles], [Comfort Bicycles],
        [Cruisers Bicycles], [Cyclocross Bicycles], [Electric Bikes],
        [Mountain Bikes], [Road Bikes])
) AS pvt;

-- 4.3 CRITICAL GOTCHA: any extra column in the inner query becomes a GROUP BY.
--     Adding model_year silently turns 1 row into one row PER YEAR.
SELECT * FROM (
    SELECT c.category_name, p.product_id, p.model_year   -- <-- extra column
    FROM production.products p
    JOIN production.categories c ON c.category_id = p.category_id
) AS src
PIVOT (
    COUNT(product_id)
    FOR category_name IN ([Children Bicycles], [Comfort Bicycles],
        [Cruisers Bicycles], [Cyclocross Bicycles], [Electric Bikes],
        [Mountain Bikes], [Road Bikes])
) AS pvt
ORDER BY model_year;
-- Rule: the inner SELECT must contain ONLY the row labels you want,
-- the FOR column, and the aggregated column. Nothing else.

-- 4.4 The CASE alternative -- more typing, but no bracket list and full control
--     (this is also the answer to the class 10 homework on order_status)
SELECT
    SUM(CASE WHEN order_status = 1 THEN 1 ELSE 0 END) AS Pending,
    SUM(CASE WHEN order_status = 2 THEN 1 ELSE 0 END) AS Processing,
    SUM(CASE WHEN order_status = 3 THEN 1 ELSE 0 END) AS Rejected,
    SUM(CASE WHEN order_status = 4 THEN 1 ELSE 0 END) AS Completed
FROM sales.orders;

-- 4.5 UNPIVOT -> take the wide result and fold it back into rows
DROP TABLE IF EXISTS sales.order_status_wide;

SELECT
    SUM(CASE WHEN order_status = 1 THEN 1 ELSE 0 END) AS Pending,
    SUM(CASE WHEN order_status = 2 THEN 1 ELSE 0 END) AS Processing,
    SUM(CASE WHEN order_status = 3 THEN 1 ELSE 0 END) AS Rejected,
    SUM(CASE WHEN order_status = 4 THEN 1 ELSE 0 END) AS Completed
INTO sales.order_status_wide
FROM sales.orders;

SELECT * FROM sales.order_status_wide;      -- 1 row, 4 columns

SELECT status_name, order_count
FROM sales.order_status_wide
UNPIVOT (
    order_count FOR status_name IN (Pending, Processing, Rejected, Completed)
) AS unpvt;                                 -- 4 rows, 2 columns
-- The unpivoted columns must all share a compatible data type.
-- UNPIVOT drops NULLs; that is expected behaviour, not a bug.

-- 4.6 Dynamic PIVOT -- when the column list is not known in advance.
--     Build the bracket list from the data, then run generated SQL.
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @cols = STRING_AGG(QUOTENAME(category_name), ', ')   -- 2017+
FROM production.categories;

SET @sql = N'
SELECT * FROM (
    SELECT c.category_name, p.product_id
    FROM production.products p
    JOIN production.categories c ON c.category_id = p.category_id
) AS src
PIVOT (COUNT(product_id) FOR category_name IN (' + @cols + N')) AS pvt;';

PRINT @sql;              -- always LOOK at generated SQL before running it
EXEC sp_executesql @sql;
-- QUOTENAME() adds the [brackets] and is your protection against SQL injection.

/* ============================================================================
   PART 5 — VARIABLES & CONTROL FLOW  (T-SQL programming)
   ----------------------------------------------------------------------------
   Plain SQL is declarative -- you describe WHAT you want. T-SQL adds the
   procedural bits: variables, IF/ELSE, loops. This is what makes stored
   procedures possible.

     DECLARE @name datatype [= value];
     SET @name = value;            -- or SELECT @name = column FROM ...
     PRINT @name;                  -- to the Messages tab, not the grid
   ========================================================================== */

-- 5.1 Declare, assign, use
DECLARE @model_year INT = 2018;      -- declare and initialise in one line

SELECT product_name, model_year, list_price
FROM production.products
WHERE model_year = @model_year
ORDER BY product_name;
GO      -- GO ends the batch; variables die here. Declare them again below.

-- 5.2 Assigning from a query: SET with a sub-query, or SELECT INTO a variable
DECLARE @product_count INT, @avg_price DECIMAL(10,2);

SET @product_count = (SELECT COUNT(*) FROM production.products);
SELECT @avg_price = AVG(list_price) FROM production.products;   -- multi-assign

PRINT 'Products: ' + CAST(@product_count AS VARCHAR(10));       -- Messages tab
SELECT @product_count AS product_count, @avg_price AS avg_price;-- Results grid
GO

-- 5.3 IF ... ELSE
DECLARE @sales DECIMAL(18,2);

SELECT @sales = SUM(i.list_price * i.quantity)
FROM sales.order_items i
JOIN sales.orders o ON o.order_id = i.order_id
WHERE YEAR(o.order_date) = 2018;

PRINT '2018 sales: ' + CAST(@sales AS VARCHAR(30));

IF @sales > 10000000
    PRINT 'Great! 2018 sales are above 10,000,000';
ELSE
    PRINT 'Alas! 2018 sales are below 10,000,000';
-- Multiple statements per branch need BEGIN ... END around them.
GO

-- 5.4 WHILE loop
DECLARE @counter INT = 1;
WHILE @counter <= 5
BEGIN
    PRINT 'Iteration ' + CAST(@counter AS VARCHAR(2));
    SET @counter += 1;               -- forget this line and you loop forever
END
GO

-- 5.5 BREAK -> exit the loop early
DECLARE @counter INT = 1;
WHILE @counter <= 10
BEGIN
    PRINT @counter;
    SET @counter += 1;
    IF @counter = 5 BREAK;           -- stops at 4
END
GO

-- 5.6 CONTINUE -> skip the rest of THIS pass, keep looping
DECLARE @counter INT = 0;
WHILE @counter < 10
BEGIN
    SET @counter += 1;
    IF @counter % 2 = 0 CONTINUE;    -- skip even numbers
    PRINT @counter;                  -- prints 1 3 5 7 9
END
GO
-- Reminder for data work: loops are a LAST resort in SQL. A set-based query
-- beats a loop almost every time. Use loops for admin/batching, not analytics.


/* ============================================================================
   PART 6 — STORED PROCEDURES
   ----------------------------------------------------------------------------
   A stored procedure is a named, saved, pre-compiled block of T-SQL.

   Why: reusable, parameterised, permission-controlled, one network round trip,
        and it can contain logic a view never could (IF, loops, transactions).

     CREATE PROCEDURE name @param type [= default] AS BEGIN ... END
     EXEC name @param = value;

   VIEW vs PROCEDURE: a view is a saved SELECT you can join to. A procedure
   takes parameters and can modify data, but you cannot join to its result.
   ========================================================================== */

-- 6.1 The simplest procedure
DROP PROCEDURE IF EXISTS sales.usp_product_list;
GO
CREATE PROCEDURE sales.usp_product_list
AS
BEGIN
    SET NOCOUNT ON;                  -- suppress "(N rows affected)" noise
    SELECT product_name, list_price
    FROM production.products
    ORDER BY product_name;
END;
GO

EXEC sales.usp_product_list;

-- 6.2 ALTER PROCEDURE -> change the body, keep the permissions
GO
ALTER PROCEDURE sales.usp_product_list
AS
BEGIN
    SET NOCOUNT ON;
    SELECT product_id, product_name, list_price   -- added product_id
    FROM production.products
    ORDER BY product_name;
END;
GO

EXEC sales.usp_product_list;

-- 6.3 Parameters, with DEFAULTS so the caller can omit them
DROP PROCEDURE IF EXISTS sales.usp_find_products;
GO
CREATE PROCEDURE sales.usp_find_products
    @min_price DECIMAL(10,2) = 0,           -- default
    @max_price DECIMAL(10,2) = 1000000,     -- default
    @name      VARCHAR(100) = NULL          -- optional filter
AS
BEGIN
    SET NOCOUNT ON;
    SELECT product_name, list_price
    FROM production.products
    WHERE list_price BETWEEN @min_price AND @max_price
      AND (@name IS NULL OR product_name LIKE @name + '%')   -- skip if NULL
    ORDER BY list_price DESC;
END;
GO

EXEC sales.usp_find_products;                                  -- all defaults
EXEC sales.usp_find_products 100, 2500;                        -- positional
EXEC sales.usp_find_products @name = 'Trek';                   -- named (clearer)
EXEC sales.usp_find_products @min_price = 3000, @name = 'Trek';
-- Use NAMED parameters in real code: positional order breaks silently when
-- someone adds a new parameter in the middle.

-- 6.4 OUTPUT parameter -> send a scalar value back to the caller
DROP PROCEDURE IF EXISTS sales.usp_year_sales;
GO
CREATE PROCEDURE sales.usp_year_sales
    @year        INT,
    @total_sales DECIMAL(18,2) OUTPUT       -- must be marked OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @total_sales = SUM(i.list_price * i.quantity * (1 - i.discount))
    FROM sales.order_items i
    JOIN sales.orders o ON o.order_id = i.order_id
    WHERE YEAR(o.order_date) = @year;
END;
GO

DECLARE @sales_2017 DECIMAL(18,2);
EXEC sales.usp_year_sales @year = 2017, @total_sales = @sales_2017 OUTPUT;
SELECT @sales_2017 AS sales_2017;           -- OUTPUT is required on both sides
GO

-- 6.5 A procedure that WRITES data, wrapped in a transaction + TRY..CATCH.
--     This is the shape of a real production procedure.
DROP PROCEDURE IF EXISTS sales.usp_add_category;
GO
CREATE PROCEDURE sales.usp_add_category
    @category_name VARCHAR(255),
    @amount        DECIMAL(10,2),
    @new_id        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @amount < 0
        THROW 50002, 'Amount cannot be negative.', 1;      -- validate first

    BEGIN TRY
        BEGIN TRANSACTION;
            INSERT INTO sales.demo_categories (category_name, amount)
            VALUES (@category_name, @amount);
            SET @new_id = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;                          -- re-raise so the caller knows it failed
    END CATCH;
END;
GO

DECLARE @id INT;
EXEC sales.usp_add_category @category_name = 'Gravel Bikes',
                           @amount = 12000, @new_id = @id OUTPUT;
SELECT @id AS inserted_id;
GO

-- This call fails the validation and inserts nothing
DECLARE @id2 INT;
EXEC sales.usp_add_category @category_name = 'Bad Row',
                           @amount = -1, @new_id = @id2 OUTPUT;
GO

-- 6.6 Inspecting and renaming
EXEC sp_helptext 'sales.usp_find_products';          -- show the source
SELECT name, create_date, modify_date FROM sys.procedures ORDER BY name;
-- EXEC sp_rename 'sales.old_name', 'new_name';               -- rename object
-- EXEC sp_rename 'sales.tbl.old_col', 'new_col', 'COLUMN';   -- rename column
-- DROP PROCEDURE sales.usp_find_products;


/* ============================================================================
   PART 7 — REMAINING TOPICS OF SECTION 1
   ----------------------------------------------------------------------------
   Everything below belongs to the syllabus but never got its own class demo.
   Covered here so Section 1 is complete end to end.
   ========================================================================== */

/* ---------------------------------------------------------------------------
   7.1 DDL: ALTER TABLE
   Classes 1-6 only ever CREATE tables. In real life you change them.
   --------------------------------------------------------------------------- */
DROP TABLE IF EXISTS sales.demo_alter;
CREATE TABLE sales.demo_alter (id INT PRIMARY KEY, name VARCHAR(50));

ALTER TABLE sales.demo_alter ADD email VARCHAR(100);              -- add column
ALTER TABLE sales.demo_alter ADD phone VARCHAR(20), city VARCHAR(50);  -- several
ALTER TABLE sales.demo_alter ALTER COLUMN name VARCHAR(200) NOT NULL;  -- retype
ALTER TABLE sales.demo_alter ADD CONSTRAINT ck_demo_id CHECK (id > 0); -- rule
ALTER TABLE sales.demo_alter ADD status VARCHAR(20) DEFAULT 'active'
    WITH VALUES;                                                  -- default
ALTER TABLE sales.demo_alter DROP CONSTRAINT ck_demo_id;          -- drop rule
ALTER TABLE sales.demo_alter DROP COLUMN phone, city;             -- drop columns

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'sales' AND TABLE_NAME = 'demo_alter';
-- Widening a column (VARCHAR(50) -> VARCHAR(200)) is safe.
-- Narrowing it fails if any existing value does not fit.

/* ---------------------------------------------------------------------------
   7.2 TEMP TABLES vs TABLE VARIABLES vs CTEs
   Three ways to hold an intermediate result. Students mix these up constantly.
   --------------------------------------------------------------------------- */
-- #local temp table -> lives in tempdb until the session ends. Indexable.
DROP TABLE IF EXISTS #top_customers;

SELECT c.customer_id,
       c.first_name + ' ' + c.last_name AS full_name,
       SUM(i.quantity * i.list_price * (1 - i.discount)) AS total_spend
INTO #top_customers
FROM sales.customers c
JOIN sales.orders o      ON o.customer_id = c.customer_id
JOIN sales.order_items i ON i.order_id    = o.order_id
GROUP BY c.customer_id, c.first_name + ' ' + c.last_name;

CREATE INDEX ix_tmp_spend ON #top_customers (total_spend);   -- yes, you can index
SELECT TOP 10 * FROM #top_customers ORDER BY total_spend DESC;

-- @table variable -> declared, scoped to the batch, no statistics, no index
DECLARE @statuses TABLE (status_id INT, status_name VARCHAR(20));
INSERT INTO @statuses VALUES (1,'Pending'),(2,'Processing'),(3,'Rejected'),(4,'Completed');

SELECT s.status_name, COUNT(*) AS order_count
FROM sales.orders o
JOIN @statuses s ON s.status_id = o.order_status
GROUP BY s.status_name;
GO

DROP TABLE IF EXISTS #top_customers;
/*  WHICH ONE?
      CTE            -> readability, single statement, no storage
      @table var     -> SMALL result sets (a few hundred rows), lookup lists
      #temp table    -> LARGE result sets, reused across several statements,
                        needs an index or accurate statistics                */

/* ---------------------------------------------------------------------------
   7.3 GROUP BY extensions: ROLLUP, CUBE, GROUPING SETS
   Class 4 covered GROUP BY, but not subtotal/grand-total rows.
   --------------------------------------------------------------------------- */
-- ROLLUP -> hierarchical subtotals + a grand total (year, then year+month)
SELECT YEAR(o.order_date)  AS order_year,
       MONTH(o.order_date) AS order_month,
       SUM(i.quantity * i.list_price) AS sales
FROM sales.orders o
JOIN sales.order_items i ON i.order_id = o.order_id
GROUP BY ROLLUP (YEAR(o.order_date), MONTH(o.order_date))
ORDER BY order_year, order_month;
-- NULL in order_month = the subtotal row for that whole year.
-- NULL in both        = the grand total.

-- GROUPING() tells a real NULL apart from a subtotal NULL
SELECT CASE WHEN GROUPING(YEAR(o.order_date)) = 1 THEN 'ALL YEARS'
            ELSE CAST(YEAR(o.order_date) AS VARCHAR(4)) END AS order_year,
       SUM(i.quantity * i.list_price) AS sales
FROM sales.orders o
JOIN sales.order_items i ON i.order_id = o.order_id
GROUP BY ROLLUP (YEAR(o.order_date));

-- CUBE -> EVERY combination (by store, by year, by both, and overall)
SELECT o.store_id, YEAR(o.order_date) AS order_year, COUNT(*) AS orders
FROM sales.orders o
GROUP BY CUBE (o.store_id, YEAR(o.order_date))
ORDER BY o.store_id, order_year;

-- GROUPING SETS -> you pick exactly which groupings you want
SELECT o.store_id, YEAR(o.order_date) AS order_year, COUNT(*) AS orders
FROM sales.orders o
GROUP BY GROUPING SETS ((o.store_id), (YEAR(o.order_date)), ())
ORDER BY o.store_id, order_year;
-- () means the grand total. This replaces three queries UNION-ed together.

/* ---------------------------------------------------------------------------
   7.4 USER-DEFINED FUNCTIONS (UDFs)
   Procedures cannot be used inside a SELECT. Functions can.
   --------------------------------------------------------------------------- */
-- Scalar function -> returns ONE value, usable anywhere an expression is legal
DROP FUNCTION IF EXISTS sales.fn_net_price;
GO
CREATE FUNCTION sales.fn_net_price (@price DECIMAL(10,2), @discount DECIMAL(4,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN @price * (1 - ISNULL(@discount, 0));
END;
GO

SELECT order_id, list_price, discount,
       sales.fn_net_price(list_price, discount) AS net_price
FROM sales.order_items;
-- Note: scalar UDFs run per row and can be slow on big tables. Prefer an
-- inline expression or a computed column for hot paths.

-- Inline TABLE-VALUED function -> a view that takes parameters. Fast.
DROP FUNCTION IF EXISTS sales.fn_products_by_price;
GO
CREATE FUNCTION sales.fn_products_by_price (@min DECIMAL(10,2))
RETURNS TABLE
AS
RETURN (
    SELECT product_id, product_name, list_price
    FROM production.products
    WHERE list_price >= @min
);
GO

SELECT * FROM sales.fn_products_by_price(3000) ORDER BY list_price DESC;

-- Because it returns a table, you can JOIN to it -- a procedure cannot do this
SELECT b.brand_name, COUNT(*) AS expensive_products
FROM sales.fn_products_by_price(3000) f
JOIN production.products p ON p.product_id = f.product_id
JOIN production.brands b   ON b.brand_id   = p.brand_id
GROUP BY b.brand_name;
/*  FUNCTION vs PROCEDURE
      Function : returns a value/table, callable in SELECT and JOIN,
                 CANNOT modify data
      Procedure: called with EXEC, CAN modify data and manage transactions,
                 cannot be used inside a SELECT                              */

/* ---------------------------------------------------------------------------
   7.5 TRIGGERS  (lab_10 in docs -- had no class demo)
   A trigger is code that fires AUTOMATICALLY when data changes. Nobody calls
   it; the engine does. Inside it you get the same "inserted" and "deleted"
   virtual tables you saw in the OUTPUT clause.
   --------------------------------------------------------------------------- */
DROP TABLE IF EXISTS sales.category_audit;
CREATE TABLE sales.category_audit (
    audit_id    INT IDENTITY PRIMARY KEY,
    category_id INT,
    action      VARCHAR(10),
    old_amount  DECIMAL(10,2),
    new_amount  DECIMAL(10,2),
    changed_at  DATETIME DEFAULT GETDATE()
);
GO

DROP TRIGGER IF EXISTS sales.trg_category_audit;
GO
CREATE TRIGGER sales.trg_category_audit
ON sales.category
AFTER INSERT, UPDATE, DELETE      -- AFTER = runs once the change succeeded
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO sales.category_audit (category_id, action, old_amount, new_amount)
    SELECT COALESCE(i.category_id, d.category_id),
           CASE WHEN i.category_id IS NOT NULL AND d.category_id IS NOT NULL THEN 'UPDATE'
                WHEN i.category_id IS NOT NULL THEN 'INSERT'
                ELSE 'DELETE' END,
           d.amount, i.amount
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.category_id = i.category_id;
END;
GO

-- Now change data normally -- the audit table fills itself
INSERT INTO sales.category VALUES (7, 'Gravel Bikes', 5000);
UPDATE sales.category SET amount = 9999 WHERE category_id = 7;
DELETE FROM sales.category WHERE category_id = 7;

SELECT * FROM sales.category_audit ORDER BY audit_id;
/*  KEY POINTS
    - A trigger fires ONCE PER STATEMENT, not once per row. "inserted" and
      "deleted" can hold many rows -- never assume one.
    - UPDATE shows a row in BOTH inserted (new) and deleted (old).
    - TRUNCATE does NOT fire triggers. DELETE does.
    - AFTER vs INSTEAD OF: INSTEAD OF replaces the action (used to make
      multi-table views updatable).
    - Use sparingly: triggers are invisible logic and hard to debug.          */

/* ---------------------------------------------------------------------------
   7.6 NULL helpers you have not seen yet
   Class 05-06 covered COALESCE; these three round out the set.
   --------------------------------------------------------------------------- */
SELECT
    ISNULL(NULL, 'fallback')          AS isnull_two_args_only,
    COALESCE(NULL, NULL, 'first_ok')  AS coalesce_many_args,
    NULLIF(100, 100)                  AS nullif_equal_gives_null,
    NULLIF(100, 50)                   AS nullif_differs_returns_first,
    IIF(10 > 5, 'yes', 'no')          AS iif_short_case;

-- NULLIF's classic use: avoid divide-by-zero without an IF statement
SELECT order_id,
       SUM(quantity) AS units,
       SUM(quantity * list_price) / NULLIF(SUM(quantity), 0) AS avg_price_per_unit
FROM sales.order_items
GROUP BY order_id;
-- If units were 0, NULLIF turns the divisor into NULL -> result is NULL, no error.


/* ============================================================================
   CLEANUP — drop everything this file created
   ========================================================================== */
GO
DROP TRIGGER IF EXISTS sales.trg_category_audit;
DROP PROCEDURE IF EXISTS sales.usp_product_list;
DROP PROCEDURE IF EXISTS sales.usp_find_products;
DROP PROCEDURE IF EXISTS sales.usp_year_sales;
DROP PROCEDURE IF EXISTS sales.usp_add_category;
DROP FUNCTION IF EXISTS sales.fn_net_price;
DROP FUNCTION IF EXISTS sales.fn_products_by_price;
GO
DROP TABLE IF EXISTS sales.invoice_items;
DROP TABLE IF EXISTS sales.invoices;
DROP TABLE IF EXISTS sales.category_audit;
DROP TABLE IF EXISTS sales.category_staging;
DROP TABLE IF EXISTS sales.category;
DROP TABLE IF EXISTS sales.order_status_wide;
DROP TABLE IF EXISTS sales.ny_customers;
DROP TABLE IF EXISTS sales.demo_categories_backup;
DROP TABLE IF EXISTS sales.demo_categories;
DROP TABLE IF EXISTS sales.demo_alter;
GO

/* ============================================================================
   PRACTICE QUESTIONS
   ============================================================================

   DML
   1. Create sales.customer_archive, then load it with every customer from
      California using INSERT INTO ... SELECT.
   2. Insert one new brand and use OUTPUT to return the generated brand_id in
      the same statement (no second SELECT).
   3. Raise the list_price of every 2018 Trek product by 5%. Write the SELECT
      first, then convert it to an UPDATE, and use OUTPUT to show old vs new.
   4. Using UPDATE ... FROM ... JOIN, set a discount_flag column on
      sales.demo_categories for categories whose amount is below average.
   5. Explain what happens if you run an UPDATE without a WHERE clause, and
      name two habits that prevent it.
   6. Fill in the table: DELETE vs TRUNCATE vs DROP for WHERE support, speed,
      IDENTITY reset, trigger firing, and whether the table survives.
   7. Why does TRUNCATE not fire a trigger, and when does that matter?

   MERGE
   8. Add two rows to sales.category_staging, change one amount, remove one
      row, then re-run the MERGE and explain each $action value you get back.
   9. Modify the MERGE so unchanged rows are skipped (hint: add a condition to
      WHEN MATCHED). Why does this matter on a million-row table?
   10. Write a MERGE that only INSERTS and UPDATES -- never deletes. When would
       a business want that behaviour?

   TRANSACTIONS & ERROR HANDLING
   11. Open a transaction, delete all rows from sales.ny_customers, confirm the
       count is 0, then ROLLBACK and confirm the rows are back.
   12. Write a TRY..CATCH block that inserts an invoice with a negative total,
       catches the error, rolls back, and prints ERROR_MESSAGE().
   13. What does @@TRANCOUNT return, and why must you check it inside CATCH?
   14. Explain each letter of ACID using the invoice example from 3.1.

   PIVOT / UNPIVOT
   15. Pivot sales.orders so each order_status is a column and each store_id
       is a row, with the order count in the cells.
   16. Pivot total sales with years as columns and brand_name as rows.
   17. Take the result of Q16 into a table and UNPIVOT it back to
       (brand_name, year, sales). Why is UNPIVOT useful in ETL?
   18. Add a new category to production.categories and re-run the STATIC pivot
       from 4.2. What happens, and how does the dynamic version in 4.6 fix it?

   VARIABLES & CONTROL FLOW
   19. Declare a variable holding the number of orders in 2017. Print a
       different message depending on whether it is above or below 700.
   20. Use a WHILE loop to print the 12 month names of 2018 with their order
       counts. Then rewrite it as a single GROUP BY query -- which is better, and why?

   STORED PROCEDURES
   21. Write usp_orders_by_store taking @store_id and an optional @year that
       defaults to NULL meaning "all years".
   22. Write usp_customer_order_count with @customer_id as input and
       @order_count as an OUTPUT parameter. Call it and print the result.
   23. Write usp_transfer_stock that moves quantity of a product from one store
       to another inside a transaction, with TRY..CATCH and validation that the
       source store has enough stock.
   24. State two things a stored procedure can do that a view cannot, and one
       thing a view can do that a procedure cannot.

   PART 7 TOPICS
   25. Use ALTER TABLE to add a NOT NULL column with a default to an existing
       populated table. Why is the default required here?
   26. Solve the same problem three ways -- with a CTE, a #temp table, and a
       @table variable -- and say which fits best and why.
   27. Produce a sales report by year and month with subtotals per year and a
       grand total, using ROLLUP and GROUPING() to label the total rows.
   28. Rewrite your Q27 query with GROUPING SETS so you get ONLY the per-year
       totals and the grand total (no monthly rows).
   29. Write a scalar function fn_full_name(@first, @last) and use it in a
       SELECT. Then explain why a scalar UDF can hurt performance.
   30. Write an inline table-valued function fn_orders_in_year(@year) and JOIN
       it to sales.customers. Why can a procedure not be used this way?
   31. Create an AFTER UPDATE trigger on production.products that logs every
       list_price change into a price_history table. Then update three products
       in ONE statement and confirm all three were logged.
   32. Use NULLIF to compute average revenue per item without risking a
       divide-by-zero error.

   ========================================================================== */
