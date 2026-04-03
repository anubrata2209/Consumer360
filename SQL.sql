-- CREATE DATABASE
CREATE DATABASE IF NOT EXISTS online_retail_db;
USE online_retail_db;
-- Session Settings
SET SQL_SAFE_UPDATES   = 0;
SET FOREIGN_KEY_CHECKS = 0;      
SET UNIQUE_CHECKS      = 0;      
SET autocommit         = 0;      
SET SESSION group_concat_max_len = 1000000;


-- STEP 2: CREATE STAGING TABLE
DROP TABLE IF EXISTS raw_transactions;
CREATE TABLE  raw_transactions (
    Invoice       VARCHAR(20),
    StockCode     VARCHAR(20),
    Description   VARCHAR(255),
    Quantity      INT,
    InvoiceDate   VARCHAR(30),
    Price         DECIMAL(10,2),
    CustomerID    VARCHAR(20),
    Country       VARCHAR(100)
)ENGINE = InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci; 
  
SELECT * FROM  raw_transactions;
-- LOAD DATA 
SET GLOBAL local_infile = 1;
SHOW VARIABLES LIKE 'local_infile';
LOAD DATA LOCAL INFILE 'C:/Users/Anubrata Parida/MyPython/Projects/Consumer360/online_retail.csv'
INTO TABLE raw_transactions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country);

-- Verify row count

SELECT * FROM raw_transactions;

SELECT COUNT(*)                          AS total_raw_rows     FROM raw_transactions;
SELECT COUNT(DISTINCT CustomerID)        AS distinct_customers FROM raw_transactions;
SELECT COUNT(DISTINCT StockCode)         AS distinct_products  FROM raw_transactions;
SELECT MIN(InvoiceDate), MAX(InvoiceDate)                      FROM raw_transactions;

-- Data cleaning
DROP TABLE IF EXISTS clean_transactions;

CREATE TABLE clean_transactions
ENGINE = InnoDB
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci
AS
SELECT
    TRIM(Invoice) AS Invoice,
    UPPER(TRIM(StockCode)) AS StockCode,
    NULLIF(TRIM(REGEXP_REPLACE(Description, '\\s+', ' ')), '')
                                                            AS Description,
	CAST(TRIM(Quantity) AS SIGNED)                        AS Quantity,
    CASE 
        WHEN InvoiceDate LIKE '%/%' 
             AND STR_TO_DATE(InvoiceDate, '%m/%d/%Y %H:%i') IS NOT NULL
        THEN STR_TO_DATE(InvoiceDate, '%m/%d/%Y %H:%i')
        
        WHEN InvoiceDate LIKE '%-%' 
             AND STR_TO_DATE(InvoiceDate, '%d-%m-%Y %H:%i') IS NOT NULL
        THEN STR_TO_DATE(InvoiceDate, '%d-%m-%Y %H:%i')
        
        ELSE NULL
    END AS InvoiceDate, 

	 CAST(TRIM(Price) AS DECIMAL(10,2))                    AS Price,

	NULLIF(TRIM(CustomerID), '')                            AS CustomerID,
	NULLIF(TRIM(Country), '')                               AS Country
FROM raw_transactions;



-- Check NULL Values
SELECT 
    COUNT(*) AS total_rows,
    SUM(Quantity IS NULL) AS null_quantity,
    SUM(InvoiceDate IS NULL) AS null_date,
    SUM(Price IS NULL) AS null_price,
    SUM(CustomerID IS NULL) AS null_customer,
    SUM(Country IS NULL) AS null_country,
    SUM(Description IS NULL) AS null_description
FROM clean_transactions;

-- Remove rows with NULL values
SET SQL_SAFE_UPDATES = 0;
DELETE FROM clean_transactions
WHERE 
    CustomerID IS NULL
    OR Description IS NULL;
SET SQL_SAFE_UPDATES = 1; 
    
-- Remove Invalid Rows
SET SQL_SAFE_UPDATES = 0;
DELETE FROM clean_transactions
WHERE Quantity <= 0 OR Price <= 0 OR Invoice IS NULL;
SET SQL_SAFE_UPDATES = 1;

-- Remove Duplicates
CREATE TABLE temp_clean AS
SELECT DISTINCT * FROM clean_transactions;

DROP TABLE clean_transactions;
RENAME TABLE temp_clean TO clean_transactions;
COMMIT;

-- Verify cleaning results
SELECT
    COUNT(*)                     AS clean_rows,
    COUNT(DISTINCT CustomerID)   AS unique_customers,
    COUNT(DISTINCT StockCode)    AS unique_products,
    COUNT(DISTINCT Invoice)      AS unique_invoices,
    MIN(InvoiceDate)             AS earliest_date,
    MAX(InvoiceDate)             AS latest_date
FROM clean_transactions;

-- NULL audit (all should be 0)
SELECT
    SUM(Invoice      IS NULL) AS null_invoice,
    SUM(StockCode    IS NULL) AS null_stockcode,
    SUM(Description  IS NULL) AS null_description,
    SUM(Quantity     IS NULL) AS null_quantity,
    SUM(InvoiceDate  IS NULL) AS null_date,
    SUM(Price        IS NULL) AS null_price,
    SUM(CustomerID   IS NULL) AS null_customer,
    SUM(Country      IS NULL) AS null_country
FROM clean_transactions;


-- ----------------Export Cleaned Data to CSV--------------------
SELECT 'Invoice', 'StockCode', 'Description', 'Quantity', 'InvoiceDate', 'Price', 'Customer ID', 'Country'
UNION ALL
SELECT * FROM clean_transactions
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/cleaned_data.csv'
FIELDS TERMINATED BY ','  
ENCLOSED BY '"'  
LINES TERMINATED BY '\n';
--  ----------------Dimension Tables-------------------------------------

-- Customer Dimension
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer AS
SELECT DISTINCT CustomerID
FROM clean_transactions;

-- Product Dimension
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS
SELECT DISTINCT StockCode, Description
FROM clean_transactions;

-- Date Dimension
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
SELECT DISTINCT 
    InvoiceDate,
    YEAR(InvoiceDate) AS Year,
    MONTH(InvoiceDate) AS Month,
    DAY(InvoiceDate) AS Day
FROM clean_transactions;


-- ---------Fact Sales-------------------------
DROP TABLE IF EXISTS fact_sales;
CREATE TABLE fact_sales AS
SELECT 
    ct.Invoice,
    ct.StockCode,
    ct.CustomerID,
    ct.InvoiceDate,
    ct.Quantity,
    ct.Price,
    (ct.Quantity * ct.Price) AS TotalAmount
FROM clean_transactions ct;


    
-- ------------ERD Verification Queries--------------------
-- Check relationships
--  orphan customers
SELECT COUNT(*) 
FROM fact_sales f
LEFT JOIN dim_customer c 
ON f.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL;

--  orphan products
SELECT COUNT(*) 
FROM fact_sales f
LEFT JOIN dim_product p 
ON f.StockCode = p.StockCode
WHERE p.StockCode IS NULL;

-- ----------Core analytical queries  (<2 sec)-----------------
-- Total Sales
SELECT SUM(TotalAmount) AS total_sales
FROM fact_sales;

-- Total Revenue by Country
SELECT
    Country,
    COUNT(DISTINCT Invoice)  AS total_orders,
    SUM(Quantity * Price)    AS total_revenue
FROM clean_transactions
GROUP BY Country
ORDER BY total_revenue DESC;

-- Top 10 Products by Revenue
SELECT 
    fs.StockCode,
    dp.Description,
    SUM(fs.TotalAmount) AS revenue
FROM fact_sales fs
JOIN dim_product dp 
    ON fs.StockCode = dp.StockCode
GROUP BY fs.StockCode, dp.Description
ORDER BY revenue DESC
LIMIT 10;

-- Monthly Sales Trend
SELECT 
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    SUM(TotalAmount) AS monthly_sales
FROM fact_sales
GROUP BY month
ORDER BY month;

-- Customer Lifetime Value (Top 20)
SELECT 
    CustomerID,
    SUM(TotalAmount) AS lifetime_value
FROM fact_sales
GROUP BY CustomerID
ORDER BY lifetime_value DESC
LIMIT 20;

-- Peak Order Hours
SELECT 
    HOUR(InvoiceDate) AS order_hour,
    COUNT(DISTINCT Invoice) AS total_orders,
    SUM(TotalAmount) AS revenue
FROM fact_sales
GROUP BY order_hour
ORDER BY total_orders DESC;

-- Top Countries by Orders
SELECT
    Country,
    COUNT(DISTINCT Invoice) AS total_orders
FROM clean_transactions
GROUP BY Country
ORDER BY total_orders DESC;


-- Average Order Value
SELECT 
    AVG(order_total) AS avg_order_value
FROM (
    SELECT Invoice, SUM(TotalAmount) AS order_total
    FROM fact_sales
    GROUP BY Invoice
) t;

-- Revenue by Geography
CREATE OR REPLACE VIEW vw_revenue_by_country AS
SELECT
    ct.Country,
    COUNT(DISTINCT fs.CustomerID)           AS customers,
    COUNT(DISTINCT fs.Invoice)              AS orders,
    ROUND(SUM(fs.TotalAmount), 2)           AS total_revenue,
    ROUND(AVG(fs.TotalAmount), 2)           AS avg_order_value,
    ROUND(
        100.0 * SUM(fs.TotalAmount) /
        SUM(SUM(fs.TotalAmount)) OVER (), 2
    )                                        AS revenue_pct
FROM fact_sales fs
JOIN clean_transactions ct
    ON  fs.Invoice    = ct.Invoice
    AND fs.CustomerID = ct.CustomerID
    AND fs.StockCode  = ct.StockCode
GROUP BY ct.Country
ORDER BY total_revenue DESC;

-- Performance Optimization
CREATE INDEX idx_country ON clean_transactions(Country);
CREATE INDEX idx_invoice ON fact_sales(Invoice);
CREATE INDEX idx_date ON fact_sales(InvoiceDate);
CREATE INDEX idx_customer ON fact_sales(CustomerID);
CREATE INDEX idx_product ON fact_sales(StockCode);

