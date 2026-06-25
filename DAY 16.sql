/* DAY - 16 */

/*💬 Priya:
"Build me the complete monthly MIS report. ONE query. The CEO reviews this every month."
For each month (delivered orders), show ALL of these in one query:

1. month (Mon YYYY)
2. revenue
3. order_count
4. unique_customers
5. avg_order_value (revenue / orders)
6. rev_per_customer (revenue / unique customers)
7. prev_revenue (LAG)
8. mom_growth_pct (CHANGE % formula with PARENTHESES!)
9. trend (📈/📉/➡️ — NULL check FIRST!)
10. running_total
11. pct_of_annual (SHARE % formula)
12. best_product — the product with highest revenue that month (correlated subquery!)*/

WITH MONTH_DATA AS( 
SELECT 
	DATE_TRUNC('MONTH', O.ORDER_DATE) AS MON_ST,
	TO_CHAR(O.ORDER_DATE, 'MON YYYY') AS MONTH,
	SUM(OI.QUANTITY*P.PRICE) AS REVENUE,
	COUNT(DISTINCT O.ORDER_ID) AS ORDER_COUNT,
	COUNT(DISTINCT O.CUSTOMER_ID) AS unique_customers
FROM ORDERS O 
JOIN ORDER_ITEMS OI ON O.ORDER_ID=OI.ORDER_ID
JOIN PRODUCTS P ON P.PRODUCT_ID=OI.PRODUCT_ID
WHERE O.STATUS='Delivered'
GROUP BY 1,2	
),	
MON_DATA2 AS (
SELECT MON_ST , MONTH, REVENUE, ORDER_COUNT, unique_customers,
	ROUND(REVENUE::NUMERIC/ NULLIF(ORDER_COUNT,0),2) AS avg_order_value,
	ROUND(REVENUE::NUMERIC/ NULLIF(unique_customers,0))	AS rev_per_customer,
	LAG(REVENUE) OVER(ORDER BY MON_ST)	AS prev_revenue,
	ROUND((REVENUE-LAG(REVENUE) OVER(ORDER BY MON_ST))::NUMERIC/ NULLIF((LAG(REVENUE) OVER(ORDER BY MON_ST)),0)*100) AS mom_growth_pct
FROM MONTH_DATA
)
SELECT  MONTH, REVENUE, ORDER_COUNT, unique_customers,avg_order_value, rev_per_customer,prev_revenue, mom_growth_pct,
	CASE 
		WHEN prev_revenue IS NULL THEN '➡️ FIRST'
		WHEN prev_revenue< REVENUE THEN '📈 GROWTH'
		ELSE '📉 DOWN' END AS TREND,
	SUM(REVENUE) OVER(ORDER BY MON_ST)	AS running_total,
	ROUND(REVENUE::NUMERIC/ NULLIF((SELECT SUM(REVENUE) FROM MONTH_DATA),0)*100,2)	as pct_of_annual,
	(SELECT	PRODUCT_NAME FROM( SELECT P2.PRODUCT_NAME, SUM(OI2.QUANTITY*P2.PRICE)
	 FROM PRODUCTS P2
	 JOIN ORDER_ITEMS OI2 ON P2.PRODUCT_ID=OI2.PRODUCT_ID
	 JOIN ORDERS O2 ON O2.ORDER_ID=OI2.ORDER_ID AND O2.STATUS='Delivered'
	 WHERE DATE_TRUNC('MONTH', O2.ORDER_DATE)=MON_DATA2.MON_ST
	 GROUP BY P2.PRODUCT_ID,1
	 ORDER BY 2 DESC
	 LIMIT 1)T)AS best_product
FROM MON_DATA2

/*💬 Priya:
"Now build a Product Performance Matrix. I want to see which products are stars, which are duds."
For each product (delivered only):
1. product_name, category
2. total_revenue, total_units
3. revenue_rank (DENSE_RANK by revenue DESC)
4. units_rank (DENSE_RANK by units DESC)
5. revenue_share_pct (product revenue / total × 100)
6. units_share_pct
7. performance_label — 'Star' if top 3 in BOTH revenue AND units, 'Cash Cow' if top 3 revenue but not units,
'Volume Player' if top 3 units but not revenue, 'Niche' otherwise.*/


WITH PRODUCTS_DATA AS (
SELECT 
	PRODUCT_NAME,
	CATEGORY,
	SUM(OI.QUANTITY*P.PRICE) AS REVENUE,
	COUNT(OI.QUANTITY) AS total_units
FROM ORDERS O
JOIN ORDER_ITEMS OI ON OI.ORDER_ID=O.ORDER_ID
JOIN PRODUCTS P ON P.PRODUCT_ID=OI.PRODUCT_ID
WHERE O.STATUS='Delivered'
group by P.PRODUCT_ID,1,2
),
PRODUCT_RNK AS (
SELECT *, 
	DENSE_RANK() OVER(ORDER BY  REVENUE DESC) AS revenue_rank,
	DENSE_RANK() OVER(ORDER BY total_units DESC) AS UNIT_RANK,
	ROUND(REVENUE::NUMERIC/ SUM(REVENUE) OVER()*100,2) AS revenue_share_pct,
	ROUND(total_units::NUMERIC/ SUM(total_units) OVER()*100,2)	AS units_share_pct
FROM PRODUCTS_DATA
)
SELECT *,CASE
        WHEN revenue_rank<=3 AND UNIT_RANK<=3 THEN '⭐ Star'
        WHEN revenue_rank<=3 THEN '💰 Cash Cow'
        WHEN UNIT_RANK<=3 THEN '📦 Volume Player'
        ELSE '🔹 Niche'
    END AS performance
FROM PRODUCT_RNK


/*💬 Priya:
"City-wise Quarterly Performance — for each city, for each quarter: revenue, orders, AOV, city's share of total, 
and quarter-over-quarter growth per city."
city, quarter_label, revenue, orders, aov, city_share_pct, prev_quarter_revenue (LAG PARTITION BY city), 
qoq_growth_pct. Delivered only.*/

WITH CITY_LBL AS (
SELECT 
	C.CITY,
	DATE_TRUNC('QUARTER', O.ORDER_DATE) AS QUA_ST,
	CONCAT('Q', EXTRACT(QUARTER FROM O.ORDER_DATE), 'Y',EXTRACT(YEAR FROM O.ORDER_DATE)) AS quarter_label,
	SUM(OI.QUANTITY*P.PRICE) AS REVENUE,
	COUNT(DISTINCT O.ORDER_ID) AS orders
FROM CUSTOMERS C
JOIN ORDERS O ON O.CUSTOMER_ID=C.CUSTOMER_ID AND O.STATUS='Delivered'
JOIN ORDER_ITEMS OI ON OI.ORDER_ID=O.ORDER_ID
JOIN PRODUCTS P ON P.PRODUCT_ID=OI.PRODUCT_ID
group by 1,2,3
),
CITY_D2 AS (
SELECT *,
	ROUND(REVENUE::NUMERIC/NULLIF(orders,0)) AS AVG_ORD_VAL,
	ROUND(REVENUE::NUMERIC/ SUM(REVENUE) OVER(PARTITION BY QUA_ST)*100,2) AS city_share_pct
FROM CITY_LBL
)
SELECT *,  
	LAG(REVENUE) OVER(PARTITION BY CITY ORDER BY QUA_ST)	AS prev_quarter_revenue,
	ROUND((REVENUE-LAG(REVENUE) OVER(PARTITION BY CITY ORDER BY QUA_ST))::NUMERIC/NULLIF(LAG(REVENUE) OVER(PARTITION BY CITY ORDER BY QUA_ST),0)*100,2) AS qoq_growth_pct
FROM CITY_D2


/*💬 Priya:
"Category cross-analysis: for each category, show revenue, units, average unit price, revenue rank, 
and which city buys this category the MOST."
Per category: category, revenue, units, avg_unit_price, rank, top_city (correlated subquery). Delivered only.*/

WITH PRODUCT_D AS (
SELECT 
	P.CATEGORY,
	SUM(OI.QUANTITY*P.PRICE) AS REVENUE,
	COUNT(OI.QUANTITY) AS units
FROM ORDERS o
JOIN ORDER_ITEMS OI ON O.ORDER_ID=OI.ORDER_ID
JOIN PRODUCTS p ON P.PRODUCT_ID=OI.PRODUCT_ID
WHERE O.STATUS='Delivered'
group by 1
)
SELECT *,
	ROUND(REVENUE::NUMERIC/NULLIF(units,0),2) AS avg_unit_price,
	DENSE_RANK() OVER(ORDER BY REVENUE DESC) AS REV_RNK,
	ROUND(REVENUE::NUMERIC/ SUM(REVENUE) OVER()*100,2)	AS REV_SHARE,
	(SELECT C2.CITY FROM CUSTOMERS C2
		JOIN ORDERS O2 ON C2.CUSTOMER_ID=O2.CUSTOMER_ID
		JOIN ORDER_ITEMS OI2 ON O2.ORDER_ID=OI2.ORDER_ID
		JOIN PRODUCTS P2 ON P2.PRODUCT_ID=OI2.PRODUCT_ID
		WHERE O2.STATUS='Delivered' and P2.CATEGORY=PRODUCT_D.CATEGORY
		GROUP BY 1
		ORDER BY SUM(OI2.QUANTITY*P2.PRICE) DESC
		LIMIT 1) AS TOP_CITY
FROM PRODUCT_D


/*💬 Priya:
"Build the customer funnel. One query. Show each stage, count, and conversion rate from previous stage."
Single query showing: stage_name, customer_count, pct_of_total, conversion_from_previous_stage.*/

WITH FUNNEL AS (
--SIGNUPS
SELECT	'STAGE 1: SIGNUP' AS stage_name, 
	COUNT(*)	AS customer_count
FROM CUSTOMERS
UNION ALL
--TOTAL_ORDERS
SELECT 'STAGE 2 : TOTAL_ORDERS', COUNT(DISTINCT CUSTOMER_ID) FROM ORDERS
UNION ALL
--Delivered
SELECT 'STAGE 3: Delivered', COUNT(DISTINCT CUSTOMER_ID) FROM ORDERS WHERE STATUS='Delivered'
union all
--Repeat
SELECT 'STAGE 4: Repeat', COUNT(CUSTOMER_ID) FROM (SELECT CUSTOMER_ID FROM ORDERS GROUP BY CUSTOMER_ID HAVING COUNT(DISTINCT ORDER_ID)>=2)X     
UNION ALL
--Loyal
SELECT 'STAGE 5: Loyal', COUNT(CUSTOMER_ID) FROM (SELECT CUSTOMER_ID FROM ORDERS GROUP BY CUSTOMER_ID HAVING COUNT(DISTINCT ORDER_ID)>=3)T
)
SELECT *, 
	ROUND(CUSTOMER_COUNT::NUMERIC/FIRST_VALUE(CUSTOMER_COUNT) OVER(ORDER BY CUSTOMER_COUNT DESC)*100,1)	AS pct_of_total, 
	ROUND(CUSTOMER_COUNT::NUMERIC/LAG(CUSTOMER_COUNT) OVER(ORDER BY CUSTOMER_COUNT DESC)*100,1)	AS conversion_from_previous_stage
FROM FUNNEL

/*💬 CEO:
"Give me ONE row with ALL the numbers I need. My executive KPI dashboard."
Single row showing 12+ KPIs:
total_revenue, total_orders, total_customers, active_customers, active_rate_pct, avg_order_value, top_city (by revenue)
, top_product, top_customer, repeat_customer_pct, revenue_concentration_top3 (top 3 customers' share %), 
avg_customer_tenure_months*/

with CUST_DATA AS (
SELECT 
	SUM(OI.QUANTITY*P.PRICE) AS total_revenue, 
	COUNT(DISTINCT O.ORDER_ID)	AS total_orders, 
	(SELECT COUNT(C.CUSTOMER_ID) FROM CUSTOMERS C )	AS total_customers, 
	(SELECT count(C1.CUSTOMER_ID) FROM CUSTOMERS C1
		WHERE EXISTS (SELECT 1 FROM ORDERS O1
			WHERE O1.CUSTOMER_ID=C1.CUSTOMER_ID))	AS active_customers
FROM ORDERS O 
JOIN ORDER_ITEMS OI ON O.ORDER_ID=OI.ORDER_ID
JOIN PRODUCTS P ON P.PRODUCT_ID=OI.PRODUCT_ID
JOIN CUSTOMERS C ON O.CUSTOMER_ID=C.CUSTOMER_ID 
WHERE O.STATUS='Delivered'
)
SELECT  *, ROUND(active_customers::NUMERIC/total_customers*100,2),
ROUND(total_revenue::NUMERIC/total_orders,2)	AS avg_order_value,
(SELECT C2.CITY FROM CUSTOMERS C2
		JOIN ORDERS O2 ON C2.CUSTOMER_ID=O2.CUSTOMER_ID AND O2.STATUS='Delivered'
		JOIN ORDER_ITEMS OI2 ON O2.ORDER_ID=OI2.ORDER_ID
		JOIN PRODUCTS P2 ON P2.PRODUCT_ID=OI2.PRODUCT_ID
		GROUP BY 1
		ORDER BY SUM(OI2.QUANTITY*P2.PRICE) DESC LIMIT 1)	AS top_city_BY_REV,
(SELECT P3.PRODUCT_NAME FROM CUSTOMERS C3
		JOIN ORDERS O3 ON C3.CUSTOMER_ID=O3.CUSTOMER_ID AND O3.STATUS='Delivered'
		JOIN ORDER_ITEMS OI3 ON O3.ORDER_ID=OI3.ORDER_ID
		JOIN PRODUCTS P3 ON P3.PRODUCT_ID=OI3.PRODUCT_ID
		GROUP BY 1	
		ORDER BY SUM(OI3.QUANTITY*P3.PRICE) DESC LIMIT 1)as top_product,
(SELECT C4.NAME FROM CUSTOMERS C4
		JOIN ORDERS O4 ON C4.CUSTOMER_ID=O4.CUSTOMER_ID AND O4.STATUS='Delivered'
		JOIN ORDER_ITEMS OI4 ON O4.ORDER_ID=OI4.ORDER_ID
		JOIN PRODUCTS P4 ON P4.PRODUCT_ID=OI4.PRODUCT_ID
		GROUP BY 1	
		ORDER BY SUM(OI4.QUANTITY*P4.PRICE) DESC LIMIT 1) 	AS top_customer,
ROUND((SELECT COUNT(*) FROM (SELECT CUSTOMER_ID FROM ORDERS 
						WHERE STATUS='Delivered'
						group by 1
						HAVING COUNT(*)>=2)T)::NUMERIC/
						NULLIF((SELECT COUNT(CUSTOMER_ID) FROM ORDERS WHERE STATUS='Delivered'),0)*100,2) as repeat_customer_pct,
ROUND((SELECT SUM(REV) FROM ( SELECT C4.NAME, SUM(OI4.QUANTITY*P4.PRICE) AS REV  FROM CUSTOMERS C4
		JOIN ORDERS O4 ON C4.CUSTOMER_ID=O4.CUSTOMER_ID AND O4.STATUS='Delivered'
		JOIN ORDER_ITEMS OI4 ON O4.ORDER_ID=OI4.ORDER_ID
		JOIN PRODUCTS P4 ON P4.PRODUCT_ID=OI4.PRODUCT_ID
		GROUP BY 1	
		ORDER BY SUM(OI4.QUANTITY*P4.PRICE) DESC LIMIT 3)Y)::NUMERIC/ SUM(( SELECT SUM(OI4.QUANTITY*P4.PRICE) AS REV  FROM CUSTOMERS C4
																			JOIN ORDERS O4 ON C4.CUSTOMER_ID=O4.CUSTOMER_ID AND O4.STATUS='Delivered'
																			JOIN ORDER_ITEMS OI4 ON O4.ORDER_ID=OI4.ORDER_ID
																			JOIN PRODUCTS P4 ON P4.PRODUCT_ID=OI4.PRODUCT_ID																		
																			))*100,2)	 AS revenue_concentration_top3,
ROUND((SELECT AVG(EXTRACT(YEAR FROM AGE(SIGNUP_DATE))*12 + EXTRACT(MONTH FROM AGE(SIGNUP_DATE))) FROM CUSTOMERS),2)	AS avg_customer_tenure_months
FROM CUST_DATA
GROUP BY cust_data.total_revenue,cust_data.total_orders, cust_data.total_customers,cust_data.active_customers

 

























