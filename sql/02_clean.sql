-- =========================================================
-- BƯỚC 2. KIỂM TRA & LÀM SẠCH
-- Chạy tại thư mục gốc repo:
--   mysql -u root -p --default-character-set=utf8mb4 --table < sql/02_clean.sql
-- =========================================================
USE customer_analytics;
SET NAMES utf8mb4;

-- 2.1 Tổng quan bảng đơn thô
SELECT COUNT(*)                         AS so_dong,
       COUNT(DISTINCT order_id)         AS so_ma_don,
       COUNT(*) - COUNT(DISTINCT order_id) AS dong_trung_ma_don,
       MIN(order_date)                  AS ngay_dau,
       MAX(order_date)                  AS ngay_cuoi
FROM orders_raw;

-- 2.2 Trạng thái đơn
SELECT status, COUNT(*) AS so_don,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders_raw
GROUP BY status
ORDER BY so_don DESC;

-- 2.3 Đơn có giá trị 0 (đơn test) và đơn không khớp khách hàng
SELECT SUM(net_value <= 0)                                        AS don_gia_tri_0,
       SUM(order_id LIKE 'TEST%')                                 AS don_ma_test,
       SUM(customer_id NOT IN (SELECT customer_id FROM customers)) AS don_khong_co_khach
FROM orders_raw;

-- 2.4 Gắn nhãn từng dòng theo lý do giữ / loại (thứ tự ưu tiên)
DROP TABLE IF EXISTS order_audit;

CREATE TABLE order_audit AS
SELECT x.*,
       CASE WHEN x.net_value <= 0 OR x.order_id LIKE 'TEST%' THEN 'L1 Đơn test / giá trị 0'
            WHEN x.rn > 1                                    THEN 'L2 Dòng trùng mã đơn'
            WHEN x.status <> 'Hoàn thành'                    THEN 'L3 Đơn hủy / hoàn trả'
            ELSE 'Giữ lại' END AS ly_do
FROM (SELECT o.*,
             ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date) AS rn
      FROM orders_raw o) x;

SELECT ly_do, COUNT(*) AS so_dong, SUM(net_value) AS tong_tien_vnd
FROM order_audit
GROUP BY ly_do
ORDER BY ly_do;

-- 2.5 Bảng đơn sạch: chỉ đơn HOÀN THÀNH, không trùng, không test
DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean AS
SELECT order_id, customer_id, order_date,
       DATE_FORMAT(order_date, '%Y-%m')                    AS ym,
       YEAR(order_date) * 12 + MONTH(order_date)           AS month_idx,
       items, gross_value, discount, net_value, voucher_used, payment_method
FROM order_audit
WHERE ly_do = 'Giữ lại';

ALTER TABLE orders_clean ADD PRIMARY KEY (order_id);
CREATE INDEX idx_oc_cust ON orders_clean (customer_id);

-- 2.6 Kiểm chứng: tổng các nhóm = bảng thô; bảng sạch không còn trùng
SELECT (SELECT COUNT(*) FROM order_audit)  AS dong_audit,
       (SELECT COUNT(*) FROM orders_raw)   AS dong_tho,
       (SELECT COUNT(*) FROM orders_clean) AS dong_sach,
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders_clean) AS con_trung,
       CASE WHEN (SELECT COUNT(*) FROM order_audit) = (SELECT COUNT(*) FROM orders_raw)
             AND (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders_clean) = 0
            THEN 'OK' ELSE 'SAI' END       AS ket_qua;
