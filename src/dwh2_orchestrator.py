"""Orchestration helpers for the DWH2 notebook.

Mirrors the DWH1 notebook style: connection, preflight, schema reset,
CSV ingestion, SQL execution, reference checks, and portable pg_dump.
The Python code does not implement student ETL. SQL remains in etl/.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
from getpass import getpass
from pathlib import Path
from typing import Sequence
from urllib.parse import quote_plus

import pandas as pd
import sqlparse
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, make_url


_GROUP_RE = re.compile(r"^\d{3}$")
_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_SEARCH_PATH_RE = re.compile(r"\bSET\s+(?:LOCAL\s+)?search_path\s+TO\b", re.IGNORECASE)
_QUALIFIED_SCHEMA_RE = re.compile(r"\b(?:stg1|stg2|dwh1|dwh2)_(?:nnn|\d{3})\s*\.", re.IGNORECASE)
_DATE_SUFFIXES = ("from", "to", "at")

# This is the correct, foreign-key-safe load order of the standard AirQ snapshot.
STANDARD_CSV_ORDER = (
    "tb_servicetype", "tb_role", "tb_employee", "tb_country", "tb_city",
    "tb_readingmode", "tb_alert", "tb_param", "tb_paramalert",
    "tb_sensortype", "tb_paramsensortype", "tb_sensordevice",
    "tb_weather", "tb_serviceevent", "tb_readingevent",
)

STAGING_DDL = "airq_create_stg2.sql"
WAREHOUSE_DDL = "airq_create_dwh2.sql"  # Provided warehouse definition with schema-neutral SQL.
ETL_FILES = (
    "a2_etl01_dim_timemonth.sql",
    "a2_etl02_dim_city.sql",
    "a2_etl03_dim_param.sql",
    "a2_etl04_dim_locationtype.sql",
    "a2_etl05_dim_alertlevel.sql",
    "a2_etl06_ft_param_city_month_location.sql",
)

def _single_group_csv(root_dir: str | Path, prefix: str, group: str | None = None) -> tuple[Path, str]:
    """Find one strictly named group CSV without guessing between candidates."""
    root = Path(root_dir).resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"Assignment directory does not exist: {root}")

    candidates = sorted(
        p for p in root.iterdir()
        if p.is_file() and p.name.lower().startswith(prefix.lower())
        and p.suffix.lower() == ".csv"
    )
    if not candidates:
        expected = f"{prefix}{group}.csv" if group else f"{prefix}NNN.csv"
        raise FileNotFoundError(f"Missing {expected} in the assignment folder: {root}")
    if len(candidates) != 1:
        names = ", ".join(p.name for p in candidates)
        raise ValueError(f"Expected exactly one {prefix}NNN.csv; found: {names}. Remove leftover templates/copies.")

    path = candidates[0]
    pattern = re.compile(rf"{re.escape(prefix)}([0-9]{{3}})\.csv")
    match = pattern.fullmatch(path.name)
    if match is None:
        if path.name == f"{prefix}NNN.csv":
            raise ValueError(
                f"Rename {path.name}: replace NNN with your three-digit group number (e.g. 007)."
            )
        raise ValueError(f"Invalid filename {path.name!r}; expected {prefix}NNN.csv (exactly three digits).")

    file_group = match.group(1)
    if group is not None and file_group != validate_group(group):
        raise ValueError(
            f"{path.name} does not match group_{group}.csv. Both files must use the same group number."
        )
    return path, file_group


def read_group_roster(root_dir: str | Path) -> dict[str, object]:
    """Load/validate the A/B roster; derive group ID solely from its filename."""
    path, group = _single_group_csv(root_dir, "group_")
    try:
        rows = pd.read_csv(path, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    except (pd.errors.ParserError, pd.errors.EmptyDataError, UnicodeError) as exc:
        raise ValueError(f"Cannot read {path.name} as a valid CSV: {exc}") from exc

    columns = ["student_role", "student_number", "student_name"]
    if list(rows.columns) != columns:
        raise ValueError(f"{path.name}: expected exactly these columns, in order: {', '.join(columns)}.")
    if len(rows) != 2:
        raise ValueError(f"{path.name}: expected exactly two rows, one for A and one for B; got {len(rows)}.")

    people: dict[str, dict[str, str]] = {}
    for record in rows.to_dict("records"):
        role = str(record["student_role"]).strip()
        if role not in ("A", "B") or role in people:
            raise ValueError(f"{path.name}: student_role must contain exactly one A row and one B row.")
        people[role] = {
            "student_role": role,
            "student_number": str(record["student_number"]).strip(),
            "student_name": str(record["student_name"]).strip(),
        }
    if set(people) != {"A", "B"}:
        raise ValueError(f"{path.name}: exactly one A row and one B row are required.")

    a, b = people["A"], people["B"]
    for person in (a, b):
        role = person["student_role"]
        number = person["student_number"]
        name = person["student_name"]
        if not number:
            raise ValueError(
                f"{path.name}: Student {role}'s student_number is required. "
                "For a one-student group, enter the same number and name in both A and B rows."
            )
        if not (number.isascii() and number.isdigit()):
            raise ValueError(f"{path.name}: Student {role}'s student_number must contain digits only.")
        if not name:
            raise ValueError(f"{path.name}: Student {role}'s student_name is required.")

    if a["student_name"].casefold() == "anton chekhov":
        raise ValueError(f"{path.name}: replace Anton Chekhov with Student A's real name.")
    if b["student_name"].casefold() == "agatha christie":
        raise ValueError(f"{path.name}: replace Agatha Christie with Student B's real name.")

    if a["student_number"] == b["student_number"]:
        if a["student_name"] != b["student_name"]:
            raise ValueError(
                f"{path.name}: A and B have the same student number, so their names "
                "must also be identical for a one-student group."
            )
        # Keep both completed CSV rows intact; display the actual student once.
        members = [a]
        membership = "One-student group"
    else:
        members = [a, b]
        membership = "Two-student group"

    return {"group": group, "members": members, "membership": membership, "path": path}




def validate_group(group: str) -> str:
    value = str(group).strip()
    if not _GROUP_RE.fullmatch(value):
        raise ValueError(f"Group number must contain exactly three digits; got {group!r}.")
    return value


def _validate_identifier(value: str) -> str:
    if not _IDENTIFIER_RE.fullmatch(value):
        raise ValueError(f"Invalid SQL identifier: {value!r}")
    return value


def _quote_identifier(value: str) -> str:
    return f'"{_validate_identifier(value)}"'


def schema_names(group: str) -> tuple[str, str]:
    """Return the independent DWH2 staging and warehouse schemas for a group."""
    group = validate_group(group)
    return f"stg2_{group}", f"dwh2_{group}"


def database_user(group: str) -> str:
    return f"grp_{validate_group(group)}"


def preflight(
    root_dir: str | Path,
    *,
    group: str,
    standard_csv_order: Sequence[str] = STANDARD_CSV_ORDER,
) -> dict[str, object]:
    """Fail early if the assignment folder lacks required files.

    Assumes that the bootstrap has already created grp_<group> and the airq DB.
    """
    group = validate_group(group)
    root = Path(root_dir).resolve()
    required_dirs = ("csv", "ddl", "etl", "src")
    missing_dirs = [name for name in required_dirs if not (root / name).is_dir()]
    if missing_dirs:
        raise FileNotFoundError("DWH2 missing folders: " + ", ".join(missing_dirs))

    order = [str(name).strip() for name in standard_csv_order]
    if len(order) != len(set(order)):
        raise ValueError("Standard CSV order contains duplicates.")
    for name in order:
        _validate_identifier(name)
    if order != list(STANDARD_CSV_ORDER):
        raise ValueError("DWH2 uses the provided correct 15-table FK-safe CSV load order.")

    required_files = [root / "csv" / f"{name}.csv" for name in order]
    required_files += [root / "ddl" / STAGING_DDL, root / "ddl" / WAREHOUSE_DDL]
    required_files += [root / "etl" / name for name in ETL_FILES]
    missing_files = [path for path in required_files if not path.is_file()]
    if missing_files:
        missing = "\n".join(f"  - {path.relative_to(root)}" for path in missing_files)
        raise FileNotFoundError("DWH2 preflight is missing the following files:\n" + missing)

    # All SQL files are schema-neutral. Ignore commented-out SET statements:
    # sqlparse removes both '-- ...' and '/* ... */' comments before checking.
    violations = []
    for path in [root / "ddl" / STAGING_DDL, root / "ddl" / WAREHOUSE_DDL]:
        content = sqlparse.format(path.read_text(encoding="utf-8-sig"), strip_comments=True)
        if _SEARCH_PATH_RE.search(content):
            violations.append(f"{path.relative_to(root)} sets search_path")
    for name in ETL_FILES:
        path = root / "etl" / name
        content = sqlparse.format(path.read_text(encoding="utf-8-sig"), strip_comments=True)
        if _SEARCH_PATH_RE.search(content) or _QUALIFIED_SCHEMA_RE.search(content):
            violations.append(f"{path.relative_to(root)} contains schema selection/qualification")
    if violations:
        raise ValueError("Remove schema configuration from SQL files:\n  - " + "\n  - ".join(violations))

    (root / "sqldump").mkdir(exist_ok=True)
    print(f"Preflight PASS for DWH2_{group}: 15 CSVs, 2 DDL files, 6 ETL files.")
    return {"root": root, "etl_files": [root / "etl" / name for name in ETL_FILES]}


def pending_etl_files(root_dir: str | Path) -> list[str]:
    """Return ETL files that still contain only starter comments.

    The SQL workspace is initialized first so students receive their assigned
    templates.  This guard then stops the notebook BEFORE any database reset
    until students have begun implementing all six ETL scripts in DBeaver.
    """
    etl_dir = Path(root_dir)
    pending = []
    for filename in ETL_FILES:
        path = etl_dir / filename
        if not path.is_file():
            raise FileNotFoundError(f"Missing ETL file: {path}")
        body = sqlparse.format(path.read_text(encoding="utf-8-sig"), strip_comments=True)
        if not body.strip(" ;\n\t\r"):
            pending.append(filename)
    return pending


def connect_database(
    group: str,
    *,
    database: str = "airq",
    host: str = "localhost",
    port: int = 5432,
    password: str | None = None,
) -> tuple[Engine, dict[str, object]]:
    group = validate_group(group)
    user = database_user(group)
    if password is None:
        password = getpass(
            f"Password for {user}@{host}:{port}/{database} (leave empty if not needed): "
        )
    if password:
        dsn = f"postgresql+psycopg2://{user}:{quote_plus(password)}@{host}:{port}/{database}"
    else:
        dsn = f"postgresql+psycopg2://{user}@{host}:{port}/{database}"

    print("Connecting via:", str(make_url(dsn).set(password="***" if password else None)))
    engine = create_engine(dsn, future=True, pool_pre_ping=True)
    with engine.begin() as connection:
        current_user, current_db = connection.exec_driver_sql(
            "SELECT current_user, current_database()"
        ).one()
    if current_user != user or current_db != database:
        engine.dispose()
        raise RuntimeError(
            f"Connected as {current_user} to {current_db}; expected {user} and {database}."
        )
    print(f"Connected as {current_user} to database {current_db}.")
    return engine, {
        "user": user, "password": password, "database": database,
        "host": host, "port": int(port),
    }


def reset_schema(engine: Engine, schema: str, *, owner: str | None = None) -> None:
    """Drop and recreate one schema in one transaction (DWH1 style)."""
    target = _quote_identifier(schema)
    owner_sql = f" AUTHORIZATION {_quote_identifier(owner)}" if owner else ""
    with engine.begin() as conn:
        conn.exec_driver_sql(f"DROP SCHEMA IF EXISTS {target} CASCADE")
        conn.exec_driver_sql(f"CREATE SCHEMA {target}{owner_sql}")
    print(f"Reset schema: {schema}")


def _set_local_search_path(conn, names: Sequence[str] | None) -> None:
    if names:
        conn.exec_driver_sql(
            "SET LOCAL search_path TO " + ", ".join(_quote_identifier(name) for name in names)
        )


def run_sql_file(
    path: str | Path,
    *,
    engine: Engine,
    search_path: Sequence[str] | None = None,
    progress: bool = False,
) -> pd.DataFrame | None:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    raw = path.read_text(encoding="utf-8-sig")
    # Allow psql metadata lines in exported SQL while executing from SQLAlchemy.
    raw = "\n".join(line for line in raw.splitlines() if not line.lstrip().startswith("\\"))
    statements = [
        statement.strip() for statement in sqlparse.split(raw)
        if statement and statement.strip(" ;\n\t")
    ]
    if not statements:
        raise ValueError(f"SQL file contains no executable statements: {path}")
    started = time.time()
    result: pd.DataFrame | None = None
    with engine.begin() as conn:
        _set_local_search_path(conn, search_path)
        for index, statement in enumerate(statements, 1):
            try:
                cursor = conn.exec_driver_sql(statement)
                if cursor.returns_rows:
                    result = pd.DataFrame(cursor.fetchall(), columns=cursor.keys())
            except Exception as exc:
                preview = " ".join(statement.split())[:180]
                raise RuntimeError(
                    f"SQL error in {path.name}, statement #{index}: {preview}"
                ) from exc
    if progress:
        print(f"Executed {path.name}: {len(statements)} statement(s) in {time.time() - started:.2f}s")
    return result


def run_sql_folder(
    folder: str | Path,
    pattern: str,
    *,
    engine: Engine,
    search_path: Sequence[str] | None = None,
    progress: bool = False,
) -> dict[str, pd.DataFrame | None]:
    folder = Path(folder)
    files = sorted(folder.glob(pattern))
    if not files:
        raise FileNotFoundError(f"No SQL files match {folder / pattern}")
    results = {}
    for path in files:
        results[path.name] = run_sql_file(
            path, engine=engine, search_path=search_path, progress=progress
        )
    print(f"Executed {len(files)} SQL file(s) from {folder.name}/")
    return results


def load_csv_tables(
    folder: str | Path,
    table_order: Sequence[str],
    *,
    engine: Engine,
    schema: str,
    if_exists: str = "append",
    chunksize: int = 20_000,
) -> dict[str, int]:
    """Load the 15 standard CSVs with the same NULL/date conventions as DWH1."""
    folder = Path(folder)
    schema = _validate_identifier(schema)
    if not folder.is_dir():
        raise FileNotFoundError(folder)
    result = {}
    started = time.time()
    for table in table_order:
        _validate_identifier(table)
        path = folder / f"{table}.csv"
        if not path.is_file():
            raise FileNotFoundError(path)
        frame = pd.read_csv(
            path, na_values=["\\N"], keep_default_na=False, low_memory=False
        )
        for column in frame.columns:
            if column.lower().endswith(_DATE_SUFFIXES):
                frame[column] = pd.to_datetime(
                    frame[column], format="%Y-%m-%d", errors="coerce"
                ).dt.date
        # Same DWH1 ingestion approach: DataFrame.to_sql(method='multi').
        frame.to_sql(
            table, con=engine, schema=schema, if_exists=if_exists,
            index=False, method="multi", chunksize=chunksize,
        )
        result[table] = len(frame)
        print(f"Loaded {len(frame):,} rows -> {schema}.{table}")
    print(f"Loaded {len(result)} tables, {sum(result.values()):,} rows in {time.time() - started:.2f}s")
    return result


def reference_etl_check(
    engine: Engine,
    *,
    staging_schema: str,
    warehouse_schema: str,
) -> pd.DataFrame:
    """Reconcile fundamental counts/sums without hardcoding synthetic-world totals."""
    with engine.begin() as conn:
        _set_local_search_path(conn, [warehouse_schema, staging_schema])
        source = conn.exec_driver_sql(
            "SELECT COUNT(*) AS readings, "
            "COALESCE(SUM(datavolumekb),0) AS kb, "
            "COALESCE(SUM(dataquality),0) AS quality "
            "FROM tb_readingevent"
        ).mappings().one()
        fact = conn.exec_driver_sql(
            "SELECT COUNT(*) AS fact_rows, "
            "COALESCE(SUM(reading_count),0) AS readings, "
            "COALESCE(SUM(data_volume_kb_sum),0) AS kb, "
            "COALESCE(SUM(data_quality_sum),0) AS quality "
            "FROM ft_param_city_month_location"
        ).mappings().one()
        dim_counts = conn.exec_driver_sql(
            "SELECT "
            "(SELECT COUNT(*) FROM dim_timemonth) AS months, "
            "(SELECT COUNT(*) FROM dim_city) AS cities, "
            "(SELECT COUNT(*) FROM dim_param) AS params, "
            "(SELECT COUNT(*) FROM dim_locationtype) AS locations, "
            "(SELECT COUNT(*) FROM dim_alertlevel) AS alerts"
        ).mappings().one()
    checks = [
        ("ReadingEvents represented", int(source["readings"]), int(fact["readings"])),
        ("Data volume (KB)", int(source["kb"]), int(fact["kb"])),
        ("Data quality sum", int(source["quality"]), int(fact["quality"])),
    ]
    rows = [
        {"check_name": name, "source": src, "warehouse": dst,
         "status": "PASS" if src == dst else "FAIL"}
        for name, src, dst in checks
    ]
    result = pd.DataFrame(rows)
    print(
        f"Warehouse fact rows: {int(fact['fact_rows']):,}; "
        f"represented readings: {int(fact['readings']):,}."
    )
    print(
        "Dimensions:", ", ".join(f"{key}={int(value)}" for key, value in dim_counts.items())
    )
    if (result["status"] != "PASS").any():
        raise RuntimeError("Reference ETL reconciliation failed. Inspect the check output.")
    return result


def _postgres_version_key(path: Path) -> tuple[int, ...]:
    numbers = re.findall(r"\d+", path.parent.parent.name)
    return tuple(int(number) for number in numbers) if numbers else (0,)


def find_pg_dump() -> Path:
    direct = os.environ.get("PG_DUMP", "").strip()
    if direct:
        path = Path(direct).expanduser()
        if path.is_file():
            return path.resolve()
        raise FileNotFoundError(f"PG_DUMP points to a nonexistent file: {path}")
    on_path = shutil.which("pg_dump") or shutil.which("pg_dump.exe")
    if on_path:
        return Path(on_path).resolve()
    found: list[Path] = []
    if os.name == "nt":
        roots: list[Path] = []
        for env_var in ("ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"):
            value = os.environ.get(env_var)
            if value:
                roots.append(Path(value))
        roots.append(Path(r"C:\Program Files"))
        for root in roots:
            found += list((root / "PostgreSQL").glob("*/bin/pg_dump.exe"))
    else:
        found += list(Path("/usr/lib/postgresql").glob("*/bin/pg_dump"))
        for value in ("/opt/homebrew/bin/pg_dump", "/usr/local/bin/pg_dump"):
            if Path(value).is_file():
                found.append(Path(value))
    found = [p for p in found if p.is_file()]
    if found:
        return max(found, key=_postgres_version_key).resolve()
    raise FileNotFoundError("pg_dump not found. Set PG_DUMP to its full path if necessary.")


def create_sql_dump(
    output_dir: str | Path,
    *,
    group: str,
    db_settings: dict[str, object],
    schema: str | None = None,
) -> Path:
    group = validate_group(group)
    schema = _validate_identifier(schema or f"dwh2_{group}")
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    path = output / f"sqldump_airq_dwh2_{group}.sql"
    command = [
        str(find_pg_dump()), "-h", str(db_settings["host"]),
        "-p", str(db_settings["port"]), "-U", str(db_settings["user"]),
        "-d", str(db_settings["database"]), "-n", schema,
        "--no-owner", "--no-privileges", "-f", str(path),
    ]
    env = dict(os.environ)
    if db_settings.get("password"):
        env["PGPASSWORD"] = str(db_settings["password"])
    try:
        subprocess.run(command, check=True, env=env, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("pg_dump failed: " + (exc.stderr or exc.stdout or str(exc))) from exc
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"pg_dump produced an empty/missing file: {path}")
    print(f"Created {path}")
    return path


def print_run_summary(status: dict[str, str], *, group: str) -> None:
    group = validate_group(group)
    title = "DWH2 orchestration summary"
    print("\n" + title + "\n" + "-" * len(title))
    width = max((len(name) for name in status), default=0)
    for name, value in status.items():
        print(f"{name:<{width}}  {value}")
    needs_attention = [name for name, value in status.items() if not value.startswith("PASS")]
    if needs_attention:
        print(f"\nDWH2_{group} completed with deferred or unsuccessful stages.")
    else:
        print(f"\nDWH2_{group} completed successfully.")
