-- Assignment 2 | SQL1 | Question 114 | Student B
-- Topic: Which pollutants are monitored in both Urban and Industrial locations?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

with tbl AS (
    select
        ft.city_key,
        ft.param_key,
        max(case when dl.location_type = 'Urban'      then 1 else 0 end) as in_urban,
        max(case when dl.location_type = 'Industrial' then 1 else 0 end) as in_industrial
    from ft_param_city_month_location ft
    left join dim_timemonth dt    ON dt.month_key = ft.month_key
    left join dim_locationtype dl ON dl.locationtype_key = ft.locationtype_key
    where dl.location_type in ('Urban','Industrial')
		and (dt.year_num = 2024)
    group by ft.city_key, ft.param_key
)

select 
	c.country_name, 
	c.city_name,
	count(case when in_urban = 1 then 1 end) as urban_parameters,
	count(case when in_industrial = 1 then 1 end) as industrial_parameters,
	count(case when in_urban = 1 and in_industrial = 1 then 1 end) as parameters_in_both
from dim_city c 
left join tbl ft on c.city_key  = ft.city_key 
where c.country_name in ('Austria','Germany','France','Hungary') 
group by 1,2
order by 1,2
