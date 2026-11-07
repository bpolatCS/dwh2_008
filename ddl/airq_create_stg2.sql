-- DWH2 staging DDL
-- Creates the standard AirQ OLTP snapshot tables in the active staging schema.
-- The orchestrator supplies the correct search_path before this file is executed.

-- -------------------------------
-- 1) DROP TABLE before attempting to create OLTP snapshot tables
-- -------------------------------
DROP TABLE IF EXISTS tb_serviceevent;
DROP TABLE IF EXISTS tb_readingevent;
DROP TABLE IF EXISTS tb_weather;
DROP TABLE IF EXISTS tb_sensordevice;
DROP TABLE IF EXISTS tb_paramsensortype;
DROP TABLE IF EXISTS tb_sensortype;
DROP TABLE IF EXISTS tb_paramalert;
DROP TABLE IF EXISTS tb_param;
DROP TABLE IF EXISTS tb_alert;
DROP TABLE IF EXISTS tb_readingmode;
DROP TABLE IF EXISTS tb_city;
DROP TABLE IF EXISTS tb_country;
DROP TABLE IF EXISTS tb_employee;
DROP TABLE IF EXISTS tb_role;
DROP TABLE IF EXISTS tb_servicetype;

-- -------------------------------
-- 2) CREATE TABLE statements
-- Please make sure the order in which individual statements are executed respects the FOREIGN KEY constraints
-- -------------------------------

CREATE TABLE tb_servicetype (
    id INT NOT NULL PRIMARY KEY
    , typename VARCHAR(255) NOT NULL
    , category VARCHAR(255) NOT NULL -- 'Hardware', 'Software', 'Diagnostics', 'Calibration'
    , minlevel INT NOT NULL -- 1-Entry, 2-Junior, 3-Senior, 4-Lead
    , servicegroup VARCHAR(255) NOT NULL
    , details VARCHAR(255) NOT NULL 
    , CHECK (minlevel IN (1, 2, 3, 4))
    , CHECK (category IN ('Hardware', 'Software', 'Diagnostics', 'Calibration'))
);

CREATE TABLE tb_role (
    id INT NOT NULL PRIMARY KEY
    , rolelevel INT NOT NULL -- 1-Entry, 2-Junior, 3-Senior, 4-Lead
    , category VARCHAR(255) NOT NULL -- 'Hardware', 'Software', 'Diagnostics', 'Calibration'
    , rolename VARCHAR(255) NOT NULL
    , CHECK (rolelevel IN (1, 2, 3, 4))    
    , CHECK (category IN ('Hardware', 'Software', 'Diagnostics', 'Calibration'))
    , CONSTRAINT uc_role_rolename UNIQUE (rolename)    
);

CREATE TABLE tb_employee (
    id INT NOT NULL PRIMARY KEY
    , roleid INT NOT NULL
    , badgenumber VARCHAR(255) NOT NULL -- tb_employee rows are role assignments between validfrom and validto dates for a given badgenumber (not distinct employees)
    , validfrom DATE NOT NULL
    , validto DATE NULL -- Chronologically last role has value of validto set to NULL
    , CONSTRAINT fk_employee_roleid FOREIGN KEY (roleid) REFERENCES tb_role(id)
);

CREATE TABLE tb_country (
    id INT NOT NULL PRIMARY KEY
    , countryname VARCHAR(255) NOT NULL
    , population INT NOT NULL
    , CONSTRAINT uc_country_countryname UNIQUE (countryname)
);

CREATE TABLE tb_city (
    id INT NOT NULL PRIMARY KEY
    , countryid INT NOT NULL
    , cityname VARCHAR(255) NOT NULL
    , population INT NOT NULL
    , latitude DECIMAL(10,4) NOT NULL
    , longitude DECIMAL(10,4) NOT NULL
    , CONSTRAINT uc_city_countryid_cityname UNIQUE (countryid, cityname)
    , CONSTRAINT fk_city_countryid FOREIGN KEY (countryid) REFERENCES tb_country(id)
);

CREATE TABLE tb_readingmode (
    id INT NOT NULL PRIMARY KEY
    , modename VARCHAR(255) NOT NULL
    , latency INT NOT NULL -- Latency in seconds = 1, 2, 5 or 10 seconds
    , validfrom DATE NOT NULL
    , validto DATE NULL
    , details VARCHAR(255) NOT NULL
    , CHECK (modename IN ('Rapid', 'Low Power', 'Standard', 'High Precision'))    
    , CHECK (latency IN (1, 2, 5, 10))        
);

CREATE TABLE tb_alert (
    id INT NOT NULL PRIMARY KEY
    , alertname VARCHAR(255) NOT NULL -- 1-Yellow, 2-Orange, 3-Red, 4-Crimson
    , colour VARCHAR(255) NOT NULL -- 1-Yellow, 2-Orange, 3-Red, 4-Dark Red
    , details VARCHAR(255) NOT NULL
    , CONSTRAINT uc_alert_alertname UNIQUE (alertname)	
);

CREATE TABLE tb_param (
    id INT NOT NULL PRIMARY KEY
    , paramname VARCHAR(255) NOT NULL
    , category VARCHAR(255) NOT NULL
    , purpose VARCHAR(50) NOT NULL
    , unit VARCHAR(255) NOT NULL
    , CHECK (category IN ('Particulate matter', 'Gas', 'Heavy Metal', 'Volatile Organic Compound', 'Biological'))
    , CHECK (purpose IN ('Health Risk', 'Comfort', 'Environmental Monitoring', 'Scientific Study', 'Regulatory Compliance'))
    , CONSTRAINT uc_param_paramname UNIQUE (paramname)
);

CREATE TABLE tb_paramalert (
    id INT NOT NULL PRIMARY KEY
    , paramid INT NOT NULL
    , alertid INT NOT NULL
    , threshold DECIMAL(10,4) NOT NULL
    , CONSTRAINT fk_paramalert_paramid FOREIGN KEY (paramid) REFERENCES tb_param(id)
    , CONSTRAINT fk_paramalert_alertid FOREIGN KEY (alertid) REFERENCES tb_alert(id)
    , CONSTRAINT uc_param_alert UNIQUE (paramid, alertid)
);

CREATE TABLE tb_sensortype (
    id INT NOT NULL PRIMARY KEY
    , typename VARCHAR(255) NOT NULL
    , manufacturer VARCHAR(255) NOT NULL
    , technology VARCHAR(255) NOT NULL
    , CHECK (manufacturer IN ('Sensirion', 'Bosch', 'Honeywell', 'Other'))
    , CHECK (technology IN ('Optical', 'Electrochemical', 'Laser'))
);

CREATE TABLE tb_paramsensortype (
    id INT NOT NULL PRIMARY KEY
    , sensortypeid INT NOT NULL
    , paramid INT NOT NULL
    , accuracy VARCHAR(255) NOT NULL
    , CHECK (accuracy IN ('High', 'Medium', 'Low'))
    , CONSTRAINT fk_paramsensortype_sensortypeid FOREIGN KEY (sensortypeid) REFERENCES tb_sensortype(id)
    , CONSTRAINT fk_paramsensortype_paramid FOREIGN KEY (paramid) REFERENCES tb_param(id)
    , CONSTRAINT uc_param_sensortype UNIQUE (paramid, sensortypeid)
);

CREATE TABLE tb_sensordevice (
    id INT NOT NULL PRIMARY KEY
    , sensortypeid INT NOT NULL
    , cityid INT NOT NULL
    , locationname VARCHAR(255) NOT NULL
    , locationtype VARCHAR(255) NOT NULL
    , altitude INT NOT NULL
    , installedat DATE NOT NULL
    , CHECK (locationtype IN ('Urban', 'Suburban', 'Industrial', 'Other'))
    , CONSTRAINT fk_sensordevice_sensortypeid FOREIGN KEY (sensortypeid) REFERENCES tb_sensortype(id)
    , CONSTRAINT fk_sensordevice_cityid FOREIGN KEY (cityid) REFERENCES tb_city(id)
);

CREATE TABLE tb_weather (
    id INT NOT NULL PRIMARY KEY
    , cityid INT NOT NULL
    , observedat DATE NOT NULL -- The observation date (YYYY-MM-DD)
    , tempdaymin DECIMAL(6,1) NULL -- The minimum air temperature in degrees Celsius
    , tempdaymax DECIMAL(6,1) NULL -- The maximum air temperature in degrees Celsius
    , tempdayavg DECIMAL(6,1) NULL -- The average air temperature in degrees Celsius
    , precipmm DECIMAL(6,1) NULL -- The daily precipitation total in mm
    , pressure DECIMAL(6,1) NULL -- The average sea-level air pressure in hPa
    , windspeed DECIMAL(6,1) NULL -- The average wind speed in km/h
    , windgusts DECIMAL(6,1) NULL -- The peak wind gust in km/h
    , CONSTRAINT fk_weather_cityid FOREIGN KEY (cityid) REFERENCES tb_city(id)
    , CONSTRAINT uc_city_observedat UNIQUE (cityid, observedat)
);

CREATE TABLE tb_readingevent (
    id INT NOT NULL PRIMARY KEY
    , sensordevid INT NOT NULL
    , paramid INT NOT NULL
    , readingmodeid INT NOT NULL
    , readat DATE NOT NULL
    , recordedvalue DECIMAL(10,4) NOT NULL
    , datavolumekb INT NOT NULL
    , dataquality INT NOT NULL -- (1..5) data quality score
    , CHECK (dataquality BETWEEN 1 AND 5)
    , CONSTRAINT fk_readingevent_sensordevid FOREIGN KEY (sensordevid) REFERENCES tb_sensordevice(id)
    , CONSTRAINT fk_readingevent_paramid FOREIGN KEY (paramid) REFERENCES tb_param(id)
    , CONSTRAINT fk_readingevent_readingmodeid FOREIGN KEY (readingmodeid) REFERENCES tb_readingmode(id)
);

CREATE TABLE tb_serviceevent (
    id INT NOT NULL PRIMARY KEY
    , servicetypeid INT NOT NULL
    , employeeid INT NOT NULL
    , sensordevid INT NOT NULL
    , servicedat DATE NOT NULL
    , servicecost INT NOT NULL -- cost metric
    , durationminutes INT NOT NULL -- duration metric
    , servicequality INT NOT NULL -- (1..5) rating
	, CHECK (servicecost >= 0)
	, CHECK (durationminutes >= 0)
	, CHECK (servicequality BETWEEN 1 AND 5)	
    , CONSTRAINT fk_serviceevent_servicetypeid FOREIGN KEY (servicetypeid) REFERENCES tb_servicetype(id)
    , CONSTRAINT fk_serviceevent_employeeid FOREIGN KEY (employeeid) REFERENCES tb_employee(id)
    , CONSTRAINT fk_serviceevent_sensordevid FOREIGN KEY (sensordevid) REFERENCES tb_sensordevice(id)
);
