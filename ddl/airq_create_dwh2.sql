-- DWH2 warehouse DDL
-- Grain of the fact table:
--   Month x City x Param x Location Type
-- alertlevel_key is a derived monthly peak classification and is not part of the grain.

-- The notebook creates the group-specific warehouse schema and sets
-- the transaction-local search path before executing this DDL.
-- Do not edit the supplied table definitions or manage schemas here.

-- -----------------------------------------------------------------------------
-- 1. Drop existing warehouse tables in dependency order
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS ft_param_city_month_location CASCADE;
DROP TABLE IF EXISTS dim_alertlevel CASCADE;
DROP TABLE IF EXISTS dim_locationtype CASCADE;
DROP TABLE IF EXISTS dim_param CASCADE;
DROP TABLE IF EXISTS dim_city CASCADE;
DROP TABLE IF EXISTS dim_timemonth CASCADE;

-- -----------------------------------------------------------------------------
-- 2. Dimensions
-- -----------------------------------------------------------------------------

-- 2.1 Month dimension
CREATE TABLE dim_timemonth (
    month_key       INT PRIMARY KEY,                 -- YYYYMM, e.g. 202501
    year_num        INT NOT NULL,
    quarter_num     SMALLINT NOT NULL CHECK (quarter_num BETWEEN 1 AND 4),
    month_num       SMALLINT NOT NULL CHECK (month_num BETWEEN 1 AND 12),
    month_name      VARCHAR(20) NOT NULL,
    mfirst_day      DATE NOT NULL,
    mlast_day       DATE NOT NULL,
    days_in_month   SMALLINT NOT NULL CHECK (days_in_month BETWEEN 28 AND 31),
    etl_load_ts     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uc_dim_timemonth_year_month UNIQUE (year_num, month_num),
    CONSTRAINT ck_dim_timemonth_dates CHECK (mfirst_day <= mlast_day)
);

-- 2.2 City dimension
-- Country is denormalized into the city dimension; no region attribute is invented.
CREATE TABLE dim_city (
    city_key         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_name     VARCHAR(255) NOT NULL,
    city_name        VARCHAR(255) NOT NULL,
    city_population  INT NOT NULL CHECK (city_population >= 0),
    latitude         DECIMAL(10,4) NOT NULL,
    longitude        DECIMAL(10,4) NOT NULL,
    etl_load_ts      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uc_dim_city_country_city UNIQUE (country_name, city_name)
);

-- 2.3 Parameter dimension
-- category and purpose are independent classification attributes in the source data;
-- they are not forced into one strict natural hierarchy.
CREATE TABLE dim_param (
    param_key       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    param_name      VARCHAR(255) NOT NULL,
    category        VARCHAR(255) NOT NULL,
    purpose         VARCHAR(50) NOT NULL,
    unit            VARCHAR(255) NOT NULL,
    etl_load_ts     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uc_dim_param_name UNIQUE (param_name)
);

-- 2.4 Location Type dimension
CREATE TABLE dim_locationtype (
    locationtype_key  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_type     VARCHAR(255) NOT NULL,
    etl_load_ts       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uc_dim_locationtype UNIQUE (location_type),
    CONSTRAINT ck_dim_locationtype_name
        CHECK (location_type IN ('Urban', 'Suburban', 'Industrial', 'Other'))
);

-- 2.5 Alert Level dimension
-- The ETL loads five members: None, Yellow, Orange, Red, Crimson.
CREATE TABLE dim_alertlevel (
    alertlevel_key    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_level_name  VARCHAR(50) NOT NULL,
    alert_rank        SMALLINT NOT NULL CHECK (alert_rank BETWEEN 0 AND 4),
    etl_load_ts       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uc_dim_alertlevel_name UNIQUE (alert_level_name),
    CONSTRAINT uc_dim_alertlevel_rank UNIQUE (alert_rank),
    CONSTRAINT ck_dim_alertlevel_name
        CHECK (alert_level_name IN ('None', 'Yellow', 'Orange', 'Red', 'Crimson'))
);

-- -----------------------------------------------------------------------------
-- 3. Fact table
-- -----------------------------------------------------------------------------
CREATE TABLE ft_param_city_month_location (
    ft_pcml_key                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Dimension foreign keys
    month_key                   INT NOT NULL,
    city_key                    BIGINT NOT NULL,
    param_key                   BIGINT NOT NULL,
    locationtype_key            BIGINT NOT NULL,
    alertlevel_key              BIGINT NOT NULL,

    -- Fully additive base measures
    reading_count               BIGINT NOT NULL CHECK (reading_count > 0),
    data_volume_kb_sum          BIGINT NOT NULL CHECK (data_volume_kb_sum >= 0),

    -- Recorded-value base measures.
    -- recordedvalue_sum is a technical numerator for weighted averages and should
    -- only be combined when the same parameter is retained.
    recordedvalue_sum           NUMERIC(20,4) NOT NULL,
    recordedvalue_min           NUMERIC(10,4) NOT NULL,
    recordedvalue_max           NUMERIC(10,4) NOT NULL,

    -- Technical numerator for weighted Average Data Quality.
    data_quality_sum            BIGINT NOT NULL,

    -- Day-level behavior retained inside the monthly grain.
    days_with_readings_count    SMALLINT NOT NULL
        CHECK (days_with_readings_count BETWEEN 1 AND 31),
    alert_days_count            SMALLINT NOT NULL,

    -- Additive alert-reading counts based on the shared reading-level alert rank.
    alert_reading_count         BIGINT NOT NULL,
    severe_alert_reading_count  BIGINT NOT NULL,

    etl_load_ts                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Fact grain
    CONSTRAINT uc_ft_pcml_grain
        UNIQUE (month_key, city_key, param_key, locationtype_key),

    -- Cross-measure consistency checks
    CONSTRAINT ck_ft_pcml_recordedvalue_range
        CHECK (recordedvalue_min <= recordedvalue_max),
    CONSTRAINT ck_ft_pcml_data_quality_sum
        CHECK (data_quality_sum BETWEEN reading_count AND reading_count * 5),
    CONSTRAINT ck_ft_pcml_alert_days
        CHECK (alert_days_count BETWEEN 0 AND days_with_readings_count),
    CONSTRAINT ck_ft_pcml_alert_readings
        CHECK (alert_reading_count BETWEEN 0 AND reading_count),
    CONSTRAINT ck_ft_pcml_severe_alert_readings
        CHECK (severe_alert_reading_count BETWEEN 0 AND alert_reading_count),

    -- Foreign keys
    CONSTRAINT fk_ft_pcml_time
        FOREIGN KEY (month_key) REFERENCES dim_timemonth (month_key),
    CONSTRAINT fk_ft_pcml_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key),
    CONSTRAINT fk_ft_pcml_param
        FOREIGN KEY (param_key) REFERENCES dim_param (param_key),
    CONSTRAINT fk_ft_pcml_locationtype
        FOREIGN KEY (locationtype_key) REFERENCES dim_locationtype (locationtype_key),
    CONSTRAINT fk_ft_pcml_alertlevel
        FOREIGN KEY (alertlevel_key) REFERENCES dim_alertlevel (alertlevel_key)
);

-- -----------------------------------------------------------------------------
-- 4. Helpful indexes for analytical joins and common filtering paths
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_ft_pcml_month
    ON ft_param_city_month_location (month_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_city
    ON ft_param_city_month_location (city_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_param
    ON ft_param_city_month_location (param_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_locationtype
    ON ft_param_city_month_location (locationtype_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_alertlevel
    ON ft_param_city_month_location (alertlevel_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_month_param
    ON ft_param_city_month_location (month_key, param_key);

CREATE INDEX IF NOT EXISTS ix_ft_pcml_city_locationtype
    ON ft_param_city_month_location (city_key, locationtype_key);
