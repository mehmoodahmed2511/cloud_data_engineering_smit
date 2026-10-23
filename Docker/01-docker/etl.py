"""Daily sales ETL - reads a CSV, cleans it, loads it into Postgres.

Deliberately plain Python. The point of the lab is the container around it,
not the pandas inside it.
"""
import os
import sys

import pandas as pd
from sqlalchemy import create_engine

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
CSV = os.path.join(DATA_DIR, "sales.csv")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "sales")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")


def clean(df):
    """Drop unusable rows and add a line total."""
    df = df.dropna(subset=["order_id", "date", "city", "qty", "price"])
    df = df[df["qty"] > 0]
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["date"])
    df["total"] = df["qty"] * df["price"]
    return df


def main():
    if not os.path.exists(CSV):
        print(f"ERROR: no input file at {CSV}", file=sys.stderr)
        return 2

    raw = pd.read_csv(CSV)
    print(f"Read {len(raw)} rows from {CSV}")

    df = clean(raw)
    print(f"{len(df)} rows left after cleaning")

    url = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    engine = create_engine(url)
    df.to_sql("sales", engine, if_exists="replace", index=False)

    total = df["total"].sum()
    print(f"Loaded {len(df)} rows, PKR {total:,.0f} in sales")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
