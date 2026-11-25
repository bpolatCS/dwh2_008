-- Assignment 2 | SQL1 | Question 111 | Student B
-- Topic: How did ozone concentrations vary by quarter across four European countries?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

select 
	c.country_name, 
	dt.year_num,
	dt.quarter_num,
	sum(ft.reading_count) as readings,
	round(sum(ft.recordedvalue_sum) / sum(ft.reading_count),2) as average_o3_ppb,
	min(ft.recordedvalue_min) as min_o3_ppb,
	max(ft.recordedvalue_max) as max_o3_ppb,
	max(ft.recordedvalue_max) - min(ft.recordedvalue_min) as range_o3_ppb
from ft_param_city_month_location ft 
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
left join dim_locationtype dl on dl.locationtype_key = ft.locationtype_key 
left join dim_param dp  on dp.param_key = ft.param_key 
where c.country_name in ('Denmark','Finland','Netherlands','Sweden') 
	and (dt.year_num = 2024 or dt.year_num = 2025)
	and dp.param_name = 'O3'
group by 1,2,3
order by 1,2,3
