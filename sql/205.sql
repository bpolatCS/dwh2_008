-- Assignment 2 | SQL2 | Question 205 | Student B
-- Topic: Which cities had the highest severe-alert rates in each quarter of 2024?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

select * from (
select 
	c.country_name, 
	dt.quarter_num,
	row_number() 
		over (partition by country_name, quarter_num 
		order by 1.0 * sum(ft.severe_alert_reading_count ) / sum(reading_count) desc,
		sum(ft.reading_count) desc, c.city_name) as city_rank,
	c.city_name,
	sum(ft.reading_count) as readings,
	sum(severe_alert_reading_count ) as severe_alert_readings,
	round(100.0 * sum(ft.severe_alert_reading_count ) / sum(reading_count),2)as severe_alert_pct
from ft_param_city_month_location ft
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
where c.country_name in ('Germany','Russia') 
	and (dt.year_num = 2024)
group by 1,2,4)
where city_rank < 4
order by country_name, quarter_num, city_rank;
