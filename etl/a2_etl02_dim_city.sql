-- DWH2 A2 ETL 02/06: dim_city
-- Table names are unqualified; the session search_path is configured externally.
-- Source: tb_city and tb_country
-- Target: dim_city
-- Country is denormalized into the City dimension; no Region is invented.

INSERT INTO dim_city (
    country_name, city_name, city_population, latitude, longitude
)
SELECT
    co.countryname AS country_name,
    c.cityname     AS city_name,
    c.population   AS city_population,
    c.latitude,
    c.longitude
FROM tb_city AS c
JOIN tb_country AS co
    ON co.id = c.countryid
ORDER BY co.countryname, c.cityname;
