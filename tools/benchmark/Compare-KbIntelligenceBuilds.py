#!/usr/bin/env python3
"""Compare two versions of the KB Intelligence engine on the same corpora.

Contributor tool for refactors that must not change behavior (for example moving data between
engine modules). Given a baseline and a candidate scripts folder (each a copy of
skills/mimir-lite/scripts/), it builds every --corpus with each folder's
Build-KbIntelligenceIndex.py into a scratch folder and compares:

- every table of the two indexes, rows sorted, plus the schema; the metadata rows
  extractor_signature_hash and last_index_build_run_at are left out, since they differ by design;
- the answers of a fixed set of queries, each run with the folder's own
  Query-KbIntelligenceIndex.py on its own index: stdout, stderr and exit code. The objects come
  from the baseline index: for each object type, the first two names and the most used object;
  reverse queries also run with --format text, so the coverage text is compared too.

The scratch folder paths are replaced by placeholders before comparing, and the two volatile keys
are dropped from JSON answers. Any other difference is reported. The tool never writes into the
repository (Python runs with -B) and deletes its scratch folder unless --keep is given.

Exit codes: 0 no difference, 1 a difference or a failed build, 2 invalid arguments.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

BUILD_SCRIPT = "Build-KbIntelligenceIndex.py"
QUERY_SCRIPT = "Query-KbIntelligenceIndex.py"
VOLATILE_KEYS = ("extractor_signature_hash", "last_index_build_run_at")
SIDES = ("baseline", "candidate")
OBJECT_QUERIES = ("who-uses", "what-uses", "impact-basic", "functional-trace-basic", "object-info")
TEXT_QUERIES = ("who-uses", "impact-basic", "functional-trace-basic", "object-info")
OBJECTS_PER_TYPE = 2
EVIDENCE_RELATIONS = 5
MAX_REPORTED = 20


def run_python(script: Path, args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    return subprocess.run(
        [sys.executable, "-B", str(script)] + args,
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def dump_index(index_path: Path) -> dict[str, list[str]]:
    """Every table as sorted JSON rows, plus the schema; volatile metadata rows left out."""
    conn = sqlite3.connect(str(index_path))
    try:
        dump: dict[str, list[str]] = {}
        schema = conn.execute(
            "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        dump["<schema>"] = sorted(json.dumps(list(row), ensure_ascii=False) for row in schema)
        tables = [row[1] for row in schema if row[0] == "table"]
        for table in tables:
            cursor = conn.execute('SELECT * FROM "{}"'.format(table.replace('"', '""')))
            columns = [description[0] for description in cursor.description]
            rows = []
            for row in cursor.fetchall():
                record = dict(zip(columns, row))
                if table == "metadata" and record.get("key") in VOLATILE_KEYS:
                    continue
                rows.append(json.dumps(record, ensure_ascii=False, sort_keys=True, default=repr))
            dump[table] = sorted(rows)
        return dump
    finally:
        conn.close()


def plan_queries(index_path: Path) -> list[list[str]]:
    """The query argument lists to run, chosen from one index."""
    conn = sqlite3.connect(str(index_path))
    try:
        types = [row[0] for row in conn.execute("SELECT DISTINCT type FROM objects ORDER BY type")]
        chosen: list[tuple[str, str]] = []
        for object_type in types:
            names = [
                row[0]
                for row in conn.execute(
                    "SELECT name FROM objects WHERE type = ? ORDER BY name LIMIT ?", (object_type, OBJECTS_PER_TYPE)
                )
            ]
            most_used = conn.execute(
                "SELECT target_name FROM relations WHERE target_type = ? "
                "GROUP BY target_name ORDER BY COUNT(*) DESC, target_name LIMIT 1",
                (object_type,),
            ).fetchone()
            if most_used is not None and most_used[0] not in names:
                names.append(most_used[0])
            chosen.extend((object_type, name) for name in names)
        relation_ids = [
            row[0]
            for row in conn.execute(
                "SELECT relation_id FROM relations ORDER BY relation_id LIMIT ?", (EVIDENCE_RELATIONS,)
            )
        ]
        css_names = [
            row[0] for row in conn.execute("SELECT DISTINCT class_name FROM css_class ORDER BY class_name LIMIT 2")
        ]
    finally:
        conn.close()

    queries: list[list[str]] = [["--query", "index-metadata"], ["--query", "css-classes"], ["--query", "css-classes", "--include-imported"]]
    for name in css_names:
        queries.append(["--query", "css-class-usage", "--object-name", str(name)])
    for object_type in types:
        queries.append(["--query", "list-by-type", "--object-type", object_type])
    for object_type, name in chosen:
        for query in OBJECT_QUERIES:
            queries.append(["--query", query, "--object-type", object_type, "--object-name", name])
        for query in TEXT_QUERIES:
            queries.append(["--query", query, "--object-type", object_type, "--object-name", name, "--format", "text"])
        queries.append(["--query", "search-objects", "--object-name", name[:3]])
        if object_type == "Attribute":
            queries.append(["--query", "attribute-info", "--object-name", name])
        if object_type == "Transaction":
            queries.append(["--query", "transaction-attributes", "--object-name", name])
            queries.append(["--query", "transaction-writable-attributes", "--object-name", name])
    for relation_id in relation_ids:
        queries.append(["--query", "show-evidence", "--relation-id", str(relation_id)])
    return queries


def drop_volatile(value: object) -> object:
    if isinstance(value, dict):
        return {key: drop_volatile(item) for key, item in value.items() if key not in VOLATILE_KEYS}
    if isinstance(value, list):
        return [drop_volatile(item) for item in value]
    return value


def normalize(text: str, replacements: list[tuple[str, str]]) -> str:
    for old, new in replacements:
        text = text.replace(old, new)
    try:
        parsed = json.loads(text)
    except ValueError:
        return text
    return json.dumps(drop_volatile(parsed), indent=2, ensure_ascii=False, sort_keys=True)


def path_replacements(path: Path, placeholder: str) -> list[tuple[str, str]]:
    forms = {str(path), str(path).replace("\\", "/"), json.dumps(str(path))[1:-1]}
    return [(form, placeholder) for form in sorted(forms, key=len, reverse=True)]


def run_queries(scripts: Path, index_path: Path, side_dir: Path, queries: list[list[str]], workers: int) -> list[dict[str, object]]:
    replacements = path_replacements(side_dir, "<SIDE_DIR>") + path_replacements(scripts, "<SCRIPTS>")

    def one(args: list[str]) -> dict[str, object]:
        completed = run_python(scripts / QUERY_SCRIPT, ["--index-path", str(index_path)] + args, side_dir)
        return {
            "exit": completed.returncode,
            "stdout": normalize(completed.stdout, replacements),
            "stderr": normalize(completed.stderr, replacements),
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(one, queries))


def compare_corpus(corpus: Path, folders: dict[str, Path], work: Path, workers: int) -> dict[str, object]:
    result: dict[str, object] = {"corpus": str(corpus), "differences": []}
    differences: list[str] = result["differences"]  # type: ignore[assignment]
    indexes: dict[str, Path] = {}
    for side in SIDES:
        side_dir = work / side
        side_dir.mkdir(parents=True)
        index_path = side_dir / "index.sqlite"
        completed = run_python(
            folders[side] / BUILD_SCRIPT,
            ["--source-root", str(corpus), "--output-path", str(index_path)],
            side_dir,
        )
        if completed.returncode != 0 or not index_path.is_file():
            differences.append(
                "{} build failed (exit {}): {}".format(side, completed.returncode, completed.stderr.strip()[-500:])
            )
            return result
        indexes[side] = index_path

    dumps = {side: dump_index(indexes[side]) for side in SIDES}
    result["rows"] = {table: len(rows) for table, rows in dumps["baseline"].items()}
    for table in sorted(set(dumps["baseline"]) | set(dumps["candidate"])):
        baseline_rows = dumps["baseline"].get(table)
        candidate_rows = dumps["candidate"].get(table)
        if baseline_rows is None or candidate_rows is None:
            differences.append("table {}: only in {}".format(table, "candidate" if baseline_rows is None else "baseline"))
            continue
        if baseline_rows != candidate_rows:
            only_baseline = sorted(set(baseline_rows) - set(candidate_rows))
            only_candidate = sorted(set(candidate_rows) - set(baseline_rows))
            differences.append(
                "table {}: {} vs {} rows; only in baseline: {}; only in candidate: {}".format(
                    table, len(baseline_rows), len(candidate_rows), only_baseline[:3], only_candidate[:3]
                )
            )

    queries = plan_queries(indexes["baseline"])
    answers = {
        side: run_queries(folders[side], indexes[side], work / side, queries, workers) for side in SIDES
    }
    result["queries"] = len(queries)
    for args, baseline, candidate in zip(queries, answers["baseline"], answers["candidate"]):
        if baseline != candidate:
            fields = [field for field in ("exit", "stdout", "stderr") if baseline[field] != candidate[field]]
            detail = ""
            if "stdout" in fields:
                detail = first_line_difference(str(baseline["stdout"]), str(candidate["stdout"]))
            elif "stderr" in fields:
                detail = first_line_difference(str(baseline["stderr"]), str(candidate["stderr"]))
            differences.append("query {}: {} differ{}".format(" ".join(args), ", ".join(fields), detail))
    return result


def first_line_difference(baseline: str, candidate: str) -> str:
    baseline_lines = baseline.splitlines()
    candidate_lines = candidate.splitlines()
    for number, (left, right) in enumerate(zip(baseline_lines, candidate_lines), start=1):
        if left != right:
            return "; line {}: baseline {!r}, candidate {!r}".format(number, left.strip(), right.strip())
    return "; baseline {} lines, candidate {} lines".format(len(baseline_lines), len(candidate_lines))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare the indexes and query answers of two engine versions.")
    parser.add_argument("--baseline-scripts", required=True, type=Path, help="Scripts folder of the old engine.")
    parser.add_argument("--candidate-scripts", required=True, type=Path, help="Scripts folder of the new engine.")
    parser.add_argument("--corpus", required=True, type=Path, action="append", help="Corpus folder (repeatable).")
    parser.add_argument("--work-dir", type=Path, help="Scratch folder (default: a new temp folder).")
    parser.add_argument("--keep", action="store_true", help="Keep the scratch folder.")
    parser.add_argument("--workers", type=int, default=4, help="Queries run at the same time (default 4).")
    parser.add_argument("--json", action="store_true", help="Print the full report as JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    folders = {"baseline": args.baseline_scripts.resolve(), "candidate": args.candidate_scripts.resolve()}
    for side, folder in folders.items():
        for script in (BUILD_SCRIPT, QUERY_SCRIPT):
            if not (folder / script).is_file():
                print("{} scripts folder has no {}: {}".format(side, script, folder), file=sys.stderr)
                return 2
    corpora = [corpus.resolve() for corpus in args.corpus]
    for corpus in corpora:
        if not corpus.is_dir():
            print("Corpus folder not found: {}".format(corpus), file=sys.stderr)
            return 2
    if args.workers < 1:
        print("--workers must be at least 1", file=sys.stderr)
        return 2

    created = args.work_dir is None
    work = Path(tempfile.mkdtemp(prefix="kb-compare-builds-")) if created else args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    try:
        reports = []
        for number, corpus in enumerate(corpora, start=1):
            corpus_work = work / "corpus-{}".format(number)
            if corpus_work.exists():
                shutil.rmtree(corpus_work)
            reports.append(compare_corpus(corpus, folders, corpus_work, args.workers))
    finally:
        if created and not args.keep:
            shutil.rmtree(work, ignore_errors=True)

    different = [report for report in reports if report["differences"]]
    if args.json:
        print(json.dumps({"identical": not different, "corpora": reports}, indent=2, ensure_ascii=False))
    else:
        for report in reports:
            differences = report["differences"]
            rows = report.get("rows", {})
            print(
                "{}: {} ({} queries; rows {})".format(
                    "DIFFERENT" if differences else "identical",
                    report["corpus"],
                    report.get("queries", 0),
                    ", ".join("{}={}".format(table, count) for table, count in sorted(rows.items()) if table != "<schema>"),
                )
            )
            for difference in differences[:MAX_REPORTED]:  # type: ignore[index]
                print("  " + difference)
            if len(differences) > MAX_REPORTED:  # type: ignore[arg-type]
                print("  ... {} more".format(len(differences) - MAX_REPORTED))  # type: ignore[arg-type]
    return 1 if different else 0


if __name__ == "__main__":
    raise SystemExit(main())
