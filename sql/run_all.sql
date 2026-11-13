-- Chạy bước 2 -> 5 một lần (sau khi đã nạp dữ liệu bằng 01_load_data.sql).
-- Đứng ở thư mục gốc repo:
--   mysql -u root -p --default-character-set=utf8mb4 --table < sql/run_all.sql > ket_qua.txt
source sql/02_clean.sql
source sql/03_cohort.sql
source sql/04_rfm.sql
source sql/05_key_metrics.sql
