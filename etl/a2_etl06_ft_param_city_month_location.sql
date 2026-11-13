
WITH param_thresholds AS (
    SELECT
        pa.paramid,
        MAX(CASE WHEN a.alertname = 'Yellow'  THEN pa.threshold END) AS yellow_thr,
        MAX(CASE WHEN a.alertname = 'Orange'  THEN pa.threshold END) AS orange_thr,
        MAX(CASE WHEN a.alertname = 'Red'     THEN pa.threshold END) AS red_thr,
        MAX(CASE WHEN a.alertname = 'Crimson' THEN pa.threshold END) AS crimson_thr
    FROM tb_paramalert AS pa
    JOIN tb_alert AS a ON a.id = pa.alertid
    GROUP BY pa.paramid
),

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
    INNER JOIN tb_sensordevice AS sd ON sd.id = r.sensordevid
    LEFT JOIN param_thresholds AS t
        ON t.paramid = r.paramid
),

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
LEFT JOIN tb_city    AS c  ON c.id  = ms.cityid
LEFT JOIN tb_country AS co ON co.id = c.countryid
LEFT JOIN tb_param   AS p  ON p.id  = ms.paramid
LEFT JOIN dim_timemonth    AS tm ON tm.month_key = ms.month_key
LEFT JOIN dim_city         AS dc ON dc.country_name = co.countryname AND dc.city_name = c.cityname
LEFT JOIN dim_param        AS dp ON dp.param_name = p.paramname
LEFT JOIN dim_locationtype AS dl ON dl.location_type = ms.locationtype
LEFT JOIN dim_alertlevel   AS da ON da.alert_rank = ms.peak_alert_rank
ORDER BY tm.month_key, dc.city_key, dp.param_key, dl.locationtype_key;
