import csv
import os
import snowflake.connector

ACCOUNT   = "GOERPYE-DR90600"
USER      = "GHADAAB"
PASSWORD  = os.environ.get("SNOWFLAKE_PASSWORD", "${SNOWFLAKE_PASSWORD}")
ROLE      = "ACCOUNTADMIN"
WAREHOUSE = "TRANSFORM_WH"
DATABASE  = "DWH"
SCHEMA    = "RAW"
TABLE     = "ORDERS"

CSV_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "orders.csv")


def connect():
    return snowflake.connector.connect(
        account=ACCOUNT,
        user=USER,
        password=PASSWORD,
        role=ROLE,
        warehouse=WAREHOUSE,
        database=DATABASE,
        schema=SCHEMA,
    )


def setup(cur):
    cur.execute(f"CREATE DATABASE IF NOT EXISTS {DATABASE}")
    cur.execute(f"CREATE SCHEMA IF NOT EXISTS {DATABASE}.{SCHEMA}")
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {TABLE} (
            order_id    INTEGER,
            customer_id VARCHAR(50),
            order_date  DATE,
            amount      FLOAT,
            status      VARCHAR(50),
            country     VARCHAR(10)
        )
    """)


def load(cur):
    cur.execute(f"TRUNCATE TABLE {TABLE}")
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        rows = [
            (int(r["order_id"]), r["customer_id"], r["order_date"],
             float(r["amount"]), r["status"], r["country"])
            for r in csv.DictReader(f)
        ]
    cur.executemany(
        f"INSERT INTO {TABLE} VALUES (%s, %s, %s, %s, %s, %s)",
        rows,
    )
    return len(rows)


def main():
    conn = connect()
    cur = conn.cursor()
    try:
        setup(cur)
        n = load(cur)
        print(f"[OK] {n} lignes chargées dans {DATABASE}.{SCHEMA}.{TABLE}")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
