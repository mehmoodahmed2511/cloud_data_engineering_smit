import pandas as pd

# 1. Load and look. Read the file and check how many rows and columns it has, the first few
# rows, and each column's type.

df = pd.read_csv("supermarket_sales_case_study.csv")
print(df['Payment'].unique())
print(df.shape)             #showing rows and columns
print(df.head(15))          #shwoing first few rows
print(df.dtypes)            #columns datatypes
initial_rows = len(df)

# 2. Audit before you fix. Count the missing values in each column, the rows that are exact
# copies, and the rows that share an Invoice ID. List the distinct values in Gender and
# Payment.

print(df.isnull().sum())      #total mising values in each column
print(f"Total Duplicated Rows: {df.duplicated().sum()}")      #total duplicated rows
print(f"Duplicated Invoice IDs: {df['Invoice ID'].duplicated().sum()}")
print(f"Unique Genders: {df['Gender'].unique()}")       #unique Genders
print(f"Unique Payments: {df['Payment'].unique()}")     #unique payments

# 3. Drop exact duplicates. Rows identical in every column are a resent upload. Remove
# the copies.
df = df.drop_duplicates()       # dropping duplicates
rows_after_step3 = len(df)
print(f"Rows after step 3: {rows_after_step3} Rows_removed: {initial_rows - rows_after_step3}")
# 4. Some IDs appear twice with different Quantity and Total. The later row is a correction, so keep thelast one  

df = df.drop_duplicates(subset=["Invoice ID"], keep="last")   
rows_after_step4 = len(df)
print(f"Rows after step 4: {rows_after_step4} Rows removed: {initial_rows - rows_after_step4}")

# 5. Standardise text columns. Remove extra spaces and lowercase, then map each value to one correct spelling: Male / Female and Cash / Credit card / Ewallet.

df['Gender'] = df['Gender'].str.strip().str.lower().map({
        'male':'Male',
        'female':'Female'
    })
df['Payment'] = df['Payment'].str.strip().str.lower().map({
    'cash':'Cash',
    'ewallet':'Ewallet',
    'credit card':'Credit Card'
})
print(f"Standardized Gender Values: {df['Gender'].unique()}")
print(f"Standardized Payment Values: {df['Payment'].unique()}")

# 6. Fix negative quantities. A minus sign is a typing error. Formula: Quantity = absolute value of Quantity.

print((df['Quantity'] < 0).sum())
print((df['Unit price'] < 0).sum())
print((df['Tax 5%'] < 0).sum())
print((df['Total'] < 0).sum())
print((df['gross margin percentage'] < 0).sum())
print((df['gross income'] < 0).sum())
print((df['Rating'] < 0).sum())

df['Quantity'] = df['Quantity'].abs()

print(df['Date'])

# 7. Parse mixed dates. Dates come in two formats, month/day/year (1/6/2023) and day-month-year (06-01-2023). Try the first, then the second; mark anything else as missing.

date1 = pd.to_datetime(df['Date'], format = '%m/%d/%Y', errors = 'coerce')
date2 = pd.to_datetime(df['Date'], format = '%d/%m/%Y', errors = 'coerce')
df['Date'] = date1.fillna(date2)

# 8. Check Total. Formula: Total = Quantity × Unit price × 1.05 (5% tax). If the file's Total is off by more than 0.50, replace it with the formula's value.
expected_total = df['Quantity'] * df['Unit price'] * 1.05

mask = (df['Total'] - expected_total).abs() > 0.5
df.loc[mask, 'Total'] = expected_total[mask]

# 9. Handle what is still missing. Fill Customer type with "Unknown" and Rating with the median rating. Drop rows with no date, because they cannot be placed in a quarter.
df['Customer type'] = df['Customer type'].fillna('Unknown')
df['Rating'] = df['Rating'].fillna(df['Rating'].median())

df.dropna(subset=['Date'])
rows_after_step9 = len(df)
print(f"Rows after step 9: {rows_after_step9} Rows removed: {initial_rows - rows_after_step9}")

# 10. Keep an audit trail. Write down the row count after each step and how many rows it removed.
# Above audit trial has been applied to each row dropping step


# ANSWERING THE BRIEF

# 1. Add time columns. From Date and Time, make Year, Quarter (e.g. 2023Q1), Day of week and Hour.
df['Date'] = pd.to_datetime(df['Date'])
df['Year'] = df['Date'].dt.year.astype('Int64')
df['Quarter'] = df['Year'].astype(str) + 'Q' + df['Date'].dt.quarter.astype('Int64').astype(str)
df['Day of week'] = df['Date'].dt.day_name()
temp_time = pd.to_datetime(df['Time'], format='mixed')
df['Hour'] = temp_time.dt.hour
df['Time'] = pd.to_datetime(temp_time).dt.strftime('%H:%M:%S')


print(df[['Date', 'Year', 'Quarter', 'Day of week', 'Time', 'Hour']])


# 2. Bucket the trading day. Stores open 10:00–21:00, so use Morning 10–13 (3 hours), Afternoon 13–17 (4 hours) and Evening 17–21 (4 hours). Formula: transactions per hour = transactions in the bucket ÷ hours in the bucket.
def get_time_bucket(hour):
    if 10 <= hour < 13:
        return 'Morning'
    elif 13 <= hour < 17:
        return 'Afternoon'
    elif 17 <= hour < 21:
        return 'Evening'
    else:
        return 'Outside Hours'

df['Time_Bucket'] = df['Hour'].apply(get_time_bucket)

bucket_counts = df['Time_Bucket'].value_counts()

transactions_per_hour = {
    'Morning':(bucket_counts.get('Morning', 0)/3).round(2),     #to remove np.flot64, wrap the calculation into float()
    'Afternoon':(bucket_counts.get('Afternoon', 0)/4).round(2),
    'Evening':(bucket_counts.get('Evening', 0)/4).round(2)
}

print(f"Transactions Per Hour: {transactions_per_hour}")

# 3. Compare against target. Add up revenue per branch per quarter and join it to a small targets table ($100,000 per branch). Formulas: Variance = Revenue − Target; % of target = Revenue ÷ Target × 100; Hit = Revenue is at least the Target.
branch_quarter = df.groupby(['Branch', 'Quarter'])['Total'].sum().round(2).reset_index()
branch_quarter.rename(columns = {'Total':'Revenue'}, inplace = True)

branch_quarter['Target'] = 100000

branch_quarter['Variance'] = branch_quarter['Revenue'] - branch_quarter['Target']
branch_quarter['% of Target'] = ((branch_quarter['Revenue']/branch_quarter['Target']) * 100).round(2)
branch_quarter['Hit'] = branch_quarter['Revenue'] >= branch_quarter['Target']

print(branch_quarter)


# 4. Summarise each branch. Average quarterly revenue, quarters hit out of 8, and best and worst quarter. Formula: YoY growth % = (2024 revenue ÷ 2023 revenue − 1) × 100.
