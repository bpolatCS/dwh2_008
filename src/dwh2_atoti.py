"""Atoti 6.2.2 cube configuration for DWH2.

The notebook owns the database connection and calls build_atoti_cube(). This
module reads only from the populated dwh2_<group> schema, imports Atoti lazily,
and creates five linked dimension tables plus one fact table in Atoti.

No MDX authoring is required. Technical measures remain hidden in the UI.
The cube is an in-memory snapshot; re-run after rebuilding PostgreSQL data.
"""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version
from numbers import Number
import re
from typing import Any

import pandas as pd
from sqlalchemy import text
from sqlalchemy.engine import Engine


CUBE_NAME = "AirQ DWH2"

# The SQL projections are intentionally explicit: timestamps, source IDs, etc.
# are not accidentally exposed as misleading drill-down axes or measures.
_TABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "dim_timemonth": (
        "month_key", "year_num", "quarter_num", "month_num",
        "month_name", "days_in_month",
    ),
    "dim_city": ("city_key", "country_name", "city_name"),
    "dim_param": ("param_key", "param_name", "category", "purpose", "unit"),
    "dim_locationtype": ("locationtype_key", "location_type"),
    "dim_alertlevel": ("alertlevel_key", "alert_level_name", "alert_rank"),
    "ft_param_city_month_location": (
        "ft_pcml_key", "month_key", "city_key", "param_key",
        "locationtype_key", "alertlevel_key", "reading_count",
        "data_volume_kb_sum", "recordedvalue_sum", "recordedvalue_min",
        "recordedvalue_max", "data_quality_sum", "days_with_readings_count",
        "alert_days_count", "alert_reading_count", "severe_alert_reading_count",
    ),
}
_TABLE_KEYS = {
    "dim_timemonth": "month_key",
    "dim_city": "city_key",
    "dim_param": "param_key",
    "dim_locationtype": "locationtype_key",
    "dim_alertlevel": "alertlevel_key",
    "ft_param_city_month_location": "ft_pcml_key",
}
_FK_TABLES = {
    "month_key": "dim_timemonth",
    "city_key": "dim_city",
    "param_key": "dim_param",
    "locationtype_key": "dim_locationtype",
    "alertlevel_key": "dim_alertlevel",
}
_MONTH_NAMES = (
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)
_ALERT_ORDER = ("None", "Yellow", "Orange", "Red", "Crimson")

# Atoti 6.2.2 requires every hierarchy level's source column to have a
# non-null default value.  These defaults are fallbacks for missing input;
# the warehouse DDL already requires real dimension values to be NOT NULL.
# Only columns used to build the seven configured hierarchies are listed.
_HIERARCHY_DEFAULT_VALUES: dict[str, dict[str, int | str]] = {
    "dim_timemonth": {"Year": 0, "Quarter": 0, "Month": "Unknown"},
    "dim_city": {"Country": "Unknown", "City": "Unknown"},
    "dim_param": {
        "Category": "Unknown",
        "Parameter": "Unknown",
        "Purpose": "Unknown",
        "Parameter by Purpose": "Unknown",
        "Unit": "Unknown",
    },
    "dim_locationtype": {"Location Type": "Unknown"},
    "dim_alertlevel": {"Peak Alert Level": "Unknown"},
}

# Visible measures provided in the DWH2 Atoti pivots.
VISIBLE_MEASURES = (
    "Readings",
    "Data volume (KB)",
    "Alert readings",
    "Severe alert readings",
    "Alert reading rate",
    "Severe alert reading rate",
    "Average KB per reading",
    "Average data quality",
    "Average recorded value (same parameter)",
    "Minimum recorded value (same parameter)",
    "Maximum recorded value (same parameter)",
    "Recorded value range (same parameter)",
    "Active days (fact combinations)",
    "Alert days (fact combinations)",
    "Alert day rate (fact combinations)",
    "Reading-day coverage (fact combinations)",
)


ATOTI_VERSION = "6.2.2"
_ATOTI_COMPONENTS = ("atoti", "atoti-client", "atoti-core", "atoti-server")


def check_atoti_environment() -> dict[str, str]:
    """Confirm the Jupyter interpreter has the approved matching Atoti 6.2.2 packages.

    The conda YAML is the installation authority; runtime checks only *verify*
    the active kernel and never upgrade or reinstall anything.
    """
    installed: dict[str, str] = {}
    problems: list[str] = []
    for package in _ATOTI_COMPONENTS:
        try:
            installed[package] = version(package)
        except PackageNotFoundError:
            problems.append(f"{package} is not installed")
            continue
        if installed[package] != ATOTI_VERSION:
            problems.append(
                f"{package}=={installed[package]} (expected {ATOTI_VERSION})"
            )
    if problems:
        raise RuntimeError(
            "The notebook requires Atoti 6.2.2 in its active 'dwh' kernel. "
            + "; ".join(problems)
            + ". Install/upgrade atoti==6.2.2 using the approved "
              "environment-dwh.yaml, then restart the Jupyter kernel."
        )
    return installed


def _import_atoti() -> Any:
    check_atoti_environment()
    import atoti as tt
    return tt


def read_star_frames(engine: Engine, warehouse_schema: str) -> dict[str, pd.DataFrame]:
    """Read the six existing warehouse tables; check row identity and FK coverage.

    The schema name comes from the notebook, never an ETL or DDL file. This
    method only issues SELECT statements, with controlled table/column names.
    """
    if not re.fullmatch(r"dwh2_\d{3}", warehouse_schema):
        raise ValueError(f"Expected a group DWH2 schema like 'dwh2_007', got {warehouse_schema!r}.")

    frames: dict[str, pd.DataFrame] = {}
    for name, columns in _TABLE_COLUMNS.items():
        projection = ", ".join(f'"{col}"' for col in columns)
        query = text(f'SELECT {projection} FROM "{warehouse_schema}"."{name}"')
        frame = pd.read_sql_query(query, con=engine)
        key = _TABLE_KEYS[name]
        if frame.empty:
            raise RuntimeError(f"{warehouse_schema}.{name} is empty; run the ETL first.")
        if frame[key].isna().any() or frame.duplicated([key]).any():
            raise RuntimeError(f"{warehouse_schema}.{name} contains null/duplicate {key} values.")
        frames[name] = frame

    fact = frames["ft_param_city_month_location"]
    for fk, dim_name in _FK_TABLES.items():
        missing = (~fact[fk].isin(frames[dim_name][fk])).sum()
        if missing:
            raise RuntimeError(f"Atoti load: {missing} fact rows have unmatched {fk} in {dim_name}.")

    month = frames["dim_timemonth"]
    # Only an Atoti helper column, NOT a new PostgreSQL fact measure. This
    # denominator counts one calendar month's days *per fact combination*.
    days = month.set_index("month_key")["days_in_month"]
    fact["calendar_days_fact"] = fact["month_key"].map(days)
    if fact["calendar_days_fact"].isna().any():
        raise RuntimeError("Cannot derive fact-grain calendar-day coverage.")

    # SQL NUMERIC is returned as Decimal on some PostgreSQL drivers; Atoti
    # loads these three measurement columns reliably as float64 instead.
    # Floating-point precision is adequate for display; source remains exact.
    for col in ("recordedvalue_sum", "recordedvalue_min", "recordedvalue_max"):
        fact[col] = pd.to_numeric(fact[col]).astype("float64")

    month.rename(columns={
        "year_num": "Year", "quarter_num": "Quarter", "month_name": "Month"
    }, inplace=True)
    frames["dim_city"].rename(columns={
        "country_name": "Country", "city_name": "City"
    }, inplace=True)
    param = frames["dim_param"]
    param.rename(columns={
        "param_name": "Parameter", "category": "Category",
        "purpose": "Purpose", "unit": "Unit"
    }, inplace=True)
    # Two independent leaf levels: category and purpose are NOT nested.
    param["Parameter by Purpose"] = param["Parameter"].copy()
    frames["dim_locationtype"].rename(columns={
        "location_type": "Location Type"
    }, inplace=True)
    frames["dim_alertlevel"].rename(columns={
        "alert_level_name": "Peak Alert Level"
    }, inplace=True)

    return frames


def _create_hierarchies(cube: Any, tables: dict[str, Any], tt: Any) -> None:
    h = cube.hierarchies
    t = tables["dim_timemonth"]
    c = tables["dim_city"]
    p = tables["dim_param"]
    loc = tables["dim_locationtype"]
    a = tables["dim_alertlevel"]

    h["Calendar"] = [t["Year"], t["Quarter"], t["Month"]]
    h["Calendar"].dimension_name = "Time"
    h["Geography"] = [c["Country"], c["City"]]
    h["Geography"].dimension_name = "City"
    h["Category and Parameter"] = [p["Category"], p["Parameter"]]
    h["Category and Parameter"].dimension_name = "Parameter"
    h["Purpose and Parameter"] = [p["Purpose"], p["Parameter by Purpose"]]
    h["Purpose and Parameter"].dimension_name = "Parameter"
    h["Unit"] = [p["Unit"]]
    h["Unit"].dimension_name = "Parameter"
    h["Location"] = [loc["Location Type"]]
    h["Location"].dimension_name = "Location Type"
    h["Peak Alert"] = [a["Peak Alert Level"]]
    h["Peak Alert"].dimension_name = "Peak Alert Level"

    cube.levels["Month"].ordering = tt.Ordering(first=list(_MONTH_NAMES))
    cube.levels["Peak Alert Level"].ordering = tt.Ordering(first=list(_ALERT_ORDER))
    cube.levels["Location Type"].ordering = tt.Ordering(
        first=["Urban", "Suburban", "Industrial", "Other"]
    )


def _create_measures(cube: Any, fact: Any, tt: Any) -> None:
    m = cube.measures

    def register(name: str, definition: Any, *, folder: str, description: str,
                 formatter: str | None = None, visible: bool = True) -> None:
        m[name] = definition
        measure = m[name]
        measure.description = description
        measure.folder = folder
        measure.visible = visible
        if formatter is not None:
            measure.formatter = formatter

    count_fmt = "INT[#,###]"
    decimal_fmt = "DOUBLE[#,##0.00]"
    pct_fmt = "DOUBLE[0.00%]"

    register("Readings", tt.agg.sum(fact["reading_count"]), folder="01 Volume",
             description="Number of source ReadingEvents represented by fact rows.", formatter=count_fmt)
    register("Data volume (KB)", tt.agg.sum(fact["data_volume_kb_sum"]), folder="01 Volume",
             description="Total telemetry KB; additive across all dimensions.", formatter=count_fmt)
    register("Alert readings", tt.agg.sum(fact["alert_reading_count"]), folder="02 Alerts",
             description="Count of readings classified Yellow or higher.", formatter=count_fmt)
    register("Severe alert readings", tt.agg.sum(fact["severe_alert_reading_count"]), folder="02 Alerts",
             description="Count of readings classified Red or Crimson.", formatter=count_fmt)
    register("Alert reading rate", m["Alert readings"] / m["Readings"], folder="02 Alerts",
             description="Alert readings / all readings. Weighted correctly across fact rows.",
             formatter=pct_fmt)
    register("Severe alert reading rate", m["Severe alert readings"] / m["Readings"],
             folder="02 Alerts", description="Severe (Red+Crimson) readings / all readings.",
             formatter=pct_fmt)
    register("Average KB per reading", m["Data volume (KB)"] / m["Readings"],
             folder="01 Volume", description="Total telemetry KB / reading count.",
             formatter=decimal_fmt)

    register("_technical_quality_sum", tt.agg.sum(fact["data_quality_sum"]),
             folder="_Internal", description="Technical numerator; not a standalone business metric.",
             visible=False)
    register("Average data quality", m["_technical_quality_sum"] / m["Readings"],
             folder="03 Data quality", description="Weighted mean of the source 1-5 score.",
             formatter=decimal_fmt)

    record_note = (
        "Only meaningful for ONE selected parameter. Never combine different "
        "parameters or incompatible units into a numeric average/min/max."
    )
    register("_technical_recordedvalue_sum", tt.agg.sum(fact["recordedvalue_sum"]),
             folder="_Internal", description="Technical numerator for parameter-specific averages.",
             visible=False)
    register("Average recorded value (same parameter)",
             m["_technical_recordedvalue_sum"] / m["Readings"], folder="04 Recorded values",
             description="Weighted average of recorded values. " + record_note,
             formatter=decimal_fmt)
    register("Minimum recorded value (same parameter)", tt.agg.min(fact["recordedvalue_min"]),
             folder="04 Recorded values", description="Minimum of monthly fact minima. " + record_note,
             formatter=decimal_fmt)
    register("Maximum recorded value (same parameter)", tt.agg.max(fact["recordedvalue_max"]),
             folder="04 Recorded values", description="Maximum of monthly fact maxima. " + record_note,
             formatter=decimal_fmt)
    register("Recorded value range (same parameter)",
             m["Maximum recorded value (same parameter)"] - m["Minimum recorded value (same parameter)"],
             folder="04 Recorded values", description="Global max minus min. " + record_note,
             formatter=decimal_fmt)

    day_note = (
        "SUM of days counted separately for each Month x City x Param x Location Type "
        "fact row, NOT distinct city-wide/calendar days across parameters or locations."
    )
    register("Active days (fact combinations)", tt.agg.sum(fact["days_with_readings_count"]),
             folder="05 Fact-combination days", description=day_note, formatter=count_fmt)
    register("Alert days (fact combinations)", tt.agg.sum(fact["alert_days_count"]),
             folder="05 Fact-combination days", description=day_note + " A day alerts if any reading is Yellow+.",
             formatter=count_fmt)
    register("Alert day rate (fact combinations)",
             m["Alert days (fact combinations)"] / m["Active days (fact combinations)"],
             folder="05 Fact-combination days",
             description="Alert fact-combination days / active fact-combination days; " + day_note,
             formatter=pct_fmt)
    register("_technical_calendar_days_fact", tt.agg.sum(fact["calendar_days_fact"]),
             folder="_Internal", description="Calendar days per fact row (not city-wide days).",
             visible=False)
    register("Reading-day coverage (fact combinations)",
             m["Active days (fact combinations)"] / m["_technical_calendar_days_fact"],
             folder="05 Fact-combination days", description="Active days / potential calendar days, " + day_note,
             formatter=pct_fmt)

    # Hide engine-generated technical measures: neither a fact-row count
    # nor a cube update timestamp should appear as a student business measure.
    for technical_name in ("contributors.COUNT", "update.TIMESTAMP"):
        if technical_name in m:
            m[technical_name].visible = False


def build_atoti_cube(engine: Engine, warehouse_schema: str) -> tuple[Any, Any, dict[str, int]]:
    """Start a fresh Atoti 6.2.2 session and load the six DWH2 star tables.

    Returns (session, cube, expected_totals). Keep the session referenced in
    the notebook; its web app is live while the Jupyter kernel is running.
    """
    tt = _import_atoti()
    frames = read_star_frames(engine, warehouse_schema)
    fact_frame = frames["ft_param_city_month_location"]
    expected_totals = {
        "Readings": int(fact_frame["reading_count"].sum()),
        "Data volume (KB)": int(fact_frame["data_volume_kb_sum"].sum()),
        "Alert readings": int(fact_frame["alert_reading_count"].sum()),
        "Severe alert readings": int(fact_frame["severe_alert_reading_count"].sum()),
        "Fact rows": int(len(fact_frame)),
    }

    session = tt.Session.start()
    tables = {
        name: session.read_pandas(
            frame,
            keys=[_TABLE_KEYS[name]],
            table_name=name,
            default_values=_HIERARCHY_DEFAULT_VALUES.get(name, {}),
        )
        for name, frame in frames.items()
    }
    fact = tables["ft_param_city_month_location"]
    for key, dimension in _FK_TABLES.items():
        fact.join(tables[dimension], fact[key] == tables[dimension][key])

    cube = session.create_cube(fact, CUBE_NAME, mode="manual")
    _create_hierarchies(cube, tables, tt)
    _create_measures(cube, fact, tt)
    print(f"Atoti cube '{CUBE_NAME}' built from {expected_totals['Fact rows']:,} DWH2 fact rows.")
    print(f"Atoti UI: {session.url}")
    return session, cube, expected_totals


def _number(value: Any) -> float:
    if isinstance(value, Number):
        return float(value)
    return float(str(value).replace(",", "").strip())


def validate_atoti_totals(cube: Any, expected: dict[str, int]) -> pd.DataFrame:
    """Compare the live cube totals to the PostgreSQL fact data just loaded."""
    names = ("Readings", "Data volume (KB)", "Alert readings", "Severe alert readings")
    result = cube.query(*(cube.measures[name] for name in names))
    if len(result) != 1:
        raise RuntimeError(f"Expected exactly one Atoti grand-total row, got {len(result)}.")
    checks = []
    for name in names:
        observed = _number(result.iloc[0][name])
        wanted = int(expected[name])
        status = "PASS" if abs(observed - wanted) <= 0.5 else "FAIL"
        checks.append({"measure": name, "warehouse": wanted, "cube": observed, "status": status})
    summary = pd.DataFrame(checks)
    if (summary["status"] != "PASS").any():
        raise RuntimeError("Atoti total mismatch; inspect the Atoti validation table.")
    return summary
