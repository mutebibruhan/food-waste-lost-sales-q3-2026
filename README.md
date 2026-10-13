# Food Waste and Lost Sales in One Store, Q3 2026

Analysis of daily food operations (waste, stock-outs, and ordering performance) for a single store over Q3 2026 (1 July – 30 September), built with MySQL and Power BI.

## Overview

- **Scope:** 1 store, 43 items, 92 days, 3,894 daily rows
- **Goal:** identify waste drivers, stock-out patterns, and test the store's stated ordering rule (10% buffer weekdays / 30% weekend)
- **Tools:** MySQL for data loading, cleaning, and analysis; Power BI for the dashboard

## Repository contents

| File | Description |
|---|---|
| `food_waste_q3_2026_fullproject.sql` | Full SQL: views, data quality checks, waste/stock-out analysis, ordering rule test, stock replay |
| `daily_food_log.csv` | Daily stock movement log: open, receive, sold, mark out, closing, variance, verification flag, per item per day |
| `items.csv` | Item master: ID, name, category, supply type (daily fresh / frozen), shelf life, cost price |
| `calendar.csv` | Date dimension: day name, weekend flag, holiday flag, month |
| `food_waste_dashboard.pdf` | Power BI dashboard export (static view) |
| `food_waste_dashboard_vid.mp4` | Screen recording of the interactive Power BI dashboard |
| `food_waste_report_final.pdf` | Full written report with findings, methodology, and recommendations |

## Key definitions

- **Mark out:** stock thrown away as expired, valued at cost price. Verified and unverified mark outs both count as waste.
- **Variance:** a unit missing from the physical count. Reported separately, never added to mark out.
- **Waste rate (primary):** mark out cost ÷ cost of stock handled (opening + received).
- **Stock-out day:** for items with shelf life ≥ 2 days, closing = 0 and mark out = 0. For the 1-day item, opening + received > 0 and mark out = 0.

## How to reproduce

1. Load `items.csv`, `calendar.csv`, and `daily_food_log.csv` into a MySQL database.
2. Run `food_waste_q3_2026_fullproject.sql` to create the helper views (`v_food_log`, `v_balance_check`, `v_stockout`, `v_order_test`) and run the analysis queries.
3. Compare output against the **Appendix** table in `food_waste_report_final.pdf`, which lists each key figure and the query that produces it.

## Key findings

- **Waste:** 21,435.83 at cost (3,126 units) over 92 days, ~233/day. Sandwiches and pastry account for 53% of it.
- **Stock-outs:** 671 of 3,894 item-days (17.2%) ended with no stock and no mark out; 19 of these are certain lost sales (no stock all day).
- **Ordering rule:** the stated 10%/30% rule could not be confirmed from the log alone — only 22.4% of orders match it exactly.
- **Alternative rules:** a same-weekday 4-week average order cuts waste ~16% but creates 167 item-days of missed recorded sales — a trade-off, not a clear win.
- **Recommendation:** no rule change yet; run a controlled trial on the highest-waste items and start recording order quantity, noon sales, sell-out time, and defrost data.

Full methodology, data quality checks, and limitations are in `food_waste_report_final.pdf`.
<img width="2182" height="1248" alt="image" src="https://github.com/user-attachments/assets/3361212b-f60a-451a-9c3b-f73df59ad107" />

## Author

Buruhani Mutebi
