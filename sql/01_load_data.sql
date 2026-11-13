-- =========================================================
-- BƯỚC 1. NẠP DỮ LIỆU
-- Mở cmd TẠI THƯ MỤC data/ rồi chạy:
--   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 --table < ../sql/01_load_data.sql
-- =========================================================
SET GLOBAL local_infile = 1;

DROP DATABASE IF EXISTS customer_analytics;
CREATE DATABASE customer_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE customer_analytics;
SET NAMES utf8mb4;

CREATE TABLE customers (
    customer_id          INT PRIMARY KEY,
    signup_date          DATE,
    city                 VARCHAR(30),
    age_group            VARCHAR(10),
    acquisition_channel  VARCHAR(30)
);

-- Bảng đơn hàng THÔ: giữ nguyên như file (có trùng, có đơn test)
CREATE TABLE orders_raw (
    order_id        VARCHAR(20),
    customer_id     INT,
    order_date      DATETIME,
    status          VARCHAR(20),
    items           INT,
    gross_value     BIGINT,       -- giá trị trước giảm giá (VND)
    discount        BIGINT,       -- tiền giảm giá (VND)
    net_value       BIGINT,       -- khách thực trả (VND)
    voucher_used    TINYINT,
    payment_method  VARCHAR(20)
);

LOAD DATA LOCAL INFILE 'customers.csv'
INTO TABLE customers CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, signup_date, city, age_group, @ch)
SET acquisition_channel = TRIM(TRAILING '\r' FROM @ch);

LOAD DATA LOCAL INFILE 'orders.csv'
INTO TABLE orders_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_date, status, items, gross_value, discount, net_value, voucher_used, @pm)
SET payment_method = TRIM(TRAILING '\r' FROM @pm);

SELECT 'customers' AS bang, COUNT(*) AS so_dong FROM customers
UNION ALL
SELECT 'orders_raw', COUNT(*) FROM orders_raw;      -- 4.685 và 11.097
