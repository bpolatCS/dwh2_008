-- Assignment 2 | SQL1 | Question 105 | Student A
-- Topic: How did sensor-data volume per reading vary by quarter?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


SELECT
    c.country_name,
    c.city_name,
    p.category,

    ROUND(
        SUM(f.data_volume_kb_sum)
        FILTER (WHERE t.quarter_num = 1)::NUMERIC
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.quarter_num = 1), 0
        ), 2
    ) AS q1_kb_per_reading,

    ROUND(
        SUM(f.data_volume_kb_sum)
        FILTER (WHERE t.quarter_num = 2)::NUMERIC
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.quarter_num = 2), 0
        ), 2
    ) AS q2_kb_per_reading,

    ROUND(
        SUM(f.data_volume_kb_sum)
        FILTER (WHERE t.quarter_num = 3)::NUMERIC
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.quarter_num = 3), 0
        ), 2
    ) AS q3_kb_per_reading,

    ROUND(
        SUM(f.data_volume_kb_sum)
        FILTER (WHERE t.quarter_num = 4)::NUMERIC
        / NULLIF(
            SUM(f.reading_count)
            FILTER (WHERE t.quarter_num = 4), 0
        ), 2
    ) AS q4_kb_per_reading

FROM ft_param_city_month_location AS f

JOIN dim_timemonth AS t
    ON f.month_key = t.month_key

JOIN dim_city AS c
    ON f.city_key = c.city_key

JOIN dim_param AS p
    ON f.param_key = p.param_key

WHERE t.year_num = 2024
    AND c.country_name IN ('Austria', 'Czech Republic')

GROUP BY
    c.country_name,
    c.city_name,
    p.category

ORDER BY
    c.country_name,
    c.city_name,
    p.category

LIMIT 25;