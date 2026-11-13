"""
Sinh dữ liệu GIẢ LẬP cho một cửa hàng thương mại điện tử (mỹ phẩm & thời trang) tại Việt Nam.
Kỳ dữ liệu: 01/2024 - 12/2025. Chạy: python scripts/generate_data.py
Kết quả: data/customers.csv, data/orders.csv (cố định seed nên chạy lại ra y hệt).

Các "kịch bản" được cài sẵn để phân tích có điều để phát hiện:
  - Khách đến từ kênh Giới thiệu / Tự nhiên quay lại nhiều hơn kênh quảng cáo trả phí.
  - Khách có đơn đầu dùng voucher giảm giá sâu ít quay lại hơn.
  - Mùa cao điểm 11.11, 12.12 và trước Tết.
  - Từ 07/2025 tăng phí vận chuyển -> tần suất mua lại của mọi khách giảm.
  - Một ít lỗi dữ liệu: đơn trùng, đơn test giá trị 0, đơn hủy/hoàn.
"""
import numpy as np, pandas as pd
from pathlib import Path

rng = np.random.default_rng(2026)
OUT = Path(__file__).resolve().parents[1] / "data"
OUT.mkdir(exist_ok=True)

months = pd.period_range("2024-01", "2025-12", freq="M")
season = {1: 1.15, 2: 1.10, 3: 0.90, 4: 0.90, 5: 0.95, 6: 0.95, 7: 0.90, 8: 0.95,
          9: 1.00, 10: 1.05, 11: 1.45, 12: 1.40}

channels = ["Facebook Ads", "TikTok Shop", "Google Search", "Giới thiệu", "Tự nhiên"]
ch_p     = [0.30, 0.26, 0.19, 0.10, 0.15]
ch_rep   = {"Facebook Ads": 0.26, "TikTok Shop": 0.20, "Google Search": 0.32,
            "Giới thiệu": 0.48, "Tự nhiên": 0.40}          # xác suất mua lại / tháng (gốc)
ch_churn = {"Facebook Ads": 0.11, "TikTok Shop": 0.14, "Google Search": 0.09,
            "Giới thiệu": 0.05, "Tự nhiên": 0.07}          # xác suất rời bỏ / tháng
voucher_p = {"Facebook Ads": 0.45, "TikTok Shop": 0.60, "Google Search": 0.30,
             "Giới thiệu": 0.25, "Tự nhiên": 0.15}
cities, city_p = ["TP.HCM", "Hà Nội", "Đà Nẵng", "Cần Thơ", "Hải Phòng", "Tỉnh khác"], \
                 [0.37, 0.31, 0.07, 0.05, 0.05, 0.15]
age_groups, age_p = ["18-24", "25-34", "35-44", "45+"], [0.33, 0.41, 0.18, 0.08]

# --- khách hàng mới mỗi tháng: tăng dần + mùa vụ ---
new_per_month = {m: int(round((125 + 5 * i) * season[m.month] * rng.uniform(0.92, 1.08)))
                 for i, m in enumerate(months)}

customers, orders = [], []
cid = 10000
for m, n_new in new_per_month.items():
    for _ in range(n_new):
        cid += 1
        ch = rng.choice(channels, p=ch_p)
        first_day = m.start_time + pd.Timedelta(days=int(rng.integers(0, m.days_in_month)))
        voucher = rng.random() < voucher_p[ch]
        city = rng.choice(cities, p=city_p)
        customers.append(dict(customer_id=cid, signup_date=first_day.date(), city=city,
                              age_group=rng.choice(age_groups, p=age_p), acquisition_channel=ch))
        taste = rng.lognormal(0, 0.35)                    # khách "chịu chi" khác nhau
        rep = ch_rep[ch] * (0.6 if voucher else 1.0) * rng.lognormal(0, 0.45)
        churn = ch_churn[ch] * (1.5 if voucher else 1.0)

        def add_order(day, first=False):
            base = rng.lognormal(np.log(380_000), 0.55) * taste * (1.12 if not first else 1.0)
            disc = 0
            if first and voucher:
                disc = round(base * rng.uniform(0.25, 0.4), -3)
            orders.append(dict(customer_id=cid, order_date=day,
                               items=int(max(1, rng.poisson(1.6 * taste))),
                               gross_value=round(base, -3), discount=disc,
                               payment_method=rng.choice(["COD", "Ví điện tử", "Thẻ"], p=[0.48, 0.37, 0.15]),
                               voucher_used=int(first and voucher)))

        add_order(pd.Timestamp(first_day) + pd.Timedelta(hours=int(rng.integers(7, 23))), first=True)
        for m2 in months[months > m]:
            if rng.random() < churn:
                break
            p = rep * season[m2.month] * (0.72 if m2 >= pd.Period("2025-07", "M") else 1.0)
            for _ in range(rng.poisson(p)):
                day = m2.start_time + pd.Timedelta(days=int(rng.integers(0, m2.days_in_month)),
                                                   hours=int(rng.integers(7, 23)))
                add_order(day)

cust = pd.DataFrame(customers)
od = pd.DataFrame(orders)
od["order_date"] = pd.to_datetime(od["order_date"])
od = od.sort_values(["order_date", "customer_id"]).reset_index(drop=True)
od.insert(0, "order_id", [f"DH{100000 + i}" for i in range(len(od))])
od["status"] = rng.choice(["Hoàn thành", "Đã hủy", "Hoàn trả"], size=len(od), p=[0.90, 0.065, 0.035])
od[["gross_value", "discount"]] = od[["gross_value", "discount"]].astype(int)
od["net_value"] = od["gross_value"] - od["discount"]

# --- lỗi dữ liệu cài sẵn ---
dups = od.sample(70, random_state=1)                          # đơn bị ghi trùng
tests = od.sample(25, random_state=2).copy()                   # đơn test giá trị 0
tests["order_id"] = [f"TEST{i:03d}" for i in range(len(tests))]
tests[["gross_value", "discount", "net_value"]] = 0
od = pd.concat([od, dups, tests]).sort_values("order_date").reset_index(drop=True)

od["order_date"] = od["order_date"].dt.strftime("%Y-%m-%d %H:%M:%S")
cols = ["order_id", "customer_id", "order_date", "status", "items", "gross_value",
        "discount", "net_value", "voucher_used", "payment_method"]
od[cols].to_csv(OUT / "orders.csv", index=False, encoding="utf-8")
cust.to_csv(OUT / "customers.csv", index=False, encoding="utf-8")
print(f"customers: {len(cust):,}  orders: {len(od):,}")
