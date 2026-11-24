-- Assignment 2 | SQL2 | Question 212 | Student B
-- Topic: How did PM10 concentrations change by month, quarter and year in Italy?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

select 
	case when
		grouping(dt.year_num) = 1 then NULL else dt.year_num end as year_num,
	case when
		grouping(dt.quarter_num) = 1 then NULL else dt.quarter_num end as quarter_num,	
	case when
		grouping(dt.month_num) = 1 then NULL else dt.month_num end as month_num,
	case 
		when grouping(dt.year_num) = 1 and grouping(dt.quarter_num) = 1 and grouping(dt.month_num) = 1 then 'GRAND TOTAL'
		when grouping(dt.year_num) = 1 then 'YEAR TOTAL'
		when grouping(dt.quarter_num ) = 1 then 'QUARTER TOTAL'
	else 'MONTH' end row_level,
	sum(ft.reading_count) as readings,
	round(sum(ft.recordedvalue_sum) / sum(ft.reading_count),2) as average_pm10_mcg_m3
from ft_param_city_month_location ft 
left join dim_city c on c.city_key  = ft.city_key 
left join dim_timemonth dt on dt.month_key = ft.month_key
left join dim_locationtype dl on dl.locationtype_key = ft.locationtype_key 
left join dim_param dp  on dp.param_key = ft.param_key 
where c.country_name  in ('Italy')
	and dp.param_name = 'PM10'
	and dt.year_num in (2024,2025)
group by rollup(dt.year_num, dt.quarter_num, dt.month_num)
order by 
	grouping(dt.year_num),
	grouping(dt.quarter_num),
	grouping(dt.month_num)

