
-- Assignment 2 | ETL 06/06 | Fact-table ETL
-- Target: ft_param_city_month_location
--
-- ETL 01-05 are supplied and load the five dimensions during a full run.
-- This script loads the monthly aggregated fact table.
--
-- Grain: one fact row per Month x City x Parameter x Location Type.
-- The monthly Peak Alert Level is a derived attribute, NOT part of this grain.
--
-- This implementation:
--   1. Reads staging tables and classifies individual readings
--      using parameter-specific alert thresholds.
--   2. Aggregates readings and all ten fact measures.
--      Counts DISTINCT calendar dates for the two day measures.
--   3. Determines the highest monthly alert level, resolves the five
--      dimension keys, and inserts the resulting fact rows.
--
-- Uses unqualified table names only.
-- The notebook supplies the correct search path.
-- No example or dummy rows are inserted.


-- ------------------------------------------------------------
-- 1) Prepare the alert thresholds for each parameter
-- ------------------------------------------------------------
-- Each parameter can have four alert thresholds:
-- Yellow (1), Orange (2), Red (3), and Crimson (4).
--
-- Convert the separate threshold records into one row per
-- parameter to avoid multiplying readings during joins.

WITH parameter_thresholds AS (
    SELECT
        pa.paramid,

        MAX(CASE
            WHEN a.alertname = 'Yellow'
            THEN pa.threshold
        END) AS yellow_threshold,

        MAX(CASE
            WHEN a.alertname = 'Orange'
            THEN pa.threshold
        END) AS orange_threshold,

        MAX(CASE
            WHEN a.alertname = 'Red'
            THEN pa.threshold
        END) AS red_threshold,

        MAX(CASE
            WHEN a.alertname = 'Crimson'
            THEN pa.threshold
        END) AS crimson_threshold

    FROM tb_paramalert AS pa

    JOIN tb_alert AS a
        ON pa.alertid = a.id

    GROUP BY
        pa.paramid
),


-- ------------------------------------------------------------
-- 2) Prepare individual readings and calculate alert levels
-- ------------------------------------------------------------
-- Join readings with their sensors, cities, countries,
-- parameters, and alert thresholds.
--
-- Calculate:
--   - reading_date: calendar date of each reading
--   - month_key: year and month in YYYYMM format
--   - alert_rank: highest threshold reached by each reading
--
-- Alert ranks:
--   0 = None
--   1 = Yellow
--   2 = Orange
--   3 = Red
--   4 = Crimson

reading_details AS (
    SELECT
        r.id AS reading_id,

        r.readat,
        r.readat::DATE AS reading_date,

        EXTRACT(YEAR FROM r.readat)::INT * 100
            + EXTRACT(MONTH FROM r.readat)::INT
            AS month_key,

        r.recordedvalue,
        r.datavolumekb,
        r.dataquality,

        s.cityid,
        s.locationtype,

        r.paramid,

        CASE
            WHEN r.recordedvalue >= pt.crimson_threshold THEN 4
            WHEN r.recordedvalue >= pt.red_threshold THEN 3
            WHEN r.recordedvalue >= pt.orange_threshold THEN 2
            WHEN r.recordedvalue >= pt.yellow_threshold THEN 1
            ELSE 0
        END AS alert_rank

    FROM tb_readingevent AS r

    JOIN tb_sensordevice AS s
        ON r.sensorid = s.id

    JOIN tb_city AS c
        ON s.cityid = c.id

    JOIN tb_country AS co
        ON c.countryid = co.id

    JOIN tb_param AS p
        ON r.paramid = p.id

    JOIN parameter_thresholds AS pt
        ON r.paramid = pt.paramid
),


-- ------------------------------------------------------------
-- 3) Aggregate readings at the required monthly grain
-- ------------------------------------------------------------
-- Group readings by:
--   - Month
--   - City
--   - Parameter
--   - Location Type
--
-- Calculate the ten required fact measures.
--
-- FILTER is used for conditional counts.
-- DISTINCT ensures that multiple readings on the same
-- calendar date count as only one monitoring or alert day.
--
-- MAX(alert_rank) determines the peak alert for the group.
-- Peak alert is NOT included in the GROUP BY.

monthly_summary AS (
    SELECT
        month_key,
        cityid,
        paramid,
        locationtype,

        -- Total number of readings
        COUNT(*) AS reading_count,

        -- Total data volume
        SUM(datavolumekb) AS data_volume_kb_sum,

        -- Recorded value measures
        SUM(recordedvalue) AS recordedvalue_sum,
        MIN(recordedvalue) AS recordedvalue_min,
        MAX(recordedvalue) AS recordedvalue_max,

        -- Total data quality
        SUM(dataquality) AS data_quality_sum,

        -- Number of distinct days with readings
        COUNT(DISTINCT reading_date)
            AS days_with_readings_count,

        -- Number of distinct days with Yellow or higher alerts
        COUNT(DISTINCT reading_date)
            FILTER (WHERE alert_rank >= 1)
            AS alert_days_count,

        -- Number of readings with Yellow or higher alerts
        COUNT(*)
            FILTER (WHERE alert_rank >= 1)
            AS alert_reading_count,

        -- Number of readings with Red or Crimson alerts
        COUNT(*)
            FILTER (WHERE alert_rank >= 3)
            AS severe_alert_reading_count,

        -- Highest alert level reached during the month
        MAX(alert_rank) AS peak_alert_rank

    FROM reading_details

    GROUP BY
        month_key,
        cityid,
        paramid,
        locationtype
)


-- ------------------------------------------------------------
-- 4) Insert aggregated data into the fact table
-- ------------------------------------------------------------
-- Insert one row for each Month x City x Parameter x
-- Location Type combination.
--
-- Resolve the five warehouse dimension keys:
--   1. month_key
--   2. city_key
--   3. param_key
--   4. locationtype_key
--   5. alertlevel_key
--
-- The source cityid and paramid are used for lookups.
-- The fact table stores the warehouse dimension keys.

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
    ms.month_key,
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


-- ------------------------------------------------------------
-- 5) Resolve the time dimension
-- ------------------------------------------------------------
-- Match the calculated YYYYMM key to dim_timemonth.

JOIN dim_timemonth AS dt
    ON ms.month_key = dt.month_key


-- ------------------------------------------------------------
-- 6) Resolve the city dimension
-- ------------------------------------------------------------
-- Find the source city and its country.
-- Match both city and country names to the warehouse
-- dimension to identify the correct city_key.

JOIN tb_city AS c
    ON ms.cityid = c.id

JOIN tb_country AS co
    ON c.countryid = co.id

JOIN dim_city AS dc
    ON dc.city_name = c.cityname
    AND dc.country_name = co.countryname


-- ------------------------------------------------------------
-- 7) Resolve the parameter dimension
-- ------------------------------------------------------------
-- Match the source parameter name to the warehouse
-- parameter dimension.

JOIN tb_param AS p
    ON ms.paramid = p.id

JOIN dim_param AS dp
    ON dp.param_name = p.paramname


-- ------------------------------------------------------------
-- 8) Resolve the location type dimension
-- ------------------------------------------------------------
-- Match the sensor's location type to the warehouse
-- location type dimension.

JOIN dim_locationtype AS dl
    ON dl.location_type = ms.locationtype


-- ------------------------------------------------------------
-- 9) Resolve the peak alert level dimension
-- ------------------------------------------------------------
-- Match the highest monthly alert rank to the warehouse
-- alert level dimension.
--
-- The peak alert is a derived foreign key.
-- It is not part of the monthly aggregation grain.

JOIN dim_alertlevel AS da
    ON da.alert_rank = ms.peak_alert_rank;
