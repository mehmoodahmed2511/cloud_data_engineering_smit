
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

SELECT * FROM sales.customers WHERE first_name LIKE '%b';		--First Names end with B--

