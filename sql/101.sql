-- Assignment 2 | SQL1 | Question 101 | Student B
-- Topic: How did reading volumes and severe alerts change across all countries?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.

SELECT
    c.country_name,

    COALESCE(
        SUM(f.reading_count)
        FILTER (WHERE t.year_num = 2024), 0
    ) AS readings_2024,

    ROUND(
        100.0 * SUM(f.severe_alert_reading_count)
        FILTER (WHERE t.year_num = 2024)
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.year_num = 2024), 0
        ), 2
    ) AS severe_alert_pct_2024,

    COALESCE(
        SUM(f.reading_count)
        FILTER (WHERE t.year_num = 2025), 0
    ) AS readings_2025,

    ROUND(
        100.0 * SUM(f.severe_alert_reading_count)
        FILTER (WHERE t.year_num = 2025)
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.year_num = 2025), 0
        ), 2
    ) AS severe_alert_pct_2025

FROM ft_param_city_month_location AS f

JOIN dim_timemonth AS t
    ON f.month_key = t.month_key

JOIN dim_city AS c
    ON f.city_key = c.city_key

WHERE t.year_num IN (2024, 2025)

GROUP BY c.country_name

HAVING SUM(f.reading_count)
    FILTER (WHERE t.year_num = 2025) > 0

ORDER BY readings_2025 DESC, c.country_name ASC

LIMIT 20;
