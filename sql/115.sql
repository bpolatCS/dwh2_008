-- Assignment 2 | SQL1 | Question 115 | Student A
-- Topic: Which pollutants are monitored in German Urban but not Industrial locations?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


SELECT
    p.param_name,
    p.category,

    SUM(f.reading_count) AS urban_readings,

    SUM(f.alert_reading_count) AS urban_alert_readings,

    ROUND(
        100.0 * SUM(f.alert_reading_count)
        / NULLIF(SUM(f.reading_count), 0), 2
    ) AS urban_alert_pct

FROM ft_param_city_month_location AS f

JOIN dim_timemonth AS t
    ON f.month_key = t.month_key

JOIN dim_city AS c
    ON f.city_key = c.city_key

JOIN dim_param AS p
    ON f.param_key = p.param_key

JOIN dim_locationtype AS l
    ON f.locationtype_key = l.locationtype_key

WHERE t.year_num = 2025
    AND c.country_name = 'Germany'
    AND l.location_type = 'Urban'

    AND NOT EXISTS (
        SELECT 1
        FROM ft_param_city_month_location AS fi

        JOIN dim_timemonth AS ti
            ON fi.month_key = ti.month_key

        JOIN dim_city AS ci
            ON fi.city_key = ci.city_key

        JOIN dim_locationtype AS li
            ON fi.locationtype_key = li.locationtype_key

        WHERE fi.param_key = f.param_key
            AND ti.year_num = 2025
            AND ci.country_name = 'Germany'
            AND li.location_type = 'Industrial'
    )

GROUP BY
    p.param_key,
    p.param_name,
    p.category

HAVING COUNT(DISTINCT f.month_key) >= 6

ORDER BY
    urban_alert_pct DESC,
    urban_readings DESC,
    p.param_name ASC

LIMIT 30;