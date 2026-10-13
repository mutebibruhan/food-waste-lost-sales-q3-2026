-- Food waste project (one store, Q3 2026)

-- Helper view: the log with item and calendar details, mark out valued at cost
CREATE VIEW v_food_log AS
SELECT  l.log_date, c.day_name, c.is_weekend, c.is_holiday, c.month_name,
        i.item_id, i.item_name, i.category, i.supply_type, i.shelf_life_days, i.cost_price,
        l.open_qty, l.receive_qty, l.sold_qty, l.mark_out_qty, l.closing_qty,
        l.variance_qty, l.mo_verified,
        l.mark_out_qty * i.cost_price AS mark_out_cost
FROM    daily_food_log l
JOIN    items    i ON i.item_id  = l.item_id
JOIN    calendar c ON c.cal_date = l.log_date;

-- The sheet's own rule: open + receive - sold - mark out + variance = closing.
-- Any row returned here does not balance (typing errors, bad counts...).
CREATE VIEW v_balance_check AS
SELECT  log_date, item_id, open_qty, receive_qty, sold_qty, mark_out_qty, variance_qty, closing_qty,
        (open_qty + receive_qty - sold_qty - mark_out_qty + variance_qty) AS expected_closing,
        closing_qty - (open_qty + receive_qty - sold_qty - mark_out_qty + variance_qty) AS difference
FROM    daily_food_log
WHERE   closing_qty <> open_qty + receive_qty - sold_qty - mark_out_qty + variance_qty;

-- Quick checks after loading
SELECT COUNT(*) AS log_rows, COUNT(DISTINCT item_id) AS items, COUNT(DISTINCT log_date) AS days FROM daily_food_log;
SELECT * FROM v_balance_check;


-- PRE-ANALYSIS DATA QUALITY CHECK

-- 1. Rows that break the sheet's balance rule
SELECT * FROM v_balance_check;

-- 2. Opening stock that doesn't match yesterday's closing
SELECT log_date, item_id, open_qty, prev_closing
FROM (SELECT log_date, item_id, open_qty,
             LAG(closing_qty) OVER (PARTITION BY item_id ORDER BY log_date) AS prev_closing
      FROM daily_food_log) t
WHERE prev_closing IS NOT NULL AND open_qty <> prev_closing;

-- 3. 2-day fresh items: mark out should equal what was left from yesterday
SELECT l.log_date, l.item_id, l.open_qty, l.sold_qty, l.mark_out_qty
FROM daily_food_log l JOIN items i ON i.item_id = l.item_id
WHERE i.supply_type = 'daily_fresh' AND i.shelf_life_days = 2
  AND l.mark_out_qty <> GREATEST(l.open_qty - l.sold_qty, 0);
  
  -- 4. 1-day item (I013): closing should always be 0
SELECT * FROM daily_food_log WHERE item_id = 'I013' AND closing_qty <> 0;

-- 5. Mark outs not ticked the next morning
SELECT * FROM daily_food_log WHERE mo_verified = 0;

-- WASTE MEASUREMENT CHECK
-- RECONCILIATION OF TOTAL WASTAGE AT COST,INCLUDE UNMARKED MARKOUTS AND EXCLUDE VARIENCES

-- Total, in units and cost
SELECT SUM(mark_out_qty) AS units, ROUND(SUM(mark_out_cost),2) AS cost FROM v_food_log;

-- By category
SELECT category, SUM(mark_out_qty) AS units, ROUND(SUM(mark_out_cost),2) AS cost,
       ROUND(100*SUM(mark_out_cost)/SUM(receive_qty*cost_price),1) AS pct_of_received_cost
FROM v_food_log GROUP BY category ORDER BY cost DESC;

-- By item
SELECT item_id, item_name, SUM(mark_out_qty) AS units, ROUND(SUM(mark_out_cost),2) AS cost,
       ROUND(100*SUM(mark_out_qty)/SUM(receive_qty),1) AS pct_units_of_received
FROM v_food_log GROUP BY item_id, item_name ORDER BY cost DESC;

-- Weekday / weekend, and by day name
SELECT IF(is_weekend=1,'Fri-Sun','Mon-Thu') AS part, COUNT(DISTINCT log_date) AS days,
       ROUND(SUM(mark_out_cost),2) AS cost, ROUND(SUM(mark_out_cost)/COUNT(DISTINCT log_date),2) AS cost_per_day
FROM v_food_log GROUP BY is_weekend;

SELECT day_name, COUNT(DISTINCT log_date) AS days, ROUND(SUM(mark_out_cost),2) AS cost,
       ROUND(SUM(mark_out_cost)/COUNT(DISTINCT log_date),2) AS cost_per_day
FROM v_food_log GROUP BY day_name ORDER BY cost_per_day DESC;

-- By month
SELECT month_name, COUNT(DISTINCT log_date) AS days, ROUND(SUM(mark_out_cost),2) AS cost,
       ROUND(100*SUM(mark_out_cost)/SUM(receive_qty*cost_price),1) AS pct_of_received_cost
FROM v_food_log GROUP BY month_name ORDER BY MIN(log_date);

-- WASTE RATE ANALYSIS-% of stock handled VS % of Sold
SELECT category,
       ROUND(SUM(mark_out_cost),2) AS cost,
       ROUND(100*SUM(mark_out_cost)/SUM((open_qty+receive_qty)*cost_price),1) AS pct_of_available,
       ROUND(100*SUM(mark_out_cost)/SUM(sold_qty*cost_price),1) AS pct_of_sold
FROM v_food_log GROUP BY category;

-- STOCK-OUT DAYS--possible lost sales
CREATE OR REPLACE VIEW v_stockout AS
SELECT v.*,
       CASE WHEN v.shelf_life_days = 1 THEN (v.open_qty + v.receive_qty > 0 AND v.mark_out_qty = 0)
            ELSE (v.closing_qty = 0 AND v.mark_out_qty = 0) END AS stockout_day,
       (v.open_qty + v.receive_qty = 0) AS no_stock_all_day
FROM v_food_log v;

-- Total, then by category
SELECT COUNT(*) AS item_days, SUM(stockout_day) AS stockout_days,
       ROUND(100*SUM(stockout_day)/COUNT(*),1) AS pct FROM v_stockout;

SELECT category, COUNT(*) AS item_days, SUM(stockout_day) AS stockout_days,
       ROUND(100*SUM(stockout_day)/COUNT(*),1) AS pct
FROM v_stockout GROUP BY category ORDER BY stockout_days DESC;


CREATE OR REPLACE VIEW v_order_test AS
SELECT order_day, item_id, item_name, category, order_dow, is_weekend,
       sold_prev, prev_order, actual_order,
       CASE WHEN sold_prev > 0 THEN sold_prev * (1 + IF(is_weekend = 1, 0.30, 0.10))
            ELSE prev_order END AS rule_order
FROM (
  SELECT v.log_date AS order_day, v.item_id, v.item_name, v.category,
         v.day_name AS order_dow, v.is_weekend,
         LAG(v.sold_qty)      OVER w AS sold_prev,
         v.receive_qty              AS prev_order,
         LEAD(v.receive_qty)  OVER w AS actual_order
  FROM v_food_log v
  WHERE v.supply_type = 'daily_fresh'
  WINDOW w AS (PARTITION BY v.item_id ORDER BY v.log_date)
) x
WHERE sold_prev IS NOT NULL AND actual_order IS NOT NULL;

SELECT order_dow, COUNT(*) AS orders,
       ROUND(100*SUM(actual_order = ROUND(rule_order))/COUNT(*),1) AS pct_exact,
       ROUND(100*SUM(ABS(actual_order - ROUND(rule_order)) <= 1)/COUNT(*),1) AS pct_within_1,
       SUM(actual_order) AS actual_units, ROUND(SUM(rule_order),1) AS rule_units
FROM v_order_test GROUP BY order_dow;

-- Backtest check -Weekday=last 4 average order Vs Actual order

SELECT log_date, item_id, day_name, receive_qty AS actual_order,
       CEIL( (LAG(sold_qty,1) OVER w + LAG(sold_qty,2) OVER w +
              LAG(sold_qty,3) OVER w + LAG(sold_qty,4) OVER w) / 4 ) AS rule_k4_order
FROM v_food_log
WHERE supply_type = 'daily_fresh' AND item_id <> 'I029'
WINDOW w AS (PARTITION BY item_id, day_name ORDER BY log_date)
ORDER BY item_id, log_date;


-- STOCKOUT DETECTION vs GROUND TRUTH

CREATE OR REPLACE VIEW v_stockout AS
SELECT v.*,
       CASE WHEN v.shelf_life_days = 1 THEN (v.open_qty + v.receive_qty > 0 AND v.mark_out_qty = 0)
            ELSE (v.closing_qty = 0 AND v.mark_out_qty = 0) END AS stockout_day,
       (v.open_qty + v.receive_qty = 0) AS no_stock_all_day
FROM v_food_log v;
 
SELECT 'sim_truth rows' AS what, COUNT(*) AS n FROM sim_truth;
SELECT 'lost_sales_units = true_demand - sold_qty on every row?' AS what,
       SUM(t.lost_sales_units <> t.true_demand - l.sold_qty) AS rows_that_differ,
       SUM(t.stockout_flag) AS truth_stockout_days, SUM(t.lost_sales_units>0) AS truth_days_with_lost_sales,
       SUM(t.lost_sales_units) AS truth_lost_units
FROM sim_truth t JOIN daily_food_log l ON l.log_date=t.log_date AND l.item_id=t.item_id;
 
-- A: my 671 stock-out days against truth, split 19 / 652
SELECT CASE WHEN s.no_stock_all_day=1 THEN 'no stock all day (19)' ELSE 'closing-zero possible (652)' END AS grp,
       COUNT(*) AS my_days,
       SUM(t.lost_sales_units > 0)  AS truly_lost_sales,
       SUM(t.lost_sales_units = 0)  AS no_lost_sales,
       SUM(t.stockout_flag = 1)     AS truth_flag_1,
       ROUND(100*SUM(t.lost_sales_units>0)/COUNT(*),1) AS pct_with_lost_sales,
       SUM(t.lost_sales_units)      AS truth_lost_units
FROM v_stockout s JOIN sim_truth t ON t.log_date=s.log_date AND t.item_id=s.item_id
WHERE s.stockout_day = 1 GROUP BY grp;
 
-- A2: by supply type, and what my rule missed
SELECT s.supply_type, SUM(s.stockout_day) AS my_days,
       SUM(s.stockout_day=1 AND t.lost_sales_units>0) AS my_days_truly_lost,
       SUM(s.stockout_day=0 AND t.lost_sales_units>0) AS missed_by_my_rule,
       SUM(t.lost_sales_units>0) AS truth_days_lost,
       SUM(CASE WHEN s.stockout_day=0 THEN t.lost_sales_units ELSE 0 END) AS lost_units_on_missed_days
FROM v_stockout s JOIN sim_truth t ON t.log_date=s.log_date AND t.item_id=s.item_id GROUP BY s.supply_type;
 
-- A3: truth stock-out flag vs lost sales (is flag = lost>0?)
SELECT stockout_flag, lost_sales_units>0 AS lost_pos, COUNT(*) n FROM sim_truth GROUP BY 1,2;
 
-- B: demand understatement on my 671 days, and overall
SELECT 'my 671 days' AS scope, SUM(t.true_demand) AS true_demand, SUM(l.sold_qty) AS recorded_sold,
       SUM(t.true_demand - l.sold_qty) AS understated_units,
       ROUND(100*SUM(t.true_demand - l.sold_qty)/SUM(t.true_demand),1) AS pct_understated
FROM v_stockout s JOIN sim_truth t ON t.log_date=s.log_date AND t.item_id=s.item_id
JOIN daily_food_log l ON l.log_date=s.log_date AND l.item_id=s.item_id WHERE s.stockout_day=1
UNION ALL
SELECT 'all 3,894 rows', SUM(t.true_demand), SUM(l.sold_qty), SUM(t.true_demand-l.sold_qty),
       ROUND(100*SUM(t.true_demand-l.sold_qty)/SUM(t.true_demand),1)
FROM sim_truth t JOIN daily_food_log l ON l.log_date=t.log_date AND l.item_id=t.item_id;
-- B2: lost units by category and weekday part
SELECT i.category, SUM(t.lost_sales_units) AS lost_units, SUM(t.lost_sales_units>0) AS days_lost
FROM sim_truth t JOIN items i ON i.item_id=t.item_id GROUP BY i.category ORDER BY lost_units DESC;
 





