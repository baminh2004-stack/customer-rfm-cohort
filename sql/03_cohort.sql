-- =========================================================
-- BƯỚC 3. PHÂN TÍCH COHORT
-- Cohort = tháng mua hàng ĐẦU TIÊN (đơn hoàn thành) của khách.
-- M0 = tháng đầu, M1 = tháng kế tiếp... Tỷ lệ giữ chân Mk = % khách của cohort còn mua ở tháng thứ k.
-- Dữ liệu kết thúc 12/2025: ô nào chưa đủ thời gian theo dõi để NULL.
-- Chạy: mysql -u root -p --default-character-set=utf8mb4 --table < sql/03_cohort.sql
-- =========================================================
USE customer_analytics;
SET NAMES utf8mb4;

-- 3.1 Bảng khách: cohort, kênh thu hút, có dùng voucher ở đơn đầu không
DROP TABLE IF EXISTS customer_cohort;

CREATE TABLE customer_cohort AS
SELECT f.customer_id,
       f.cohort_idx,
       f.cohort,
       c.acquisition_channel,
       c.city,
       c.age_group,
       (SELECT MAX(o.voucher_used) FROM orders_clean o
        WHERE o.customer_id = f.customer_id AND o.month_idx = f.cohort_idx) AS voucher_first
FROM (SELECT customer_id, MIN(month_idx) AS cohort_idx, MIN(ym) AS cohort
      FROM orders_clean GROUP BY customer_id) f
JOIN customers c ON c.customer_id = f.customer_id;

CREATE INDEX idx_cc ON customer_cohort (customer_id);

-- Bảng hoạt động: mỗi khách x mỗi tháng có mua (dùng chung cho các truy vấn dưới)
DROP TABLE IF EXISTS customer_activity;

CREATE TABLE customer_activity AS
SELECT DISTINCT o.customer_id, cc.cohort, cc.cohort_idx,
       o.month_idx - cc.cohort_idx AS m
FROM orders_clean o
JOIN customer_cohort cc ON cc.customer_id = o.customer_id;

-- 3.2 Ma trận giữ chân (%) theo cohort
--     2025*12+12 = chỉ số của tháng 12/2025 (tháng cuối có dữ liệu)
SELECT cohort,
       SUM(m = 0) AS so_khach,
       CASE WHEN MIN(cohort_idx) + 1  <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 1)  / SUM(m = 0), 1) END AS M1,
       CASE WHEN MIN(cohort_idx) + 2  <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 2)  / SUM(m = 0), 1) END AS M2,
       CASE WHEN MIN(cohort_idx) + 3  <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 3)  / SUM(m = 0), 1) END AS M3,
       CASE WHEN MIN(cohort_idx) + 6  <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 6)  / SUM(m = 0), 1) END AS M6,
       CASE WHEN MIN(cohort_idx) + 9  <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 9)  / SUM(m = 0), 1) END AS M9,
       CASE WHEN MIN(cohort_idx) + 12 <= 2025*12+12 THEN ROUND(100.0 * SUM(m = 12) / SUM(m = 0), 1) END AS M12
FROM customer_activity
GROUP BY cohort
ORDER BY cohort;

-- 3.3 Đường giữ chân trung bình (có trọng số), chỉ tính cohort đã đủ thời gian theo dõi
SELECT k                                                       AS thang_thu,
       SUM(so_khach_con_mua)                                   AS khach_con_mua,
       SUM(co_so)                                              AS khach_co_so,
       ROUND(100.0 * SUM(so_khach_con_mua) / SUM(co_so), 1)    AS ty_le_giu_chan_pct
FROM (SELECT b.k, a.cohort,
             SUM(a.m = b.k) AS so_khach_con_mua,
             SUM(a.m = 0)   AS co_so
      FROM customer_activity a
      JOIN (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 6
            UNION ALL SELECT 9 UNION ALL SELECT 12) b
      WHERE a.cohort_idx + b.k <= 2025*12+12
      GROUP BY b.k, a.cohort) t
GROUP BY k
ORDER BY k;

-- 3.4 Giữ chân và giá trị theo KÊNH THU HÚT
--     Chỉ dùng cohort 01/2024 - 06/2025 để mọi khách đều có đủ 6 tháng theo dõi
WITH k AS (
  SELECT cc.customer_id, cc.acquisition_channel,
         MAX(a.m BETWEEN 1 AND 3) AS mua_lai_3_thang,
         MAX(a.m BETWEEN 1 AND 6) AS mua_lai_6_thang
  FROM customer_cohort cc
  JOIN customer_activity a ON a.customer_id = cc.customer_id
  WHERE cc.cohort_idx <= 2025*12+6
  GROUP BY cc.customer_id, cc.acquisition_channel
), v AS (
  SELECT o.customer_id, SUM(o.net_value) AS dt_6_thang
  FROM orders_clean o
  JOIN customer_cohort cc ON cc.customer_id = o.customer_id
  WHERE cc.cohort_idx <= 2025*12+6
    AND o.month_idx - cc.cohort_idx BETWEEN 0 AND 6
  GROUP BY o.customer_id
)
SELECT k.acquisition_channel                                  AS kenh,
       COUNT(*)                                               AS so_khach,
       ROUND(100.0 * SUM(k.mua_lai_3_thang) / COUNT(*), 1)    AS mua_lai_trong_3_thang_pct,
       ROUND(100.0 * SUM(k.mua_lai_6_thang) / COUNT(*), 1)    AS mua_lai_trong_6_thang_pct,
       ROUND(SUM(v.dt_6_thang) / COUNT(*), -3)                AS dt_6_thang_moi_khach_vnd
FROM k JOIN v ON v.customer_id = k.customer_id
GROUP BY k.acquisition_channel
ORDER BY mua_lai_trong_6_thang_pct DESC;

-- 3.5 Giữ chân theo việc dùng VOUCHER ở đơn đầu tiên (cùng điều kiện 3.4)
SELECT CASE WHEN cc.voucher_first = 1 THEN 'Có voucher' ELSE 'Không voucher' END AS don_dau,
       COUNT(DISTINCT cc.customer_id)                                            AS so_khach,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.m BETWEEN 1 AND 6 THEN a.customer_id END)
                   / COUNT(DISTINCT cc.customer_id), 1)                          AS mua_lai_trong_6_thang_pct
FROM customer_cohort cc
JOIN customer_activity a ON a.customer_id = cc.customer_id
WHERE cc.cohort_idx <= 2025*12+6
GROUP BY CASE WHEN cc.voucher_first = 1 THEN 'Có voucher' ELSE 'Không voucher' END;

-- 3.6 Có điều gì thay đổi từ 07/2025 (tăng phí vận chuyển)?
--     So tỷ lệ quay lại tháng kế tiếp (M1) của CÙNG THÁNG cohort giữa 2024 và 2025.
--     Cohort T1-T5: tháng M1 rơi vào trước 07/2025. Cohort T6-T11: tháng M1 rơi vào từ 07/2025.
--     So cùng tháng giúp loại bỏ ảnh hưởng mùa vụ.
WITH r AS (
  SELECT cohort,
         MONTH(CONCAT(cohort, '-01')) AS thang,
         LEFT(cohort, 4)              AS nam,
         SUM(m = 0)                   AS co_so,
         SUM(m = 1)                   AS quay_lai_m1
  FROM customer_activity
  WHERE cohort <= '2025-11'
  GROUP BY cohort
)
SELECT thang                                                                         AS thang_cohort,
       MAX(CASE WHEN nam = '2024' THEN ROUND(100.0 * quay_lai_m1 / co_so, 1) END)    AS m1_2024_pct,
       MAX(CASE WHEN nam = '2025' THEN ROUND(100.0 * quay_lai_m1 / co_so, 1) END)    AS m1_2025_pct,
       CASE WHEN thang <= 5 THEN 'M1 trước 07/2025' ELSE 'M1 từ 07/2025' END         AS ghi_chu
FROM r
WHERE thang <= 11
GROUP BY thang
ORDER BY thang;

-- 3.7 Tóm tắt 3.6 (có trọng số theo số khách)
WITH r AS (
  SELECT LEFT(cohort, 4) AS nam,
         CASE WHEN MONTH(CONCAT(cohort, '-01')) <= 5 THEN 'Cohort T1-T5 (M1 trước 07/2025)'
              ELSE 'Cohort T6-T11 (M1 từ 07/2025)' END AS nhom,
         SUM(m = 0) AS co_so, SUM(m = 1) AS quay_lai_m1
  FROM customer_activity
  WHERE cohort <= '2025-11' AND MONTH(CONCAT(cohort, '-01')) <= 11
  GROUP BY cohort
)
SELECT nhom,
       ROUND(100.0 * SUM(CASE WHEN nam = '2024' THEN quay_lai_m1 END) / SUM(CASE WHEN nam = '2024' THEN co_so END), 1) AS m1_2024_pct,
       ROUND(100.0 * SUM(CASE WHEN nam = '2025' THEN quay_lai_m1 END) / SUM(CASE WHEN nam = '2025' THEN co_so END), 1) AS m1_2025_pct
FROM r
GROUP BY nhom
ORDER BY nhom;
