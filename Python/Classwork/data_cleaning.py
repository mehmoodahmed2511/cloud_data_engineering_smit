import pandas as pd
import numpy as np

df = pd.read_csv("brewbuzz_raw_orders.csv")
print("Dataframe Shape:", df.shape)
print(df.columns)

#checking dataframe info
df.info()
df.shape
#checking for null values
print(df.isnull().sum())

#Creating a dataframe for missing count and missing percentage to compare with after data cleaning
audit = pd.DataFrame({
    "missing_count": df.isnull().sum(),
    "missing_percentage": (df.isnull().sum() / len(df) * 100).round(2)
})
print("Missing Values:", audit[audit.missing_count > 0])
print("Exact Duplicate Rows:", df.duplicated().sum())

#removing duplicated rows
df.duplicated().sum()
df = df.drop_duplicates()
print(df)

# checking datatypes of df
df.info()
#adding 3 following columns with correct datatypes
df["quantity_num"] = pd.to_numeric(df["quantity"], errors = "coerce")
df["unit_price_float"] = pd.to_numeric(df["unit_price"], errors = "coerce")
df["order_date_dt"] = pd.to_datetime(df["order_date"], errors = "coerce")


