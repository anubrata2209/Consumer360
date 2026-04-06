-- CREATE DATABASE
-- DROP DATABASE online_retail_db;

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

-- Disable safe updates
SET SQL_SAFE_UPDATES = 0;

-- Remove NULL & empty values
DELETE FROM clean_transactions
WHERE 
    CustomerID IS NULL
    OR TRIM(CustomerID) = ''
    OR Description IS NULL
    OR InvoiceDate IS NULL;

-- Remove invalid numeric values
DELETE FROM clean_transactions
WHERE 
    Quantity <= 0 
    OR Price <= 0
    OR Invoice IS NULL;

-- Remove cancelled invoices
DELETE FROM clean_transactions
WHERE Invoice LIKE 'C%';

-- Remove non-product / noise records (IMPORTANT)
DELETE FROM clean_transactions
WHERE 
    UPPER(TRIM(StockCode)) IN (
        'POST', 'D', 'M', 'DOT', 'CRUK',
        'BANK CHARGES', 'PADS', 'ADJUST', 'ADJUST2',
        'TEST001', 'TEST002', 'AMAZONFEE', 'MANUAL', 'CHECK','C2'
    )
    OR
    UPPER(TRIM(Description)) IN (
        'POSTAGE', 'DOTCOM POSTAGE', 'MANUAL', 'DISCOUNT',
        'AMAZON FEE', 'BANK CHARGES', 'CRUK DONATION',
        'ADJUST', 'INCORRECTLY CREDITED', 'INCORRECTLY DEBITED',
        'WRONGLY CODED'
    );

-- Remove duplicates 
CREATE TABLE temp_clean AS
SELECT DISTINCT * FROM clean_transactions;

DROP TABLE clean_transactions;
RENAME TABLE temp_clean TO clean_transactions;

-- Commit changes
COMMIT;

-- Enable safe updates
SET SQL_SAFE_UPDATES = 1;

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

CREATE TABLE dim_customer (
    CustomerID VARCHAR(20) NOT NULL,
    Country VARCHAR(100),
    PRIMARY KEY (CustomerID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_customer
SELECT 
    CustomerID,
    MAX(Country)
FROM clean_transactions
WHERE CustomerID IS NOT NULL
GROUP BY CustomerID;


-- Product Dimension
DROP TABLE IF EXISTS dim_product;

CREATE TABLE dim_product (
    StockCode VARCHAR(20) NOT NULL,
    Description TEXT,
    PRIMARY KEY (StockCode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_product
SELECT 
    StockCode,
    MAX(Description)
FROM clean_transactions
GROUP BY StockCode;

-- Date Dimension
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
    date_key DATE PRIMARY KEY,
    Year INT,
    Month INT,
    Day INT,
    DayName VARCHAR(20),
    Quarter INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_date
SELECT DISTINCT
    DATE(InvoiceDate),
    YEAR(InvoiceDate),
    MONTH(InvoiceDate),
    DAY(InvoiceDate),
    DAYNAME(InvoiceDate),
    QUARTER(InvoiceDate)
FROM clean_transactions;

-- COLLATION ALIGNMENT
ALTER TABLE dim_customer 
MODIFY CustomerID VARCHAR(20)
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

ALTER TABLE dim_product 
MODIFY StockCode VARCHAR(20)
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;


-- ---------Fact Sales-------------------------
DROP TABLE IF EXISTS fact_sales;
CREATE TABLE fact_sales (
    sale_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    Invoice VARCHAR(20),
    StockCode VARCHAR(20),
    CustomerID VARCHAR(20),
    InvoiceDate DATETIME,
    Quantity INT,
    Price DECIMAL(10,2),
	TotalAmount DECIMAL(12,2),
    FOREIGN KEY (CustomerID) REFERENCES dim_customer(CustomerID),
    FOREIGN KEY (StockCode)  REFERENCES dim_product(StockCode)
)ENGINE=InnoDB 
DEFAULT CHARSET=utf8mb4 
COLLATE=utf8mb4_unicode_ci;

INSERT INTO fact_sales 
(Invoice, StockCode, CustomerID, InvoiceDate, Quantity, Price, TotalAmount)
SELECT 
    Invoice, 
    StockCode, 
    CustomerID, 
    InvoiceDate, 
    Quantity, 
    Price,
    (Quantity * Price) 

FROM clean_transactions;
COMMIT;
-- Verify
SELECT COUNT(*)                      AS total_rows      FROM fact_sales;
SELECT COUNT(DISTINCT CustomerID)    AS customers       FROM fact_sales;
SELECT COUNT(DISTINCT StockCode)     AS products        FROM fact_sales;
SELECT ROUND(SUM(TotalAmount), 2)    AS gross_revenue   FROM fact_sales;

-- Performance Indexes on fact_sales
CREATE INDEX idx_country ON clean_transactions(Country);
CREATE INDEX idx_invoice ON fact_sales(Invoice);
CREATE INDEX idx_date ON fact_sales(InvoiceDate);
CREATE INDEX idx_customer ON fact_sales(CustomerID);
CREATE INDEX idx_product ON fact_sales(StockCode);
    
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
SELECT
    dc.Country,
    
    COUNT(DISTINCT fs.CustomerID) AS customers,
    COUNT(DISTINCT fs.Invoice) AS orders,

    ROUND(SUM(fs.TotalAmount), 2) AS total_revenue,

    ROUND(
        SUM(fs.TotalAmount) / COUNT(DISTINCT fs.Invoice),
    2) AS avg_order_value,

    ROUND(
        100 * SUM(fs.TotalAmount) / SUM(SUM(fs.TotalAmount)) OVER (),
    2) AS revenue_pct

FROM fact_sales fs
JOIN dim_customer dc
    ON fs.CustomerID = dc.CustomerID

GROUP BY dc.Country
ORDER BY total_revenue DESC;


 -- Restore Session Settings
SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS      = 1;
SET autocommit         = 1;
SET SQL_SAFE_UPDATES   = 1;

SELECT 'Consumer360 schema build complete' AS status;

