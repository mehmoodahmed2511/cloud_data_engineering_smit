
SELECT * FROM production.brands;

SELECT * FROM sales.customers WHERE customer_id = 7;
SELECT * FROM sales.customers WHERE city = 'New York';
SELECT * FROM sales.customers WHERE city = 'Victoria';
SELECT * FROM sales.customers WHERE state = 'NY';
SELECT * FROM sales.customers WHERE city = 'New York' AND last_name = 'Tyler';
SELECT * FROM sales.customers ORDER BY first_name;
SELECT * FROM sales.customers ORDER BY first_name DESC;
SELECT first_name, last_name FROM sales.customers ORDER BY first_name ASC, city DESC;
SELECT * FROM sales.customers WHERE city = 'Orchard Park' ORDER BY customer_id;
SELECT TOP 10 * FROM sales.customers ORDER BY first_name;


SELECT * FROM production.products ORDER BY list_price;
SELECT * FROM production.products ORDER BY list_price DESC;
SELECT * FROM production.products ORDER BY model_year, list_price;
SELECT TOP 10 PERCENT * FROM production.products ORDER BY list_price DESC;
SELECT * FROM production.products ORDER BY list_price DESC OFFSET 10 ROWS; --skip first 10 rows--
SELECT * FROM production.products ORDER BY list_price DESC OFFSET 10 ROWS FETCH NEXT 7 ROWS ONLY; --skip top 10 rows and fetch next 7 rows--

SELECT DISTINCT city FROM sales.customers;
SELECT DISTINCT city, state FROM sales.customers;

SELECT * FROM production.products WHERE category_id = 1 AND list_price > 400; 
SELECT * FROM production.products WHERE category_id = 1 OR list_price > 400;

--Class Exercise: Products priced above 1000 AND from brand id 1 OR brand id 2--
--Tip: If condition contain both AND and OR then write condition in () parynthesis--
SELECT * FROM production.products WHERE (list_price > 1000) AND (brand_id = 1 OR brand_id =2);

SELECT * FROM sales.customers WHERE phone IS NULL;

SELECT first_name, last_name, city, state, phone FROM sales.customers WHERE (state = 'CA') AND (city = 'Campbell') AND (phone IS NULL);

 --IN is use for multipe OR conditions-- 
 SELECT * FROM sales.customers WHERE state IN ('NY', 'TX', 'CA');

SELECT * FROM production.products WHERE list_price BETWEEN 1000 AND 2000 ORDER BY list_price;

SELECT * FROM sales.customers WHERE first_name LIKE '_a%';		--second character should be 'a'--
SELECT * FROM sales.customers WHERE first_name LIKE '%b';		--First Names end with B--

SELECT first_name + ' ' + last_name AS full_name FROM sales.customers;		--Concatenation--

SELECT p.product_name, p.list_price FROM production.products AS p WHERE list_price > 2000;


--ASSIGNMENT--

--  Question 1 — SELECT & WHERE
--  Retrieve the first name, last name, city, and phone number
--  of all customers who live in the state of 'CA' (California)
--  and have a phone number on record.
SELECT first_name, last_name, city, phone FROM sales.customers WHERE state = 'CA' AND phone IS NOT NULL;

--  Question 2 — ORDER BY (Multiple Columns)
--  Fetch the product_id, product_name, model_year, and
--  list_price of all products.
--  Sort the results by model_year in descending order, and
--  within the same year sort by list_price in ascending order.
SELECT product_id, product_name, model_year, list_price FROM production.products ORDER BY model_year DESC, list_price ASC;

--Question 3 — TOP N & TOP PERCENT
--  a) Return the top 5 most expensive products showing only
--     product_name and list_price.
--  b) Return the top 5% of cheapest products (all columns).
--     How many rows does the 5% result return? Add the row
--     count as a comment in your answer.
SELECT TOP 5 product_name, list_price FROM production.products ORDER BY list_price DESC;
SELECT TOP 5 PERCENT * FROM production.products ORDER BY list_price ASC; --Returns 17 Rows

 --Question 4 — OFFSET & FETCH (Pagination)
--  The sales team wants to browse products page by page,
--  10 products per page, sorted by list_price descending.
--  Write queries to return:
--    a) Page 1  (rows  1 – 10)
--    b) Page 2  (rows 11 – 20)
--    c) Page 3  (rows 21 – 30)--
SELECT TOP 10 * FROM production.products ORDER BY list_price DESC;
SELECT * FROM production.products ORDER BY list_price DESC OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;
SELECT * FROM production.products ORDER BY list_price DESC OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

--  Question 5 — DISTINCT
--  a) List all unique states in which BikeStores has customers.
--     Sort the result alphabetically.
--  b) List every unique combination of state and city,
--     sorted by state then city (both ascending).
--  c) How many unique model years exist in the products table?
--     (Retrieve the distinct values; count them manually or
--     use COUNT — your choice.)
SELECT DISTINCT state FROM sales.customers WHERE customer_id IS NOT NULL ORDER BY state;
SELECT DISTINCT state, city FROM sales.customers ORDER BY state, city;
SELECT COUNT (DISTINCT model_year) AS Total_Model_Years FROM production.products;

--  Question 6 — Logical Operators (AND / OR)
--  Write a single query that returns the product_id,
--  product_name, brand_id, category_id, and list_price for
--  products that meet ALL of the following conditions:
--    • list_price is between $500 and $1500 (inclusive)
--    • model_year is 2019 OR 2020
--  Sort the results by list_price ascending.
--  Hint: use parentheses to control the order of evaluation.
SELECT product_id, product_name, brand_id, category_id, list_price FROM production.products WHERE (list_price >= 500 AND list_price <= 1500) AND (model_year = '2019' OR model_year = '2020') ORDER BY list_price ASC;


--JOINS--
--Inner Join: Common values in both tables--
SELECT c.first_name, c.last_name, o.shipped_date FROM sales.customers c JOIN sales.orders o ON c.customer_id = o.order_id;

--Left Join: Retreive all data from left table and common data from right table--
SELECT * FROM production.products p LEFT JOIN sales.order_items oi ON p.product_id = oi.product_id;

--Right Join: Retreive all data from right table and common data from left table--
SELECT * FROM production.products p RIGHT JOIN sales.order_items oi ON p.product_id = oi.product_id;

--Outer Join: Retreive data that are not common in both tables--
SELECT * FROM production.products p FULL OUTER JOIN sales.order_items oi ON p.product_id = oi.product_id;


--AGGREGATE FUNCTIONS--
SELECT COUNT(*) AS total_orders FROM sales.orders;

SELECT COUNT(*) AS total_order_items, MIN(list_price) AS minimum_list_price, MAX(list_price) as maximum_list_price, AVG(list_price) AS avg_list_price FROM sales.order_items;

--Retreive not shipped orders--
SELECT COUNT(*) - COUNT(shipped_date) AS not_shipped_orders FROM sales.orders;

SELECT COUNT(*) AS total_orders, COUNT (DISTINCT customer_id) AS total_unique_customers FROM sales.orders;

--GROUP BY--
SELECT customer_id, COUNT(order_id) AS total_orders FROM sales.orders GROUP BY customer_id;

SELECT category_id, COUNT(product_name) AS total_products FROM production.products GROUP BY category_id;

--Customer with id 1 and 2 placed order in which year--
SELECT customer_id, YEAR(order_date) AS order_year, COUNT(order_id) AS total_orders FROM sales.orders WHERE customer_id IN (1, 2) GROUP BY customer_id, YEAR(order_date);

--On which year, month and day the customer placed order and how much--
SELECT customer_id, YEAR(order_date) AS order_year, MONTH(order_date) order_month, DAY(order_date) AS order_day, COUNT(order_id) AS total_order FROM sales.orders GROUP BY customer_id, YEAR(order_date), MONTH(order_date), DAY(order_date);  

--How many customers are from each city--
SELECT city, COUNT(customer_id) AS total_customers FROM sales.customers GROUP BY city;

--Calculate Min, Max and Avg list price of each product category--
SELECT category_id, MAX(list_price) AS max_price, MIN(list_price) AS min_price, AVG(list_price) AS avg_price FROM production.products GROUP BY category_id;

--HAVING--
--customer who have placed more than 1 order in a year--
SELECT customer_id, YEAR(order_date) AS order_year, COUNT(order_id) AS total_orders FROM sales.orders GROUP BY customer_id, YEAR(order_date) HAVING COUNT(order_id) > 1;


--XXXXXX Incomplete
--products having list price greater than avg list price--
SELECT category_id, MIN(list_price) AS min_list_price, MAX(list_price) AS max_list_price, AVG(list_price) AS avg_list_price, COUNT(product_id) AS total_products FROM production.products GROUP BY category_id HAVING list_price > AVG(list_price); 


--Sub Queries--
SELECT product_id, product_name FROM production.products WHERE category_id IN (SELECT category_id FROM production.categories);

SELECT * FROM production.products;
SELECT * FROM production.brands WHERE brand_id IN (SELECT brand_id FROM production.products WHERE brand_name IN ('Electra', 'Trek'));

--Find Average list price for brand name 'Electra' and 'Trek'--
SELECT AVG(list_price) FROM production.products WHERE category_id IN (SELECT category_id FROM production.brands WHERE brand_name IN ('Electra', 'Trek'));

--For each model year, show the number of products and average price where the average price is greater than 1000--
SELECT model_year, COUNT(product_id) AS total_products, AVG(list_price) AS avg_list_price FROM production.products GROUP BY model_year HAVING AVG(list_price) > 1000;


--EXIST--
--It is used for checking which data exists in other table and return with which we want to check--
--NOT EXIST--
--It is used for checking which data does not exist in other table --

SELECT c.customer_id, c.first_name, c.last_name FROM sales.customers c WHERE EXISTS (SELECT 1 FROM sales.orders o WHERE o.customer_id = c.customer_id);


--UNION--
--It combines two tables rows of only same column quantity, and same data type. It does not do no repetition of values. Column names are considered of first query--
SELECT first_name, last_name FROM sales.staffs
UNION
SELECT first_name, last_name FROM sales.customers;

--UNION ALL--
--It combines two tables rows of same columns, same column numbers, and same data type. It do repetition of values--

--INTERSECT--
--It retreives common values between tables--
SELECT city FROM sales.customers INTERSECT SELECT city FROM sales.stores;

--EXCEPT--



--Defining constraint Benefit: If we want to remove constraint from a column we will just delete constraint name, otherwise we need to delete the column--

--CTE (Common Table Expressions)--
--Very Important & Usedul.	`y are used to less complex the query--




--Views--
--Q: Create sales.vw_top_10_orders with order_id, customer full name, order date, item count and total orders. Then find the 10 largest orders from it.
CREATE VIEW vw_top_10_orders AS
SELECT TOP 10 o.order_id, c.first_name + ' ' + c.last_name as full_name, o.order_date, COUNT(oi.order_id) AS total_orders, COUNT(oi.item_id) AS total_items, SUM(quantity * list_price) AS order_price FROM sales.customers c JOIN sales.orders o ON c.customer_id = o.customer_id JOIN sales.order_items oi ON o.order_id = oi.order_id GROUP BY o.order_id, c.first_name + ' ' + c.last_name, o.order_date ORDER BY order_price DESC;
GO

SELECT * FROM vw_top_10_orders;


