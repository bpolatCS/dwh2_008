-- Assignment 2 | SQL1 | Question 109 | Student A
-- Topic: Does a monthly peak-alert level mean all readings were alerts?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


SELECT
    c.country_name,
    p.category,
    a.alert_level_name AS peak_alert_level,

    SUM(f.reading_count) AS readings,

    SUM(f.alert_reading_count) AS alert_readings,

    ROUND(
        100.0 * SUM(f.alert_reading_count)
        / NULLIF(SUM(f.reading_count), 0), 2
    ) AS alert_reading_pct

FROM ft_param_city_month_location AS f

JOIN dim_timemonth AS t
    ON f.month_key = t.month_key

JOIN dim_city AS c
    ON f.city_key = c.city_key

JOIN dim_param AS p
    ON f.param_key = p.param_key

JOIN dim_alertlevel AS a
    ON f.alertlevel_key = a.alertlevel_key

WHERE t.year_num = 2025
    AND c.country_name IN ('Austria', 'Hungary')
    AND p.category IN ('Gas', 'Particulate matter')

GROUP BY
    c.country_name,
    p.category,
    a.alert_level_name,
    a.alert_rank

ORDER BY
    c.country_name,
    p.category,
    a.alert_rank

LIMIT 20;