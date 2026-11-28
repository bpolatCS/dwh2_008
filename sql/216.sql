-- Assignment 2 | SQL2 | Question 216 | Student A
-- Topic: Are Russian cities above or below their peers in quarterly alert-reading rates?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


WITH city_quarter_totals AS (
    SELECT
        c.city_name,
        t.quarter_num,

        SUM(f.reading_count) AS city_readings,

        SUM(f.alert_reading_count) AS city_alert_readings

    FROM ft_param_city_month_location AS f

    JOIN dim_timemonth AS t
        ON f.month_key = t.month_key

    JOIN dim_city AS c
        ON f.city_key = c.city_key

    WHERE t.year_num = 2024
        AND c.country_name = 'Russia'

    GROUP BY
        c.city_name,
        t.quarter_num
),

russian_quarter_totals AS (
    SELECT
        city_name,
        quarter_num,
        city_readings,
        city_alert_readings,

        SUM(city_readings) OVER (
            PARTITION BY quarter_num
        ) AS russian_readings,

        SUM(city_alert_readings) OVER (
            PARTITION BY quarter_num
        ) AS russian_alert_readings

    FROM city_quarter_totals
),

calculated_percentages AS (
    SELECT
        city_name,
        quarter_num,
        city_readings,

        100.0 * city_alert_readings
        / NULLIF(city_readings, 0)
            AS city_alert_pct,

        100.0 * (russian_alert_readings - city_alert_readings)
        / NULLIF(russian_readings - city_readings, 0)
            AS other_cities_alert_pct

    FROM russian_quarter_totals
)

SELECT
    city_name,
    quarter_num,
    city_readings,

    ROUND(city_alert_pct, 2) AS city_alert_pct,

    ROUND(other_cities_alert_pct, 2) AS other_cities_alert_pct,

    ROUND(
        city_alert_pct - other_cities_alert_pct, 2
    ) AS difference_pp

FROM calculated_percentages

ORDER BY
    city_name,
    quarter_num

LIMIT 16;