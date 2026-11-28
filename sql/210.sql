-- Assignment 2 | SQL2 | Question 210 | Student A
-- Topic: How do alert rates compare across pollutant categories in five countries?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


SELECT
    CASE
        WHEN GROUPING(c.country_name) = 1
            THEN 'ALL SELECTED COUNTRIES'
        ELSE c.country_name
    END AS country_name,

    CASE
        WHEN GROUPING(p.category) = 1
            THEN 'ALL CATEGORIES'
        ELSE p.category
    END AS category,

    CASE
        WHEN GROUPING(c.country_name) = 1
            AND GROUPING(p.category) = 1
            THEN 'GRAND TOTAL'
        WHEN GROUPING(c.country_name) = 1
            THEN 'CATEGORY TOTAL'
        WHEN GROUPING(p.category) = 1
            THEN 'COUNTRY TOTAL'
        ELSE 'COUNTRY-CATEGORY'
    END AS row_level,

    SUM(f.reading_count) AS readings,

    SUM(f.alert_reading_count) AS alert_readings,

    ROUND(
        100.0 * SUM(f.alert_reading_count)
        / NULLIF(SUM(f.reading_count), 0), 2
    ) AS alert_pct,

    SUM(f.severe_alert_reading_count)
        AS severe_alert_readings,

    ROUND(
        100.0 * SUM(f.severe_alert_reading_count)
        / NULLIF(SUM(f.reading_count), 0), 2
    ) AS severe_alert_pct

FROM ft_param_city_month_location AS f

JOIN dim_timemonth AS t
    ON f.month_key = t.month_key

JOIN dim_city AS c
    ON f.city_key = c.city_key

JOIN dim_param AS p
    ON f.param_key = p.param_key

WHERE t.year_num = 2025
    AND c.country_name IN (
        'Austria',
        'Germany',
        'Hungary',
        'Russia',
        'Turkey'
    )

GROUP BY CUBE (
    c.country_name,
    p.category
)

ORDER BY
    GROUPING(c.country_name),
    c.country_name,
    GROUPING(p.category),
    p.category

LIMIT 36;