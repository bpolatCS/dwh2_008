-- Assignment 2 | SQL2 | Question 202 | Student B
-- Topic: How did O3 concentrations and alert rates vary across French cities and quarters?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

select 
	case when grouping(c.city_name) = 1 then 'ALL CITIES' else c.city_name end as city_name,
	dt.quarter_num,
	case 
		when grouping(c.city_name) = 1 and grouping(dt.quarter_num) = 1 then 'GRAND TOTAL'
		when grouping(c.city_name) = 1 then 'QUARTER TOTAL'
		when grouping(dt.quarter_num ) = 1 then 'CITY TOTAL'
	else 'CITY-QUARTER' end row_level,
	sum(ft.reading_count) as readings,
	round(sum(ft.recordedvalue_sum) / sum(ft.reading_count),2) as average_o3_ppb,
	sum(ft.alert_reading_count) as alert_readings,
	round(100.0 * sum(ft.alert_reading_count ) / sum(ft.reading_count),2) as alert_pct
from ft_param_city_month_location ft 
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
left join dim_locationtype dl on dl.locationtype_key = ft.locationtype_key 
left join dim_param dp  on dp.param_key = ft.param_key 
where c.country_name = 'France'
	and dp.param_name = 'O3'
	and dt.year_num = 2024
group by cube(c.city_name,dt.quarter_num)
order by grouping(c.city_name),
c.city_name,
grouping(dt.quarter_num),
dt.quarter_num

