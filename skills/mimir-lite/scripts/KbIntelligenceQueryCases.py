#!/usr/bin/env python3
"""Validate KB Intelligence query behavior against small JSON case files.

Case runner behind Test-KbIntelligenceQueries.ps1; it loads Query-KbIntelligenceIndex.py
from its own folder.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sqlite3
from pathlib import Path
from typing import Any


def load_query_engine(script_dir: Path) -> Any:
    engine_path = script_dir / "Query-KbIntelligenceIndex.py"
    spec = importlib.util.spec_from_file_location("kb_intelligence_query", engine_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Unable to load query engine: {engine_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def split_typed_name(value: str) -> tuple[str, str]:
    if ":" not in value:
        raise ValueError(f"Expected Type:Name value: {value}")
    object_type, object_name = value.split(":", 1)
    return object_type, object_name


def typed_name(row: dict[str, object], prefix: str) -> str:
    return f"{row.get(prefix + '_type')}:{row.get(prefix + '_name')}"


def validate_impact_basic(query_engine: Any, conn: sqlite3.Connection, raw_case: dict[str, Any]) -> dict[str, Any]:
    object_type, object_name = split_typed_name(raw_case["object"])
    result = query_engine.impact_basic(conn, object_type, object_name, raw_case.get("limit"))
    should_exist = bool(raw_case.get("should_exist", True))

    failures: list[str] = []
    if bool(result.get("found")) != should_exist:
        failures.append(f"found={result.get('found')} expected {should_exist}")

    if should_exist:
        incoming = int(result.get("incoming_relations", 0))
        outgoing = int(result.get("outgoing_relations", 0))
        if incoming < int(raw_case.get("min_incoming_relations", 0)):
            failures.append(f"incoming_relations={incoming} below minimum {raw_case.get('min_incoming_relations')}")
        if outgoing < int(raw_case.get("min_outgoing_relations", 0)):
            failures.append(f"outgoing_relations={outgoing} below minimum {raw_case.get('min_outgoing_relations')}")

        dependents = {typed_name(row, "source") for row in result.get("dependents", []) if isinstance(row, dict)}
        dependencies = {typed_name(row, "target") for row in result.get("dependencies", []) if isinstance(row, dict)}
        for expected in raw_case.get("expected_dependents", []):
            if expected not in dependents:
                failures.append(f"missing expected dependent {expected}")
        for expected in raw_case.get("expected_dependencies", []):
            if expected not in dependencies:
                failures.append(f"missing expected dependency {expected}")

    case_result = dict(raw_case)
    case_result["status"] = "failed" if failures else "passed"
    if failures:
        case_result["failures"] = failures
    return case_result


def validate_functional_trace_basic(query_engine: Any, conn: sqlite3.Connection, raw_case: dict[str, Any]) -> dict[str, Any]:
    object_type, object_name = split_typed_name(raw_case["object"])
    result = query_engine.functional_trace_basic(conn, object_type, object_name, raw_case.get("limit"))
    should_exist = bool(raw_case.get("should_exist", True))

    failures: list[str] = []
    if bool(result.get("found")) != should_exist:
        failures.append(f"found={result.get('found')} expected {should_exist}")

    if should_exist:
        trace_rows = result.get("technical_trace", [])
        if not isinstance(trace_rows, list):
            failures.append("technical_trace is not a list")
            trace_rows = []
        reading_plan = result.get("xml_reading_plan", [])
        if not isinstance(reading_plan, list):
            failures.append("xml_reading_plan is not a list")
            reading_plan = []

        trace_targets = {typed_name(row, "target") for row in trace_rows if isinstance(row, dict)}
        trace_sources = {typed_name(row, "source") for row in trace_rows if isinstance(row, dict)}
        trace_rules = {str(row.get("extractor_rule")) for row in trace_rows if isinstance(row, dict)}
        plan_files = {str(row.get("file_path")) for row in reading_plan if isinstance(row, dict)}
        response_contract = result.get("response_contract", [])

        for expected in raw_case.get("expected_trace_targets", []):
            if expected not in trace_targets:
                failures.append(f"missing expected trace target {expected}")
        for expected in raw_case.get("expected_trace_sources", []):
            if expected not in trace_sources:
                failures.append(f"missing expected trace source {expected}")
        for expected in raw_case.get("expected_rules", []):
            if expected not in trace_rules:
                failures.append(f"missing expected rule {expected}")
        for expected in raw_case.get("expected_reading_plan_files", []):
            if expected not in plan_files:
                failures.append(f"missing expected reading plan file {expected}")
        if "expected_suppressed_redundant_custom_type_relations" in raw_case:
            expected_suppressed = int(raw_case["expected_suppressed_redundant_custom_type_relations"])
            actual_suppressed = int(result.get("suppressed_redundant_custom_type_relations", 0))
            if actual_suppressed != expected_suppressed:
                failures.append(
                    "suppressed_redundant_custom_type_relations="
                    f"{actual_suppressed} expected {expected_suppressed}"
                )
        for expected in ("Direct evidence", "Additional XML reading", "Strong inference", "Hypothesis"):
            if not isinstance(response_contract, list) or expected not in response_contract:
                failures.append(f"missing response contract section {expected}")
        if "Does not constitute complete functional proof" not in str(result.get("notice", "")):
            failures.append("notice does not declare functional proof limit")

    case_result = dict(raw_case)
    case_result["status"] = "failed" if failures else "passed"
    if failures:
        case_result["failures"] = failures
    return case_result


def validate_object_info(query_engine: Any, conn: sqlite3.Connection, raw_case: dict[str, Any]) -> dict[str, Any]:
    object_type, object_name = split_typed_name(raw_case["object"])
    result = query_engine.object_info(conn, object_type, object_name)
    should_exist = bool(raw_case.get("should_exist", True))

    failures: list[str] = []
    if bool(result.get("found")) != should_exist:
        failures.append(f"found={result.get('found')} expected {should_exist}")

    if should_exist:
        obj = result.get("object", {})
        if not isinstance(obj, dict):
            failures.append("missing object payload")
        else:
            expected_file_contains = raw_case.get("expected_file_contains")
            if expected_file_contains and expected_file_contains not in str(obj.get("file_path", "")):
                failures.append(f"file_path={obj.get('file_path')} does not contain {expected_file_contains}")

    case_result = dict(raw_case)
    case_result["status"] = "failed" if failures else "passed"
    if failures:
        case_result["failures"] = failures
    return case_result


def validate_attribute_info(query_engine: Any, conn: sqlite3.Connection, raw_case: dict[str, Any]) -> dict[str, Any]:
    object_type, object_name = split_typed_name(raw_case["object"])
    if object_type != "Attribute":
        raise ValueError(f"attribute-info expects Attribute:Name object, got {raw_case['object']}")

    result = query_engine.attribute_info(conn, object_name)
    should_exist = bool(raw_case.get("should_exist", True))

    failures: list[str] = []
    if bool(result.get("found")) != should_exist:
        failures.append(f"found={result.get('found')} expected {should_exist}")

    if should_exist:
        for key in ("isFormula", "formulaExpression", "basedOn"):
            expected_key = f"expected_{key}"
            if expected_key in raw_case and result.get(key) != raw_case[expected_key]:
                failures.append(f"{key}={result.get(key)!r} expected {raw_case[expected_key]!r}")

        expected_file_contains = raw_case.get("expected_file_contains")
        obj = result.get("object", {})
        if expected_file_contains and (
            not isinstance(obj, dict) or expected_file_contains not in str(obj.get("file_path", ""))
        ):
            actual_file = obj.get("file_path") if isinstance(obj, dict) else None
            failures.append(f"file_path={actual_file} does not contain {expected_file_contains}")

    case_result = dict(raw_case)
    case_result["status"] = "failed" if failures else "passed"
    if failures:
        case_result["failures"] = failures
    return case_result


def validate_transaction_attribute_query(
    query_engine: Any,
    conn: sqlite3.Connection,
    raw_case: dict[str, Any],
    *,
    writable_only: bool,
) -> dict[str, Any]:
    object_type, object_name = split_typed_name(raw_case["object"])
    if object_type != "Transaction":
        raise ValueError(f"{raw_case.get('query')} expects Transaction:Name object, got {raw_case['object']}")

    if writable_only:
        result = query_engine.transaction_writable_attributes(conn, object_name)
    else:
        result = query_engine.transaction_attributes(conn, object_name)
    should_exist = bool(raw_case.get("should_exist", True))

    failures: list[str] = []
    if bool(result.get("found")) != should_exist:
        failures.append(f"found={result.get('found')} expected {should_exist}")

    if should_exist:
        rows = result.get("results", [])
        if not isinstance(rows, list):
            failures.append("results is not a list")
            rows = []

        by_attribute = {str(row.get("attribute")): row for row in rows if isinstance(row, dict)}
        if len(rows) < int(raw_case.get("min_attributes", 0)):
            failures.append(f"total attributes={len(rows)} below minimum {raw_case.get('min_attributes')}")

        for expected in raw_case.get("expected_attributes", []):
            if expected not in by_attribute:
                failures.append(f"missing expected attribute {expected}")

        for attribute, expected_classification in raw_case.get("expected_classifications", {}).items():
            row = by_attribute.get(attribute)
            if row is None:
                failures.append(f"missing expected attribute {attribute}")
            elif row.get("classification") != expected_classification:
                failures.append(
                    f"{attribute}.classification={row.get('classification')!r} "
                    f"expected {expected_classification!r}"
                )

        for attribute, expected_writable in raw_case.get("expected_writable", {}).items():
            row = by_attribute.get(attribute)
            if row is None:
                failures.append(f"missing expected attribute {attribute}")
            elif row.get("writable") != expected_writable:
                failures.append(
                    f"{attribute}.writable={row.get('writable')!r} expected {expected_writable!r}"
                )

    case_result = dict(raw_case)
    case_result["status"] = "failed" if failures else "passed"
    if failures:
        case_result["failures"] = failures
    return case_result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate KB Intelligence query behavior.")
    parser.add_argument("--index-path", required=True, type=Path)
    parser.add_argument("--validation-cases-path", required=True, type=Path)
    parser.add_argument("--validation-report-path", type=Path)
    parser.add_argument("--fail-on-validation-failure", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.index_path.exists():
        raise SystemExit(f"IndexPath not found: {args.index_path}")
    if not args.validation_cases_path.exists():
        raise SystemExit(f"ValidationCasesPath not found: {args.validation_cases_path}")

    query_engine = load_query_engine(Path(__file__).resolve().parent)
    raw_cases = json.loads(args.validation_cases_path.read_text(encoding="utf-8"))

    cases: list[dict[str, Any]] = []
    conn = sqlite3.connect(args.index_path)
    try:
        for raw_case in raw_cases.get("cases", []):
            query = raw_case.get("query")
            if query == "impact-basic":
                case_result = validate_impact_basic(query_engine, conn, raw_case)
            elif query == "functional-trace-basic":
                case_result = validate_functional_trace_basic(query_engine, conn, raw_case)
            elif query == "object-info":
                case_result = validate_object_info(query_engine, conn, raw_case)
            elif query == "attribute-info":
                case_result = validate_attribute_info(query_engine, conn, raw_case)
            elif query == "transaction-attributes":
                case_result = validate_transaction_attribute_query(
                    query_engine,
                    conn,
                    raw_case,
                    writable_only=False,
                )
            elif query == "transaction-writable-attributes":
                case_result = validate_transaction_attribute_query(
                    query_engine,
                    conn,
                    raw_case,
                    writable_only=True,
                )
            else:
                case_result = dict(raw_case)
                case_result["status"] = "failed"
                case_result["failures"] = [f"Unsupported query validation: {query}"]
            cases.append(case_result)
    finally:
        conn.close()

    report = {
        "index_path": str(args.index_path.resolve()),
        "validation_cases_path": str(args.validation_cases_path.resolve()),
        "cases": cases,
    }

    if args.validation_report_path:
        args.validation_report_path.parent.mkdir(parents=True, exist_ok=True)
        args.validation_report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.fail_on_validation_failure and any(case.get("status") == "failed" for case in cases):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
