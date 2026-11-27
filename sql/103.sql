-- Assignment 2 | SQL1 | Question 103 | Student A
-- Topic: How reliably was BlackCarbon monitored, and how many monitored days had alerts?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


select 
	c.country_name, 
	c.city_name,
	dl.location_type,
	dt.year_num,
	sum(ft.days_with_readings_count) as monitored_days,
	round(100.0 * sum(ft.days_with_readings_count) / sum(days_in_month),2) as coverage_pct,
	round(100.0 * sum(ft.alert_days_count) / sum(ft.days_with_readings_count),2) as alert_day_pct 	
from ft_param_city_month_location ft
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
left join dim_locationtype dl on dl.locationtype_key = ft.locationtype_key 
left join dim_param dp  on dp.param_key = ft.param_key 
where c.country_name in ('Austria','Germany') 
	and (dt.year_num = 2024 or dt.year_num = 2025)
	and (dl.location_type in ('Urban','Industrial'))
	and (dp.param_name = 'BlackCarbon')
group by 1,2,3,4
order by 1,2,3,4


