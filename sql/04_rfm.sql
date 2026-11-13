-- =========================================================
-- BƯỚC 4. PHÂN NHÓM KHÁCH HÀNG RFM
-- Ngày chốt dữ liệu: 2026-01-01 (ngày sau đơn cuối cùng)
--   R (Recency)   = số ngày từ đơn gần nhất đến ngày chốt  -> càng nhỏ càng tốt
--   F (Frequency) = số đơn hoàn thành
--   M (Monetary)  = tổng tiền khách thực trả (VND)
-- Chấm điểm 1-5:
--   R, M: NTILE(5) chia đều 5 nhóm (5 = tốt nhất)
--   F   : ngưỡng cố định vì phần lớn khách chỉ có 1-2 đơn (NTILE sẽ chia ngẫu nhiên các khách bằng nhau)
--         1 đơn = 1 | 2 đơn = 2 | 3 đơn = 3 | 4-5 đơn = 4 | 6+ đơn = 5
-- Chạy: mysql -u root -p --default-character-set=utf8mb4 --table < sql/04_rfm.sql
-- =========================================================
USE customer_analytics;
SET NAMES utf8mb4;

DROP TABLE IF EXISTS customer_rfm;

CREATE TABLE customer_rfm AS
SELECT s.*,
       CASE
         WHEN s.r_score >= 4 AND s.f_score >= 4 THEN '1 Champions'
         WHEN (s.r_score >= 4 AND s.f_score = 3)
           OR (s.r_score = 3 AND s.f_score >= 3) THEN '2 Trung thành'
         WHEN s.r_score >= 4 AND s.f_score <= 2  THEN '3 Mới / Tiềm năng'
         WHEN s.r_score = 3 AND s.f_score <= 2   THEN '4 Cần chú ý'
         WHEN s.r_score <= 2 AND s.f_score >= 4  THEN '5 Không thể mất'
         WHEN s.r_score <= 2 AND s.f_score = 3   THEN '6 Có nguy cơ rời bỏ'
         ELSE                                         '7 Đã rời bỏ'
       END AS segment
FROM (
  SELECT b.*,
         NTILE(5) OVER (ORDER BY b.recency_days DESC, b.customer_id) AS r_score,
         CASE WHEN b.frequency >= 6 THEN 5
              WHEN b.frequency >= 4 THEN 4
              WHEN b.frequency = 3  THEN 3
              WHEN b.frequency = 2  THEN 2
              ELSE 1 END                                             AS f_score,
         NTILE(5) OVER (ORDER BY b.monetary, b.customer_id)          AS m_score
  FROM (
    SELECT o.customer_id,
           cc.acquisition_channel,
           cc.city,
           cc.cohort                                   AS first_month,
           DATE(MAX(o.order_date))                     AS last_order_date,
           DATEDIFF('2026-01-01', MAX(o.order_date))   AS recency_days,
           COUNT(*)                                    AS frequency,
           SUM(o.net_value)                            AS monetary,
           ROUND(SUM(o.net_value) / COUNT(*), 0)       AS avg_order_value
    FROM orders_clean o
    JOIN customer_cohort cc ON cc.customer_id = o.customer_id
    GROUP BY o.customer_id, cc.acquisition_channel, cc.city, cc.cohort
  ) b
) s;

-- 4.1 Kiểm chứng: mỗi khách 1 dòng, tổng tiền khớp bảng đơn sạch
SELECT (SELECT COUNT(*) FROM customer_rfm)                    AS so_khach_rfm,
       (SELECT COUNT(DISTINCT customer_id) FROM orders_clean) AS so_khach_co_don,
       (SELECT SUM(monetary) FROM customer_rfm)               AS tong_tien_rfm,
       (SELECT SUM(net_value) FROM orders_clean)              AS tong_tien_don,
       CASE WHEN (SELECT COUNT(*) FROM customer_rfm) = (SELECT COUNT(DISTINCT customer_id) FROM orders_clean)
             AND (SELECT SUM(monetary) FROM customer_rfm) = (SELECT SUM(net_value) FROM orders_clean)
            THEN 'OK' ELSE 'SAI' END                         AS ket_qua;

-- 4.2 Ngưỡng của điểm R (để giải thích: R=5 nghĩa là mua trong bao nhiêu ngày gần đây)
SELECT r_score, MIN(recency_days) AS tu_ngay, MAX(recency_days) AS den_ngay, COUNT(*) AS so_khach
FROM customer_rfm
GROUP BY r_score
ORDER BY r_score DESC;

-- 4.3 Hồ sơ từng nhóm khách
SELECT segment,
       COUNT(*)                                                     AS so_khach,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_khach,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_doanh_thu,
       ROUND(AVG(recency_days), 0)                                  AS recency_tb_ngay,
       ROUND(AVG(frequency), 1)                                     AS so_don_tb,
       ROUND(SUM(monetary) / COUNT(*), -3)                          AS chi_tieu_tb_vnd
FROM customer_rfm
GROUP BY segment
ORDER BY segment;

-- 4.4 Kênh nào mang về khách giá trị? % khách thuộc nhóm Champions + Trung thành theo kênh
SELECT acquisition_channel                                                         AS kenh,
       COUNT(*)                                                                    AS so_khach,
       ROUND(100.0 * SUM(segment IN ('1 Champions', '2 Trung thành')) / COUNT(*), 1) AS pct_champions_trung_thanh,
       ROUND(100.0 * SUM(segment = '7 Đã rời bỏ') / COUNT(*), 1)                   AS pct_da_roi_bo,
       ROUND(SUM(monetary) / COUNT(*), -3)                                         AS chi_tieu_tb_vnd
FROM customer_rfm
GROUP BY acquisition_channel
ORDER BY pct_champions_trung_thanh DESC;

-- 4.5 Danh sách ưu tiên chăm sóc: 15 khách "Không thể mất" chi nhiều nhất
SELECT customer_id, acquisition_channel, city, last_order_date, recency_days, frequency, monetary
FROM customer_rfm
WHERE segment = '5 Không thể mất'
ORDER BY monetary DESC, customer_id
LIMIT 15;

-- 4.6 Xuất bảng RFM (Workbench: bỏ giới hạn 1000 dòng -> Export -> CSV)
SELECT customer_id, acquisition_channel, city, first_month, last_order_date,
       recency_days, frequency, monetary, avg_order_value,
       r_score, f_score, m_score, CONCAT(r_score, f_score, m_score) AS rfm_code, segment
FROM customer_rfm
ORDER BY customer_id;
