#!/usr/bin/env python3
"""Measure the KB Intelligence build and a fixed set of queries on a corpus.

Contributor tool. Builds the index from --corpus-root into --output-dir (default: a new folder
under the system temp folder) and reports:

- build wall-clock time and peak memory, from a plain build in a child process (no profiler);
- the top functions by cumulative and by own time, from a second build under cProfile, plus the
  call count and time of a few build functions that are candidates for optimization (reading
  and parsing each corpus file);
- the tracemalloc peak of Python allocations, from a third build under tracemalloc;
- the corpus size, the index size, and the object, relation and evidence counts;
- the time of who-uses, impact-basic, functional-trace-basic, list-by-type and search-objects,
  each called through the query engine's own functions on a fresh connection, with the reverse
  relation coverage and the JSON serialization the command line adds.

Each build runs in its own child process so that one measurement does not disturb the next.
Peak RSS comes from resource.getrusage on Linux and macOS and from GetProcessMemoryInfo
(PeakWorkingSetSize) through ctypes on Windows; elsewhere it is reported as null with the
reason. The tool never writes into the repository. The JSON report is saved as report.json in
the output folder and printed with --json; otherwise a short text summary is printed.

Exit codes: 0 success, 1 a build or query failed, 2 invalid arguments.
"""

from __future__ import annotations

import argparse
import contextlib
import cProfile
import importlib.util
import io
import json
import os
import platform
import pstats
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time
import tracemalloc
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "skills" / "mimir-lite" / "scripts"
BUILD_SCRIPT = SCRIPTS_DIR / "Build-KbIntelligenceIndex.py"
QUERY_SCRIPT = SCRIPTS_DIR / "Query-KbIntelligenceIndex.py"
PHASES = ("plain", "profile", "tracemalloc")
TOP_COUNT = 15
# Build functions watched as optimization candidates (reading and parsing each corpus file).
WATCHED_FUNCTIONS = (
    "read_text",
    "direct_call_pattern",
    "line_number_at",
    "source_blocks",
    "extract_evidence",
    "extract_code_attribute_evidence",
    "collect_all_objects",
    "write_index",
    "write_index_rows",
    "create_schema",
    "validation_report",
)


def load_module(name: str, path: Path):
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    # Registered before it runs: dataclasses look their module up in sys.modules.
    sys.modules[name] = module
    spec.loader.exec_module(module)  # type: ignore[union-attr]
    return module


def peak_rss() -> tuple[float | None, str]:
    """Peak resident set size of this process in MB, and where it came from."""
    if sys.platform == "win32":
        try:
            import ctypes
            from ctypes import wintypes

            class ProcessMemoryCounters(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            counters = ProcessMemoryCounters()
            counters.cb = ctypes.sizeof(ProcessMemoryCounters)
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            psapi = ctypes.WinDLL("psapi", use_last_error=True)
            kernel32.GetCurrentProcess.restype = wintypes.HANDLE
            psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
            psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
            if psapi.GetProcessMemoryInfo(kernel32.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
                return counters.PeakWorkingSetSize / (1024 * 1024), "GetProcessMemoryInfo.PeakWorkingSetSize"
            return None, "GetProcessMemoryInfo failed"
        except (OSError, AttributeError) as exc:
            return None, "ctypes unavailable: {}".format(exc)
    try:
        import resource
    except ImportError:
        return None, "no resource module on this platform"
    maxrss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # ru_maxrss is in bytes on macOS and in kilobytes on Linux.
    divisor = 1024 * 1024 if sys.platform == "darwin" else 1024
    return maxrss / divisor, "resource.getrusage.ru_maxrss"


def profile_rows(stats: pstats.Stats, key_index: int) -> list[dict[str, object]]:
    rows = []
    for (filename, line, function), (_cc, ncalls, tottime, cumtime, _callers) in stats.stats.items():  # type: ignore[attr-defined]
        rows.append(
            {
                "function": "{}:{}({})".format(os.path.basename(filename), line, function) if line else function,
                "calls": ncalls,
                "tottime_s": round(tottime, 4),
                "cumtime_s": round(cumtime, 4),
                "_key": (tottime, cumtime)[key_index],
            }
        )
    rows.sort(key=lambda row: row["_key"], reverse=True)
    for row in rows:
        del row["_key"]
    return rows


def watched_rows(stats: pstats.Stats) -> list[dict[str, object]]:
    rows = []
    build_name = os.path.basename(str(BUILD_SCRIPT))
    for (filename, line, function), (_cc, ncalls, tottime, cumtime, _callers) in stats.stats.items():  # type: ignore[attr-defined]
        if os.path.basename(filename) == build_name and function in WATCHED_FUNCTIONS:
            rows.append({"function": function, "calls": ncalls, "tottime_s": round(tottime, 4), "cumtime_s": round(cumtime, 4)})
    rows.sort(key=lambda row: WATCHED_FUNCTIONS.index(str(row["function"])))
    return rows


def run_child_phase(phase: str, corpus_root: Path, index_path: Path, result_path: Path) -> int:
    """Body of one child process: build once, measured as the phase says, and save the result."""
    build = load_module("kb_benchmark_build", BUILD_SCRIPT)
    sys.argv = [str(BUILD_SCRIPT), "--source-root", str(corpus_root), "--output-path", str(index_path)]
    result: dict[str, object] = {"phase": phase}
    sink = io.StringIO()
    profiler = cProfile.Profile() if phase == "profile" else None
    if phase == "tracemalloc":
        tracemalloc.start()
    started = time.perf_counter()
    with contextlib.redirect_stdout(sink):
        exit_code = profiler.runcall(build.main) if profiler else build.main()
    result["wall_clock_seconds"] = round(time.perf_counter() - started, 3)
    result["exit_code"] = exit_code
    if phase == "tracemalloc":
        _current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        result["tracemalloc_peak_mb"] = round(peak / (1024 * 1024), 1)
    if profiler is not None:
        stats = pstats.Stats(profiler, stream=io.StringIO())
        result["top_cumulative"] = profile_rows(stats, 1)[:TOP_COUNT]
        result["top_tottime"] = profile_rows(stats, 0)[:TOP_COUNT]
        result["watched"] = watched_rows(stats)
    rss_mb, rss_source = peak_rss()
    result["peak_rss_mb"] = round(rss_mb, 1) if rss_mb is not None else None
    result["peak_rss_source"] = rss_source
    result_path.write_text(json.dumps(result), encoding="utf-8")
    return 0 if exit_code == 0 else 1


def launch_phase(phase: str, corpus_root: Path, output_dir: Path, timeout: int) -> dict[str, object]:
    index_path = output_dir / ("index-{}.sqlite".format(phase) if phase != "plain" else "index.sqlite")
    result_path = output_dir / "phase-{}.json".format(phase)
    command = [
        sys.executable, str(Path(__file__).resolve()), "--child-phase", phase,
        "--corpus-root", str(corpus_root), "--output-dir", str(output_dir),
    ]
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if completed.returncode != 0 or not result_path.exists():
        raise RuntimeError(
            "phase {} failed (exit {}): {}".format(phase, completed.returncode, completed.stderr.decode("utf-8", "replace")[-2000:])
        )
    result = json.loads(result_path.read_text(encoding="utf-8"))
    result_path.unlink()
    if phase != "plain":
        with contextlib.suppress(OSError):
            index_path.unlink()
    return result


def corpus_size(corpus_root: Path) -> dict[str, int]:
    files = 0
    size = 0
    for folder, _dirs, names in os.walk(str(corpus_root)):
        for name in names:
            if name.lower().endswith(".xml"):
                files += 1
                size += os.path.getsize(os.path.join(folder, name))
    return {"xml_files": files, "size_bytes": size}


def index_counts(index_path: Path) -> dict[str, object]:
    conn = sqlite3.connect(str(index_path))
    try:
        counts: dict[str, object] = {}
        for table in ("objects", "relations", "evidence"):
            counts[table] = conn.execute("SELECT COUNT(*) FROM {}".format(table)).fetchone()[0]
        counts["objects_by_type"] = dict(conn.execute("SELECT type, COUNT(*) FROM objects GROUP BY type ORDER BY type").fetchall())
        counts["relations_by_kind"] = dict(
            conn.execute("SELECT relation_kind, COUNT(*) FROM relations GROUP BY relation_kind ORDER BY relation_kind").fetchall()
        )
        return counts
    finally:
        conn.close()


def most_referenced(conn: sqlite3.Connection, target_type: str) -> str | None:
    row = conn.execute(
        "SELECT target_name, COUNT(*) FROM relations WHERE target_type = ? GROUP BY target_name ORDER BY 2 DESC, 1 LIMIT 1",
        (target_type,),
    ).fetchone()
    if row:
        return row[0]
    row = conn.execute("SELECT name FROM objects WHERE type = ? ORDER BY name LIMIT 1", (target_type,)).fetchone()
    return row[0] if row else None


def query_plan(index_path: Path) -> list[tuple[str, str, str]]:
    """(query, object type, object name or name fragment), chosen from the index itself."""
    conn = sqlite3.connect(str(index_path))
    try:
        procedure = most_referenced(conn, "Procedure") or ""
        transaction = most_referenced(conn, "Transaction")
        trace_type, trace_name = ("Transaction", transaction) if transaction else ("Procedure", procedure)
    finally:
        conn.close()
    return [
        ("who-uses", "Procedure", procedure),
        ("impact-basic", "Procedure", procedure),
        ("functional-trace-basic", trace_type, trace_name or ""),
        ("list-by-type", "Procedure", ""),
        ("search-objects", "", procedure[:4]),
    ]


def run_queries(index_path: Path, repeats: int) -> list[dict[str, object]]:
    query = load_module("kb_benchmark_query", QUERY_SCRIPT)
    results = []
    for name, object_type, object_name in query_plan(index_path):
        timings = []
        ok = True
        error = None
        rows = None
        for _ in range(repeats):
            started = time.perf_counter()
            try:
                conn = sqlite3.connect(str(index_path))
                try:
                    query.validate_schema_version(conn)
                    if name == "who-uses":
                        result = query.who_uses(conn, object_type, object_name, None)
                    elif name == "impact-basic":
                        result = query.impact_basic(conn, object_type, object_name, None)
                    elif name == "functional-trace-basic":
                        result = query.functional_trace_basic(conn, object_type, object_name, None)
                    elif name == "list-by-type":
                        result = query.list_by_type(conn, object_type, None)
                    else:
                        result = query.search_objects(conn, object_name, None, None)
                    if name in query.REVERSE_RELATION_QUERIES:
                        result["coverage"] = query.reverse_relation_coverage(conn, object_type)
                    text = json.dumps(result, indent=2, ensure_ascii=False)
                finally:
                    conn.close()
            except Exception as exc:  # noqa: BLE001 - reported, not raised
                ok = False
                error = "{}: {}".format(type(exc).__name__, exc)
                break
            timings.append((time.perf_counter() - started) * 1000)
            rows = len(text)
        results.append(
            {
                "query": name,
                "object_type": object_type,
                "object_name": object_name,
                "ok": ok,
                "error": error,
                "repeats": len(timings),
                "median_ms": round(statistics.median(timings), 1) if timings else None,
                "min_ms": round(min(timings), 1) if timings else None,
                "output_chars": rows,
            }
        )
    return results


def text_summary(report: dict[str, object]) -> str:
    build = report["build"]  # type: ignore[index]
    memory = report["memory"]  # type: ignore[index]
    counts = report["counts"]  # type: ignore[index]
    lines = [
        "Corpus: {} XML files, {:.1f} MB".format(report["corpus"]["xml_files"], report["corpus"]["size_bytes"] / 1048576),  # type: ignore[index]
        "Build: {} s wall clock (exit {})".format(build["wall_clock_seconds"], build["exit_code"]),
        "Memory: peak RSS {} MB ({}), tracemalloc peak {} MB".format(
            memory["peak_rss_mb"], memory["peak_rss_source"], memory["tracemalloc_peak_mb"]
        ),
        "Index: {:.2f} MB; {} objects, {} relations, {} evidence rows".format(
            report["index"]["size_bytes"] / 1048576, counts["objects"], counts["relations"], counts["evidence"]  # type: ignore[index]
        ),
        "Queries (median ms):",
    ]
    for query in report["queries"]:  # type: ignore[union-attr]
        lines.append("  {:<24} {}".format(query["query"], query["median_ms"] if query["ok"] else "FAILED " + str(query["error"])))
    profile = report.get("profile") or {}
    if profile.get("top_cumulative"):  # type: ignore[union-attr]
        lines.append("Top cumulative (profiled run):")
        for row in profile["top_cumulative"][:8]:  # type: ignore[index]
            lines.append("  {:>8.2f} s  {}".format(row["cumtime_s"], row["function"]))
    lines.append("Report: {}".format(report["report_path"]))
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Measure the KB Intelligence build and fixed queries on a corpus.")
    parser.add_argument("--corpus-root", type=Path, required=True, help="Folder with one sub-folder per object type.")
    parser.add_argument("--output-dir", type=Path, help="Folder for the index and report.json (default: a new temp folder).")
    parser.add_argument("--phases", default=",".join(PHASES), help="Comma-separated subset of plain,profile,tracemalloc (default all).")
    parser.add_argument("--query-repeats", type=int, default=3, help="Runs per query; the median is reported (default 3).")
    parser.add_argument("--phase-timeout", type=int, default=7200, help="Seconds before a build phase is stopped (default 7200).")
    parser.add_argument("--json", action="store_true", help="Print the JSON report instead of the text summary.")
    parser.add_argument("--child-phase", choices=PHASES, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.child_phase:
        index_name = "index.sqlite" if args.child_phase == "plain" else "index-{}.sqlite".format(args.child_phase)
        return run_child_phase(
            args.child_phase,
            args.corpus_root.resolve(),
            args.output_dir / index_name,
            args.output_dir / "phase-{}.json".format(args.child_phase),
        )

    corpus_root = args.corpus_root.resolve()
    if not corpus_root.is_dir():
        print("ERROR: corpus folder not found: {}".format(corpus_root), file=sys.stderr)
        return 2
    phases = [phase.strip() for phase in args.phases.split(",") if phase.strip()]
    if "plain" not in phases or any(phase not in PHASES for phase in phases):
        print("ERROR: --phases must include plain and use only {}.".format(",".join(PHASES)), file=sys.stderr)
        return 2
    if args.query_repeats < 1:
        print("ERROR: --query-repeats must be at least 1.", file=sys.stderr)
        return 2
    if args.output_dir is None:
        output_dir = Path(tempfile.mkdtemp(prefix="mimir-kb-benchmark-"))
    else:
        output_dir = args.output_dir.resolve()
        try:
            output_dir.relative_to(REPO_ROOT)
            print("ERROR: refused output folder inside the repository: {}".format(output_dir), file=sys.stderr)
            return 2
        except ValueError:
            pass
        output_dir.mkdir(parents=True, exist_ok=True)

    phase_results: dict[str, dict[str, object]] = {}
    try:
        for phase in PHASES:
            if phase in phases:
                phase_results[phase] = launch_phase(phase, corpus_root, output_dir, args.phase_timeout)
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 1

    index_path = output_dir / "index.sqlite"
    plain = phase_results["plain"]
    profiled = phase_results.get("profile", {})
    report: dict[str, object] = {
        "tool": "Measure-KbIntelligenceBuild",
        "measured_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "host": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
        },
        "corpus": dict(corpus_size(corpus_root), path=str(corpus_root)),
        "build": {"wall_clock_seconds": plain["wall_clock_seconds"], "exit_code": plain["exit_code"]},
        "memory": {
            "peak_rss_mb": plain["peak_rss_mb"],
            "peak_rss_source": plain["peak_rss_source"],
            "tracemalloc_peak_mb": phase_results.get("tracemalloc", {}).get("tracemalloc_peak_mb"),
        },
        "profile": {
            "wall_clock_seconds": profiled.get("wall_clock_seconds"),
            "top_cumulative": profiled.get("top_cumulative", []),
            "top_tottime": profiled.get("top_tottime", []),
            "watched": profiled.get("watched", []),
        },
        "index": {"path": str(index_path), "size_bytes": index_path.stat().st_size},
        "counts": index_counts(index_path),
        "queries": run_queries(index_path, args.query_repeats),
        "report_path": str(output_dir / "report.json"),
    }
    (output_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(text_summary(report))
    failed = plain["exit_code"] != 0 or any(not query["ok"] for query in report["queries"])  # type: ignore[union-attr]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
