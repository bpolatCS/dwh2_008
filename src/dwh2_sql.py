"""DWH2 SQL1/SQL2 fixed-group allocations and submission checks.

Both A and B identities are established together from group_NNN.csv. For a
solo group, the two completed CSV rows have identical student details and the
student receives one SQL1 and one SQL2 bundle. A pair receives four disjoint
bundles, two per student. The group cannot change mid-assignment routinely.

Student-facing code contains no hidden feasibility Y/N answer key, and never
replaces completed SQL or CSV answers. SQL results are inspected in DBeaver.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Any

import pandas as pd
from sqlalchemy.engine import Engine


ALGORITHM_VERSION = "AirQ-DWH2-SQL-C1-v1"
MANIFEST_NAME = "a2_sql_assignments.json"
FEASIBILITY_NAME = "a2_atoti_feasibility.csv"
CSV_COLUMNS = ("student", "question_id", "atoti_ui_possible", "reason")

# Each pool partitions 16 question IDs into four disjoint bundles.
# No feasibility classifications are included in the student code.
QUESTION_BUNDLES: dict[str, tuple[tuple[int, ...], ...]] = {
    "SQL1": (
        (101, 106, 111, 114),
        (102, 107, 110, 116),
        (103, 105, 109, 115),
        (104, 108, 112, 113),
    ),
    "SQL2": (
        (201, 206, 209, 214),
        (202, 205, 212, 215),
        (203, 207, 210, 216),
        (204, 208, 211, 213),
    ),
}

# Brief public question titles only. The handout defines the full requirements.
# Titles never contain SQL solutions or Atoti Y/N feasibility labels.
QUESTION_TITLES: dict[int, str] = {
    101: "How did reading volumes and severe alerts change across all countries?",
    102: "Did alert rates change across Mediterranean monitoring networks?",
    103: "How reliably was BlackCarbon monitored, and how many monitored days had alerts?",
    104: "Did severe-alert rates change across different monitoring purposes?",
    105: "How did sensor-data volume per reading vary by quarter?",
    106: "How often do Urban and Industrial readings reach alert levels?",
    107: "Were severe-alert rates unusually high in particular quarters for four pollutants?",
    108: "How do PM2 and PM10 readings vary within Vienna, Berlin and Moscow?",
    109: "Does a monthly peak-alert level mean all readings were alerts?",
    110: "How much do O3 and NO2 readings vary between Danube-region cities?",
    111: "How did ozone concentrations vary by quarter across four European countries?",
    112: "Which pollutant categories had unusually high severe-alert quarters in Turkey?",
    113: "How big is Industrial data volume compared to Urban data volume in all countries?",
    114: "Which pollutants are monitored in both Urban and Industrial locations?",
    115: "Which pollutants are monitored in German Urban but not Industrial locations?",
    116: "Which pollutant categories account for at least 20% of a German city's readings?",
    201: "How did severe-alert rates vary across cities in France and Germany in 2024?",
    202: "How did O3 concentrations and alert rates vary across French cities and quarters?",
    203: "How did severe-alert rates vary across French health-risk and compliance pollutants?",
    204: "How do quarterly NO2 concentrations compare in neighboring countries?",
    205: "Which cities had the highest severe-alert rates in each quarter of 2024?",
    206: "How did Austria's reading count change from month to month in 2025?",
    207: "Which month had the largest average concentration above the annual average for each pollutant in French cities?",
    208: "Which city had the biggest change in alert percentage from one quarter to the next?",
    209: "How did alert rates vary across Italian gas and particulate pollutants?",
    210: "How do alert rates compare across pollutant categories in five countries?",
    211: "How often did readings trigger alerts in Russian monitoring locations?",
    212: "How did PM10 concentrations change by month, quarter and year in Italy?",
    213: "How much higher was each city's worst PM10 month than its typical month?",
    214: "Which two reporting cities in each selected country differ most in annual quality?",
    215: "How did short-term alert rates change in Ankara and Istanbul?",
    216: "Are Russian cities above or below their peers in quarterly alert-reading rates?",
}

_GROUP_RE = re.compile(r"\d{3}\Z")
_STUDENT_RE = re.compile(r"[0-9]+\Z")
_DWH_SCHEMA_RE = re.compile(r"dwh2_\d{3}\Z")
_SCHEMA_QUALIFIER_RE = re.compile(
    r"\b(?:stg1|stg2|dwh1|dwh2)_(?:nnn|\d{3})\"?\s*\.\s*\"?|\bpublic\"?\s*\.\s*\"?",
    flags=re.IGNORECASE,
)
# Reject *any* explicitly qualified table after FROM/JOIN, even if it does not
# have a stg*/dwh* prefix. Ordinary alias.column expressions remain allowed.
_EXPLICIT_RELATION_SCHEMA_RE = re.compile(
    r'\b(?:FROM|JOIN)\s+"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*"?[A-Za-z_]',
    flags=re.IGNORECASE,
)


@dataclass(frozen=True)
class SqlWorkspace:
    root: Path
    group: str
    students: dict[str, str]
    assignments: dict[str, dict[str, tuple[int, ...]]]
    created_sql: tuple[str, ...]
    preserved_sql: tuple[str, ...]
    added_csv_rows: int
    created_csv: bool

    @property
    def sql_dir(self) -> Path:
        return self.root / "sql"

    @property
    def feasibility_path(self) -> Path:
        return self.root / FEASIBILITY_NAME

    @property
    def all_question_ids(self) -> tuple[int, ...]:
        return tuple(sorted(q for pools in self.assignments.values() for ids in pools.values() for q in ids))


def _validated_group(group: str) -> str:
    group = str(group).strip()
    if not _GROUP_RE.fullmatch(group):
        raise ValueError("Group number must be exactly three digits, e.g. '007'.")
    return group


def _roster(student_a: str, student_b: str) -> dict[str, str]:
    """Resolve a fixed completed A/B roster into one or two active students.

    Missing B is INVALID; identical A and B are the explicitly selected
    one-student configuration. There is no late-join allocation transition.
    """
    a, b = str(student_a).strip(), str(student_b).strip()
    if not _STUDENT_RE.fullmatch(a) or not _STUDENT_RE.fullmatch(b):
        raise ValueError(
            "Both A and B student numbers must contain digits only. "
            "For a solo group, enter the same number and name in both CSV rows."
        )
    return {"A": a} if a == b else {"A": a, "B": b}


def _bundles_signature() -> str:
    payload = json.dumps(QUESTION_BUNDLES, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def _validate_bundles() -> None:
    for pool, start in (("SQL1", 101), ("SQL2", 201)):
        bundles = QUESTION_BUNDLES[pool]
        ids = [q for bundle in bundles for q in bundle]
        if len(bundles) != 4 or any(len(bundle) != 4 for bundle in bundles):
            raise ValueError(f"{pool} needs four bundles of four questions each.")
        if len(ids) != len(set(ids)) or set(ids) != set(range(start, start + 16)):
            raise ValueError(f"{pool} bundles must partition question IDs {start}-{start + 15}.")


def _stable_index(*values: str, modulo: int) -> int:
    seed = "|".join((ALGORITHM_VERSION, *values))
    digest = hashlib.sha256(seed.encode("ascii")).digest()
    return int.from_bytes(digest[:8], "big") % modulo


def calculate_assignments(student_a: str, student_b: str) -> dict[str, dict[str, tuple[int, ...]]]:
    """Allocate two distinct bundles per student from the FIXED complete roster.

    Paired allocation is computed in a single pass; later membership changes
    are prohibited by the saved manifest. Existing C1 selection stays stable.
    """
    _validate_bundles()
    students = _roster(student_a, student_b)
    assignments: dict[str, dict[str, tuple[int, ...]]] = {label: {} for label in students}
    for pool, bundles in QUESTION_BUNDLES.items():
        a_index = _stable_index(pool, "A", students["A"], modulo=len(bundles))
        assignments["A"][pool] = tuple(sorted(bundles[a_index]))
        if "B" in students:
            choices = [i for i in range(len(bundles)) if i != a_index]
            b_pos = _stable_index(pool, "B", students["A"], students["B"], modulo=len(choices))
            assignments["B"][pool] = tuple(sorted(bundles[choices[b_pos]]))
    return assignments


def assignment_table(workspace: SqlWorkspace) -> pd.DataFrame:
    """The three-column table shown to the students in Jupyter."""
    return pd.DataFrame(
        [{"Student": label,
          "SQL1": ", ".join(map(str, pools["SQL1"])),
          "SQL2": ", ".join(map(str, pools["SQL2"]))}
         for label, pools in workspace.assignments.items()],
        columns=["Student", "SQL1", "SQL2"],
    )


def _assignment_pairs(assignments: dict[str, dict[str, tuple[int, ...]]]) -> list[tuple[str, int]]:
    return [(label, q) for label, pools in assignments.items() for pool in ("SQL1", "SQL2") for q in pools[pool]]


def _manifest_body(group: str, students: dict[str, str], assignments: dict[str, dict[str, tuple[int, ...]]]) -> dict[str, Any]:
    return {
        "format_version": 1,
        "algorithm": ALGORITHM_VERSION,
        "group": group,
        "bundle_signature": _bundles_signature(),
        "students": students,
        "assignments": {label: {pool: list(ids) for pool, ids in pools.items()} for label, pools in assignments.items()},
    }


def _read_feasibility(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != CSV_COLUMNS:
            raise ValueError(f"{path.name} has an unexpected CSV header; it was not modified.")
        rows = list(reader)
    if any(None in row for row in rows):
        raise ValueError(f"{path.name} contains malformed CSV rows; it was not modified.")
    seen: set[tuple[str, str]] = set()
    for row in rows:
        key = (row["student"], row["question_id"])
        if key in seen:
            raise ValueError(f"Duplicate feasibility row {key}; the CSV was not modified.")
        seen.add(key)
    return rows


def _feasibility_header() -> str:
    return ",".join(CSV_COLUMNS) + "\n"


def _feasibility_line(student: str, question_id: int) -> str:
    # Always double-quote the reason field, including an initially empty one.
    return f'{student},{question_id},,""\n'


def _validate_existing_rows(path: Path, rows: list[dict[str, str]],
                            new_assignments: dict[str, dict[str, tuple[int, ...]]],
                            old_assignments: dict[str, dict[str, tuple[int, ...]]] | None) -> set[tuple[str, int]]:
    valid = set(_assignment_pairs(new_assignments))
    present: set[tuple[str, int]] = set()
    for row in rows:
        try:
            key = (row["student"], int(row["question_id"]))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Invalid question ID in {path.name}; file unchanged.") from exc
        if key not in valid or row["question_id"] != str(key[1]):
            raise ValueError(f"Unexpected feasibility row {key}; existing file unchanged.")
        present.add(key)
    if old_assignments is not None:
        missing_old = set(_assignment_pairs(old_assignments)) - present
        if missing_old:
            raise ValueError(
                "Existing feasibility CSV is missing previously assigned questions: "
                f"{sorted(missing_old)}. Existing file unchanged."
            )
    return present


def _question_template(q: int, label: str) -> str:
    pool = "SQL1" if q < 200 else "SQL2"
    title = QUESTION_TITLES[q]
    if "\n" in title or "\r" in title:
        raise ValueError("Question title must be a single line.")
    return (
        f"-- Assignment 2 | {pool} | Question {q} | Student {label}\n"
        f"-- Topic: {title}\n"
        "-- Read the assignment description for the complete question,\n"
        "-- required SQL technique, result columns, sorting, and row limit.\n"
        "-- Write exactly one read-only SELECT or WITH ... SELECT statement.\n"
        "-- Use unqualified table names; the notebook selects only the DWH2 schema.\n"
        "-- Place your SQL query below. Keep the comments above for reference.\n"
        "\n\n"
    )


def prepare_sql_workspace(root: str | Path, *, group: str,
                          student_a: str, student_b: str) -> SqlWorkspace:
    """Initialize the full fixed-group allocation without overwriting work.

    Reruns are idempotent. A solo group is A=B in the external CSV, and
    receives eight questions. A paired group receives sixteen. Once the
    manifest exists, ANY change of student numbers or member count stops.
    """
    group = _validated_group(group)
    students = _roster(student_a, student_b)
    root = Path(root).resolve()
    if root.name.lower() not in (f"dwh2_{group}", "dwh2_nnn"):
        raise ValueError(
            f"The notebook must run inside its DWH2 group folder, not {root}. "
            "No files were changed."
        )
    assignments = calculate_assignments(students["A"], students.get("B", students["A"]))
    manifest_path = root / MANIFEST_NAME
    csv_path = root / FEASIBILITY_NAME
    previous: dict[str, Any] | None = None
    previous_assignments: dict[str, dict[str, tuple[int, ...]]] | None = None
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        for key, value in (("format_version", 1), ("algorithm", ALGORITHM_VERSION),
                           ("group", group), ("bundle_signature", _bundles_signature())):
            if previous.get(key) != value:
                raise ValueError(f"Existing {MANIFEST_NAME} has a different {key}; no files changed.")
        old_students = previous.get("students", {})
        if old_students != students:
            raise ValueError(
                f"The A/B group membership differs from {MANIFEST_NAME}; no files changed. "
                "Both students must be fixed when the assignment begins. "
                "Contact the teaching team for an exceptional group change; "
                "do not edit or delete the manifest or student answers."
            )
        previous_assignments = calculate_assignments(
            old_students["A"], old_students.get("B", old_students["A"])
        )
        stored = _manifest_body(group, old_students, previous_assignments)["assignments"]
        if previous.get("assignments") != stored:
            raise ValueError("Assignment manifest does not match its algorithm; no files changed.")
        if not csv_path.exists():
            raise FileNotFoundError(
                f"Existing {MANIFEST_NAME} but missing {FEASIBILITY_NAME}: "
                "restore the original CSV before continuing; nothing was replaced."
            )

    prior_rows = _read_feasibility(csv_path) if csv_path.exists() else []
    present = _validate_existing_rows(csv_path, prior_rows, assignments, previous_assignments)
    pairs = _assignment_pairs(assignments)
    new_rows = [(label, q) for label, q in pairs if (label, q) not in present]
    # An existing manifest/CSV is immutable. Missing rows must not be silently
    # regenerated because that could hide lost student answers.
    if previous is not None and previous_assignments == assignments and new_rows:
        raise ValueError(f"Missing rows in {FEASIBILITY_NAME}; existing file was not modified.")

    if csv_path.exists() and new_rows:
        # Refuse to append to an unterminated final record. Students can correct
        # this without losing any existing data.
        with csv_path.open("rb") as handle:
            handle.seek(-1, 2)
            if handle.read(1) not in (b"\n", b"\r"):
                raise ValueError(f"{FEASIBILITY_NAME} lacks final newline; no files changed.")
    sql_dir = root / "sql"
    if sql_dir.exists() and not sql_dir.is_dir():
        raise ValueError("sql exists but is not a directory; no files changed.")
    if not root.is_dir():
        raise FileNotFoundError(root)

    sql_dir.mkdir(exist_ok=True)
    created: list[str] = []
    preserved: list[str] = []
    for label, q in pairs:
        filename = f"{q}.sql"
        path = sql_dir / filename
        # 'x' uses O_EXCL: an already existing answer can never be truncated.
        try:
            with path.open("x", encoding="utf-8", newline="\n") as handle:
                handle.write(_question_template(q, label))
            created.append(filename)
        except FileExistsError:
            preserved.append(filename)

    created_csv = not csv_path.exists()
    if created_csv:
        with csv_path.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(_feasibility_header())
            for label, q in new_rows:
                handle.write(_feasibility_line(label, q))
    elif new_rows:
        # Strictly append; never rewrite/edit existing Y/N answers or reasons.
        with csv_path.open("a", encoding="utf-8", newline="\n") as handle:
            for label, q in new_rows:
                handle.write(_feasibility_line(label, q))

    if previous is None:
        new_body = _manifest_body(group, students, assignments)
        temp_path = manifest_path.with_suffix(".json.pending")
        temp_path.write_text(json.dumps(new_body, indent=2) + "\n", encoding="utf-8")
        temp_path.replace(manifest_path)

    return SqlWorkspace(root=root, group=group, students=students,
                        assignments=assignments, created_sql=tuple(created),
                        preserved_sql=tuple(preserved), added_csv_rows=len(new_rows),
                        created_csv=created_csv)


def _query_or_template(sql: str) -> str | None:
    """Enforce a conservative one-statement SELECT-only submission contract.

    SQL text inspection is a usability check, NOT a security sandbox. The actual
    execution also uses a PostgreSQL READ ONLY transaction and a timeout.
    """
    import sqlparse
    from sqlparse.tokens import DDL, DML, Keyword

    code = sqlparse.format(sql, strip_comments=True).strip()
    if not code or not code.strip(" ;\t\r\n"):
        return None
    stmts = [stmt for stmt in sqlparse.parse(code) if str(stmt).strip(" ;\r\n\t")]
    if len(stmts) != 1:
        raise ValueError("Exactly one SQL statement is required.")
    stmt = stmts[0]
    if stmt.get_type() != "SELECT":
        raise ValueError("Only SELECT or WITH ... SELECT is permitted.")
    for token in stmt.flatten():
        if token.ttype in DDL or (token.ttype in DML and token.normalized.upper() != "SELECT"):
            raise ValueError("Data modification is forbidden, even inside a CTE.")
        if token.ttype in Keyword and token.normalized.upper() == "INTO":
            raise ValueError("SELECT INTO is forbidden.")
    if _SCHEMA_QUALIFIER_RE.search(code) or _EXPLICIT_RELATION_SCHEMA_RE.search(code):
        raise ValueError("Do not hardcode schema names; reference DWH2 tables unqualified.")
    return code


def run_assigned_sql(engine: Engine, workspace: SqlWorkspace, *, warehouse_schema: str,
                     max_result_rows: int = 100_000,
                     timeout_ms: int = 30_000) -> pd.DataFrame:
    """Run assigned queries read-only and return ONLY status/row counts.

    No result rows or preview DataFrames are displayed or retained. Successful
    execution is not a correctness judgement; students inspect SQL in DBeaver.
    """
    if not _DWH_SCHEMA_RE.fullmatch(warehouse_schema) or warehouse_schema != f"dwh2_{workspace.group}":
        raise ValueError("Only the matching group DWH2 schema can be queried.")
    if not 1 <= max_result_rows <= 1_000_000:
        raise ValueError("Invalid SQL result-row limit.")
    if not 1_000 <= timeout_ms <= 300_000:
        raise ValueError("SQL statement timeout must be between 1 and 300 seconds.")

    report: list[dict[str, Any]] = []
    for label, q in _assignment_pairs(workspace.assignments):
        path = workspace.sql_dir / f"{q}.sql"
        entry: dict[str, Any] = {"Student": label, "Question": q,
                                 "File": path.name, "Status": "MISSING",
                                 "Rows": None, "Detail": ""}
        if not path.is_file():
            entry["Detail"] = "SQL file is missing."
            report.append(entry)
            continue
        try:
            query = _query_or_template(path.read_text(encoding="utf-8-sig"))
            if query is None:
                entry.update(Status="TEMPLATE", Detail="Develop the SQL in DBeaver.")
            else:
                with engine.begin() as conn:
                    conn.exec_driver_sql("SET TRANSACTION READ ONLY")
                    conn.exec_driver_sql(f'SET LOCAL search_path TO "{warehouse_schema}"')
                    conn.exec_driver_sql(f"SET LOCAL statement_timeout = {timeout_ms}")
                    result = conn.exec_driver_sql(query)
                    if not result.returns_rows:
                        raise ValueError("The query must return rows.")
                    total = 0
                    while True:
                        chunk = result.fetchmany(1000)
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > max_result_rows:
                            raise ValueError(f"Result exceeded {max_result_rows:,} rows; narrow the result.")
                    entry.update(Status="EXECUTED", Rows=total, Detail="Correctness not checked.")
        except Exception as exc:
            entry.update(Status="ERROR", Detail=str(exc).split("\n")[0][:260])
        report.append(entry)
    return pd.DataFrame(report, columns=["Student", "Question", "File", "Status", "Rows", "Detail"])


def check_feasibility(workspace: SqlWorkspace) -> pd.DataFrame:
    """Check 4-column CSV shape/completeness without revealing any Y/N key."""
    if not workspace.feasibility_path.is_file():
        raise FileNotFoundError(workspace.feasibility_path)
    entries = _read_feasibility(workspace.feasibility_path)
    by_key = {(r["student"], r["question_id"]): r for r in entries}
    expected_keys = {(label, str(q)) for label, q in _assignment_pairs(workspace.assignments)}
    extra = set(by_key) - expected_keys
    if extra:
        raise ValueError(f"Unexpected entries in feasibility CSV: {sorted(extra)}")
    output: list[dict[str, str | int]] = []
    for label, q in _assignment_pairs(workspace.assignments):
        r = by_key.get((label, str(q)))
        if r is None:
            value, note, status = "", "Missing row", "INVALID"
        else:
            value = (r["atoti_ui_possible"] or "").strip()
            reason = (r["reason"] or "").strip()
            if value == "":
                status, note = ("PENDING", "Enter Y or N; reason only for N.") if not reason else ("INVALID", "Reason present before Y/N.")
            elif value == "Y":
                status, note = ("READY", "") if not reason else ("INVALID", "Y requires an empty reason.")
            elif value == "N":
                status, note = ("READY", "") if reason else ("INVALID", "N requires a 1-2 sentence reason.")
            else:
                status, note = "INVALID", "Use uppercase Y or N."
        output.append({"Student": label, "Question": q, "Y/N": value, "Status": status, "Detail": note})
    return pd.DataFrame(output, columns=["Student", "Question", "Y/N", "Status", "Detail"])
