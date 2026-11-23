"""Smoke run of the Python engines on the running interpreter.

Builds the KB Intelligence index from the synthetic fixture, runs a fixed set of queries, and
runs every tests/**/Test*.py unit test file. Meant to run on Python 3.8, the product's minimum,
through tools/Invoke-Python38SmokeInDocker.ps1, but it works on any Python 3.8 or later.
The repository is only read: the corpus is copied to a temporary folder (the build and the
queries take the corpus lock, which creates a lock file in the corpus), and the index and all
scratch files go there too.
Prints one PASS/FAIL/SKIP line per step and exits 1 when any step failed. Each step is stopped
after --step-timeout seconds and then counts as failed.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROCEDURE_NAME = "CalculateInvoiceTotal"
DEFAULT_STEP_TIMEOUT_SECONDS = 600


def run_step(name: str, command: list, failures: list, timeout: float) -> str:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        completed = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, env=env, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        failures.append(name)
        print(f"FAIL {name} (timed out after {timeout:g} s)")
        return ""
    stdout = completed.stdout.decode("utf-8", errors="replace")
    stderr = completed.stderr.decode("utf-8", errors="replace")
    if completed.returncode == 0:
        print(f"PASS {name}")
    else:
        failures.append(name)
        detail = (stderr.strip() or stdout.strip()).splitlines()[-3:]
        print(f"FAIL {name} (exit {completed.returncode}): {' | '.join(detail)}")
    return stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--source-root", type=Path, help="Corpus to index. Default: tests/fixtures/sample-kb.")
    parser.add_argument("--tests-root", type=Path, help="Folder searched for Test*.py. Default: tests.")
    parser.add_argument(
        "--step-timeout", type=float, default=DEFAULT_STEP_TIMEOUT_SECONDS, help="Seconds before a step is stopped."
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    given_source_root = (args.source_root or repo_root / "tests" / "fixtures" / "sample-kb").resolve()
    scripts = repo_root / "skills" / "mimir-lite" / "scripts"
    python = [sys.executable, "-B"]
    failures: list = []

    print(f"Python {platform.python_version()} ({sys.executable})")
    scratch = Path(tempfile.mkdtemp(prefix="mimir-py38-smoke-"))
    try:
        source_root = scratch / "corpus"
        if given_source_root.is_dir():
            shutil.copytree(str(given_source_root), str(source_root))
        else:
            source_root = given_source_root  # the build step reports the missing corpus
        index_path = scratch / "kb-intelligence.sqlite"
        run_step(
            "build",
            python + [str(scripts / "Build-KbIntelligenceIndex.py"), "--source-root", str(source_root), "--output-path", str(index_path)],
            failures,
            args.step_timeout,
        )

        if index_path.exists():
            transactions = sorted((source_root / "Transaction").glob("*.xml"))
            transaction_name = transactions[0].stem if transactions else ""
            queries = [
                ("index-metadata", []),
                ("list-by-type", ["--object-type", "Procedure"]),
                ("who-uses", ["--object-type", "Procedure", "--object-name", PROCEDURE_NAME]),
                ("impact-basic", ["--object-type", "Procedure", "--object-name", PROCEDURE_NAME]),
                ("functional-trace-basic", ["--object-type", "Procedure", "--object-name", PROCEDURE_NAME]),
                ("transaction-writable-attributes", ["--object-type", "Transaction", "--object-name", transaction_name]),
            ]
            for query, extra in queries:
                name = f"query {query}"
                if query == "transaction-writable-attributes" and not transaction_name:
                    print(f"SKIP {name}: the corpus has no Transaction objects")
                    continue
                before = len(failures)
                stdout = run_step(
                    name,
                    python + [str(scripts / "Query-KbIntelligenceIndex.py"), "--index-path", str(index_path), "--query", query] + extra,
                    failures,
                    args.step_timeout,
                )
                if len(failures) == before:
                    try:
                        json.loads(stdout)
                    except ValueError as exc:
                        failures.append(name)
                        print(f"FAIL {name}: output is not JSON ({exc})")
        else:
            failures.append("queries")
            print("FAIL queries: skipped, the build produced no index")

        tests_root = (args.tests_root or repo_root / "tests").resolve()
        for test_file in sorted(tests_root.rglob("Test*.py")):
            try:
                label = test_file.relative_to(repo_root).as_posix()
            except ValueError:
                label = test_file.as_posix()
            run_step(f"unittest {label}", python + [str(test_file)], failures, args.step_timeout)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(f"STEPS FAILED={len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
