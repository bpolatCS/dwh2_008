-- DWH2 A2 ETL 05/06: dim_alertlevel
-- Table names are unqualified; the session search_path is configured externally.
-- Fixed analytical ladder, including the derived 'None' (rank 0).
-- The source defines alert thresholds for Yellow, Orange, Red, Crimson.
-- Alert dimension keys are generated; the ETL resolves them by alert_rank.

INSERT INTO dim_alertlevel (alert_level_name, alert_rank)
SELECT v.alert_level_name, v.alert_rank
FROM (
    VALUES
        ('None',    0),
        ('Yellow',  1),
        ('Orange',  2),
        ('Red',     3),
        ('Crimson', 4)
) AS v(alert_level_name, alert_rank)
ORDER BY v.alert_rank;
