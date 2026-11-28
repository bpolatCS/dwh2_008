-- Assignment 2 | SQL2 | Question 203 | Student A
-- Topic: How did severe-alert rates vary across French health-risk and compliance pollutants?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


SELECT
    CASE
        WHEN GROUPING(p.purpose) = 1
            THEN 'ALL SELECTED PURPOSES'
        ELSE p.purpose
    END AS purpose,

    CASE
        WHEN GROUPING(p.param_name) = 1
            THEN 'ALL PARAMETERS'
        ELSE p.param_name
    END AS parameter_name,

    CASE
        WHEN GROUPING(p.purpose) = 1
            THEN 'GRAND TOTAL'
        WHEN GROUPING(p.param_name) = 1
            THEN 'PURPOSE TOTAL'
        ELSE 'PARAMETER'
    END AS row_level,

    SUM(f.reading_count) AS readings,

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

WHERE t.year_num = 2024
    AND c.country_name = 'France'
    AND p.purpose IN (
        'Health Risk',
        'Regulatory Compliance'
    )

GROUP BY GROUPING SETS (
    (p.purpose, p.param_name),
    (p.purpose),
    ()
)

ORDER BY
    GROUPING(p.purpose),
    p.purpose,
    GROUPING(p.param_name),
    p.param_name

LIMIT 22;