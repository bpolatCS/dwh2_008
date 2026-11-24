-- Assignment 2 | SQL2 | Question 215 | Student B
-- Topic: How did short-term alert rates change in Ankara and Istanbul?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


select
    city_name,
    month_num,
    readings,
    round(100.0 * alert_readings / nullif(readings, 0), 2)       as current_alert_pct,
    round(100.0 * alert_readings_3m / nullif(readings_3m, 0), 2) as rolling_3m_alert_pct,
    round(100.0 * alert_readings / nullif(readings, 0) - 100.0 * alert_readings_3m / nullif(readings_3m, 0), 2) as difference_pp
from (
    select
        c.city_name,
        dt.year_num,
        dt.month_num,
        coalesce(sum(ft.reading_count), 0)       as readings,
        coalesce(sum(ft.alert_reading_count), 0) as alert_readings,
        sum(coalesce(sum(ft.reading_count), 0)) over (
            partition by c.city_name order by dt.year_num, dt.month_num
            rows between 2 preceding and current row)  as readings_3m,
        sum(coalesce(sum(ft.alert_reading_count), 0)) over (
            partition by c.city_name order by dt.year_num, dt.month_num
            rows between 2 preceding and current row)  as alert_readings_3m
    from dim_city c
    cross join dim_timemonth dt
    left join ft_param_city_month_location ft on ft.city_key  = c.city_key and ft.month_key = dt.month_key
    where c.city_name in ('Ankara', 'Istanbul')
      and ((dt.year_num = 2024 and dt.month_num >= 11) or dt.year_num = 2025)
    group by 
    	c.city_name, 
    	dt.year_num, 
    	dt.month_num
) t
where year_num = 2025
order by city_name, month_num;

