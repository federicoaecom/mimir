#!/usr/bin/env python3
"""Query the KB Intelligence SQLite index."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import sys
from pathlib import Path
from typing import NamedTuple

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from GeneXusObjectTypeCatalogCore import (  # noqa: E402
    CatalogOverrideDiagnosticError,
    resolve_effective_object_type_catalog_for_query,
)


EXPECTED_SCHEMA_VERSION = "5"
LEVEL_RE = re.compile(r"<Level\b(?P<attrs>[^>]*)>(?P<body>.*?)</Level>", re.IGNORECASE | re.DOTALL)
LEVEL_ATTRIBUTE_RE = re.compile(
    r"<Attribute\b(?P<attrs>[^>]*)>(?P<name>.*?)</Attribute>",
    re.IGNORECASE | re.DOTALL,
)
XML_ATTR_RE = re.compile(r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)="(?P<value>[^"]*)"')
PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>(?P<name>.*?)</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
INSTANCE_KEY_GUID_PREFIX_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}-"
)

SEMANTIC_QUERIES = frozenset(
    {"who-uses", "what-uses", "impact-basic", "functional-trace-basic"}
)
EXIT_QUERY_NOT_SEMANTIC_FOR_TYPE = 11
EXIT_CATALOG_OVERRIDE_BLOCKED = 2

# Queries whose answer lists or counts the callers/users of an object (incoming relations).
REVERSE_RELATION_QUERIES = frozenset(
    {"who-uses", "impact-basic", "functional-trace-basic", "object-info"}
)
# Types whose objects carry code or bindings that reference other objects (events, a
# Source part, or the declarative task bindings and conditions of a GXflow Business
# Process Diagram), but whose references the extractor does not read: none of them is in
# INDEXED_SOURCE_TYPES of Build-KbIntelligenceIndex.py, and the WorkWithForWeb action/link
# extractors that also receive WorkWith match only the web Work With XML shape. When the
# index holds objects of these types, an incoming-relation answer may miss callers.
# Keep disjoint from INDEXED_SOURCE_TYPES (checked by
# tests/mimir-lite/Test-KbIntelligenceReverseCoverageSelfTest.ps1).
UNEXTRACTED_CALL_SOURCE_TYPES = (
    "BusinessProcessDiagram",
    "OfflineDatabase",
    "Panel",
    "SmartDevicesApplication",
    "WorkPanel",
    "WorkWith",
)
class ExtractedPart(NamedTuple):
    """A part of a partly extracted type and the extractor version that first indexed it."""

    name: str
    since_version: int


class PartialAttributeUseExtraction(NamedTuple):
    """What a partly extracted type's index holds (extracted) and what no version reads (missing)."""

    extracted: tuple[ExtractedPart, ...]
    missing: tuple[str, ...]


# Types whose attribute uses are extracted only in part: what the index holds and what it
# misses. "extracted" pairs each indexed part with the extractor_signature_version that first
# indexed it (index metadata): an index built by an older extractor reports that part as missing,
# and a type none of whose parts its index holds is reported as not extracted. "missing" lists
# the parts no extractor version reads. WorkWithForWeb emits workwith_references_attribute from
# its pattern instance: grid, filter, order and view attributes since 13, the attribute names of
# filter <condition value="..."> expressions since 14; view captions, view and action
# parameters, tab condition attributes and <variable> or event code are not read. Procedure,
# WebPanel, Transaction and DataProvider emit code_references_attribute since 15 from the code
# Parts the builder selects by type (Procedure Source, Rules and Events, DataProvider Source and
# Rules): reads, and writes only where the target is unambiguous ("block writes": a
# statement-start assignment inside for each or new; "rule writes": a Transaction assignment
# rule; "Transaction item writes": an item's left side when the DataProvider outputs a
# Transaction). Not read: other assignment targets (ambiguous writes, reported as reads),
# Conditions, Procedure Layout and WebForm Parts, the items of an SDT-output DataProvider,
# Business Component members (&bc.Attribute) and code in a <Source> outside any <Part>. A classic
# Report (GeneXus 7.5 to 9 export) emits code_references_attribute since 19 from its
# Layout/Block/CodeBlock/Source, Rules and Events, read like a Procedure's; its layout print
# blocks are not read. The mobile
# WorkWith emits workwith_references_attribute since 18 from its pattern instance: layout
# <data attribute>, order, search and break by attributes, and advanced filter attributes; grid
# conditions, rules, events and captions are not read.
PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES: dict[str, PartialAttributeUseExtraction] = {
    "DataProvider": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 15),
            ExtractedPart("rule reads", 15),
            ExtractedPart("Transaction item writes", 15),
        ),
        missing=("SDT output items", "Business Component members", "code outside a Part"),
    ),
    "Procedure": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 15),
            ExtractedPart("rule reads", 15),
            ExtractedPart("block writes", 15),
        ),
        missing=("ambiguous writes", "conditions", "layout", "Business Component members", "code outside a Part"),
    ),
    "Report": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 19),
            ExtractedPart("rule reads", 19),
            ExtractedPart("block writes", 19),
        ),
        missing=("ambiguous writes", "layout", "Business Component members"),
    ),
    "Transaction": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("rule reads", 15),
            ExtractedPart("rule writes", 15),
            ExtractedPart("event reads", 15),
            ExtractedPart("block writes", 15),
        ),
        missing=("ambiguous writes", "WebForm bindings", "Business Component members", "code outside a Part"),
    ),
    "WebPanel": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("rule reads", 15),
            ExtractedPart("event reads", 15),
            ExtractedPart("block writes", 15),
        ),
        missing=(
            "ambiguous writes",
            "conditions",
            "WebForm bindings",
            "Business Component members",
            "code outside a Part",
        ),
    ),
    "WorkWith": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("layouts", 18),
            ExtractedPart("orders", 18),
            ExtractedPart("search", 18),
            ExtractedPart("break by", 18),
            ExtractedPart("filters", 18),
        ),
        missing=("grid conditions", "rules", "events", "captions"),
    ),
    "WorkWithForWeb": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("grids", 13),
            ExtractedPart("filters", 13),
            ExtractedPart("orders", 13),
            ExtractedPart("views", 13),
            ExtractedPart("filter conditions", 14),
        ),
        missing=("captions", "parameters", "tab conditions", "code"),
    ),
}
# Types whose objects can use attributes (code, rules, formulas, conditions, grids, filters,
# views, layouts, or item types) while the extractor emits no attribute-use relation for any
# of them. Besides workwith_references_attribute (WorkWithForWeb, WorkWith) and
# code_references_attribute (Procedure, WebPanel, Transaction, DataProvider, Report), see
# PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES, the relations that target an Attribute are
# structural: has_level_attribute (Transaction levels), has_key_attribute and
# has_index_member_attribute (Table keys and indexes). Chosen from the object type catalog: the
# rest of the Source scope (INDEXED_SOURCE_TYPES: API, DataSelector), Attribute (formulas), SDT
# (items based on an attribute), DataView and Query (attribute lists), the web pattern
# WorkWithPlusInstance (grid, filter, order and view attributes), and every type of
# UNEXTRACTED_CALL_SOURCE_TYPES that is not partly extracted for attribute uses (the mobile
# WorkWith is). Table is left out: its attributes come from Transaction levels and its keys and
# indexes are extracted. Every UNEXTRACTED_CALL_SOURCE_TYPES type must be here or in
# PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES, and the two stay disjoint (checked by
# tests/mimir-lite/Test-KbIntelligenceReverseCoverageSelfTest.ps1).
UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES = tuple(
    sorted(
        (
            set(UNEXTRACTED_CALL_SOURCE_TYPES)
            | {
                "API",
                "Attribute",
                "DataSelector",
                "DataView",
                "Query",
                "SDT",
                "WorkWithPlusInstance",
            }
        )
        - set(PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES)
    )
)
COVERAGE_SCOPE_CALLS = "calls"
COVERAGE_SCOPE_ATTRIBUTE_REFERENCES = "attribute_references"
_CATALOG_TYPES_CACHE: dict[tuple[str | None, str | None, str], dict[str, dict[str, object]]] = {}


def _catalog_cache_key(
    index_path: Path,
    kb_workspace_root: Path | None,
    catalog_override_path: Path | None,
) -> tuple[str | None, str | None, str]:
    workspace_key = str(kb_workspace_root.resolve()) if kb_workspace_root is not None else None
    override_key = (
        str(catalog_override_path.resolve()) if catalog_override_path is not None else None
    )
    return workspace_key, override_key, str(index_path.resolve())


def load_catalog_types_by_name(
    index_path: Path,
    kb_workspace_root: Path | None = None,
    catalog_override_path: Path | None = None,
) -> dict[str, dict[str, object]]:
    """Effective catalog (base + optional override), aligned with Build-KbIntelligenceIndex."""
    cache_key = _catalog_cache_key(index_path, kb_workspace_root, catalog_override_path)
    cached = _CATALOG_TYPES_CACHE.get(cache_key)
    if cached is not None:
        return cached

    merged, _override_path = resolve_effective_object_type_catalog_for_query(
        index_path,
        kb_workspace_root=kb_workspace_root,
        catalog_override_path=catalog_override_path,
    )
    types_by_name = merged["types"]
    if not isinstance(types_by_name, dict):
        raise RuntimeError("Invalid effective object type catalog: missing types map")

    _CATALOG_TYPES_CACHE[cache_key] = types_by_name
    return types_by_name


def semantic_query_allowed(
    object_type: str,
    types_by_name: dict[str, dict[str, object]],
) -> tuple[bool, dict[str, object] | None]:
    """Return whether semantic index queries are allowed for this canonical type name."""
    entry = types_by_name.get(object_type)
    if entry is None:
        return True, None
    return bool(entry.get("queryableByKbIntelligence", True)), entry


def build_semantic_blocked_result(
    query: str,
    object_type: str,
    object_name: str,
    entry: dict[str, object] | None,
) -> dict[str, object]:
    inventory_eligible = entry.get("inventoryEligible") if entry is not None else None
    return {
        "query": query,
        "blocked": True,
        "reason": "QUERY_NOT_SEMANTIC_FOR_TYPE",
        "object": {"type": object_type, "name": object_name},
        "catalog": {
            "queryableByKbIntelligence": False,
            "inventoryEligible": inventory_eligible,
        },
        "notice": (
            "Type eligible for inventory (object-info, search-objects, list-by-type), not for "
            "who-uses/what-uses/impact-basic/functional-trace-basic with the current extractor. "
            "Empty graphs do not mean the addon or configuration has no impact."
        ),
        "suggested_queries": ["object-info", "search-objects", "list-by-type"],
    }


def format_semantic_blocked_text(result: dict[str, object]) -> str:
    obj = result.get("object")
    if not isinstance(obj, dict):
        obj = {}
    lines = [
        f"{result.get('query')}: BLOCKED ({result.get('reason')})",
        f"object: {obj.get('type')}:{obj.get('name')}",
        str(result.get("notice")),
        "suggested_queries: " + ", ".join(result.get("suggested_queries", [])),
    ]
    return "\n".join(lines)


def build_catalog_override_blocked_result(exc: CatalogOverrideDiagnosticError) -> dict[str, object]:
    diagnostic = dict(exc.diagnostic)
    return {
        "blocked": True,
        "reason": diagnostic.get("reason"),
        "status": diagnostic.get("status", "OVERRIDE_RESOLUTION_BLOCKED"),
        "diagnosticReason": diagnostic.get("diagnosticReason"),
        "fieldPath": diagnostic.get("fieldPath"),
        "overridePath": diagnostic.get("overridePath"),
        "message": diagnostic.get("message", str(exc)),
        "catalogOverrideDiagnostic": diagnostic,
    }


def format_catalog_override_blocked_text(result: dict[str, object]) -> str:
    return "\n".join(
        [
            f"catalog override: BLOCKED ({result.get('status')})",
            f"reason: {result.get('reason')} / {result.get('diagnosticReason')}",
            f"field: {result.get('fieldPath')}",
            f"override: {result.get('overridePath')}",
            str(result.get("message")),
        ]
    )


def validate_schema_version(conn: sqlite3.Connection) -> None:
    row = conn.execute(
        "SELECT value FROM metadata WHERE key = 'schema_version'"
    ).fetchone()
    if row is None:
        raise SystemExit(
            "Index schema version not found in metadata. "
            "This index was built by an older engine that predates schema versioning. "
            "Rebuild the index with Build-KbIntelligenceIndex before querying."
        )
    index_version = row[0]
    if index_version != EXPECTED_SCHEMA_VERSION:
        raise SystemExit(
            f"Index schema version mismatch: index has {index_version}, "
            f"engine expects {EXPECTED_SCHEMA_VERSION}. "
            "Rebuild the index before querying."
        )
    cursor = conn.execute("PRAGMA table_info(objects)")
    columns = {row[1] for row in cursor.fetchall()}
    if "guid" not in columns:
        raise SystemExit(
            "Index schema is missing required column 'guid' in objects table. "
            "Rebuild the index with the current engine before querying."
        )


def row_to_dict(cursor: sqlite3.Cursor, row: sqlite3.Row) -> dict[str, object]:
    return {description[0]: row[index] for index, description in enumerate(cursor.description)}


def fetch_all(conn: sqlite3.Connection, sql: str, params: tuple[object, ...]) -> list[dict[str, object]]:
    cursor = conn.execute(sql, params)
    return [row_to_dict(cursor, row) for row in cursor.fetchall()]


def fetch_one(conn: sqlite3.Connection, sql: str, params: tuple[object, ...]) -> dict[str, object] | None:
    cursor = conn.execute(sql, params)
    row = cursor.fetchone()
    if row is None:
        return None
    return row_to_dict(cursor, row)


def metadata_map(conn: sqlite3.Connection) -> dict[str, str]:
    rows = fetch_all(conn, "SELECT key, value FROM metadata", ())
    return {str(row["key"]): str(row["value"]) for row in rows}


def index_file_folder(conn: sqlite3.Connection) -> Path | None:
    """Folder of the open index file, or None for an in-memory database."""
    for row in conn.execute("PRAGMA database_list"):
        if row[1] == "main":
            return Path(row[2]).resolve().parent if row[2] else None
    return None


def resolve_source_root(conn: sqlite3.Connection, stored_source_root: str) -> Path:
    """Resolve metadata.source_root: relative to the index folder, or absolute as is."""
    source_root = Path(stored_source_root)
    if source_root.is_absolute():
        return source_root
    index_folder = index_file_folder(conn)
    if index_folder is None:
        raise SystemExit(
            f"Index metadata source_root '{stored_source_root}' is relative to the index folder, "
            "but the index is not backed by a file."
        )
    return Path(os.path.normpath(index_folder / source_root))


def resolve_index_file(conn: sqlite3.Connection, file_path: object) -> Path:
    path = Path(str(file_path))
    if path.is_absolute():
        return path
    source_root = metadata_map(conn).get("source_root")
    if not source_root:
        raise SystemExit("Index metadata does not expose source_root; rebuild index before file-backed queries.")
    return resolve_source_root(conn, source_root) / path


def read_indexed_text(conn: sqlite3.Connection, file_path: object) -> str:
    resolved = resolve_index_file(conn, file_path)
    if not resolved.is_file():
        message = f"Indexed XML file not found on disk: {resolved}"
        if not Path(str(file_path)).is_absolute():
            source_root = resolve_source_root(conn, metadata_map(conn)["source_root"])
            message += (
                f" (resolved_source_root: {source_root}). The corpus must be moved or copied "
                "together with the index, with the same relative layout; otherwise regenerate the index."
            )
        raise SystemExit(message)
    return resolved.read_text(encoding="utf-8-sig")


def parse_xml_attrs(raw_attrs: str) -> dict[str, str]:
    return {match.group("name"): html.unescape(match.group("value")) for match in XML_ATTR_RE.finditer(raw_attrs)}


def parse_properties(xml_text: str) -> dict[str, str]:
    properties: dict[str, str] = {}
    for match in PROPERTY_RE.finditer(xml_text):
        name = html.unescape(match.group("name")).strip()
        value = html.unescape(match.group("value")).strip()
        if name:
            properties[name] = value
    return properties


def fetch_object(conn: sqlite3.Connection, object_type: str, object_name: str) -> dict[str, object] | None:
    return fetch_one(
        conn,
        """
        SELECT object_id, type, name, guid, file_path, last_update, file_hash, is_generated_object, pattern_object_id, instance_key
        FROM objects
        WHERE type = ? AND LOWER(name) = LOWER(?)
        """,
        (object_type, object_name),
    )


def limit_rows(rows: list[dict[str, object]], limit: int | None) -> list[dict[str, object]]:
    if limit is None or limit <= 0:
        return rows
    return rows[:limit]


def generated_filter_clause(generated_filter: str | None) -> str:
    """Literal SQL clause for the authored-vs-generated filter (no params; literal 0/1 values)."""
    if generated_filter == "generated":
        return "AND is_generated_object = 1"
    if generated_filter == "authored":
        return "AND is_generated_object = 0"
    return ""


def generated_filter_from_args(args: argparse.Namespace) -> str | None:
    if getattr(args, "generated", False):
        return "generated"
    if getattr(args, "authored", False):
        return "authored"
    return None


def derive_instance_name(instance_key: object) -> str | None:
    """WorkWithForWeb instance name derived from instance_key.

    GeneXus convention: <canonical GUID 8-4-4-4-12>-<name>. Anchors on the GUID + first
    hyphen; never does a blind split (the GUID has internal hyphens). Hyphens inside the name
    are preserved. NULL / non-canonical / empty name -> None (not derivable).
    """
    if instance_key is None:
        return None
    text = str(instance_key)
    match = INSTANCE_KEY_GUID_PREFIX_RE.match(text)
    if not match:
        return None
    name = text[match.end():]
    return name or None


def classify_instance_filter(value: str) -> dict[str, str]:
    """Classifies the --instance-key argument as full-key or instance-name mode.

    full-key iff the value starts with a canonical GUID + hyphen AND there is a name after it;
    otherwise, instance-name. A <GUID>- key with no name is not a valid key -> error.
    Auto-detection is a documented contract (see kb-index-reference.md).
    """
    match = INSTANCE_KEY_GUID_PREFIX_RE.match(value)
    if match:
        if match.end() >= len(value):
            raise SystemExit(
                "--instance-key: a full key requires <GUID>-<name>; name missing after the GUID."
            )
        return {"mode": "full-key", "value": value}
    return {"mode": "instance-name", "value": value}


def index_metadata(conn: sqlite3.Connection) -> dict[str, object]:
    rows = fetch_all(
        conn,
        """
        SELECT key, value
        FROM metadata
        ORDER BY key
        """,
        (),
    )
    metadata = {str(row["key"]): row["value"] for row in rows}
    last_index_build_run_at = metadata.get("last_index_build_run_at")
    if not last_index_build_run_at:
        raise SystemExit(
            "index-metadata requires metadata.last_index_build_run_at; "
            "legacy or incompatible index detected, regenerate before using it for triage."
        )
    stored_source_root = metadata.get("source_root")
    return {
        "query": "index-metadata",
        "metadata": metadata,
        "last_index_build_run_at": last_index_build_run_at,
        "resolved_source_root": (
            str(resolve_source_root(conn, str(stored_source_root))) if stored_source_root else None
        ),
    }


def object_info(conn: sqlite3.Connection, object_type: str, object_name: str) -> dict[str, object]:
    obj = fetch_object(conn, object_type, object_name)
    if obj is None:
        return {
            "query": "object-info",
            "object": {"type": object_type, "name": object_name},
            "found": False,
        }

    obj["instance_name"] = derive_instance_name(obj.get("instance_key"))
    outgoing = fetch_one(
        conn,
        "SELECT COUNT(*) AS count FROM relations WHERE source_object_id = ?",
        (obj["object_id"],),
    )
    incoming = fetch_one(
        conn,
        "SELECT COUNT(*) AS count FROM relations WHERE target_type = ? AND LOWER(target_name) = LOWER(?)",
        (object_type, object_name),
    )
    return {
        "query": "object-info",
        "object": obj,
        "found": True,
        "outgoing_relations": outgoing["count"] if outgoing else 0,
        "incoming_relations": incoming["count"] if incoming else 0,
    }


def attribute_info(conn: sqlite3.Connection, attribute_name: str) -> dict[str, object]:
    obj = fetch_object(conn, "Attribute", attribute_name)
    if obj is None:
        return {
            "query": "attribute-info",
            "attribute": attribute_name,
            "found": False,
        }
    xml_text = read_indexed_text(conn, obj["file_path"])
    properties = parse_properties(xml_text)
    formula_expression = properties.get("Formula")
    based_on = properties.get("idBasedOn")
    return {
        "query": "attribute-info",
        "attribute": obj["name"],
        "found": True,
        "object": obj,
        "isFormula": formula_expression is not None,
        "formulaExpression": formula_expression,
        "basedOn": based_on,
        "properties": properties,
    }


def nullable_bool_from_sqlite(value: object) -> bool | None:
    if value is None:
        return None
    return bool(int(value))


def fetch_materialized_writability_rows(
    conn: sqlite3.Connection,
    transaction_name: str,
    attribute_name: str | None = None,
    include_attribute_facts: bool = True,
) -> list[dict[str, object]]:
    """Materialized writability rows of a Transaction, optionally for one attribute only.

    include_attribute_facts=False leaves out isFormula and formulaExpression, the two fields read
    from the attribute's XML file, so the rows come from the index alone.
    """
    attribute_clause = "AND LOWER(w.attribute_name) = LOWER(?)" if attribute_name is not None else ""
    params: tuple[object, ...] = (transaction_name,) if attribute_name is None else (transaction_name, attribute_name)
    materialized = fetch_all(
        conn,
        f"""
        SELECT
            w.transaction_name,
            w.level_name,
            w.attribute_name,
            w.key_in_level,
            w.is_redundant,
            w.classification,
            w.writable,
            w.can_assign_in_new,
            w.reason,
            w.evidence,
            w.writability_rule_version,
            o.file_path AS attribute_file
        FROM transaction_attribute_writability w
        JOIN objects o_tx ON o_tx.object_id = w.transaction_object_id
        LEFT JOIN objects o ON o.type = 'Attribute' AND LOWER(o.name) = LOWER(w.attribute_name)
        WHERE LOWER(o_tx.name) = LOWER(?) {attribute_clause}
        ORDER BY w.level_name, w.attribute_name
        """,
        params,
    )
    rows: list[dict[str, object]] = []
    for row in materialized:
        attr_name = str(row["attribute_name"])
        attribute_facts: dict[str, object] = {}
        if include_attribute_facts:
            attr_payload = attribute_info(conn, attr_name)
            attribute_facts = {
                "isFormula": bool(attr_payload.get("isFormula")) if attr_payload.get("found") else None,
                "formulaExpression": attr_payload.get("formulaExpression"),
            }
        writable = nullable_bool_from_sqlite(row.get("writable"))
        rows.append(
            {
                "transaction": row["transaction_name"],
                "levelName": row["level_name"],
                "attribute": attr_name,
                "key": bool(row["key_in_level"]),
                "isRedundant": bool(row["is_redundant"]),
                **attribute_facts,
                "classification": row["classification"],
                "writable": writable,
                "canAssignInNew": nullable_bool_from_sqlite(row.get("can_assign_in_new")),
                "reason": row["reason"],
                "evidence": row["evidence"],
                "writabilityRuleVersion": row["writability_rule_version"],
                "attributeFile": row.get("attribute_file"),
            }
        )
    return rows


def transaction_attribute_rows(conn: sqlite3.Connection, transaction_name: str) -> tuple[dict[str, object] | None, list[dict[str, object]]]:
    obj = fetch_object(conn, "Transaction", transaction_name)
    if obj is None:
        return None, []
    rows = fetch_materialized_writability_rows(conn, transaction_name)
    if rows:
        return obj, rows
    return obj, []


def transaction_attributes(conn: sqlite3.Connection, transaction_name: str) -> dict[str, object]:
    obj, rows = transaction_attribute_rows(conn, transaction_name)
    if obj is None:
        return {
            "query": "transaction-attributes",
            "transaction": transaction_name,
            "found": False,
        }
    return {
        "query": "transaction-attributes",
        "transaction": obj,
        "found": True,
        "total": len(rows),
        "results": rows,
    }


def transaction_writable_attributes(conn: sqlite3.Connection, transaction_name: str) -> dict[str, object]:
    obj, rows = transaction_attribute_rows(conn, transaction_name)
    if obj is None:
        return {
            "query": "transaction-writable-attributes",
            "transaction": transaction_name,
            "found": False,
        }
    return {
        "query": "transaction-writable-attributes",
        "transaction": obj,
        "found": True,
        "total": len(rows),
        "results": rows,
        "notice": (
            "Classification materialized in the index by GeneXusTransactionWritabilityCore.py. "
            "unclassified-* attributes require additional XML reading before generating New or assignments."
        ),
    }


def search_objects(conn: sqlite3.Connection, object_name: str | None, object_type: str | None, limit: int | None, generated_filter: str | None = None, instance_filter: dict[str, str] | None = None) -> dict[str, object]:
    # Dynamic WHERE: object_name can be None when only -InstanceKey is used.
    where: list[str] = []
    params: list[object] = []
    if object_name:
        pattern = object_name.replace("*", "%")
        if "%" not in pattern:
            pattern = f"%{pattern}%"
        where.append("name LIKE ?")
        params.append(pattern)
    if object_type:
        where.append("type = ?")
        params.append(object_type)
    if instance_filter and instance_filter["mode"] == "full-key":
        # full key: exact comparison ignoring case (LOWER SQLite, ASCII).
        where.append("LOWER(instance_key) = LOWER(?)")
        params.append(instance_filter["value"])
    if generated_filter == "generated":
        where.append("is_generated_object = 1")
    elif generated_filter == "authored":
        where.append("is_generated_object = 0")
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    rows = fetch_all(
        conn,
        f"""
        SELECT type, name, guid, file_path, last_update, is_generated_object, pattern_object_id, instance_key
        FROM objects
        {where_sql}
        ORDER BY type, name
        """,
        tuple(params),
    )
    if instance_filter and instance_filter["mode"] == "instance-name":
        # plain name: exact match ignoring case against the derived name.
        target = instance_filter["value"].casefold()
        rows = [
            r for r in rows
            if (dn := derive_instance_name(r.get("instance_key"))) is not None and dn.casefold() == target
        ]
    for r in rows:
        r["instance_name"] = derive_instance_name(r.get("instance_key"))
    total = len(rows)
    return {
        "query": "search-objects",
        "pattern": object_name,
        "object_type": object_type,
        "generated_filter": generated_filter,
        "instance_filter": instance_filter,
        "total": total,
        "shown": len(limit_rows(rows, limit)),
        "results": limit_rows(rows, limit),
    }


def index_extractor_version(conn: sqlite3.Connection) -> int:
    """The index's extractor_signature_version as a number; 0 when absent or not numeric."""
    value = metadata_map(conn).get("extractor_signature_version")
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return 0


def partial_extraction_for_version(version: int) -> dict[str, dict[str, tuple[str, ...]]]:
    """Partly extracted attribute-use types as an index of that extractor version holds them.

    A part the version predates moves to the front of "missing"; a type left with no extracted
    part is omitted, so the caller reports it as not extracted.
    """
    partial: dict[str, dict[str, tuple[str, ...]]] = {}
    for object_type, parts in PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES.items():
        extracted = tuple(part.name for part in parts.extracted if version >= part.since_version)
        if not extracted:
            continue
        not_yet = tuple(part.name for part in parts.extracted if version < part.since_version)
        partial[object_type] = {
            "extracted": extracted,
            "missing": not_yet + parts.missing,
        }
    return partial


def reverse_relation_coverage(
    conn: sqlite3.Connection, target_type: str | None = None
) -> dict[str, object]:
    """Coverage of incoming-relation answers for the target's type.

    An Attribute target uses the attribute_references scope (types whose attribute uses are
    not extracted, plus types whose attribute uses are extracted only in part); any other target
    uses the calls scope (types whose calls are not extracted; nothing is partly extracted).
    The type is compared ignoring case, so a differently cased "attribute" never falls back to
    the calls scope and its empty answer still discloses the attribute gap. Coverage is complete
    only when the index holds no object of an unextracted or partly extracted type. A partly
    extracted type claims only the parts the index's extractor_signature_version already
    extracted; with none of them (or no readable version) it is listed as not extracted.
    """
    partial_types: dict[str, dict[str, tuple[str, ...]]] = {}
    gated_types: tuple[str, ...] = ()
    if target_type is not None and target_type.casefold() == "attribute":
        scope = COVERAGE_SCOPE_ATTRIBUTE_REFERENCES
        source_types = UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES
        gated_types = tuple(sorted(PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES))
        partial_types = partial_extraction_for_version(index_extractor_version(conn))
    else:
        scope = COVERAGE_SCOPE_CALLS
        source_types = UNEXTRACTED_CALL_SOURCE_TYPES
    counted_types = tuple(source_types) + gated_types
    placeholders = ", ".join("?" for _ in counted_types)
    rows = fetch_all(
        conn,
        f"""
        SELECT type, COUNT(*) AS count
        FROM objects
        WHERE type IN ({placeholders})
        GROUP BY type
        ORDER BY type
        """,
        counted_types,
    )
    unextracted = [
        {"type": str(row["type"]), "count": int(row["count"])}
        for row in rows
        if str(row["type"]) not in partial_types
    ]
    partially_extracted = [
        {
            "type": str(row["type"]),
            "count": int(row["count"]),
            "extracted": list(partial_types[str(row["type"])]["extracted"]),
            "missing": list(partial_types[str(row["type"])]["missing"]),
        }
        for row in rows
        if str(row["type"]) in partial_types
    ]
    return {
        "complete": not unextracted and not partially_extracted,
        "unextracted_source_types": unextracted,
        "partially_extracted_source_types": partially_extracted,
        "scope": scope,
    }


def join_english_list(values: list[str]) -> str:
    if len(values) <= 1:
        return "".join(values)
    return ", ".join(values[:-1]) + " and " + values[-1]


def format_coverage_note(result: dict[str, object]) -> str | None:
    coverage = result.get("coverage")
    if not isinstance(coverage, dict) or coverage.get("complete") is not False:
        return None
    entries = coverage.get("unextracted_source_types", [])
    listed = ", ".join(
        f"{entry.get('type')} ({entry.get('count')})"
        for entry in entries
        if isinstance(entry, dict)
    )
    if coverage.get("scope") == COVERAGE_SCOPE_ATTRIBUTE_REFERENCES:
        segments: list[str] = []
        if listed:
            segments.append(f"attribute uses (grids, filters, code, rules, formulas) from {listed} are not extracted")
        partial_entries = [
            entry for entry in coverage.get("partially_extracted_source_types", []) if isinstance(entry, dict)
        ]
        if partial_entries:
            described = "; ".join(
                "{type} ({count}): {extracted} are indexed, {missing} are not".format(
                    type=entry.get("type"),
                    count=entry.get("count"),
                    extracted=join_english_list([str(item) for item in entry.get("extracted", [])]),
                    missing=join_english_list([str(item) for item in entry.get("missing", [])]),
                )
                for entry in partial_entries
            )
            segments.append(f"attribute uses are partly extracted from {described}")
        segments.append(
            "otherwise only structural relations (Transaction levels, Table keys and indexes) are indexed, "
            "so an empty or short list does not prove the attribute is unused"
        )
        return "coverage: incomplete - " + "; ".join(segments)
    return (
        f"coverage: incomplete - calls made from {listed} are not extracted; "
        "callers of those types can be missing, so an empty or short list does not prove the object is unused"
    )


def attach_level_writability(conn: sqlite3.Connection, rows: list[dict[str, object]]) -> None:
    """Attach to each Transaction level row that Transaction's materialized writability row.

    Only has_level_attribute rows whose source is a Transaction get the "writability" key: the
    object transaction-writable-attributes returns for that attribute without its file-backed
    isFormula and formulaExpression (so who-uses keeps reading the index alone), or None when the
    Transaction has no materialized row for it. Rows from other relations are left unchanged.
    """
    cache: dict[tuple[str, str], dict[str, object] | None] = {}
    for row in rows:
        if row.get("source_type") != "Transaction" or row.get("relation_kind") != "has_level_attribute":
            continue
        transaction_name = str(row["source_name"])
        attribute_name = str(row["target_name"])
        cache_key = (transaction_name.casefold(), attribute_name.casefold())
        if cache_key not in cache:
            materialized = fetch_materialized_writability_rows(
                conn, transaction_name, attribute_name, include_attribute_facts=False
            )
            # GeneXus allows an attribute only once per Transaction structure, so at most one
            # materialized row exists per (Transaction, attribute); the first one is attached.
            cache[cache_key] = materialized[0] if materialized else None
        row["writability"] = cache[cache_key]


def format_writability_line(row: dict[str, object], indent: str) -> str | None:
    if "writability" not in row:
        return None
    writability = row.get("writability")
    if not isinstance(writability, dict):
        return f"{indent}writability: (no materialized row)"
    return (
        f"{indent}writability: [{writability.get('levelName')}] "
        f"classification={writability.get('classification')} writable={writability.get('writable')} "
        f"reason={writability.get('reason')}"
    )


def who_uses(conn: sqlite3.Connection, object_type: str, object_name: str, limit: int | None) -> dict[str, object]:
    rows = fetch_all(
        conn,
        """
        SELECT
            r.relation_id,
            o.type AS source_type,
            o.name AS source_name,
            o.file_path AS source_file,
            r.target_type,
            r.target_name,
            r.relation_kind,
            r.confidence,
            e.line,
            e.column,
            e.snippet,
            e.evidence_role,
            e.extractor_rule
        FROM relations r
        JOIN objects o ON o.object_id = r.source_object_id
        JOIN evidence e ON e.evidence_id = r.evidence_id
        WHERE r.target_type = ? AND LOWER(r.target_name) = LOWER(?)
        ORDER BY o.type, o.name, e.line
        """,
        (object_type, object_name),
    )
    total = len(rows)
    shown_rows = limit_rows(rows, limit)
    if object_type.casefold() == "attribute":
        attach_level_writability(conn, shown_rows)
    return {
        "query": "who-uses",
        "object": {"type": object_type, "name": object_name},
        "total": total,
        "shown": len(shown_rows),
        "results": shown_rows,
    }


def what_uses(conn: sqlite3.Connection, object_type: str, object_name: str, limit: int | None) -> dict[str, object]:
    rows = fetch_all(
        conn,
        """
        SELECT
            r.relation_id,
            o.type AS source_type,
            o.name AS source_name,
            o.file_path AS source_file,
            r.target_type,
            r.target_name,
            r.relation_kind,
            r.confidence,
            e.line,
            e.column,
            e.snippet,
            e.evidence_role,
            e.extractor_rule
        FROM relations r
        JOIN objects o ON o.object_id = r.source_object_id
        JOIN evidence e ON e.evidence_id = r.evidence_id
        WHERE o.type = ? AND LOWER(o.name) = LOWER(?)
        ORDER BY r.target_type, r.target_name, e.line
        """,
        (object_type, object_name),
    )
    total = len(rows)
    return {
        "query": "what-uses",
        "object": {"type": object_type, "name": object_name},
        "total": total,
        "shown": len(limit_rows(rows, limit)),
        "results": limit_rows(rows, limit),
    }


def impact_basic(conn: sqlite3.Connection, object_type: str, object_name: str, limit: int | None) -> dict[str, object]:
    info = object_info(conn, object_type, object_name)
    if info.get("found") is False:
        return {
            "query": "impact-basic",
            "object": {"type": object_type, "name": object_name},
            "found": False,
            "notice": "Direct technical impact based on the index; does not represent complete runtime impact.",
        }

    incoming = who_uses(conn, object_type, object_name, limit)
    outgoing = what_uses(conn, object_type, object_name, limit)
    return {
        "query": "impact-basic",
        "object": info["object"],
        "found": True,
        "incoming_relations": info.get("incoming_relations", 0),
        "outgoing_relations": info.get("outgoing_relations", 0),
        "incoming_shown": incoming.get("shown", 0),
        "outgoing_shown": outgoing.get("shown", 0),
        "dependents": incoming.get("results", []),
        "dependencies": outgoing.get("results", []),
        "notice": "Direct technical impact based on the index; does not represent complete runtime impact.",
    }


def functional_trace_basic(conn: sqlite3.Connection, object_type: str, object_name: str, limit: int | None) -> dict[str, object]:
    impact = impact_basic(conn, object_type, object_name, None)
    if impact.get("found") is False:
        return {
            "query": "functional-trace-basic",
            "object": {"type": object_type, "name": object_name},
            "found": False,
            "technical_trace": [],
            "xml_reading_plan": [],
            "response_contract": [
                "Direct evidence",
                "Additional XML reading",
                "Strong inference",
                "Hypothesis",
            ],
            "notice": "Basic functional triage based on a derived technical index. Does not constitute complete functional proof, nor does it replace reading the official XML.",
        }

    trace_rows: list[dict[str, object]] = []
    for direction, section in (("incoming", "dependents"), ("outgoing", "dependencies")):
        rows = impact.get(section, [])
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            trace_row = dict(row)
            trace_row["direction"] = direction
            trace_rows.append(trace_row)

    def custom_type_payload(target_name: object) -> str | None:
        value = str(target_name)
        if ":" not in value:
            return None
        return value.split(":", 1)[1].split(",", 1)[0].strip().lower()

    resolved_keys: set[tuple[object, object, object, str]] = set()
    for row in trace_rows:
        if row.get("target_type") == "CustomType":
            continue
        if "resolved" not in str(row.get("extractor_rule")):
            continue
        key = (row.get("direction"), row.get("source_file"), row.get("line"), str(row.get("target_name")).lower())
        resolved_keys.add(key)

    filtered_trace_rows: list[dict[str, object]] = []
    suppressed_custom_type_count = 0
    for row in trace_rows:
        if row.get("target_type") == "CustomType":
            payload = custom_type_payload(row.get("target_name"))
            key = (row.get("direction"), row.get("source_file"), row.get("line"), payload or "")
            if payload and key in resolved_keys:
                suppressed_custom_type_count += 1
                continue
        filtered_trace_rows.append(row)
    trace_rows = filtered_trace_rows

    def trace_sort_key(row: dict[str, object]) -> tuple[int, int, str, str, int]:
        target_type = str(row.get("target_type", ""))
        relation_kind = str(row.get("relation_kind", ""))
        direction_rank = 0 if row.get("direction") == "incoming" else 1
        # For functional triage, resolved/local objects are usually better first
        # than literal CustomType edges, while still preserving every relation.
        target_rank = 1 if target_type == "CustomType" else 0
        resolved_rank = 0 if "resolved" in relation_kind else 1
        line = row.get("line")
        return (direction_rank, target_rank, resolved_rank, target_type, int(line) if isinstance(line, int) else 0)

    trace_rows = limit_rows(sorted(trace_rows, key=trace_sort_key), limit)

    reading_plan_by_file: dict[str, dict[str, object]] = {}
    obj = impact.get("object")
    if isinstance(obj, dict) and obj.get("file_path"):
        reading_plan_by_file[str(obj["file_path"])] = {
            "file_path": obj["file_path"],
            "reason": "Open the official XML of the main object before concluding functionally.",
            "trigger": f"{object_type}:{object_name}",
            "index_limit": "The index confirms existence and direct technical relations; it does not prove complete functional semantics.",
        }

    for row in trace_rows:
        source_file = row.get("source_file")
        if not source_file:
            continue
        source = f"{row.get('source_type')}:{row.get('source_name')}"
        target = f"{row.get('target_type')}:{row.get('target_name')}"
        reading_plan_by_file.setdefault(
            str(source_file),
            {
                "file_path": source_file,
                "reason": "Open the official XML to review the snippet anchored by the technical evidence.",
                "trigger": f"{source} -> {target}",
                "index_limit": "The evidence indicates a direct technical relation; the functional conclusion depends on reading the official XML.",
            },
        )

    return {
        "query": "functional-trace-basic",
        "object": impact["object"],
        "found": True,
        "incoming_relations": impact.get("incoming_relations", 0),
        "outgoing_relations": impact.get("outgoing_relations", 0),
        "technical_trace_shown": len(trace_rows),
        "suppressed_redundant_custom_type_relations": suppressed_custom_type_count,
        "technical_trace": trace_rows,
        "xml_reading_plan": list(reading_plan_by_file.values()),
        "response_contract": [
            "Direct evidence",
            "Additional XML reading",
            "Strong inference",
            "Hypothesis",
        ],
        "notice": "Basic functional triage based on a derived technical index. Does not constitute complete functional proof, nor does it replace reading the official XML.",
    }


def list_by_type(conn: sqlite3.Connection, object_type: str, limit: int | None, generated_filter: str | None = None) -> dict[str, object]:
    generated_clause = generated_filter_clause(generated_filter)
    rows = fetch_all(
        conn,
        f"""
        SELECT type, name, guid, file_path, last_update, is_generated_object, pattern_object_id, instance_key
        FROM objects
        WHERE type = ? {generated_clause}
        ORDER BY name
        """,
        (object_type,),
    )
    for r in rows:
        r["instance_name"] = derive_instance_name(r.get("instance_key"))
    total = len(rows)
    return {
        "query": "list-by-type",
        "object_type": object_type,
        "generated_filter": generated_filter,
        "total": total,
        "shown": len(limit_rows(rows, limit)),
        "results": limit_rows(rows, limit),
    }


def css_classes(
    conn: sqlite3.Connection,
    class_name: str | None,
    model: str | None,
    origin: str | None,
    include_imported: bool,
    limit: int | None,
) -> dict[str, object]:
    where: list[str] = []
    params: list[object] = []
    if class_name:
        if "*" in class_name:
            where.append("class_name LIKE ?")
            params.append(class_name.replace("*", "%"))
        else:
            # Exact and case-sensitive match: CSS classes are case-sensitive.
            where.append("class_name = ?")
            params.append(class_name)
    if model:
        where.append("model = ?")
        params.append(model)
    if origin:
        where.append("origin = ?")
        params.append(origin)
    elif not include_imported and not class_name:
        # Default view (no name lookup and no explicit origin): only KB-authored classes.
        # A lookup by name NEVER filters by origin, so it does not produce a false "does not exist" for an imported class.
        where.append("origin = 'kb-authored'")
    clause = ("WHERE " + " AND ".join(where)) if where else ""
    rows = fetch_all(
        conn,
        f"""
        SELECT class_name, model, origin, defining_object_type,
               defining_object_name, defining_file, parent_class, extractor_rule
        FROM css_class
        {clause}
        ORDER BY model, class_name, defining_object_name
        """,
        tuple(params),
    )
    for row in rows:
        row["deprecated"] = row.get("model") == "legacy-theme"
    total = len(rows)
    return {
        "query": "css-classes",
        "filters": {
            "class_name": class_name,
            "model": model,
            "origin": origin,
            "include_imported": include_imported,
        },
        "total": total,
        "shown": len(limit_rows(rows, limit)),
        "results": limit_rows(rows, limit),
        "notice": (
            "model='legacy-theme' marked deprecated=true (old model, migration candidate to DesignSystem). "
            "Without a name lookup and without --origin, the view lists only origin='kb-authored'; use --include-imported "
            "or --origin packaged-module for imported-lib classes."
        ),
    }


def css_class_usage(
    conn: sqlite3.Connection,
    class_name: str | None,
    limit: int | None,
) -> dict[str, object]:
    dynamic_row = fetch_one(
        conn,
        "SELECT COUNT(*) AS count FROM relations WHERE relation_kind = 'uses_css_class_dynamic'",
        (),
    )
    dynamic_total = dynamic_row["count"] if dynamic_row else 0
    honest_notice = (
        "Honest coverage: resolvable_uses are uses with a literal class name (layout + code). "
        "dynamic_uses_total is the total of dynamic .Class= assignments (variable/Format) in the corpus, "
        "NOT attributable to a specific class by name. found_in_catalog=false indicates a class used "
        "but not cataloged (e.g. an imported one not scanned), not a nonexistent one. A destructive operation requires "
        "confirmation via a literal search in the XML."
    )

    if not class_name:
        resolvable_row = fetch_one(
            conn,
            "SELECT COUNT(*) AS count FROM relations WHERE relation_kind = 'uses_css_class'",
            (),
        )
        uncatalogued_rows = fetch_all(
            conn,
            """
            SELECT DISTINCT r.target_name AS class_name
            FROM relations r
            WHERE r.relation_kind = 'uses_css_class'
              AND r.target_name NOT IN (SELECT class_name FROM css_class)
            ORDER BY r.target_name
            """,
            (),
        )
        uncatalogued = [str(row["class_name"]) for row in uncatalogued_rows]
        return {
            "query": "css-class-usage",
            "scope": "overview",
            "resolvable_uses_total": resolvable_row["count"] if resolvable_row else 0,
            "dynamic_uses_total": dynamic_total,
            "used_but_uncatalogued_total": len(uncatalogued),
            "used_but_uncatalogued": uncatalogued if limit is None or limit <= 0 else uncatalogued[:limit],
            "notice": honest_notice,
        }

    catalog = fetch_all(
        conn,
        """
        SELECT class_name, model, origin, defining_object_type, defining_object_name, defining_file, parent_class
        FROM css_class
        WHERE class_name = ?
        ORDER BY model, defining_object_name
        """,
        (class_name,),
    )
    uses = fetch_all(
        conn,
        """
        SELECT
            o.type AS source_type,
            o.name AS source_name,
            o.file_path AS source_file,
            r.relation_kind,
            e.evidence_role,
            e.line,
            e.snippet
        FROM relations r
        JOIN objects o ON o.object_id = r.source_object_id
        JOIN evidence e ON e.evidence_id = r.evidence_id
        WHERE r.target_type = 'CssClass' AND r.target_name = ? AND r.relation_kind = 'uses_css_class'
        ORDER BY o.type, o.name, e.evidence_role
        """,
        (class_name,),
    )
    return {
        "query": "css-class-usage",
        "scope": "class",
        "class_name": class_name,
        "found_in_catalog": len(catalog) > 0,
        "catalog": catalog,
        "resolvable_uses_total": len(uses),
        "resolvable_uses_shown": len(limit_rows(uses, limit)),
        "resolvable_uses": limit_rows(uses, limit),
        "dynamic_uses_total": dynamic_total,
        "notice": honest_notice,
    }


def show_evidence(
    conn: sqlite3.Connection,
    relation_id: int | None,
    source_type: str | None,
    source_name: str | None,
    target_type: str | None,
    target_name: str | None,
    limit: int | None,
) -> dict[str, object]:
    if relation_id is not None:
        rows = fetch_all(
            conn,
            """
            SELECT
                r.relation_id,
                o.type AS source_type,
                o.name AS source_name,
                o.file_path AS source_file,
                r.target_type,
                r.target_name,
                r.relation_kind,
                r.confidence,
                e.line,
                e.column,
                e.snippet,
                e.evidence_role,
                e.extractor_rule
            FROM relations r
            JOIN objects o ON o.object_id = r.source_object_id
            JOIN evidence e ON e.evidence_id = r.evidence_id
            WHERE r.relation_id = ?
            """,
            (relation_id,),
        )
    else:
        required = [source_type, source_name, target_type, target_name]
        if any(value is None for value in required):
            raise SystemExit("show-evidence requires --relation-id or source/target type and name.")
        rows = fetch_all(
            conn,
            """
            SELECT
                r.relation_id,
                o.type AS source_type,
                o.name AS source_name,
                o.file_path AS source_file,
                r.target_type,
                r.target_name,
                r.relation_kind,
                r.confidence,
                e.line,
                e.column,
                e.snippet,
                e.evidence_role,
                e.extractor_rule
            FROM relations r
            JOIN objects o ON o.object_id = r.source_object_id
            JOIN evidence e ON e.evidence_id = r.evidence_id
            WHERE o.type = ? AND LOWER(o.name) = LOWER(?) AND r.target_type = ? AND LOWER(r.target_name) = LOWER(?)
            ORDER BY e.line
            """,
            (source_type, source_name, target_type, target_name),
        )
    total = len(rows)
    return {"query": "show-evidence", "total": total, "shown": len(limit_rows(rows, limit)), "results": limit_rows(rows, limit)}


def format_text(result: dict[str, object]) -> str:
    text = format_result_text(result)
    note = format_coverage_note(result)
    return f"{text}\n{note}" if note else text


def format_result_text(result: dict[str, object]) -> str:
    if result.get("blocked") is True:
        return format_semantic_blocked_text(result)

    lines: list[str] = []
    query = result.get("query")
    if query == "index-metadata":
        metadata = result.get("metadata")
        lines.append("index-metadata")
        lines.append(f"last_index_build_run_at: {result.get('last_index_build_run_at')}")
        resolved_source_root = result.get("resolved_source_root")
        lines.append(
            f"resolved_source_root: {resolved_source_root if resolved_source_root is not None else '(not recorded)'}"
        )
        if isinstance(metadata, dict):
            for key in sorted(metadata):
                if key == "last_index_build_run_at":
                    continue
                lines.append(f"{key}: {metadata[key]}")
        return "\n".join(lines)

    if query == "css-classes":
        lines.append(f"css-classes: {result.get('shown', 0)}/{result.get('total', 0)}")
        if result.get("notice"):
            lines.append(str(result.get("notice")))
        rows = result.get("results", [])
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                deprecated = " [deprecated]" if row.get("deprecated") else ""
                lines.append(
                    f"- {row.get('class_name')} [{row.get('model')}/{row.get('origin')}]{deprecated}"
                )
                lines.append(
                    f"  def: {row.get('defining_object_type')}:{row.get('defining_object_name')} "
                    f"({row.get('defining_file')})"
                    + (f" parent={row.get('parent_class')}" if row.get("parent_class") else "")
                )
        return "\n".join(lines)

    if query == "css-class-usage":
        if result.get("scope") == "overview":
            lines.append("css-class-usage: overview")
            lines.append(f"resolvable_uses_total: {result.get('resolvable_uses_total', 0)}")
            lines.append(f"dynamic_uses_total: {result.get('dynamic_uses_total', 0)}")
            lines.append(f"used_but_uncatalogued_total: {result.get('used_but_uncatalogued_total', 0)}")
            uncat = result.get("used_but_uncatalogued", [])
            if isinstance(uncat, list):
                for name in uncat:
                    lines.append(f"  - {name}")
            if result.get("notice"):
                lines.append(str(result.get("notice")))
            return "\n".join(lines)
        lines.append(f"css-class-usage: {result.get('class_name')}")
        lines.append(f"found_in_catalog: {result.get('found_in_catalog')}")
        catalog = result.get("catalog", [])
        if isinstance(catalog, list):
            for entry in catalog:
                if not isinstance(entry, dict):
                    continue
                lines.append(
                    f"  catalog: [{entry.get('model')}/{entry.get('origin')}] "
                    f"{entry.get('defining_object_type')}:{entry.get('defining_object_name')}"
                )
        lines.append(
            f"resolvable_uses: {result.get('resolvable_uses_shown', 0)}/{result.get('resolvable_uses_total', 0)}"
        )
        uses = result.get("resolvable_uses", [])
        if isinstance(uses, list):
            for row in uses:
                if not isinstance(row, dict):
                    continue
                lines.append(
                    f"  - {row.get('source_type')}:{row.get('source_name')} "
                    f"[{row.get('evidence_role')}] {row.get('source_file')}"
                )
                lines.append(f"    {row.get('snippet')}")
        lines.append(f"dynamic_uses_total: {result.get('dynamic_uses_total', 0)}")
        if result.get("notice"):
            lines.append(str(result.get("notice")))
        return "\n".join(lines)

    obj = result.get("object")
    if isinstance(obj, dict):
        if result.get("found") is False:
            lines.append(f"{query}: {obj.get('type')}:{obj.get('name')} not found")
            if query in ("impact-basic", "functional-trace-basic"):
                lines.append(str(result.get("notice")))
            return "\n".join(lines)
        lines.append(f"{query}: {obj.get('type')}:{obj.get('name')}")
    else:
        if query == "search-objects":
            inst = result.get("instance_filter")
            inst_val = inst.get("value") if isinstance(inst, dict) else None
            pat = result.get("pattern")
            if pat and inst_val:
                lines.append(f"{query}: {pat} (instance: {inst_val})")
            elif inst_val:
                lines.append(f"{query}: (instance: {inst_val})")
            else:
                lines.append(f"{query}: {pat}")
        elif query == "list-by-type":
            lines.append(f"{query}: {result.get('object_type')}")
        else:
            lines.append(str(query))

    if query == "object-info" and isinstance(obj, dict):
        lines.append(f"guid: {obj.get('guid')}")
        lines.append(f"file: {obj.get('file_path')}")
        lines.append(f"last_update: {obj.get('last_update')}")
        lines.append(f"generated: {obj.get('is_generated_object')}")
        lines.append(f"pattern_object_id: {obj.get('pattern_object_id')}")
        lines.append(f"instance_key: {obj.get('instance_key')}")
        lines.append(f"instance_name: {obj.get('instance_name')}")
        lines.append(f"incoming_relations: {result.get('incoming_relations', 0)}")
        lines.append(f"outgoing_relations: {result.get('outgoing_relations', 0)}")
        return "\n".join(lines)

    if query == "attribute-info":
        if result.get("found") is False:
            lines.append(f"attribute-info: {result.get('attribute')} not found")
            return "\n".join(lines)
        lines.append(f"attribute-info: {result.get('attribute')}")
        obj_payload = result.get("object")
        if isinstance(obj_payload, dict):
            lines.append(f"file: {obj_payload.get('file_path')}")
        lines.append(f"isFormula: {result.get('isFormula')}")
        if result.get("formulaExpression") is not None:
            lines.append(f"formulaExpression: {result.get('formulaExpression')}")
        if result.get("basedOn") is not None:
            lines.append(f"basedOn: {result.get('basedOn')}")
        return "\n".join(lines)

    if query in ("transaction-attributes", "transaction-writable-attributes"):
        tx = result.get("transaction")
        if result.get("found") is False:
            lines.append(f"{query}: {tx} not found")
            return "\n".join(lines)
        if isinstance(tx, dict):
            lines.append(f"{query}: {tx.get('name')}")
            lines.append(f"file: {tx.get('file_path')}")
        notice = result.get("notice")
        if notice:
            lines.append(str(notice))
        rows = result.get("results", [])
        lines.append(f"results: {len(rows) if isinstance(rows, list) else 0}/{result.get('total', 0)}")
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                lines.append(
                    f"- [{row.get('levelName')}] {row.get('attribute')} "
                    f"classification={row.get('classification')} writable={row.get('writable')} reason={row.get('reason')}"
                )
        return "\n".join(lines)

    if query == "impact-basic" and isinstance(obj, dict):
        lines.append(f"guid: {obj.get('guid')}")
        lines.append(f"file: {obj.get('file_path')}")
        lines.append(f"last_update: {obj.get('last_update')}")
        lines.append(f"incoming_relations: {result.get('incoming_relations', 0)}")
        lines.append(f"outgoing_relations: {result.get('outgoing_relations', 0)}")
        lines.append(str(result.get("notice")))
        for section, title in (("dependents", "dependents"), ("dependencies", "dependencies")):
            rows = result.get(section, [])
            shown_key = "incoming_shown" if section == "dependents" else "outgoing_shown"
            total_key = "incoming_relations" if section == "dependents" else "outgoing_relations"
            lines.append(f"{title}: {result.get(shown_key, 0)}/{result.get(total_key, 0)}")
            if not isinstance(rows, list) or not rows:
                lines.append("  (no results)")
                continue
            for row in rows:
                if not isinstance(row, dict):
                    continue
                source = f"{row.get('source_type')}:{row.get('source_name')}"
                target = f"{row.get('target_type')}:{row.get('target_name')}"
                lines.append(
                    f"  - #{row.get('relation_id')} {source} -> {target} "
                    f"[{row.get('relation_kind')}, {row.get('confidence')}]"
                )
                lines.append(
                    f"    {row.get('source_file')}:{row.get('line')} "
                    f"{row.get('evidence_role')} via {row.get('extractor_rule')}"
                )
                lines.append(f"    {row.get('snippet')}")
                writability_line = format_writability_line(row, "    ")
                if writability_line:
                    lines.append(writability_line)
        return "\n".join(lines)

    if query == "functional-trace-basic" and isinstance(obj, dict):
        lines.append(f"guid: {obj.get('guid')}")
        lines.append(f"file: {obj.get('file_path')}")
        lines.append(f"last_update: {obj.get('last_update')}")
        lines.append(f"incoming_relations: {result.get('incoming_relations', 0)}")
        lines.append(f"outgoing_relations: {result.get('outgoing_relations', 0)}")
        lines.append(str(result.get("notice")))

        trace_rows = result.get("technical_trace", [])
        lines.append(f"technical_trace: {result.get('technical_trace_shown', 0)}")
        if isinstance(trace_rows, list):
            for row in trace_rows:
                if not isinstance(row, dict):
                    continue
                source = f"{row.get('source_type')}:{row.get('source_name')}"
                target = f"{row.get('target_type')}:{row.get('target_name')}"
                lines.append(
                    f"  - {row.get('direction')} #{row.get('relation_id')} {source} -> {target} "
                    f"[{row.get('relation_kind')}, {row.get('confidence')}]"
                )
                lines.append(
                    f"    {row.get('source_file')}:{row.get('line')} "
                    f"{row.get('evidence_role')} via {row.get('extractor_rule')}"
                )
                lines.append(f"    {row.get('snippet')}")

        reading_plan = result.get("xml_reading_plan", [])
        lines.append("xml_reading_plan:")
        if isinstance(reading_plan, list):
            for item in reading_plan:
                if not isinstance(item, dict):
                    continue
                lines.append(f"  - {item.get('file_path')}")
                lines.append(f"    reason: {item.get('reason')}")
                lines.append(f"    trigger: {item.get('trigger')}")
        lines.append("response_contract: Direct evidence | Additional XML reading | Strong inference | Hypothesis")
        return "\n".join(lines)

    total = result.get("total", 0)
    shown = result.get("shown", 0)
    lines.append(f"results: {shown}/{total}")

    rows = result.get("results", [])
    if not isinstance(rows, list) or not rows:
        lines.append("(no results)")
        return "\n".join(lines)

    for row in rows:
        if not isinstance(row, dict):
            continue
        if query in ("search-objects", "list-by-type"):
            lines.append(f"- {row.get('type')}:{row.get('name')}")
            line2 = f"  guid={row.get('guid')} {row.get('file_path')} last_update={row.get('last_update')} generated={row.get('is_generated_object')}"
            if row.get("instance_name"):
                line2 += f" instance_name={row.get('instance_name')}"
            lines.append(line2)
            continue
        source = f"{row.get('source_type')}:{row.get('source_name')}"
        target = f"{row.get('target_type')}:{row.get('target_name')}"
        lines.append(
            f"- #{row.get('relation_id')} {source} -> {target} "
            f"[{row.get('relation_kind')}, {row.get('confidence')}]"
        )
        lines.append(
            f"  {row.get('source_file')}:{row.get('line')} "
            f"{row.get('evidence_role')} via {row.get('extractor_rule')}"
        )
        lines.append(f"  {row.get('snippet')}")
        writability_line = format_writability_line(row, "  ")
        if writability_line:
            lines.append(writability_line)
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Query a KB Intelligence SQLite index.")
    parser.add_argument("--index-path", required=True, type=Path)
    parser.add_argument(
        "--query",
        required=True,
        choices=[
            "object-info",
            "attribute-info",
            "search-objects",
            "list-by-type",
            "transaction-attributes",
            "transaction-writable-attributes",
            "who-uses",
            "what-uses",
            "show-evidence",
            "impact-basic",
            "functional-trace-basic",
            "index-metadata",
            "css-classes",
            "css-class-usage",
        ],
    )
    parser.add_argument("--object-type")
    parser.add_argument("--object-name")
    parser.add_argument("--model", help="Model filter for css-classes: legacy-theme | design-system.")
    parser.add_argument("--origin", help="Origin filter for css-classes: kb-authored | packaged-module.")
    parser.add_argument(
        "--include-imported",
        action="store_true",
        help="css-classes: includes PackagedModule classes (imported libs) in the view without a name lookup.",
    )
    generated_group = parser.add_mutually_exclusive_group()
    generated_group.add_argument(
        "--generated",
        action="store_true",
        help="search-objects/list-by-type: only Pattern-generated objects (is_generated_object=1).",
    )
    generated_group.add_argument(
        "--authored",
        action="store_true",
        help="search-objects/list-by-type: only authored objects (is_generated_object=0).",
    )
    parser.add_argument(
        "--instance-key",
        help="search-objects: filters by the WorkWithForWeb instance (plain name or full key <GUID>-<name>).",
    )
    parser.add_argument("--relation-id", type=int)
    parser.add_argument("--source-type")
    parser.add_argument("--source-name")
    parser.add_argument("--target-type")
    parser.add_argument("--target-name")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument(
        "--kb-workspace-root",
        type=Path,
        help="Root of the KB workspace folder; resolves scripts/gx-object-type-catalog.override.json.",
    )
    parser.add_argument(
        "--catalog-override-path",
        type=Path,
        help="Explicit path of the catalog override (takes precedence over detection from kb-workspace-root).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.instance_key is not None and args.query != "search-objects":
        raise SystemExit("--instance-key is only valid with search-objects.")

    if args.query in SEMANTIC_QUERIES and args.object_type:
        try:
            catalog_types = load_catalog_types_by_name(
                args.index_path,
                kb_workspace_root=args.kb_workspace_root,
                catalog_override_path=args.catalog_override_path,
            )
        except CatalogOverrideDiagnosticError as exc:
            blocked_override = build_catalog_override_blocked_result(exc)
            if args.format == "text":
                print(format_catalog_override_blocked_text(blocked_override))
            else:
                print(json.dumps(blocked_override, indent=2, ensure_ascii=False))
            return EXIT_CATALOG_OVERRIDE_BLOCKED
        allowed, entry = semantic_query_allowed(args.object_type, catalog_types)
        if not allowed:
            blocked = build_semantic_blocked_result(
                args.query,
                args.object_type,
                args.object_name or "",
                entry,
            )
            if args.format == "text":
                print(format_semantic_blocked_text(blocked))
            else:
                print(json.dumps(blocked, indent=2, ensure_ascii=False))
            return EXIT_QUERY_NOT_SEMANTIC_FOR_TYPE

    if not args.index_path.exists():
        raise SystemExit(f"IndexPath not found: {args.index_path}")

    conn = sqlite3.connect(args.index_path)
    try:
        validate_schema_version(conn)
        if args.query == "index-metadata":
            result = index_metadata(conn)
        elif args.query == "object-info":
            if not args.object_type or not args.object_name:
                raise SystemExit("object-info requires --object-type and --object-name.")
            result = object_info(conn, args.object_type, args.object_name)
        elif args.query == "attribute-info":
            if not args.object_name:
                raise SystemExit("attribute-info requires --object-name.")
            result = attribute_info(conn, args.object_name)
        elif args.query == "search-objects":
            if not args.object_name and not args.instance_key:
                raise SystemExit("search-objects requires --object-name or --instance-key.")
            instance_filter = classify_instance_filter(args.instance_key) if args.instance_key else None
            result = search_objects(conn, args.object_name, args.object_type, args.limit, generated_filter_from_args(args), instance_filter)
        elif args.query == "list-by-type":
            if not args.object_type:
                raise SystemExit("list-by-type requires --object-type.")
            result = list_by_type(conn, args.object_type, args.limit, generated_filter_from_args(args))
        elif args.query == "transaction-attributes":
            if not args.object_name:
                raise SystemExit("transaction-attributes requires --object-name.")
            result = transaction_attributes(conn, args.object_name)
        elif args.query == "transaction-writable-attributes":
            if not args.object_name:
                raise SystemExit("transaction-writable-attributes requires --object-name.")
            result = transaction_writable_attributes(conn, args.object_name)
        elif args.query == "who-uses":
            if not args.object_type or not args.object_name:
                raise SystemExit("who-uses requires --object-type and --object-name.")
            result = who_uses(conn, args.object_type, args.object_name, args.limit)
        elif args.query == "what-uses":
            if not args.object_type or not args.object_name:
                raise SystemExit("what-uses requires --object-type and --object-name.")
            result = what_uses(conn, args.object_type, args.object_name, args.limit)
        elif args.query == "impact-basic":
            if not args.object_type or not args.object_name:
                raise SystemExit("impact-basic requires --object-type and --object-name.")
            result = impact_basic(conn, args.object_type, args.object_name, args.limit)
        elif args.query == "functional-trace-basic":
            if not args.object_type or not args.object_name:
                raise SystemExit("functional-trace-basic requires --object-type and --object-name.")
            result = functional_trace_basic(conn, args.object_type, args.object_name, args.limit)
        elif args.query == "css-classes":
            result = css_classes(
                conn,
                args.object_name,
                args.model,
                args.origin,
                args.include_imported,
                args.limit,
            )
        elif args.query == "css-class-usage":
            result = css_class_usage(conn, args.object_name, args.limit)
        else:
            result = show_evidence(
                conn,
                args.relation_id,
                args.source_type,
                args.source_name,
                args.target_type,
                args.target_name,
                args.limit,
            )
        if args.query in REVERSE_RELATION_QUERIES:
            result["coverage"] = reverse_relation_coverage(conn, args.object_type)
    finally:
        conn.close()

    if args.format == "text":
        print(format_text(result))
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
