-- DWH2 A2 ETL 03/06: dim_param
-- Table names are unqualified; the session search_path is configured externally.
-- Source: tb_param
-- Target: dim_param
-- Category and purpose are independent grouping attributes, not one hierarchy.

INSERT INTO dim_param (
    param_name, category, purpose, unit
)
SELECT
    paramname AS param_name,
    category,
    purpose,
    unit
FROM tb_param
ORDER BY paramname;
