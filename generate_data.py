"""Generates the synthetic 'Aegean Brew Co.' dataset with deliberate data-quality issues."""
import numpy as np, pandas as pd, sqlite3, os, sys

rng = np.random.default_rng(42)
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(f"{OUT}/data", exist_ok=True)

# ---------- products ----------
products = [
    ("Coffee Beans", "Ethiopia Yirgacheffe 250g", 12.5, 5.1), ("Coffee Beans", "Colombia Huila 250g", 11.0, 4.4),
    ("Coffee Beans", "Brazil Santos 1kg", 32.0, 14.0), ("Coffee Beans", "House Espresso Blend 500g", 17.5, 7.0),
    ("Coffee Beans", "Decaf Swiss Water 250g", 13.0, 5.6), ("Coffee Beans", "Kenya AA 250g", 14.5, 6.3),
    ("Tea", "Greek Mountain Tea 50g", 6.5, 2.0), ("Tea", "Chamomile 50g", 5.0, 1.5),
    ("Tea", "Earl Grey 100g", 7.5, 2.6), ("Tea", "Matcha Ceremonial 30g", 24.0, 11.0),
    ("Equipment", "Pour-over Dripper", 22.0, 8.0), ("Equipment", "Manual Grinder", 49.0, 21.0),
    ("Equipment", "French Press 1L", 35.0, 14.0), ("Equipment", "Moka Pot 6-cup", 29.0, 11.5),
    ("Equipment", "Electric Gooseneck Kettle", 79.0, 38.0), ("Equipment", "Digital Scale", 25.0, 9.5),
    ("Accessories", "Paper Filters x100", 4.5, 1.2), ("Accessories", "Ceramic Mug", 12.0, 4.0),
    ("Accessories", "Travel Tumbler", 19.0, 7.5), ("Accessories", "Gift Card 25 EUR", 25.0, 25.0),
]
prod = pd.DataFrame(products, columns=["category", "product_name", "unit_price", "unit_cost"])
prod.insert(0, "product_id", range(101, 101 + len(prod)))
popularity = np.array([9, 8, 5, 10, 3, 6, 6, 4, 5, 3, 4, 3, 3, 4, 2, 3, 8, 6, 4, 2], float)
popularity /= popularity.sum()

# ---------- customers ----------
N_CUST = 2500
countries = ["Greece", "Cyprus", "Germany", "Italy", "France", "Netherlands", "Spain", "Austria"]
c_w = [0.42, 0.08, 0.15, 0.10, 0.09, 0.06, 0.06, 0.04]
channels = ["Organic Search", "Paid Social", "Email", "Referral", "Paid Search"]
ch_w = [0.30, 0.25, 0.15, 0.12, 0.18]
signup = pd.to_datetime("2024-01-01") + pd.to_timedelta((rng.beta(1.3, 1.0, N_CUST) * 725).astype(int), unit="D")
cust = pd.DataFrame({
    "customer_id": range(1, N_CUST + 1),
    "signup_date": signup,
    "country": rng.choice(countries, N_CUST, p=c_w),
    "acquisition_channel": rng.choice(channels, N_CUST, p=ch_w),
    "birth_year": rng.integers(1955, 2006, N_CUST).astype(float),
})
# loyalty by channel: referral/email customers buy more often
ch_mult = {"Organic Search": 1.0, "Paid Social": 0.6, "Email": 1.4, "Referral": 1.6, "Paid Search": 0.8}
cust["rate_"] = cust["acquisition_channel"].map(ch_mult) * rng.gamma(1.2, 1.0, N_CUST)

# ---------- orders ----------
END = pd.Timestamp("2025-12-31")
orders, items = [], []
oid = 50001
for r in cust.itertuples():
    days_active = (END - r.signup_date).days
    if days_active <= 0:
        continue
    n = rng.poisson(r.rate_ * days_active / 120)
    if rng.random() < 0.8:
        n = max(n, 1)  # most signups place at least one order
    first = r.signup_date + pd.Timedelta(days=int(rng.integers(0, 10)))
    dates = [first] + list(r.signup_date + pd.to_timedelta(rng.integers(0, days_active, max(n - 1, 0)), unit="D"))
    for d in sorted(dates)[:n]:
        # seasonality: push some Nov/Dec boost by duplication chance handled below
        status = rng.choice(["Delivered", "Delivered", "Delivered", "Delivered", "Delivered", "Delivered",
                             "Delivered", "Delivered", "Cancelled", "Returned"], p=[0.1] * 10)
        orders.append((oid, r.customer_id, d + pd.Timedelta(minutes=int(rng.integers(0, 1440))), status,
                       rng.choice(["Card", "PayPal", "Bank Transfer"], p=[0.6, 0.32, 0.08])))
        k = rng.choice([1, 1, 1, 2, 2, 3, 4])
        for pid in rng.choice(prod.product_id, k, replace=False, p=popularity):
            qty = int(rng.choice([1, 1, 1, 2, 2, 3]))
            price = float(prod.loc[prod.product_id == pid, "unit_price"].iloc[0])
            disc = rng.choice([0, 0, 0, 0, 0.1, 0.15, 0.2])
            if d.month in (11, 12) and rng.random() < 0.4:
                disc = 0.2  # holiday promo
            items.append((oid, int(pid), qty, price, float(disc)))
        oid += 1

# holiday seasonality: extra orders in Nov/Dec
extra = []
for o in orders:
    if o[2].month in (11, 12) and rng.random() < 0.9:
        extra.append(o)
for o in extra:
    new_date = o[2] + pd.Timedelta(days=int(rng.integers(1, 20)))
    if new_date > END:
        continue
    orders.append((oid, o[1], new_date, "Delivered", o[4]))
    for pid in rng.choice(prod.product_id, int(rng.choice([1, 2, 2, 3])), replace=False, p=popularity):
        items.append((oid, int(pid), int(rng.choice([1, 1, 2])), 0.0, 0.2))
    oid += 1

ord_df = pd.DataFrame(orders, columns=["order_id", "customer_id", "order_ts", "status", "payment_method"])
ord_df = ord_df[ord_df.order_ts <= END].sort_values("order_ts").reset_index(drop=True)
it = pd.DataFrame(items, columns=["order_id", "product_id", "quantity", "unit_price", "discount"])
it = it[it.order_id.isin(ord_df.order_id)]
# fill the 0.0 placeholder prices
it["unit_price"] = np.where(it.unit_price == 0, it.product_id.map(prod.set_index("product_id").unit_price), it.unit_price)
# 2025 price increase on beans (+8%)
ts = it.order_id.map(ord_df.set_index("order_id").order_ts)
beans = it.product_id.isin(prod[prod.category == "Coffee Beans"].product_id)
it.loc[beans & (ts >= "2025-03-01"), "unit_price"] = (it.loc[beans & (ts >= "2025-03-01"), "unit_price"] * 1.08).round(2)
it.insert(0, "item_id", range(1, len(it) + 1))

# ---------- inject messiness (documented in solutions only) ----------
# 1. inconsistent country spellings / whitespace
idx = rng.choice(cust.index, 120, replace=False)
cust.loc[idx[:40], "country"] = cust.loc[idx[:40], "country"].str.upper()
cust.loc[idx[40:80], "country"] = " " + cust.loc[idx[40:80], "country"] + " "
cust.loc[cust.index.isin(idx[80:]) & (cust.country == "Greece"), "country"] = "GR"
cust.loc[cust.index.isin(idx[80:]) & (cust.country == "Germany"), "country"] = "Deutschland"
# 2. missing birth years + impossible ones
cust.loc[rng.choice(cust.index, 180, replace=False), "birth_year"] = np.nan
cust.loc[rng.choice(cust.index, 6, replace=False), "birth_year"] = 1900
# 3. missing acquisition channel
cust.loc[rng.choice(cust.index, 60, replace=False), "acquisition_channel"] = None
# 4. duplicate customer rows (exact)
cust = pd.concat([cust, cust.sample(25, random_state=1)]).sort_values("customer_id").reset_index(drop=True)
# 5. duplicate order_items rows (double ingest)
it = pd.concat([it, it.sample(90, random_state=2)]).sort_values("item_id").reset_index(drop=True)
# 6. negative / zero quantities
it.loc[rng.choice(it.index, 15, replace=False), "quantity"] = 0
it.loc[rng.choice(it.index, 10, replace=False), "quantity"] = -1
# 7. test orders from internal account
test_orders = pd.DataFrame({"order_id": [99001, 99002, 99003], "customer_id": [0, 0, 0],
                            "order_ts": pd.to_datetime(["2025-06-02 10:00", "2025-06-02 10:05", "2025-09-15 14:30"]),
                            "status": "Delivered", "payment_method": "Card"})
ord_df = pd.concat([ord_df, test_orders], ignore_index=True)
it = pd.concat([it, pd.DataFrame({"item_id": [900001, 900002, 900003], "order_id": [99001, 99002, 99003],
                                  "product_id": [115, 115, 112], "quantity": [50, 50, 40],
                                  "unit_price": [79.0, 79.0, 49.0], "discount": [0, 0, 0]})], ignore_index=True)
# 8. order timestamps as mixed-format strings in CSV
ord_df["order_ts"] = ord_df.order_ts.dt.strftime("%Y-%m-%d %H:%M:%S")
mixed = rng.choice(ord_df.index, 300, replace=False)
ord_df.loc[mixed, "order_ts"] = pd.to_datetime(ord_df.loc[mixed, "order_ts"]).dt.strftime("%d/%m/%Y %H:%M")

cust = cust.drop(columns="rate_")
cust["signup_date"] = cust.signup_date.dt.strftime("%Y-%m-%d")
cust["birth_year"] = cust.birth_year.astype("Int64")

cust.to_csv(f"{OUT}/data/customers.csv", index=False)
prod.to_csv(f"{OUT}/data/products.csv", index=False)
ord_df.to_csv(f"{OUT}/data/orders.csv", index=False)
it.to_csv(f"{OUT}/data/order_items.csv", index=False)

db = f"{OUT}/data/aegean_brew.db"
if os.path.exists(db):
    os.remove(db)
con = sqlite3.connect(db)
for name, df in [("customers", cust), ("products", prod), ("orders", ord_df), ("order_items", it)]:
    df.to_sql(name, con, index=False)
con.close()
print(len(cust), len(prod), len(ord_df), len(it))
