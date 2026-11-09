-- Assignment 2 | ETL 06/06 | Fact-table ETL (STUDENT TODO)
-- Target: ft_param_city_month_location
--
-- ETL 01-05 are supplied and load the five dimensions during a full run.
-- Implement this SQL file yourself in DBeaver. Do not modify the supplied DDL.
--
-- Grain: one fact row per Month x City x Parameter x Location Type.
-- The monthly Peak Alert Level is a derived attribute, NOT part of this grain.
--
-- Your implementation must:
--   1. Read the relevant staging tables and classify individual readings
--      using the parameter-specific alert thresholds.
--   2. Aggregate readings and all fact measures at the specified grain.
--      Count DISTINCT calendar dates for the two day measures.
--   3. Determine each month's highest alert level, resolve the five
--      dimension keys, and insert the resulting fact rows.
--
-- Use unqualified table names only; the notebook supplies the search path.
-- Do not insert example/dummy rows into the warehouse.
--
-- This starter contains COMMENTS ONLY on purpose. The notebook creates your
-- assigned SQL question files and feasibility CSV on the first run, then
-- stops BEFORE resetting database schemas until you implement this ETL.
--
-- 1) One row per parameter with its four thresholds (Yellow, Orange, Red, Crimson)
WITH param_thresholds AS (
    SELECT
        pa.paramid,
        MAX(CASE WHEN a.alertname = 'Yellow'  THEN pa.threshold END) AS yellow_thr,
        MAX(CASE WHEN a.alertname = 'Orange'  THEN pa.threshold END) AS orange_thr,
        MAX(CASE WHEN a.alertname = 'Red'     THEN pa.threshold END) AS red_thr,
        MAX(CASE WHEN a.alertname = 'Crimson' THEN pa.threshold END) AS crimson_thr
    FROM tb_paramalert AS pa
    JOIN tb_alert AS a
        ON a.id = pa.alertid
    GROUP BY pa.paramid
),

-- 2) Each individual reading with its grain attributes and alert rank
--    (None = 0, Yellow = 1, Orange = 2, Red = 3, Crimson = 4)
classified_readings AS (
    SELECT
        EXTRACT(YEAR FROM r.readat)::INT * 100
            + EXTRACT(MONTH FROM r.readat)::INT AS month_key,
        sd.cityid,
        r.paramid,
        sd.locationtype,
        r.readat,
        r.recordedvalue,
        r.datavolumekb,
        r.dataquality,
        CASE
            WHEN r.recordedvalue >= t.crimson_thr THEN 4
            WHEN r.recordedvalue >= t.red_thr     THEN 3
            WHEN r.recordedvalue >= t.orange_thr  THEN 2
            WHEN r.recordedvalue >= t.yellow_thr  THEN 1
            ELSE 0
        END AS alert_rank
    FROM tb_readingevent AS r
    JOIN tb_sensordevice AS sd
        ON sd.id = r.sensordevid
    LEFT JOIN param_thresholds AS t
        ON t.paramid = r.paramid
),

-- 3) Aggregate to the fact grain: Month x City x Parameter x Location Type
monthly_summary AS (
    SELECT
        month_key,
        cityid,
        paramid,
        locationtype,
        MAX(alert_rank)                                        AS peak_alert_rank,
        COUNT(*)                                               AS reading_count,
        SUM(datavolumekb)                                      AS data_volume_kb_sum,
        SUM(recordedvalue)                                     AS recordedvalue_sum,
        MIN(recordedvalue)                                     AS recordedvalue_min,
        MAX(recordedvalue)                                     AS recordedvalue_max,
        SUM(dataquality)                                       AS data_quality_sum,
        COUNT(DISTINCT readat)                                 AS days_with_readings_count,
        COUNT(DISTINCT CASE WHEN alert_rank >= 1 THEN readat END) AS alert_days_count,
        SUM(CASE WHEN alert_rank >= 1 THEN 1 ELSE 0 END)       AS alert_reading_count,
        SUM(CASE WHEN alert_rank >= 3 THEN 1 ELSE 0 END)       AS severe_alert_reading_count
    FROM classified_readings
    GROUP BY month_key, cityid, paramid, locationtype
)

-- 4) Resolve the five dimension keys and insert the fact rows
INSERT INTO ft_param_city_month_location (
    month_key,
    city_key,
    param_key,
    locationtype_key,
    alertlevel_key,
    reading_count,
    data_volume_kb_sum,
    recordedvalue_sum,
    recordedvalue_min,
    recordedvalue_max,
    data_quality_sum,
    days_with_readings_count,
    alert_days_count,
    alert_reading_count,
    severe_alert_reading_count
)
SELECT
    tm.month_key,
    dc.city_key,
    dp.param_key,
    dl.locationtype_key,
    da.alertlevel_key,
    ms.reading_count,
    ms.data_volume_kb_sum,
    ms.recordedvalue_sum,
    ms.recordedvalue_min,
    ms.recordedvalue_max,
    ms.data_quality_sum,
    ms.days_with_readings_count,
    ms.alert_days_count,
    ms.alert_reading_count,
    ms.severe_alert_reading_count
FROM monthly_summary AS ms
JOIN tb_city    AS c  ON c.id  = ms.cityid
JOIN tb_country AS co ON co.id = c.countryid
JOIN tb_param   AS p  ON p.id  = ms.paramid
JOIN dim_timemonth    AS tm ON tm.month_key     = ms.month_key
JOIN dim_city         AS dc ON dc.country_name  = co.countryname
                           AND dc.city_name     = c.cityname
JOIN dim_param        AS dp ON dp.param_name    = p.paramname
JOIN dim_locationtype AS dl ON dl.location_type = ms.locationtype
JOIN dim_alertlevel   AS da ON da.alert_rank    = ms.peak_alert_rank
ORDER BY tm.month_key, dc.city_key, dp.param_key, dl.locationtype_key;
