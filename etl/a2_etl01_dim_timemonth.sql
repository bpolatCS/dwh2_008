-- DWH2 A2 ETL 01/06: dim_timemonth
-- Table names are unqualified; the session search_path is configured externally.
-- Source: tb_readingevent
-- Target: dim_timemonth
-- Requires: DWH2 DDL executed; fresh, empty dimension tables.

INSERT INTO dim_timemonth (
    month_key, year_num, quarter_num, month_num, month_name,
    mfirst_day, mlast_day, days_in_month
)
SELECT
    EXTRACT(YEAR FROM m.month_start)::INT * 100
        + EXTRACT(MONTH FROM m.month_start)::INT        AS month_key,
    EXTRACT(YEAR FROM m.month_start)::INT               AS year_num,
    EXTRACT(QUARTER FROM m.month_start)::INT            AS quarter_num,
    EXTRACT(MONTH FROM m.month_start)::INT              AS month_num,
    TO_CHAR(m.month_start, 'FMMonth')                   AS month_name,
    m.month_start::DATE                                AS mfirst_day,
    (m.month_start + INTERVAL '1 month - 1 day')::DATE AS mlast_day,
    EXTRACT(DAY FROM (
        m.month_start + INTERVAL '1 month - 1 day'
    ))::INT                                             AS days_in_month
FROM GENERATE_SERIES(
    (SELECT DATE_TRUNC('month', MIN(readat)::TIMESTAMP) FROM tb_readingevent),
    (SELECT DATE_TRUNC('month', MAX(readat)::TIMESTAMP) FROM tb_readingevent),
    INTERVAL '1 month'
) AS m(month_start)
ORDER BY m.month_start;
