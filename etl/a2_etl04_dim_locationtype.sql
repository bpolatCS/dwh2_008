-- DWH2 A2 ETL 04/06: dim_locationtype
-- Table names are unqualified; the session search_path is configured externally.
-- Source: distinct location types of installed devices.
-- Target: dim_locationtype
-- All source-supported location types are loaded, including unused ones.

INSERT INTO dim_locationtype (location_type)
SELECT DISTINCT
    locationtype AS location_type
FROM tb_sensordevice
ORDER BY location_type;
