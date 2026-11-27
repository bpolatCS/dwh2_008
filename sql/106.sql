-- Assignment 2 | SQL1 | Question 106 | Student B
-- Topic: How often do Urban and Industrial readings reach alert levels?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

select 
	c.country_name, 
	c.city_name,
	dl.location_type,
	sum(ft.reading_count) as readings,
	sum(ft.alert_reading_count) as alert_readings,
	round(100.0 * sum(ft.alert_reading_count) / sum(ft.reading_count),2)as alert_pct,
	sum(ft.severe_alert_reading_count ) as severe_alert_readings,
	round(100.0 * sum(ft.severe_alert_reading_count ) / sum(ft.reading_count),2)as severe_alert_pct
from ft_param_city_month_location ft
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
left join dim_locationtype dl on dl.locationtype_key = ft.locationtype_key 
left join dim_param dp  on dp.param_key = ft.param_key 
where c.country_name in ('Austria','Germany','Russia') 
	and (dt.year_num = 2024)
	and (dl.location_type in ('Urban','Industrial'))
group by 1,2,3
order by 1,2,3
