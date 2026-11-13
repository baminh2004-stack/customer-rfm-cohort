-- =========================================================
-- BƯỚC 5. BẢNG SỐ LIỆU CHÍNH (dùng trong README)
-- Chạy: mysql -u root -p --default-character-set=utf8mb4 --table < sql/05_key_metrics.sql
-- =========================================================
USE customer_analytics;
SET NAMES utf8mb4;

SELECT 'Số khách có đơn hoàn thành'               AS chi_so, COUNT(*) AS gia_tri FROM customer_rfm
UNION ALL
SELECT 'Số đơn hoàn thành (sau làm sạch)', COUNT(*) FROM orders_clean
UNION ALL
SELECT 'Doanh thu thuần (triệu VND)', ROUND(SUM(net_value) / 1000000, 1) FROM orders_clean
UNION ALL
SELECT 'Giá trị đơn trung bình (nghìn VND)', ROUND(SUM(net_value) / COUNT(*) / 1000, 0) FROM orders_clean
UNION ALL
SELECT 'Tỷ lệ khách mua từ 2 đơn (%)', ROUND(100.0 * SUM(frequency >= 2) / COUNT(*), 1) FROM customer_rfm
UNION ALL
SELECT 'Doanh thu từ khách mua từ 2 đơn (%)',
       ROUND(100.0 * SUM(CASE WHEN frequency >= 2 THEN monetary ELSE 0 END) / SUM(monetary), 1) FROM customer_rfm
UNION ALL
SELECT 'Champions + Trung thành: % khách',
       ROUND(100.0 * SUM(segment IN ('1 Champions', '2 Trung thành')) / COUNT(*), 1) FROM customer_rfm
UNION ALL
SELECT 'Champions + Trung thành: % doanh thu',
       ROUND(100.0 * SUM(CASE WHEN segment IN ('1 Champions', '2 Trung thành') THEN monetary ELSE 0 END) / SUM(monetary), 1)
FROM customer_rfm;
