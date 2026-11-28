-- Assignment 2 | SQL2 | Question 207 | Student A
-- Topic: Which month had the largest average concentration above the annual average for each pollutant in French cities?
-- Read the assignment description for the complete question,
-- required SQL technique, result columns, sorting, and row limit.
-- Write exactly one read-only SELECT or WITH ... SELECT statement.
-- Use unqualified table names; the notebook selects only the DWH2 schema.
-- Place your SQL query below. Keep the comments above for reference.


WITH monthly_totals AS (
    SELECT
        c.city_name,
        p.param_name,
        p.unit,
        t.month_num,

        SUM(f.reading_count) AS month_readings,

        SUM(f.recordedvalue_sum) AS month_value_sum

    FROM ft_param_city_month_location AS f

    JOIN dim_timemonth AS t
        ON f.month_key = t.month_key

    JOIN dim_city AS c
        ON f.city_key = c.city_key

    JOIN dim_param AS p
        ON f.param_key = p.param_key

    WHERE t.year_num = 2024
        AND c.country_name = 'France'
        AND c.city_name IN ('Lyon', 'Marseille', 'Paris')
        AND p.param_name IN ('PM2', 'PM10', 'NO2', 'O3')

    GROUP BY
        c.city_name,
        p.param_name,
        p.unit,
        t.month_num
),

calculated_averages AS (
    SELECT
        city_name,
        param_name,
        unit,
        month_num,
        month_readings,

        month_value_sum::NUMERIC
        / NULLIF(month_readings, 0)
            AS month_avg_value,

        (SUM(month_value_sum) OVER (
            PARTITION BY city_name, param_name
        ))::NUMERIC
        / NULLIF(
            SUM(month_readings) OVER (
                PARTITION BY city_name, param_name
            ), 0
        ) AS annual_avg_value

    FROM monthly_totals
),

ranked_months AS (
    SELECT
        *,
        month_avg_value - annual_avg_value AS excess_value,

        ROW_NUMBER() OVER (
            PARTITION BY city_name, param_name
            ORDER BY
                (month_avg_value - annual_avg_value) DESC,
                month_num ASC
        ) AS rn

    FROM calculated_averages
)

SELECT
    city_name,
    param_name,
    unit,
    month_num AS peak_month,
    month_readings,
    ROUND(month_avg_value, 2) AS month_avg_value,
    ROUND(annual_avg_value, 2) AS annual_avg_value,
    ROUND(excess_value, 2) AS excess_value

FROM ranked_months

WHERE rn = 1

ORDER BY
    city_name,
    param_name

LIMIT 12;