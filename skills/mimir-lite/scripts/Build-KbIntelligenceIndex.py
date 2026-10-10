#!/usr/bin/env python3
"""
Build a minimal GeneXus KB intelligence SQLite index.

Current scope:
- object inventory for every immediate SourceRoot type folder with XML files
- object identity via guid extracted from XML
- Source relations among Procedure, WebPanel, DataProvider, Transaction, API and DataSelector
  (including static calls resolved from the local inventory and legacy call/udp forms)
- WorkWith and WorkWithForWeb action gxobject links to Procedure and WebPanel
- WorkWith and WorkWithForWeb action parameters with Procedure .Link() references
- WorkWith and WorkWithForWeb condition expressions to Procedure
- WorkWith and WorkWithForWeb condition attributes to Procedure
- WorkWith and WorkWithForWeb explicit link tags to WebPanel
- WorkWith and WorkWithForWeb explicit prompt attributes to WebPanel
- WorkWith and WorkWithForWeb explicit transaction binding
- WorkWithForWeb pattern instance attribute references (grids, orders, views, fixed data,
  description and filter attributes, and the attribute names of filter <condition value="...">
  expressions) to Attribute; <variable> elements are not read
- attribute reads in code Parts selected by Part type (Procedure Source, Rules and Events of
  Procedure, WebPanel and Transaction, DataProvider Source) to Attribute, skipping comments,
  literals, variables, members, called objects, for each heads, Domain enumeration members,
  Event headers, keywords, DataProvider group headers and SDT-output item names
- Source WebComponent Create calls to WebPanel
- literal ATTCUSTOMTYPE CustomType values
- explicit Source for each table references in Procedure and WebPanel
- qualified Source for each table-prefix references in Procedure and WebPanel
- Source Business Component Load calls with receiver resolved by variable ATTCUSTOMTYPE
- Source Business Component Save calls with receiver resolved by variable ATTCUSTOMTYPE
- Source Business Component Delete calls with receiver resolved by variable ATTCUSTOMTYPE
- Source Business Component Check calls with receiver resolved by variable ATTCUSTOMTYPE
- Source simple Business Component Insert and Update calls with receiver resolved by variable ATTCUSTOMTYPE
- Source ExternalObject method calls with receiver resolved by variable ATTCUSTOMTYPE
- Procedure .Link() references in effective Source and Attribute Formula
- Attribute Formula property references to Procedure, WebPanel and DataProvider when resolvable in the local inventory
- idBasedOn Domain relations (based_on_domain) from Attribute and other scoped object types, with module suffix resolution via fullyQualifiedName
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import sqlite3
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Iterable

# Increment when the indexer's coverage or rules change materially (not on an inert refactor).
EXTRACTOR_SIGNATURE_VERSION = "15"

# Sources of the generalized idBasedOn -> Domain extractor (relation_scope + Attribute; outside: Panel/Stencil/PackagedModule).
IDBASEDON_DOMAIN_SOURCE_TYPES = (
    "Procedure",
    "WebPanel",
    "DataProvider",
    "Transaction",
    "API",
    "DataSelector",
    "Domain",
    "SDT",
    "WorkWith",
    "WorkWithForWeb",
    "Attribute",
)


def portable_source_root(source_root: Path, index_dir: Path) -> str:
    """Value stored as metadata.source_root: relative to the index folder, '/' separators.

    A relative value lets the index move together with its corpus (same relative layout),
    including to another OS. When no relative path exists (Windows: another drive), the
    absolute path is stored instead; readers accept both forms.
    """
    try:
        relative = os.path.relpath(source_root, index_dir)
    except ValueError:
        return str(source_root)
    return Path(relative).as_posix()


def compute_extractor_signature_hash() -> str:
    script_path = Path(__file__).resolve()
    return hashlib.sha256(script_path.read_bytes()).hexdigest()


SOURCE_RE = re.compile(r"<Source(?:\s[^>]*)?>(?P<body>.*?)</Source>", re.IGNORECASE | re.DOTALL)
CDATA_RE = re.compile(r"^\s*<!\[CDATA\[(?P<body>.*)\]\]>\s*$", re.DOTALL)
LAST_UPDATE_RE = re.compile(r'\blastUpdate="([^"]+)"')
GUID_RE = re.compile(r'\bguid="([^"]+)"')
PROCEDURE_DOT_CALL_RE = re.compile(r"\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Call\s*\(", re.IGNORECASE)
PROCEDURE_CALL_COMMAND_RE = re.compile(r"(?<![&.\w])call\s*\(\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?!\s*:)", re.IGNORECASE)
PROCEDURE_UDP_FUNC_RE = re.compile(r"(?<![&.\w])udp\s*\(\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?!\s*:)", re.IGNORECASE)
PROCEDURE_DOT_UDP_RE = re.compile(r"(?<![&.])\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*udp\s*\(", re.IGNORECASE)
PROCEDURE_DOT_LINK_RE = re.compile(r"(?<![&.])\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Link\s*\(", re.IGNORECASE)
WEBPANEL_DOT_LINK_RE = re.compile(r"\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Link\s*\(", re.IGNORECASE)
WEBPANEL_DOT_CREATE_RE = re.compile(r"(?<![&.])\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Create\s*\(", re.IGNORECASE)
FOR_EACH_EXPLICIT_TABLE_RE = re.compile(
    r"\bfor\s+each\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b(?!\s*\.)",
    re.IGNORECASE,
)
FOR_EACH_QUALIFIED_TABLE_RE = re.compile(
    r"\bfor\s+each\s+(?P<prefix>[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?P<member>[A-Za-z_][A-Za-z0-9_]*)\b",
    re.IGNORECASE,
)
BC_LOAD_RE = re.compile(r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Load\s*\(", re.IGNORECASE)
BC_SAVE_RE = re.compile(r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Save\s*\(", re.IGNORECASE)
BC_DELETE_RE = re.compile(r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Delete\s*\(", re.IGNORECASE)
BC_CHECK_RE = re.compile(r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Check\s*\(", re.IGNORECASE)
BC_SIMPLE_INSERT_UPDATE_RE = re.compile(
    r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?P<method>Insert|Update)\s*\(",
    re.IGNORECASE,
)
EXTERNAL_OBJECT_METHOD_RE = re.compile(
    r"(?P<receiver>&[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?P<method>[A-Za-z_][A-Za-z0-9_]*)\s*\(",
    re.IGNORECASE,
)
INDEXED_SOURCE_TYPES = ("Procedure", "WebPanel", "DataProvider", "Transaction", "API", "DataSelector")
FOR_EACH_SOURCE_TYPES = ("Procedure", "WebPanel")
BC_LOAD_SOURCE_TYPES = ("Procedure", "WebPanel", "DataProvider")
ACTION_RE = re.compile(r"<action\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
ACTION_BLOCK_RE = re.compile(r"<action\b(?P<attrs>[^>]*)>(?P<body>.*?)</action>", re.IGNORECASE | re.DOTALL)
CONDITION_RE = re.compile(r"<condition\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
TAG_RE = re.compile(r"<(?P<tag>[A-Za-z][A-Za-z0-9]*)\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
PARAMETER_RE = re.compile(r"<parameter\b(?P<attrs>[^>]*)/?>", re.IGNORECASE | re.DOTALL)
VARIABLE_RE = re.compile(r"<Variable\b(?P<attrs>[^>]*)>(?P<body>.*?)</Variable>", re.IGNORECASE | re.DOTALL)
ATTR_RE = re.compile(r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)="(?P<value>[^"]*)"')
GXOBJECT_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}-(?P<name>.+)$")
ATTCUSTOMTYPE_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>ATTCUSTOMTYPE</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
ATTCOLLECTION_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>AttCollection</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
IDBASEDON_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>idBasedOn</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
FORMULA_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>Formula</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
OBJECT_TYPE_GUID_RE = re.compile(r'<Object\b[^>]*\btype="([^"]+)"')
ATTRIBUTE_ROOT_RE = re.compile(r"^\s*(?:<\?xml[^>]*\?>\s*)?<Attribute\b", re.IGNORECASE)

# CSS class catalog and traceability (layer 1: css_class catalog; layer 2: usage via relations/evidence).
# The SCSS of the design-system model's classes lives in the "Styles" Part of this type GUID, both in
# authored DesignSystem objects and in DesignSystem nested inside PackagedModule (imported libs).
DESIGN_SYSTEM_STYLES_PART_GUID = "c6b14574-4f5f-4e35-aaa7-e322e88a9a10"
CSS_USAGE_SOURCE_TYPES = ("WebPanel", "Panel", "Transaction")
# CSS class identifier accepts hyphen and digit (e.g. Card-Basico) — distinct from the GeneXus identifier.
CSS_SELECTOR_RE = re.compile(r"^\s*\.(?P<name>[A-Za-z][A-Za-z0-9_-]*)\s*\{", re.MULTILINE)
CSS_CLASS_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
PART_RE = re.compile(r"<Part\b[^>]*\btype=\"(?P<type>[^\"]+)\"[^>]*>(?P<body>.*?)</Part>", re.IGNORECASE | re.DOTALL)
NAME_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>Name</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
OBJECT_PARENT_ATTR_RE = re.compile(r"<Object\b[^>]*?\bparent=\"(?P<value>[^\"]*)\"", re.IGNORECASE)
SCSS_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
SCSS_LINE_COMMENT_RE = re.compile(r"//[^\n]*")
DOT_CLASS_ASSIGN_RE = re.compile(r"\.Class\s*=\s*(?P<rhs>\S.*)$", re.IGNORECASE)
CSS_QUOTED_LITERAL_RE = re.compile(r"(?P<q>['\"])(?P<value>.*?)(?P=q)", re.DOTALL)
CSS_PREFIX_CLASS_RE = re.compile(r"\b(?:style|theme)class\s*:\s*(?P<name>[A-Za-z][A-Za-z0-9_-]*)", re.IGNORECASE)
CSS_DYNAMIC_HINT_RE = re.compile(r"&[A-Za-z_]|\bFormat\s*\(", re.IGNORECASE)
# Real theme-class vectors in GeneXus layout: class (control), cellClass (cell),
# rowClass (row), formClass (form). gxObjClass does NOT enter (numeric value, not a CSS class).
LAYOUT_CLASS_ATTR_RE = re.compile(
    r"\b(?:class|cellClass|rowClass|formClass)\s*=\s*\"(?P<value>[^\"]*)\"",
    re.IGNORECASE,
)

from GeneXusObjectTypeCatalogCore import (  # noqa: E402
    CatalogOverrideDiagnosticError,
    build_type_guid_index,
    load_gx_object_type_catalog,
    resolve_effective_object_type_catalog,
)
from GeneXusTransactionWritabilityCore import (  # noqa: E402
    WRITABILITY_RULE_VERSION,
    build_corpus_writability,
    get_transaction_type_guid,
)


def build_catalog_override_blocked_result(exc: CatalogOverrideDiagnosticError) -> dict[str, object]:
    diagnostic = dict(exc.diagnostic)
    return {
        "status": diagnostic.get("status", "OVERRIDE_RESOLUTION_BLOCKED"),
        "blocked": True,
        "reason": diagnostic.get("reason"),
        "diagnosticReason": diagnostic.get("diagnosticReason"),
        "fieldPath": diagnostic.get("fieldPath"),
        "overridePath": diagnostic.get("overridePath"),
        "message": diagnostic.get("message", str(exc)),
        "catalogOverrideDiagnostic": diagnostic,
    }


def activate_object_type_catalog(
    source_root: Path,
    kb_workspace_root: Path | None = None,
    catalog_override_path: Path | None = None,
    base_catalog_path: Path | None = None,
) -> Path | None:
    """Set module-level catalog maps used during index build (base + override)."""
    global GX_OBJECT_TYPE_CATALOG, GX_TYPE_CATALOG_BY_NAME, GX_TYPE_BY_GUID
    merged, override_path = resolve_effective_object_type_catalog(
        source_root,
        kb_workspace_root=kb_workspace_root,
        catalog_override_path=catalog_override_path,
        base_catalog_path=base_catalog_path,
    )
    GX_OBJECT_TYPE_CATALOG = merged
    GX_TYPE_CATALOG_BY_NAME = merged["types"]
    GX_TYPE_BY_GUID = build_type_guid_index(GX_TYPE_CATALOG_BY_NAME)
    return override_path


GX_OBJECT_TYPE_CATALOG = load_gx_object_type_catalog()
GX_TYPE_CATALOG_BY_NAME: dict[str, dict[str, object]] = GX_OBJECT_TYPE_CATALOG["types"]
GX_TYPE_BY_GUID: dict[str, str] = build_type_guid_index(GX_TYPE_CATALOG_BY_NAME)


def load_legacy_export_registry() -> dict:
    """Loads gx-legacy-export-element-registry.json (GX9 legacy export governance layer).

    Dynamic: reads the registry next to the script. Missing -> empty registry (unchanged behavior).
    """
    registry_path = Path(__file__).resolve().parent / "gx-legacy-export-element-registry.json"
    if not registry_path.exists():
        return {"elements": {}}
    return json.loads(registry_path.read_text(encoding="utf-8"))


def build_legacy_orphan_folders(registry: dict) -> set[str]:
    """Set of materializedFolderName values for legacy elements of class 'orphan' (e.g. Report)."""
    folders: set[str] = set()
    elements = registry.get("elements", {})
    if not isinstance(elements, dict):
        return folders
    for element in elements.values():
        if isinstance(element, dict) and element.get("class") == "orphan":
            folder = element.get("materializedFolderName")
            if folder:
                folders.add(str(folder))
    return folders


def build_legacy_orphan_folder_to_token(registry: dict) -> dict[str, str]:
    """Map materializedFolderName -> typeToken (lower) for legacy elements of class 'orphan'."""
    mapping: dict[str, str] = {}
    elements = registry.get("elements", {})
    if not isinstance(elements, dict):
        return mapping
    for element in elements.values():
        if isinstance(element, dict) and element.get("class") == "orphan":
            folder = element.get("materializedFolderName")
            token = element.get("typeToken")
            if folder and token:
                mapping[str(folder)] = str(token).lower()
    return mapping


GX_LEGACY_EXPORT_REGISTRY: dict = load_legacy_export_registry()
LEGACY_ORPHAN_FOLDERS: set[str] = build_legacy_orphan_folders(GX_LEGACY_EXPORT_REGISTRY)
LEGACY_ORPHAN_FOLDER_TO_TOKEN: dict[str, str] = build_legacy_orphan_folder_to_token(GX_LEGACY_EXPORT_REGISTRY)
LEVEL_RE = re.compile(r"<Level\b(?P<attrs>[^>]*)>(?P<body>.*?)</Level>", re.IGNORECASE | re.DOTALL)
LEVEL_ATTRIBUTE_RE = re.compile(
    r"<Attribute\b(?P<attrs>[^>]*)>(?P<name>.*?)</Attribute>",
    re.IGNORECASE | re.DOTALL,
)
KEY_RE = re.compile(r"<Key\b[^>]*>(?P<body>.*?)</Key>", re.IGNORECASE | re.DOTALL)
KEY_ITEM_RE = re.compile(
    r"<Item\b(?P<attrs>[^>]*)>(?P<name>.*?)</Item>",
    re.IGNORECASE | re.DOTALL,
)
INDEX_MEMBER_RE = re.compile(
    r"<Member\b(?P<attrs>[^>]*)>(?P<name>.*?)</Member>",
    re.IGNORECASE | re.DOTALL,
)
SDT_ITEM_RE = re.compile(r"<Item\b(?P<attrs>[^>]*)>(?P<body>.*?)</Item>", re.IGNORECASE | re.DOTALL)
WORKWITH_TRANSACTION_RE = re.compile(r"<transaction\b[^>]*\btransaction=\"(?P<value>[^\"]+)\"", re.IGNORECASE)
WORKWITH_WEBPANEL_LINK_RE = re.compile(r"<link\b[^>]*\bwebpanel=\"(?P<name>[^\"]+)\"", re.IGNORECASE)
WORKWITH_PROMPT_RE = re.compile(r"\bprompt=\"(?P<value>[^\"]+)\"", re.IGNORECASE)
# WorkWithForWeb pattern instance: <Data Pattern="<WorkWithForWeb pattern guid>"> holds the CDATA <instance>.
WORKWITH_FOR_WEB_INSTANCE_DATA_RE = re.compile(
    r"<Data\b[^>]*\bPattern=\"78cecefe-be7d-4980-86ce-8d6e91fba04b\"[^>]*>(?P<body>.*?)</Data>",
    re.IGNORECASE | re.DOTALL,
)
# <variable> elements (self-closing or with nested code) are masked before attribute matching.
WORKWITH_VARIABLE_ELEMENT_RE = re.compile(r"<variable\b[^>]*?(?:/>|>.*?</variable>)", re.IGNORECASE | re.DOTALL)
# <attribute attribute="<typeGuid>-<Name>">, <descriptionAttribute attribute="<typeGuid>-<Name>">
# and <filterAttribute name="<Name>">; condition expressions are never matched.
WORKWITH_ATTRIBUTE_REFERENCE_RE = re.compile(
    r"<(?P<tag>attribute|descriptionAttribute)\b[^>]*?\battribute=\"(?P<value>[^\"]+)\""
    r"|<(?P<filter_tag>filterAttribute)\b[^>]*?\bname=\"(?P<name>[^\"]+)\"",
    re.IGNORECASE,
)
WORKWITH_ATTRIBUTE_REFERENCE_ROLES = {
    "attribute": "WorkWithForWeb attribute",
    "descriptionattribute": "WorkWithForWeb description attribute",
    "filterattribute": "WorkWithForWeb filter attribute",
}
WORKWITH_CONDITION_ROLE = "WorkWithForWeb condition"
# <filter> elements (selection and Grid tab): only the <condition> elements inside one are read.
WORKWITH_FOR_WEB_FILTER_RE = re.compile(
    r"<filter\b[^>]*?(?:/>|>(?P<body>.*?)</filter>)",
    re.IGNORECASE | re.DOTALL,
)
# <condition value="..."> inside a filter; quoted values may hold a raw '>'.
WORKWITH_FOR_WEB_CONDITION_RE = re.compile(
    r"<condition\b(?P<attrs>(?:[^>\"']|\"[^\"]*\"|'[^']*')*)/?>",
    re.IGNORECASE,
)
# Condition expression tokens, tried in order: // comment (to the end of its line), string
# literals, legacy dotted operators (.and. .or. .not.), &variables, numbers, names, a member dot,
# any other character.
WORKWITH_CONDITION_TOKEN_RE = re.compile(
    r"(?P<comment>//[^\n]*)"
    r"|(?P<literal>'[^']*(?:'|$)|\"[^\"]*(?:\"|$))"
    r"|(?P<operator>\.(?:and|or|not)\.)"
    r"|(?P<variable>&[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<number>\d[A-Za-z0-9_]*(?:\.\d+)?)"
    r"|(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<dot>\.)"
    r"|(?P<other>\S)",
    re.IGNORECASE,
)
# A name followed by '(' or by an object call method ('.udp(', '.call(', '.link(', '.submit(')
# is a called object, not an attribute; an attribute method such as '.IsEmpty(' keeps the name.
WORKWITH_CONDITION_CALL_FOLLOW_RE = re.compile(r"\s*(?:\(|\.\s*(?:udp|call|link|submit)\s*\()", re.IGNORECASE)
# The first argument of the legacy udp(Name, ...) and call(Name, ...) forms names the object.
WORKWITH_CONDITION_CALL_FUNCTIONS = frozenset({"udp", "call"})
WORKWITH_CONDITION_KEYWORDS = frozenset({"and", "or", "not", "like", "when", "null", "true", "false", "in"})

# Code Parts read for attribute uses (code_references_attribute), selected by Part type GUID, and
# the Part name each evidence role starts with ("<Part> read" or "<Part> write"). WebForm, Layout
# and Conditions Parts, and a bare <Source> outside any <Part>, are not read by this extractor
# (the other Source extractors keep reading every <Source>).
PROCEDURE_SOURCE_PART_GUID = "528d1c06-a9c2-420d-bd35-21dca83f12ff"
RULES_PART_GUID = "9b0a32a3-de6d-4be1-a4dd-1b85d3741534"
EVENTS_PART_GUID = "c44bd5ff-f918-415b-98e6-aca44fed84fa"
DATA_PROVIDER_SOURCE_PART_GUID = "1d8aeb5a-6e98-45a7-92d2-d8de7384e432"
CODE_ATTRIBUTE_PART_NAMES: dict[str, dict[str, str]] = {
    "Procedure": {
        PROCEDURE_SOURCE_PART_GUID: "Procedure Source",
        RULES_PART_GUID: "Rules",
        EVENTS_PART_GUID: "Events",
    },
    "WebPanel": {RULES_PART_GUID: "Rules", EVENTS_PART_GUID: "Events"},
    "Transaction": {RULES_PART_GUID: "Rules", EVENTS_PART_GUID: "Events"},
    "DataProvider": {DATA_PROVIDER_SOURCE_PART_GUID: "DataProvider Source", RULES_PART_GUID: "Rules"},
}
# A <Part> element, self-closing or with a body (PART_RE would run a self-closing Part into the next one).
CODE_PART_RE = re.compile(r"<Part\b(?P<attrs>[^>]*?)(?:/>|>(?P<body>.*?)</Part>)", re.IGNORECASE | re.DOTALL)
# Code tokens, tried in order: // and /* */ comments, single-line string literals, legacy dotted
# operators, &variables, numbers, names, a member dot, any other character.
CODE_TOKEN_RE = re.compile(
    r"(?P<comment>//[^\n]*|/\*.*?(?:\*/|\Z))"
    r"|(?P<literal>'[^'\n]*'?|\"[^\"\n]*\"?)"
    r"|(?P<operator>\.(?:and|or|not)\.)"
    r"|(?P<variable>&[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<number>\d[A-Za-z0-9_]*(?:\.\d+)?)"
    r"|(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<dot>\.)"
    r"|(?P<other>\S)",
    re.IGNORECASE | re.DOTALL,
)
# A name followed, on its own line, by '(' or by an object call method ('.udp(', '.call(',
# '.link(', '.submit(') is called, not used as an attribute. Never crosses a line break: a '('
# opening the next line starts another expression.
CODE_CALL_FOLLOW_RE = re.compile(r"[ \t]*(?:\(|\.[ \t]*(?:udp|call|link|submit)[ \t]*\()", re.IGNORECASE)
# Commands that, alone on their line at a statement start, are not attribute uses (an attribute
# may carry the same name, so they are not keywords).
CODE_LINE_COMMANDS = frozenset({"load", "refresh"})
# GeneXus keywords never read as attribute names, even when an attribute has that name.
CODE_KEYWORDS = WORKWITH_CONDITION_KEYWORDS | frozenset(
    {
        "by", "call", "case", "commit", "default", "defined", "do", "duplicate", "each", "else",
        "elseif", "endcase", "enddo", "endevent", "endfor", "endif", "endnew", "endsub", "error",
        "event", "exit", "for", "if", "inout", "input", "msg", "new", "noaccept", "none", "order",
        "otherwise", "out", "parm", "return", "rollback", "sub", "to", "udp", "unique", "using",
        "where", "while",
    }
)
# A token before a line break that carries the expression on to the next line.
CODE_CONTINUATION_OTHERS = frozenset({"+", "-", "*", "/", ",", "(", "=", "<", ">", "["})
CODE_CONTINUATION_NAMES = frozenset({"and", "or", "not", "like"})


@dataclass(frozen=True)
class SourceBlock:
    text: str
    start_line: int


@dataclass(frozen=True)
class ObjectInfo:
    object_type: str
    name: str
    guid: str | None
    path: Path
    rel_path: str
    last_update: str | None
    file_hash: str
    is_generated_object: int
    pattern_object_id: str | None
    instance_key: str | None


@dataclass(frozen=True)
class InventorySemanticIssue:
    issue_kind: str
    expected_type: str
    actual_type: str
    file_path: str


@dataclass(frozen=True)
class InventoryScanSummary:
    snapshot_objects_by_directory: dict[str, int]
    folder_type_mismatches: list[InventorySemanticIssue]
    unknown_type_folders: list[str]
    legacy_orphan_directories_skipped: list[dict[str, object]]


@dataclass(frozen=True)
class Evidence:
    source_type: str
    source_name: str
    target_type: str
    target_name: str
    relation_kind: str
    source_file: str
    line: int
    column: int
    snippet: str
    evidence_role: str
    extractor_rule: str
    confidence: str


@dataclass(frozen=True)
class CssClass:
    class_name: str
    model: str  # legacy-theme | design-system
    origin: str  # kb-authored | packaged-module
    defining_object_type: str
    defining_object_name: str
    defining_file: str
    parent_class: str | None
    extractor_rule: str


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="replace")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


# Pattern-generated object markers (WorkWith For Web): extracted ONLY from the
# object-level <Properties> block (direct child of the root <Object>), NEVER from an <Object>
# nested in <Part>/<ExportFile> (e.g. a PackagedModule that packages an imported lib and materializes
# its internal objects, each with its own IsGeneratedObject). See converged design.
OBJECT_MARKER_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>(?P<name>.*?)</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
PROPERTIES_BLOCK_RE = re.compile(r"<Properties\b[^>]*>(?P<body>.*?)</Properties>", re.IGNORECASE | re.DOTALL)
XML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
XML_CDATA_RE = re.compile(r"<!\[CDATA\[.*?\]\]>", re.DOTALL)
ROOT_FQFN_RE = re.compile(
    r"<(?:Object|Attribute)\b[^>]*\bfullyQualifiedName=\"(?P<fqfn>[^\"]*)\"",
    re.IGNORECASE | re.DOTALL,
)


def mask_xml_cdata_and_comments(text: str) -> str:
    """Masks CDATA and comments while preserving length and line breaks.

    Offsets in the masked text stay valid against the raw XML (line/snippet of the raw text).
    Distinct from the strip in object_level_property_dict_via_regex, which erases content.

    A single left-to-right pass with mutually exclusive state: on finding ``<![CDATA[``
    it masks up to ``]]>`` (ignoring ``<!--`` in between); on finding ``<!--`` it masks
    up to ``-->`` (ignoring ``<![CDATA[`` in between). An unclosed block is not
    masked (same contract as the old regexes, which required the closer).
    """
    n = len(text)
    out = list(text)
    i = 0
    while i < n:
        if text.startswith("<![CDATA[", i):
            closer = text.find("]]>", i + 9)
            if closer < 0:
                i += 1
                continue
            end = closer + 3
            for j in range(i, end):
                if out[j] != "\n":
                    out[j] = "X"
            i = end
            continue
        if text.startswith("<!--", i):
            closer = text.find("-->", i + 4)
            if closer < 0:
                i += 1
                continue
            end = closer + 3
            for j in range(i, end):
                if out[j] != "\n":
                    out[j] = "X"
            i = end
            continue
        i += 1
    return "".join(out)


def extract_root_fully_qualified_name(text: str) -> str | None:
    match = ROOT_FQFN_RE.search(text)
    if not match:
        return None
    value = match.group("fqfn").strip()
    return value or None


def collect_fully_qualified_names(
    objects_by_type: dict[str, dict[str, ObjectInfo]],
) -> dict[tuple[str, str], str | None]:
    """Map (type.lower(), path.stem.lower()) -> fqfn of the root element (or None)."""
    result: dict[tuple[str, str], str | None] = {}
    for object_type, by_name in objects_by_type.items():
        type_key = object_type.lower()
        for name, info in by_name.items():
            result[(type_key, name.lower())] = extract_root_fully_qualified_name(read_text(info.path))
    return result


def markers_from_property_dict(props: dict[str, str]) -> tuple[int, str | None, str | None]:
    is_generated = 1 if props.get("IsGeneratedObject", "").strip().lower() == "true" else 0
    pattern_object_id = props.get("PatternObjectId")
    pattern_object_id = pattern_object_id.strip() if pattern_object_id else None
    instance_key = props.get("InstanceKey")
    instance_key = instance_key.strip() if instance_key else None
    return is_generated, pattern_object_id, instance_key


def object_level_property_dict_via_parse(text: str) -> dict[str, str]:
    """<Property> children of the <Properties> that is a DIRECT child of the root <Object> (ignores nested ones)."""
    root = ElementTree.fromstring(text.encode("utf-8"))
    props: dict[str, str] = {}
    properties_el = root.find("Properties")
    if properties_el is not None:
        for prop in properties_el.findall("Property"):
            name_el = prop.find("Name")
            value_el = prop.find("Value")
            if name_el is not None and name_el.text:
                value = value_el.text if (value_el is not None and value_el.text is not None) else ""
                props[name_el.text.strip()] = value
    return props


def object_level_property_dict_via_regex(text: str) -> dict[str, str]:
    """Best-effort fallback for malformed XML (the primary parser covers 100% of well-formed XML).

    Uses the LAST <Properties> block (the object-level one comes after the <Part>s), ignoring
    comments/CDATA. Documented limitation: a pathologically malformed shape may diverge.
    """
    stripped = XML_CDATA_RE.sub("", XML_COMMENT_RE.sub("", text))
    blocks = PROPERTIES_BLOCK_RE.findall(stripped)
    props: dict[str, str] = {}
    if blocks:
        for match in OBJECT_MARKER_PROPERTY_RE.finditer(blocks[-1]):
            props[html.unescape(match.group("name")).strip()] = html.unescape(match.group("value"))
    return props


def extract_object_level_markers(text: str) -> tuple[int, str | None, str | None]:
    """(is_generated_object, pattern_object_id, instance_key) from the ROOT OBJECT's <Properties>.

    Primary: XML parse by bytes (portable across versions; str with an encoding declaration
    breaks on old versions). Fallback: regex on the last block, only for malformed XML.
    """
    try:
        props = object_level_property_dict_via_parse(text)
    except (ElementTree.ParseError, ValueError):
        props = object_level_property_dict_via_regex(text)
    return markers_from_property_dict(props)


def line_number_at(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def resolve_canonical_type(text: str) -> tuple[str | None, str | None]:
    """Return (canonical_type, guid). canonical_type is None when the GUID is unknown."""
    if ATTRIBUTE_ROOT_RE.match(text[:1024]):
        return "Attribute", None
    m = OBJECT_TYPE_GUID_RE.search(text)
    if not m:
        return None, None
    guid = m.group(1)
    return GX_TYPE_BY_GUID.get(guid.lower()), guid


def collect_objects(
    folder: Path,
    source_root: Path,
    unknown_guids: list[tuple[str, str]],
    folder_type_mismatches: list[InventorySemanticIssue],
) -> dict[str, dict[str, ObjectInfo]]:
    objects_by_type: dict[str, dict[str, ObjectInfo]] = {}
    folder_name = folder.name
    for path in sorted(folder.glob("*.xml")):
        text = read_text(path)
        canonical_type, guid = resolve_canonical_type(text)
        if canonical_type is None:
            unknown_guids.append((guid or "(no type attribute)", path.relative_to(source_root).as_posix()))
            continue
        if canonical_type != folder_name:
            folder_type_mismatches.append(
                InventorySemanticIssue(
                    issue_kind="folder_type_mismatch",
                    expected_type=folder_name,
                    actual_type=canonical_type,
                    file_path=path.relative_to(source_root).as_posix(),
                )
            )
        last_update_match = LAST_UPDATE_RE.search(text)
        guid_match = GUID_RE.search(text)
        rel_path = path.relative_to(source_root).as_posix()
        name = path.stem
        if canonical_type not in objects_by_type:
            objects_by_type[canonical_type] = {}
        is_generated_object, pattern_object_id, instance_key = extract_object_level_markers(text)
        objects_by_type[canonical_type][name] = ObjectInfo(
            object_type=canonical_type,
            name=name,
            guid=guid_match.group(1) if guid_match else None,
            path=path,
            rel_path=rel_path,
            last_update=last_update_match.group(1) if last_update_match else None,
            file_hash=sha256_text(text),
            is_generated_object=is_generated_object,
            pattern_object_id=pattern_object_id,
            instance_key=instance_key,
        )
    return objects_by_type


def folder_is_all_legacy_orphan(folder: Path) -> bool:
    """True iff the folder has XML(s) and EVERY XML has Object/@type == the typeToken REGISTERED for this
    orphan folder (materializedFolderName -> typeToken in the registry).

    Content-aware skip GOVERNED BY THE REGISTRY: the 'Report' folder is only skipped if EVERY XML is
    exactly the registered token (gxlegacy/Report). Modern content (real GUID) OR a gxlegacy token
    that is wrong/unregistered for the folder (e.g. gxlegacy/Foo in a Report folder) is NOT skipped — it follows the
    normal path, which flags it (folder_type_mismatch / unknown_guids). Avoids silently masking a
    mis-named directory or an orphan with a divergent token.
    """
    expected_token = LEGACY_ORPHAN_FOLDER_TO_TOKEN.get(folder.name)
    if expected_token is None:
        return False
    xmls = sorted(folder.glob("*.xml"))
    if not xmls:
        return False
    for path in xmls:
        text = read_text(path)
        match = OBJECT_TYPE_GUID_RE.search(text)
        if match is None or match.group(1).lower() != expected_token:
            return False
    return True


def collect_all_objects(source_root: Path) -> tuple[dict[str, dict[str, ObjectInfo]], InventoryScanSummary]:
    objects_by_type: dict[str, dict[str, ObjectInfo]] = {}
    unknown_guids: list[tuple[str, str]] = []
    folder_type_mismatches: list[InventorySemanticIssue] = []
    snapshot_objects_by_directory: dict[str, int] = {}
    unknown_type_folders: list[str] = []
    legacy_orphan_directories_skipped: list[dict[str, object]] = []
    for folder in sorted(source_root.iterdir(), key=lambda item: item.name.lower()):
        if not folder.is_dir():
            continue
        xml_count = sum(1 for _ in folder.glob("*.xml"))
        if xml_count == 0:
            continue
        # Folders of orphan legacy elements (gx-legacy-export-element-registry.json registry):
        # recognized as known-legacy and skipped in the SAME pass — they stay out of the snapshot, of
        # unknown_type_folders and of the collection. Avoids the SystemExit raise from unknown_guids (type=gxlegacy/*
        # does not match a GUID) and the BLOCK from directory_inventory_mismatch (a folder outside the snapshot does not diverge).
        # The skip is CONTENT-AWARE (folder_is_all_legacy_orphan): it only skips if EVERY XML is gxlegacy/* orphan;
        # a mis-named folder with modern content is NOT skipped — it follows the normal path, which flags it.
        # The skip stays auditable in legacy_orphan_directories_skipped (do not silence orphan XML that is present).
        if folder.name in LEGACY_ORPHAN_FOLDERS and folder_is_all_legacy_orphan(folder):
            legacy_orphan_directories_skipped.append({"directory": folder.name, "xml_count": xml_count})
            continue
        snapshot_objects_by_directory[folder.name] = xml_count
        if folder.name not in GX_TYPE_CATALOG_BY_NAME:
            unknown_type_folders.append(folder.name)
        folder_objects = collect_objects(folder, source_root, unknown_guids, folder_type_mismatches)
        for type_name, objs in folder_objects.items():
            if type_name not in objects_by_type:
                objects_by_type[type_name] = {}
            objects_by_type[type_name].update(objs)
    if unknown_guids:
        lines = [
            "",
            "ERROR: unknown type GUIDs found in the corpus.",
            "The index cannot be built until every type is identified.",
            "Tell the agent or the corpus administrator to update scripts/gx-object-type-catalog.json",
            "(or scripts/gx-object-type-catalog.override.json in the KB workspace, as a stopgap) and reflect",
            "the new type in 01a-catalog-and-empirical-patterns.md when it becomes an upstream entry.",
            "GUIDs found:",
            "",
        ]
        for guid, rel in sorted(set(unknown_guids)):
            lines.append(f"  GUID: {guid}")
            lines.append(f"  File: {rel}")
            lines.append("")
        raise SystemExit("\n".join(lines))
    return objects_by_type, InventoryScanSummary(
        snapshot_objects_by_directory=snapshot_objects_by_directory,
        folder_type_mismatches=folder_type_mismatches,
        unknown_type_folders=sorted(set(unknown_type_folders)),
        legacy_orphan_directories_skipped=sorted(
            legacy_orphan_directories_skipped, key=lambda item: str(item["directory"])
        ),
    )


def validate_inventory_semantics(
    objects_by_type: dict[str, dict[str, ObjectInfo]],
    scan_summary: InventoryScanSummary,
) -> dict[str, object]:
    indexed_objects_by_type = {key: len(value) for key, value in objects_by_type.items()}
    mismatches: list[dict[str, object]] = []

    for folder_name, snapshot_count in sorted(scan_summary.snapshot_objects_by_directory.items()):
        indexed_count = indexed_objects_by_type.get(folder_name, 0)
        if indexed_count != snapshot_count:
            mismatches.append(
                {
                    "issue_kind": "directory_inventory_mismatch",
                    "directory": folder_name,
                    "snapshot_count": snapshot_count,
                    "indexed_count": indexed_count,
                }
            )

    for issue in scan_summary.folder_type_mismatches:
        mismatches.append(
            {
                "issue_kind": issue.issue_kind,
                "expected_type": issue.expected_type,
                "actual_type": issue.actual_type,
                "file_path": issue.file_path,
            }
        )

    for folder_name in scan_summary.unknown_type_folders:
        mismatches.append(
            {
                "issue_kind": "unknown_type_folder",
                "directory": folder_name,
                "snapshot_count": scan_summary.snapshot_objects_by_directory.get(folder_name, 0),
            }
        )

    indexed_only_types = sorted(
        type_name
        for type_name in indexed_objects_by_type
        if type_name not in scan_summary.snapshot_objects_by_directory
    )
    for type_name in indexed_only_types:
        mismatches.append(
            {
                "issue_kind": "indexed_type_without_snapshot_directory",
                "type": type_name,
                "indexed_count": indexed_objects_by_type[type_name],
            }
        )

    return {
        "status": "OK" if not mismatches else "BLOCK",
        "catalog_version": GX_OBJECT_TYPE_CATALOG["version"],
        "snapshot_objects_by_directory": dict(sorted(scan_summary.snapshot_objects_by_directory.items())),
        "indexed_objects_by_type": dict(sorted(indexed_objects_by_type.items())),
        "legacy_orphan_directories_skipped": scan_summary.legacy_orphan_directories_skipped,
        "mismatch_count": len(mismatches),
        "mismatches": mismatches,
    }


def unwrap_source_body(raw_body: str) -> str:
    body = raw_body
    cdata_match = CDATA_RE.match(body)
    if cdata_match:
        return cdata_match.group("body")
    return html.unescape(body)


def source_blocks(xml_text: str, start: int = 0, end: int | None = None) -> Iterable[SourceBlock]:
    for match in SOURCE_RE.finditer(xml_text, start, len(xml_text) if end is None else end):
        raw_body = match.group("body")
        body_start = match.start("body")
        cdata_prefix = re.match(r"\s*<!\[CDATA\[", raw_body, re.DOTALL)
        if cdata_prefix:
            body_start += cdata_prefix.end()
        body = unwrap_source_body(raw_body)
        if not body.strip():
            continue
        yield SourceBlock(text=body, start_line=line_number_at(xml_text, body_start))


def active_line(line: str) -> str:
    stripped = line.lstrip()
    if stripped.startswith("//"):
        return ""
    return line.split("//", 1)[0]


def add_evidence(
    evidences: list[Evidence],
    *,
    source: ObjectInfo,
    target_type: str,
    target_name: str,
    relation_kind: str,
    line: int,
    column: int,
    snippet: str,
    extractor_rule: str,
    evidence_role: str = "effective Source",
) -> None:
    evidences.append(
        Evidence(
            source_type=source.object_type,
            source_name=source.name,
            target_type=target_type,
            target_name=target_name,
            relation_kind=relation_kind,
            source_file=source.rel_path,
            line=line,
            column=column,
            snippet=compact_snippet(snippet),
            evidence_role=evidence_role,
            extractor_rule=extractor_rule,
            confidence="direct",
        )
    )


def compact_snippet(text: str, limit: int = 220) -> str:
    snippet = " ".join(text.strip().split())
    if len(snippet) <= limit:
        return snippet
    return snippet[: limit - 3].rstrip() + "..."


def case_insensitive_lookup(names: set[str], object_type: str) -> dict[str, str]:
    grouped: dict[str, list[str]] = {}
    for name in names:
        grouped.setdefault(name.lower(), []).append(name)
    collisions = {key: sorted(values) for key, values in grouped.items() if len(values) > 1}
    if collisions:
        details = "; ".join(f"{key}: {', '.join(values)}" for key, values in sorted(collisions.items()))
        raise ValueError(f"Ambiguous {object_type} names differing only by case: {details}")
    return {key: values[0] for key, values in grouped.items()}


def direct_call_pattern(names: set[str]) -> re.Pattern[str] | None:
    if not names:
        return None
    alternatives = "|".join(re.escape(name) for name in sorted(names, key=len, reverse=True))
    return re.compile(rf"(?<![&.])\b(?P<name>{alternatives})\s*\(", re.IGNORECASE)


def append_call_evidences_from_expression(
    evidences: list[Evidence],
    *,
    source: ObjectInfo,
    xml_text: str,
    expression: str,
    expression_start: int,
    evidence_role: str,
    procedure_lookup: dict[str, str],
    webpanel_lookup: dict[str, str],
    data_provider_lookup: dict[str, str],
    data_provider_direct_re: re.Pattern[str] | None,
    procedure_direct_re: re.Pattern[str] | None,
    relation_kind_procedure: str,
    relation_kind_webpanel_link: str,
    relation_kind_webpanel_create: str,
    relation_kind_dataprovider: str,
    extractor_rule_procedure_direct: str,
    extractor_rule_procedure_dot: str,
    extractor_rule_procedure_dot_link: str,
    extractor_rule_webpanel_link: str,
    extractor_rule_procedure_call_command: str | None,
    extractor_rule_webpanel_create: str,
    extractor_rule_dataprovider_direct: str,
    extractor_rule_procedure_udp_func: str | None = None,
    extractor_rule_procedure_dot_udp: str | None = None,
) -> None:
    line_no = line_number_at(xml_text, expression_start)
    for match in PROCEDURE_DOT_CALL_RE.finditer(expression):
        matched_name = match.group("name")
        target_name = procedure_lookup.get(matched_name.lower())
        if target_name:
            add_evidence(
                evidences,
                source=source,
                target_type="Procedure",
                target_name=target_name,
                relation_kind=relation_kind_procedure,
                line=line_no,
                column=match.start("name") + 1,
                snippet=expression,
                extractor_rule=extractor_rule_procedure_dot,
                evidence_role=evidence_role,
            )

    direct_matches = procedure_direct_re.finditer(expression) if procedure_direct_re else ()
    for match in direct_matches:
        matched_name = match.group("name")
        target_name = procedure_lookup.get(matched_name.lower())
        if target_name:
            add_evidence(
                evidences,
                source=source,
                target_type="Procedure",
                target_name=target_name,
                relation_kind=relation_kind_procedure,
                line=line_no,
                column=match.start("name") + 1,
                snippet=expression,
                extractor_rule=extractor_rule_procedure_direct,
                evidence_role=evidence_role,
            )

    if extractor_rule_procedure_call_command:
        for match in PROCEDURE_CALL_COMMAND_RE.finditer(expression):
            matched_name = match.group("name")
            target_name = procedure_lookup.get(matched_name.lower())
            if target_name:
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Procedure",
                    target_name=target_name,
                    relation_kind=relation_kind_procedure,
                    line=line_no,
                    column=match.start("name") + 1,
                    snippet=expression,
                    extractor_rule=extractor_rule_procedure_call_command,
                    evidence_role=evidence_role,
                )

    if extractor_rule_procedure_udp_func:
        for match in PROCEDURE_UDP_FUNC_RE.finditer(expression):
            matched_name = match.group("name")
            target_name = procedure_lookup.get(matched_name.lower())
            if target_name:
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Procedure",
                    target_name=target_name,
                    relation_kind=relation_kind_procedure,
                    line=line_no,
                    column=match.start("name") + 1,
                    snippet=expression,
                    extractor_rule=extractor_rule_procedure_udp_func,
                    evidence_role=evidence_role,
                )

    if extractor_rule_procedure_dot_udp:
        for match in PROCEDURE_DOT_UDP_RE.finditer(expression):
            matched_name = match.group("name")
            target_name = procedure_lookup.get(matched_name.lower())
            if target_name:
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Procedure",
                    target_name=target_name,
                    relation_kind=relation_kind_procedure,
                    line=line_no,
                    column=match.start("name") + 1,
                    snippet=expression,
                    extractor_rule=extractor_rule_procedure_dot_udp,
                    evidence_role=evidence_role,
                )

    for match in PROCEDURE_DOT_LINK_RE.finditer(expression):
        matched_name = match.group("name")
        target_name = procedure_lookup.get(matched_name.lower())
        if target_name:
            add_evidence(
                evidences,
                source=source,
                target_type="Procedure",
                target_name=target_name,
                relation_kind=relation_kind_procedure,
                line=line_no,
                column=match.start("name") + 1,
                snippet=expression,
                extractor_rule=extractor_rule_procedure_dot_link,
                evidence_role=evidence_role,
            )

    for match in WEBPANEL_DOT_LINK_RE.finditer(expression):
        matched_name = match.group("name")
        target_name = webpanel_lookup.get(matched_name.lower())
        if target_name:
            add_evidence(
                evidences,
                source=source,
                target_type="WebPanel",
                target_name=target_name,
                relation_kind=relation_kind_webpanel_link,
                line=line_no,
                column=match.start("name") + 1,
                snippet=expression,
                extractor_rule=extractor_rule_webpanel_link,
                evidence_role=evidence_role,
            )

    for match in WEBPANEL_DOT_CREATE_RE.finditer(expression):
        matched_name = match.group("name")
        target_name = webpanel_lookup.get(matched_name.lower())
        if target_name:
            add_evidence(
                evidences,
                source=source,
                target_type="WebPanel",
                target_name=target_name,
                relation_kind=relation_kind_webpanel_create,
                line=line_no,
                column=match.start("name") + 1,
                snippet=expression,
                extractor_rule=extractor_rule_webpanel_create,
                evidence_role=evidence_role,
            )

    if data_provider_direct_re:
        for match in data_provider_direct_re.finditer(expression):
            matched_name = match.group("name")
            target_name = data_provider_lookup.get(matched_name.lower())
            if target_name:
                add_evidence(
                    evidences,
                    source=source,
                    target_type="DataProvider",
                    target_name=target_name,
                    relation_kind=relation_kind_dataprovider,
                    line=line_no,
                    column=match.start("name") + 1,
                    snippet=expression,
                    extractor_rule=extractor_rule_dataprovider_direct,
                    evidence_role=evidence_role,
                )


def extract_evidence(
    source_root: Path,
    source_objects: Iterable[ObjectInfo],
    procedure_names: set[str],
    webpanel_names: set[str],
    data_provider_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    procedure_lookup = case_insensitive_lookup(procedure_names, "Procedure")
    webpanel_lookup = case_insensitive_lookup(webpanel_names, "WebPanel")
    data_provider_lookup = case_insensitive_lookup(data_provider_names, "DataProvider")
    procedure_direct_re = direct_call_pattern(procedure_names)
    data_provider_direct_re = direct_call_pattern(data_provider_names)

    for source in source_objects:
        xml_text = read_text(source.path)
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in PROCEDURE_DOT_CALL_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_dot_call",
                        )

                direct_matches = procedure_direct_re.finditer(cleaned) if procedure_direct_re else ()
                for match in direct_matches:
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_direct_call",
                        )

                for match in PROCEDURE_CALL_COMMAND_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_call_command",
                        )

                for match in PROCEDURE_UDP_FUNC_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_udp_func",
                        )

                for match in PROCEDURE_DOT_UDP_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_dot_udp",
                        )

                for match in PROCEDURE_DOT_LINK_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = procedure_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="Procedure",
                            target_name=target_name,
                            relation_kind="calls_procedure",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="procedure_dot_link",
                        )

                for match in WEBPANEL_DOT_LINK_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = webpanel_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="WebPanel",
                            target_name=target_name,
                            relation_kind="calls_webpanel",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="webpanel_dot_link",
                        )

                for match in WEBPANEL_DOT_CREATE_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = webpanel_lookup.get(matched_name.lower())
                    if target_name:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="WebPanel",
                            target_name=target_name,
                            relation_kind="creates_webcomponent",
                            line=line_no,
                            column=match.start("name") + 1,
                            snippet=cleaned,
                            extractor_rule="webpanel_dot_create",
                        )

                if data_provider_direct_re:
                    for match in data_provider_direct_re.finditer(cleaned):
                        matched_name = match.group("name")
                        target_name = data_provider_lookup.get(matched_name.lower())
                        if target_name:
                            add_evidence(
                                evidences,
                                source=source,
                                target_type="DataProvider",
                                target_name=target_name,
                                relation_kind="calls_dataprovider",
                                line=line_no,
                                column=match.start("name") + 1,
                                snippet=cleaned,
                                extractor_rule="dataprovider_direct_call",
                            )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_for_each_explicit_table_evidence(
    source_objects: Iterable[ObjectInfo],
    table_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    table_lookup = case_insensitive_lookup(table_names, "Table")

    for source in source_objects:
        xml_text = read_text(source.path)
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in FOR_EACH_EXPLICIT_TABLE_RE.finditer(cleaned):
                    matched_name = match.group("name")
                    target_name = table_lookup.get(matched_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Table",
                        target_name=target_name,
                        relation_kind="navigates_explicit_table",
                        line=line_no,
                        column=match.start("name") + 1,
                        snippet=cleaned,
                        extractor_rule="source_for_each_explicit_table",
                        evidence_role="Source explicit for each table",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_for_each_qualified_table_prefix_evidence(
    source_objects: Iterable[ObjectInfo],
    table_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    table_lookup = case_insensitive_lookup(table_names, "Table")

    for source in source_objects:
        xml_text = read_text(source.path)
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in FOR_EACH_QUALIFIED_TABLE_RE.finditer(cleaned):
                    matched_prefix = match.group("prefix")
                    target_name = table_lookup.get(matched_prefix.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Table",
                        target_name=target_name,
                        relation_kind="navigates_qualified_table_prefix",
                        line=line_no,
                        column=match.start("prefix") + 1,
                        snippet=cleaned,
                        extractor_rule="source_for_each_qualified_table_prefix",
                        evidence_role="Source qualified for each table prefix",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def parse_attributes(raw_attrs: str) -> dict[str, str]:
    return {match.group("name"): html.unescape(match.group("value")) for match in ATTR_RE.finditer(raw_attrs)}


def gxobject_name(value: str) -> str | None:
    match = GXOBJECT_RE.match(value)
    if not match:
        return None
    return match.group("name")


def effective_condition_expression(value: str) -> str:
    return value.split("//", 1)[0]


def bc_variable_targets(xml_text: str, transaction_lookup: dict[str, str]) -> dict[str, str]:
    targets: dict[str, str] = {}
    for match in VARIABLE_RE.finditer(xml_text):
        attrs = parse_attributes(match.group("attrs"))
        variable_name = attrs.get("Name")
        if not variable_name:
            continue
        custom_type_match = ATTCUSTOMTYPE_PROPERTY_RE.search(match.group("body"))
        if not custom_type_match:
            continue
        custom_type = normalize_custom_type(custom_type_match.group("value"))
        if not custom_type.lower().startswith("bc:"):
            continue
        raw_transaction_name = custom_type.split(":", 1)[1].strip()
        target_name = transaction_lookup.get(raw_transaction_name.lower())
        if not target_name:
            continue
        targets[variable_name.lower()] = target_name
    return targets


def simple_bc_variable_targets(xml_text: str, transaction_lookup: dict[str, str]) -> dict[str, str]:
    targets: dict[str, str] = {}
    for match in VARIABLE_RE.finditer(xml_text):
        attrs = parse_attributes(match.group("attrs"))
        variable_name = attrs.get("Name")
        if not variable_name:
            continue
        body = match.group("body")
        collection_match = ATTCOLLECTION_PROPERTY_RE.search(body)
        if collection_match and collection_match.group("value").strip().lower() == "true":
            continue
        custom_type_match = ATTCUSTOMTYPE_PROPERTY_RE.search(body)
        if not custom_type_match:
            continue
        custom_type = normalize_custom_type(custom_type_match.group("value"))
        if not custom_type.lower().startswith("bc:"):
            continue
        raw_transaction_name = custom_type.split(":", 1)[1].strip()
        target_name = transaction_lookup.get(raw_transaction_name.lower())
        if not target_name:
            continue
        targets[variable_name.lower()] = target_name
    return targets


def external_object_variable_targets(xml_text: str, external_object_lookup: dict[str, str]) -> dict[str, str]:
    targets: dict[str, str] = {}
    for match in VARIABLE_RE.finditer(xml_text):
        attrs = parse_attributes(match.group("attrs"))
        variable_name = attrs.get("Name")
        if not variable_name:
            continue
        custom_type_match = ATTCUSTOMTYPE_PROPERTY_RE.search(match.group("body"))
        if not custom_type_match:
            continue
        custom_type = normalize_custom_type(custom_type_match.group("value"))
        if not custom_type.lower().startswith("exo:"):
            continue
        raw_external_object_name = custom_type.split(":", 1)[1].split(",", 1)[0].strip()
        target_name = external_object_lookup.get(raw_external_object_name.lower())
        if not target_name:
            continue
        targets[variable_name.lower()] = target_name
    return targets


def extract_source_bc_load_transaction_evidence(
    source_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = bc_variable_targets(xml_text, transaction_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in BC_LOAD_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Transaction",
                        target_name=target_name,
                        relation_kind="loads_business_component",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule="source_bc_load_transaction",
                        evidence_role="Source BC Load",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_bc_save_transaction_evidence(
    source_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = bc_variable_targets(xml_text, transaction_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in BC_SAVE_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Transaction",
                        target_name=target_name,
                        relation_kind="saves_business_component",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule="source_bc_save_transaction",
                        evidence_role="Source BC Save",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_bc_delete_transaction_evidence(
    source_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = bc_variable_targets(xml_text, transaction_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in BC_DELETE_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Transaction",
                        target_name=target_name,
                        relation_kind="deletes_business_component",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule="source_bc_delete_transaction",
                        evidence_role="Source BC Delete",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_bc_check_transaction_evidence(
    source_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = bc_variable_targets(xml_text, transaction_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in BC_CHECK_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Transaction",
                        target_name=target_name,
                        relation_kind="checks_business_component",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule="source_bc_check_transaction",
                        evidence_role="Source BC Check",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_simple_bc_insert_update_transaction_evidence(
    source_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = simple_bc_variable_targets(xml_text, transaction_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in BC_SIMPLE_INSERT_UPDATE_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    method = match.group("method").lower()
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Transaction",
                        target_name=target_name,
                        relation_kind=f"{method}s_business_component",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule=f"source_simple_bc_{method}_transaction",
                        evidence_role=f"Source Simple BC {method.capitalize()}",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_source_external_object_method_evidence(
    source_objects: Iterable[ObjectInfo],
    external_object_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    external_object_lookup = case_insensitive_lookup(external_object_names, "ExternalObject")

    for source in source_objects:
        xml_text = read_text(source.path)
        variable_targets = external_object_variable_targets(xml_text, external_object_lookup)
        if not variable_targets:
            continue
        for block in source_blocks(xml_text):
            for offset, line in enumerate(block.text.splitlines()):
                cleaned = active_line(line)
                if not cleaned.strip():
                    continue
                line_no = block.start_line + offset

                for match in EXTERNAL_OBJECT_METHOD_RE.finditer(cleaned):
                    receiver_name = match.group("receiver")[1:]
                    target_name = variable_targets.get(receiver_name.lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="ExternalObject",
                        target_name=target_name,
                        relation_kind="calls_external_object_method",
                        line=line_no,
                        column=match.start("receiver") + 1,
                        snippet=cleaned,
                        extractor_rule="source_external_object_method",
                        evidence_role="Source ExternalObject method",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_workwith_action_evidence(
    workwith_objects: Iterable[ObjectInfo],
    procedure_names: set[str],
    webpanel_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    procedure_lookup = case_insensitive_lookup(procedure_names, "Procedure")
    webpanel_lookup = case_insensitive_lookup(webpanel_names, "WebPanel")

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for match in ACTION_RE.finditer(xml_text):
            attrs = parse_attributes(match.group("attrs"))
            raw_gxobject = attrs.get("gxobject")
            if not raw_gxobject:
                continue
            raw_target_name = gxobject_name(raw_gxobject)
            if not raw_target_name:
                continue

            target_type = None
            target_name = procedure_lookup.get(raw_target_name.lower())
            relation_kind = "workwith_action_calls_procedure"
            if target_name:
                target_type = "Procedure"
            else:
                target_name = webpanel_lookup.get(raw_target_name.lower())
                relation_kind = "workwith_action_calls_webpanel"
                if target_name:
                    target_type = "WebPanel"

            if not target_type or not target_name:
                continue

            add_evidence(
                evidences,
                source=source,
                target_type=target_type,
                target_name=target_name,
                relation_kind=relation_kind,
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0),
                extractor_rule="workwith_action_gxobject",
                evidence_role="WorkWith action",
            )

        for action_match in ACTION_BLOCK_RE.finditer(xml_text):
            action_body = action_match.group("body")
            for parameter_match in PARAMETER_RE.finditer(action_body):
                attrs = parse_attributes(parameter_match.group("attrs"))
                expression = attrs.get("name")
                if not expression:
                    continue
                parameter_start = action_match.start("body") + parameter_match.start()
                for link_match in PROCEDURE_DOT_LINK_RE.finditer(expression):
                    target_name = procedure_lookup.get(link_match.group("name").lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Procedure",
                        target_name=target_name,
                        relation_kind="workwith_action_parameter_calls_procedure",
                        line=line_number_at(xml_text, parameter_start),
                        column=link_match.start("name") + 1,
                        snippet=parameter_match.group(0),
                        extractor_rule="workwith_action_parameter_procedure_dot_link",
                        evidence_role="WorkWith action parameter",
                    )

    unique: dict[tuple[str, str, str, str, int, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
        )
        unique[key] = evidence
    return list(unique.values())


def append_workwith_condition_extra_procedure_calls(
    evidences: list[Evidence],
    *,
    source: ObjectInfo,
    expression: str,
    procedure_lookup: dict[str, str],
    relation_kind: str,
    extractor_rule_prefix: str,
    snippet: str,
    line: int,
    evidence_role: str,
) -> None:
    for regex, suffix in (
        (PROCEDURE_DOT_CALL_RE, "dot_call"),
        (PROCEDURE_CALL_COMMAND_RE, "call_command"),
        (PROCEDURE_UDP_FUNC_RE, "udp_func"),
        (PROCEDURE_DOT_UDP_RE, "dot_udp"),
    ):
        for match in regex.finditer(expression):
            target_name = procedure_lookup.get(match.group("name").lower())
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="Procedure",
                target_name=target_name,
                relation_kind=relation_kind,
                line=line,
                column=1,
                snippet=snippet,
                extractor_rule=f"{extractor_rule_prefix}_{suffix}",
                evidence_role=evidence_role,
            )


def extract_workwith_condition_evidence(
    workwith_objects: Iterable[ObjectInfo],
    procedure_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    procedure_lookup = case_insensitive_lookup(procedure_names, "Procedure")
    procedure_direct_re = direct_call_pattern(procedure_names)

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for condition_match in CONDITION_RE.finditer(xml_text):
            attrs = parse_attributes(condition_match.group("attrs"))
            condition_value = attrs.get("value")
            if not condition_value:
                continue

            expression = effective_condition_expression(condition_value)
            direct_matches = procedure_direct_re.finditer(expression) if procedure_direct_re else ()
            for procedure_match in direct_matches:
                target_name = procedure_lookup.get(procedure_match.group("name").lower())
                if not target_name:
                    continue
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Procedure",
                    target_name=target_name,
                    relation_kind="workwith_condition_calls_procedure",
                    line=line_number_at(xml_text, condition_match.start()),
                    column=1,
                    snippet=condition_match.group(0),
                    extractor_rule="workwith_condition_procedure",
                    evidence_role="WorkWith condition",
                )

            append_workwith_condition_extra_procedure_calls(
                evidences,
                source=source,
                expression=expression,
                procedure_lookup=procedure_lookup,
                relation_kind="workwith_condition_calls_procedure",
                extractor_rule_prefix="workwith_condition_procedure",
                snippet=condition_match.group(0),
                line=line_number_at(xml_text, condition_match.start()),
                evidence_role="WorkWith condition",
            )

    unique: dict[tuple[str, str, str, str, int], Evidence] = {}
    for evidence in evidences:
        unique[(evidence.source_type, evidence.source_name, evidence.target_name, evidence.extractor_rule, evidence.line)] = evidence
    return list(unique.values())


def extract_workwith_condition_attribute_evidence(
    workwith_objects: Iterable[ObjectInfo],
    procedure_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    procedure_lookup = case_insensitive_lookup(procedure_names, "Procedure")
    procedure_direct_re = direct_call_pattern(procedure_names)

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for tag_match in TAG_RE.finditer(xml_text):
            attrs = parse_attributes(tag_match.group("attrs"))
            for attr_name, attr_value in attrs.items():
                if not attr_name.lower().endswith("condition"):
                    continue

                expression = effective_condition_expression(attr_value)
                direct_matches = procedure_direct_re.finditer(expression) if procedure_direct_re else ()
                for procedure_match in direct_matches:
                    target_name = procedure_lookup.get(procedure_match.group("name").lower())
                    if not target_name:
                        continue
                    add_evidence(
                        evidences,
                        source=source,
                        target_type="Procedure",
                        target_name=target_name,
                        relation_kind="workwith_condition_attribute_calls_procedure",
                        line=line_number_at(xml_text, tag_match.start()),
                        column=1,
                        snippet=tag_match.group(0),
                        extractor_rule="workwith_condition_attribute_procedure",
                        evidence_role="WorkWith condition attribute",
                    )

                append_workwith_condition_extra_procedure_calls(
                    evidences,
                    source=source,
                    expression=expression,
                    procedure_lookup=procedure_lookup,
                    relation_kind="workwith_condition_attribute_calls_procedure",
                    extractor_rule_prefix="workwith_condition_attribute_procedure",
                    snippet=tag_match.group(0),
                    line=line_number_at(xml_text, tag_match.start()),
                    evidence_role="WorkWith condition attribute",
                )

    unique: dict[tuple[str, str, str, str, int], Evidence] = {}
    for evidence in evidences:
        unique[(evidence.source_type, evidence.source_name, evidence.target_name, evidence.extractor_rule, evidence.line)] = evidence
    return list(unique.values())


def extract_workwith_transaction_evidence(
    workwith_objects: Iterable[ObjectInfo],
    transaction_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    transaction_lookup = case_insensitive_lookup(transaction_names, "Transaction")

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for match in WORKWITH_TRANSACTION_RE.finditer(xml_text):
            raw_target_name = gxobject_name(html.unescape(match.group("value")))
            if not raw_target_name:
                continue
            target_name = transaction_lookup.get(raw_target_name.lower())
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="Transaction",
                target_name=target_name,
                relation_kind="workwith_references_transaction",
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0),
                extractor_rule="workwith_transaction_binding",
                evidence_role="WorkWith transaction",
            )

    unique: dict[tuple[str, str, str, str, int], Evidence] = {}
    for evidence in evidences:
        unique[(evidence.source_type, evidence.source_name, evidence.target_name, evidence.extractor_rule, evidence.line)] = evidence
    return list(unique.values())


def extract_workwith_webpanel_link_evidence(
    workwith_objects: Iterable[ObjectInfo],
    webpanel_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    webpanel_lookup = case_insensitive_lookup(webpanel_names, "WebPanel")

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for match in WORKWITH_WEBPANEL_LINK_RE.finditer(xml_text):
            raw_target_name = html.unescape(match.group("name"))
            target_name = webpanel_lookup.get(raw_target_name.lower())
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="WebPanel",
                target_name=target_name,
                relation_kind="workwith_links_webpanel",
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0),
                extractor_rule="workwith_link_webpanel",
                evidence_role="WorkWith link",
            )

    unique: dict[tuple[str, str, str, str, int], Evidence] = {}
    for evidence in evidences:
        unique[(evidence.source_type, evidence.source_name, evidence.target_name, evidence.extractor_rule, evidence.line)] = evidence
    return list(unique.values())


def extract_workwith_prompt_evidence(
    workwith_objects: Iterable[ObjectInfo],
    webpanel_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    webpanel_lookup = case_insensitive_lookup(webpanel_names, "WebPanel")

    for source in workwith_objects:
        xml_text = read_text(source.path)
        for match in WORKWITH_PROMPT_RE.finditer(xml_text):
            raw_target_name = gxobject_name(html.unescape(match.group("value")))
            if not raw_target_name:
                continue
            target_name = webpanel_lookup.get(raw_target_name.lower())
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="WebPanel",
                target_name=target_name,
                relation_kind="workwith_prompts_webpanel",
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0),
                extractor_rule="workwith_prompt_webpanel",
                evidence_role="WorkWith prompt",
            )

    unique: dict[tuple[str, str, str, str, int], Evidence] = {}
    for evidence in evidences:
        unique[(evidence.source_type, evidence.source_name, evidence.target_name, evidence.extractor_rule, evidence.line)] = evidence
    return list(unique.values())


def mask_preserving_lines(match: re.Match[str]) -> str:
    return re.sub(r"[^\n]", " ", match.group(0))


def workwith_condition_attribute_names(expression: str) -> list[str]:
    """Names a WorkWithForWeb condition expression uses as attributes, in order of appearance.

    The expression is already XML-unescaped. Skipped: // comments (each to the end of its line
    only, so a multi-line value goes on after it), string literals, &variables, members after
    '.', names followed by '(' or an object call method such as '.udp(' (called objects), the
    object named first in udp(...) and call(...), and GeneXus keywords. The legacy
    .and./.or./.not. operators are not member dots. The caller keeps only names in the
    Attribute inventory.
    """
    names: list[str] = []
    # (kind, lowercased text) of the last three tokens; ("start", "") pads the beginning.
    previous: list[tuple[str, str]] = [("start", "")] * 3
    for token in WORKWITH_CONDITION_TOKEN_RE.finditer(expression):
        kind = token.lastgroup or "other"
        if kind == "comment":
            # A // comment ends at its line; a multi-line value goes on after it.
            continue
        if kind == "name":
            name = token.group("name")
            after_dot = previous[-1][0] == "dot"
            is_call = WORKWITH_CONDITION_CALL_FOLLOW_RE.match(expression, token.end()) is not None
            # udp(Name, ...) or call(Name, ...), but not the argument of Proc.udp(Arg).
            is_called_object = (
                previous[-3][0] != "dot"
                and previous[-2][0] == "name"
                and previous[-2][1] in WORKWITH_CONDITION_CALL_FUNCTIONS
                and previous[-1] == ("other", "(")
            )
            if not (after_dot or is_call or is_called_object or name.lower() in WORKWITH_CONDITION_KEYWORDS):
                names.append(name)
        previous = previous[1:] + [(kind, token.group(0).lower())]
    return names


def extract_workwith_for_web_attribute_evidence(
    workwith_for_web_objects: Iterable[ObjectInfo],
    attribute_names: set[str],
) -> list[Evidence]:
    """Attribute references from the WorkWithForWeb pattern instance, one per source and target.

    Reads <attribute>/<descriptionAttribute> (typeGuid-Name form), bare <filterAttribute name>
    and the attribute names of filter <condition value="..."> expressions (see
    workwith_condition_attribute_names) inside the pattern instance Data only; a <condition>
    outside a <filter> element is not read. <variable> elements are masked first. Targets
    resolve against the Attribute inventory only. The first occurrence in document order wins,
    whichever part names it.
    """
    evidences: list[Evidence] = []
    seen: set[tuple[str, str]] = set()
    attribute_lookup = case_insensitive_lookup(attribute_names, "Attribute")
    for source in workwith_for_web_objects:
        xml_text = read_text(source.path)
        for data_match in WORKWITH_FOR_WEB_INSTANCE_DATA_RE.finditer(xml_text):
            body = WORKWITH_VARIABLE_ELEMENT_RE.sub(mask_preserving_lines, data_match.group("body"))
            body_offset = data_match.start("body")
            # (offset in body, raw attribute name, snippet, evidence role)
            candidates: list[tuple[int, str, str, str]] = []
            for match in WORKWITH_ATTRIBUTE_REFERENCE_RE.finditer(body):
                if match.group("filter_tag"):
                    tag = match.group("filter_tag")
                    raw_value = html.unescape(match.group("name")).strip()
                else:
                    tag = match.group("tag")
                    raw_value = html.unescape(match.group("value")).strip()
                raw_attribute_name = gxobject_name(raw_value) or raw_value
                candidates.append(
                    (match.start(), raw_attribute_name, match.group(0), WORKWITH_ATTRIBUTE_REFERENCE_ROLES[tag.lower()])
                )
            for filter_match in WORKWITH_FOR_WEB_FILTER_RE.finditer(body):
                if filter_match.group("body") is None:
                    continue
                # pos/endpos keep match offsets relative to the whole body.
                for match in WORKWITH_FOR_WEB_CONDITION_RE.finditer(
                    body, filter_match.start("body"), filter_match.end("body")
                ):
                    expression = parse_attributes(match.group("attrs")).get("value")
                    if not expression:
                        continue
                    for raw_attribute_name in workwith_condition_attribute_names(expression):
                        candidates.append((match.start(), raw_attribute_name, match.group(0), WORKWITH_CONDITION_ROLE))
            candidates.sort(key=lambda candidate: candidate[0])
            for offset, raw_attribute_name, snippet, role in candidates:
                target_name = attribute_lookup.get(raw_attribute_name.lower())
                if not target_name:
                    continue
                pair_key = (source.name.lower(), target_name.lower())
                if pair_key in seen:
                    continue
                seen.add(pair_key)
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Attribute",
                    target_name=target_name,
                    relation_kind="workwith_references_attribute",
                    line=line_number_at(xml_text, body_offset + offset),
                    column=1,
                    snippet=snippet,
                    extractor_rule="workwith_for_web_attribute_reference",
                    evidence_role=role,
                )
    return evidences


@dataclass(frozen=True)
class CodeToken:
    kind: str
    text: str
    start: int
    end: int
    line: int  # 0-based line inside the code block


def code_tokens(code: str) -> list[CodeToken]:
    """Significant tokens of a code block (comments dropped), each with its 0-based line."""
    tokens: list[CodeToken] = []
    line = 0
    position = 0
    for match in CODE_TOKEN_RE.finditer(code):
        line += code.count("\n", position, match.start())
        position = match.start()
        kind = match.lastgroup or "other"
        if kind != "comment":
            tokens.append(CodeToken(kind, match.group(0), match.start(), match.end(), line))
    return tokens


class CodeMode(Enum):
    """How code_attribute_names reads a code block, chosen from its Part and object."""

    # Procedure Source and Events: writes only inside for each / new blocks.
    BLOCK_CODE = "block code"
    # Rules of a Procedure, WebPanel or DataProvider: reads only.
    PLAIN_RULES = "plain rules"
    # Transaction Rules: an assignment rule 'Attr = expr [if ...];' writes its target.
    TRANSACTION_RULES = "transaction rules"
    # DataProvider Source whose output is a Transaction: item left sides are writes.
    DATA_PROVIDER_TRANSACTION_OUTPUT = "data provider transaction output"
    # DataProvider Source whose output is an SDT: item left sides name SDT items, not uses.
    DATA_PROVIDER_SDT_OUTPUT = "data provider sdt output"


@dataclass
class CodeBlockFrame:
    """An open 'for each' ... endfor, new ... endnew or plain 'for' ... endfor block."""

    kind: str  # "each", "new" or "loop"
    in_exception_branch: bool = False  # inside its when none / when duplicate branch


def code_attribute_names(code: str, *, domain_names: set[str], mode: CodeMode) -> list[tuple[str, int, str]]:
    """(name, 0-based line, "read" or "write") of the names a code block may use as attributes.

    Skipped: comments (// and /* */), string literals, &variables, members after '.', names
    followed on their own line by '(' or an object call method such as '.udp(' (a '(' opening
    the next line does not count), the object named first in udp(...) and call(...), the table
    named after 'for each' on its line, a Domain name followed by '.Member' that is not a method
    call (an enumeration value), every name on an 'Event' header line, the Load and Refresh
    commands alone on their line at a statement start, and GeneXus keywords. In a DataProvider
    Source (either DATA_PROVIDER_* mode), a group header (a name that starts a statement and is
    not followed by '=', '.' or '(') is skipped, and so is an item's left side (a
    statement-start name followed by '=') in DATA_PROVIDER_SDT_OUTPUT: it names an SDT item.

    "write" marks only an unambiguous assignment target: in DATA_PROVIDER_TRANSACTION_OUTPUT,
    an item's left side; in TRANSACTION_RULES, a name followed by '=' that starts a rule (first
    in the block or after ';'); in BLOCK_CODE, a name followed by '=' at a statement start
    (first on its line, not continuing an expression, outside parentheses) whose innermost
    enclosing 'for each' ... endfor or new ... endnew block is not in its when none / when
    duplicate branch. A plain 'for' loop is neither a write block nor a barrier; an Event or
    Sub boundary closes every open block. PLAIN_RULES has no write. Every other use is "read".
    The caller keeps only names in the Attribute inventory.
    """
    tokens = code_tokens(code)
    names: list[tuple[str, int, str]] = []
    event_header_line = -1
    track_blocks = mode is CodeMode.BLOCK_CODE
    data_provider_source = mode in (CodeMode.DATA_PROVIDER_TRANSACTION_OUTPUT, CodeMode.DATA_PROVIDER_SDT_OUTPUT)
    # Open blocks, innermost last.
    blocks: list[CodeBlockFrame] = []
    depth = 0
    for index, token in enumerate(tokens):
        if token.kind == "other":
            if token.text == "(":
                depth += 1
            elif token.text == ")":
                depth = max(0, depth - 1)
            continue
        if token.kind != "name":
            continue
        lowered = token.text.lower()
        previous = tokens[index - 1] if index > 0 else None
        following = tokens[index + 1] if index + 1 < len(tokens) else None
        first_on_line = previous is None or previous.line != token.line
        continues_expression = previous is not None and (
            (previous.kind == "other" and previous.text in CODE_CONTINUATION_OTHERS)
            or previous.kind == "operator"
            or (previous.kind == "name" and previous.text.lower() in CODE_CONTINUATION_NAMES)
        )
        line_start = first_on_line and not continues_expression and depth == 0
        alone_on_line = following is None or following.line != token.line
        if track_blocks and line_start:
            following_lowered = following.text.lower() if following is not None else ""
            if lowered in ("event", "endevent", "sub", "endsub"):
                blocks.clear()
                depth = 0
            elif lowered == "for":
                blocks.append(CodeBlockFrame("each" if following_lowered == "each" else "loop"))
            elif lowered == "new" and (alone_on_line or following.kind == "name"):
                blocks.append(CodeBlockFrame("new"))
            elif lowered in ("endfor", "endnew"):
                closing = ("each", "loop") if lowered == "endfor" else ("new",)
                while blocks:
                    if blocks.pop().kind in closing:
                        break
            elif lowered == "when" and following_lowered in ("none", "duplicate"):
                branch_kind = "each" if following_lowered == "none" else "new"
                for frame in reversed(blocks):
                    if frame.kind == branch_kind:
                        frame.in_exception_branch = True
                        break
        if lowered == "event" and first_on_line:
            event_header_line = token.line
            depth = 0
        if token.line == event_header_line or lowered in CODE_KEYWORDS:
            continue
        if lowered in CODE_LINE_COMMANDS and line_start and alone_on_line:
            continue
        if previous is not None and previous.kind == "dot":
            continue
        if CODE_CALL_FOLLOW_RE.match(code, token.end) is not None:
            continue
        # udp(Name, ...) or call(Name, ...), but not the argument of Proc.udp(Arg).
        if (
            index >= 2
            and previous is not None
            and previous.text == "("
            and tokens[index - 2].kind == "name"
            and tokens[index - 2].text.lower() in WORKWITH_CONDITION_CALL_FUNCTIONS
            and (index < 3 or tokens[index - 3].kind != "dot")
        ):
            continue
        # for each Table[.Level]: the head names a table, not an attribute.
        if (
            index >= 2
            and previous is not None
            and previous.kind == "name"
            and previous.text.lower() == "each"
            and previous.line == token.line
            and tokens[index - 2].kind == "name"
            and tokens[index - 2].text.lower() == "for"
        ):
            continue
        # Domain.Member (an enumeration value); Domain.Method(...) keeps the attribute.
        if (
            lowered in domain_names
            and following is not None
            and following.kind == "dot"
            and index + 2 < len(tokens)
            and tokens[index + 2].kind == "name"
            and CODE_CALL_FOLLOW_RE.match(code, tokens[index + 2].end) is None
        ):
            continue
        followed_by_assignment = following is not None and following.text == "="
        access = "read"
        if data_provider_source:
            statement_start = (first_on_line and not continues_expression) or (
                previous is not None and previous.text in ("{", "}")
            )
            if statement_start:
                if not followed_by_assignment and not (
                    following is not None and (following.kind == "dot" or following.text == "(")
                ):
                    continue  # group header
                if followed_by_assignment:
                    if mode is CodeMode.DATA_PROVIDER_SDT_OUTPUT:
                        continue  # SDT item name
                    access = "write"
        elif mode is CodeMode.TRANSACTION_RULES:
            if followed_by_assignment and (previous is None or previous.text == ";"):
                access = "write"
        elif track_blocks and followed_by_assignment and line_start:
            write_block = next((frame for frame in reversed(blocks) if frame.kind in ("each", "new")), None)
            if write_block is not None and not write_block.in_exception_branch:
                access = "write"
        names.append((token.text, token.line, access))
    return names


def code_part_blocks(xml_text: str, part_names: dict[str, str]) -> Iterable[tuple[SourceBlock, str, str]]:
    """(<Source> block, Part type GUID, Part name) of every <Part> whose type GUID is in part_names."""
    for part in CODE_PART_RE.finditer(xml_text):
        if part.group("body") is None:
            continue
        part_type = (parse_attributes(part.group("attrs")).get("type") or "").strip().lower()
        part_name = part_names.get(part_type)
        if part_name is None:
            continue
        for block in source_blocks(xml_text, part.start("body"), part.end("body")):
            yield block, part_type, part_name


def data_provider_output_kind(xml_text: str, transaction_type_guid: str) -> str:
    """'transaction' when the DataProvider's OutputSDT names a Transaction (by type GUID), else 'sdt'."""
    try:
        props = object_level_property_dict_via_parse(xml_text)
    except (ElementTree.ParseError, ValueError):
        props = object_level_property_dict_via_regex(xml_text)
    output = html.unescape(props.get("OutputSDT", "")).strip().lower()
    return "transaction" if output.startswith(transaction_type_guid.lower() + "-") else "sdt"


def extract_code_attribute_evidence(
    code_objects: Iterable[ObjectInfo],
    attribute_names: set[str],
    domain_names: set[str],
    transaction_type_guid: str,
) -> list[Evidence]:
    """Attribute uses from GeneXus code Parts (CODE_ATTRIBUTE_PART_NAMES), roles '<Part> read'
    and '<Part> write'.

    Reads only <Source> elements inside the selected <Part> elements; names come from
    code_attribute_names in the CodeMode of their Part (which decides read or write;
    Transaction Rules carry assignment rules) and resolve against the Attribute inventory
    only. One relation per source, attribute and evidence role: the first occurrence in
    document order. A write occurrence gives no read row of its own.
    """
    evidences: list[Evidence] = []
    attribute_lookup = case_insensitive_lookup(attribute_names, "Attribute")
    domain_keys = {name.lower() for name in domain_names}
    for source in code_objects:
        part_names = CODE_ATTRIBUTE_PART_NAMES.get(source.object_type)
        if not part_names:
            continue
        xml_text = read_text(source.path)
        data_provider_mode = None
        if source.object_type == "DataProvider":
            data_provider_mode = (
                CodeMode.DATA_PROVIDER_TRANSACTION_OUTPUT
                if data_provider_output_kind(xml_text, transaction_type_guid) == "transaction"
                else CodeMode.DATA_PROVIDER_SDT_OUTPUT
            )
        rules_mode = CodeMode.TRANSACTION_RULES if source.object_type == "Transaction" else CodeMode.PLAIN_RULES
        seen: set[tuple[str, str]] = set()
        for block, part_type, part_name in code_part_blocks(xml_text, part_names):
            code_lines = block.text.split("\n")
            if part_type == RULES_PART_GUID:
                mode = rules_mode
            elif part_type == DATA_PROVIDER_SOURCE_PART_GUID and data_provider_mode is not None:
                mode = data_provider_mode
            else:
                mode = CodeMode.BLOCK_CODE
            for raw_name, code_line, access in code_attribute_names(block.text, domain_names=domain_keys, mode=mode):
                target_name = attribute_lookup.get(raw_name.lower())
                if not target_name:
                    continue
                role = f"{part_name} {access}"
                key = (target_name.lower(), role)
                if key in seen:
                    continue
                seen.add(key)
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Attribute",
                    target_name=target_name,
                    relation_kind="code_references_attribute",
                    line=block.start_line + code_line,
                    column=1,
                    snippet=code_lines[code_line],
                    extractor_rule="code_attribute_reference",
                    evidence_role=role,
                )
    return evidences


def normalize_custom_type(value: str) -> str:
    return " ".join(html.unescape(value).strip().split())


def extract_attcustomtype_evidence(source_objects: Iterable[ObjectInfo]) -> list[Evidence]:
    evidences: list[Evidence] = []
    for source in source_objects:
        xml_text = read_text(source.path)
        for match in ATTCUSTOMTYPE_PROPERTY_RE.finditer(xml_text):
            target_name = normalize_custom_type(match.group("value"))
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="CustomType",
                target_name=target_name,
                relation_kind="uses_custom_type",
                line=line_number_at(xml_text, match.start("value")),
                column=1,
                snippet=match.group(0),
                extractor_rule="attcustomtype_property",
                evidence_role="Property ATTCUSTOMTYPE",
            )
    return evidences


def resolve_custom_type_target(
    custom_type: str,
    sdt_lookup: dict[str, str],
    domain_lookup: dict[str, str],
    external_object_lookup: dict[str, str],
) -> tuple[str, str] | None:
    if ":" not in custom_type:
        return None
    prefix, raw_name = custom_type.split(":", 1)
    if prefix.lower() == "sdt":
        target_name = sdt_lookup.get(raw_name.lower())
        if target_name:
            return "SDT", target_name
    if prefix.lower() in {"dom", "domain"}:
        target_name = domain_lookup.get(raw_name.lower())
        if target_name:
            return "Domain", target_name
    if prefix.lower() == "exo":
        normalized_name = raw_name.split(",", 1)[0].strip()
        target_name = external_object_lookup.get(normalized_name.lower())
        if target_name:
            return "ExternalObject", target_name
    return None


def extract_attcustomtype_resolved_evidence(
    source_objects: Iterable[ObjectInfo],
    sdt_names: set[str],
    domain_names: set[str],
    external_object_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    sdt_lookup = case_insensitive_lookup(sdt_names, "SDT")
    domain_lookup = case_insensitive_lookup(domain_names, "Domain")
    external_object_lookup = case_insensitive_lookup(external_object_names, "ExternalObject")
    for source in source_objects:
        xml_text = read_text(source.path)
        for match in ATTCUSTOMTYPE_PROPERTY_RE.finditer(xml_text):
            custom_type = normalize_custom_type(match.group("value"))
            if not custom_type:
                continue
            resolved = resolve_custom_type_target(
                custom_type,
                sdt_lookup,
                domain_lookup,
                external_object_lookup,
            )
            if not resolved:
                continue
            target_type, target_name = resolved
            add_evidence(
                evidences,
                source=source,
                target_type=target_type,
                target_name=target_name,
                relation_kind="uses_resolved_custom_type",
                line=line_number_at(xml_text, match.start("value")),
                column=1,
                snippet=match.group(0),
                extractor_rule="attcustomtype_resolved_object",
                evidence_role="Property ATTCUSTOMTYPE",
            )
    return evidences


def extract_sdt_item_attcustomtype_resolved_sdt_evidence(
    source_objects: Iterable[ObjectInfo],
    sdt_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    seen: set[tuple[str, str]] = set()
    sdt_lookup = case_insensitive_lookup(sdt_names, "SDT")
    for source in source_objects:
        xml_text = read_text(source.path)
        for item_match in SDT_ITEM_RE.finditer(xml_text):
            item_body = item_match.group("body")
            match = ATTCUSTOMTYPE_PROPERTY_RE.search(item_body)
            if not match:
                continue
            custom_type = normalize_custom_type(match.group("value"))
            if not custom_type.lower().startswith("sdt:"):
                continue
            raw_sdt_name = custom_type.split(":", 1)[1].strip()
            target_name = sdt_lookup.get(raw_sdt_name.lower())
            if not target_name:
                continue
            pair_key = (source.name.lower(), target_name.lower())
            if pair_key in seen:
                continue
            seen.add(pair_key)
            match_start = item_match.start("body") + match.start()
            add_evidence(
                evidences,
                source=source,
                target_type="SDT",
                target_name=target_name,
                relation_kind="has_sdt_item_type",
                line=line_number_at(xml_text, match_start),
                column=1,
                snippet=match.group(0),
                extractor_rule="sdt_item_attcustomtype_resolved_sdt",
                evidence_role="SDT Item ATTCUSTOMTYPE",
            )
    return evidences


def parse_domain_idbasedon_value(value: str) -> tuple[str, str | None] | None:
    """Parse Domain:<name>[, <module>] after normalize_custom_type.

    Returns (name, module_or_None) or None if it is not a Domain: resolvable at the edge
    (missing prefix, empty name, multiple commas).
    """
    normalized = normalize_custom_type(value)
    if not normalized.lower().startswith("domain:"):
        return None
    rest = normalized.split(":", 1)[1].strip()
    if not rest:
        return None
    if rest.count(",") > 1:
        return None
    if "," in rest:
        name_part, module_part = rest.split(",", 1)
        name = name_part.strip()
        module = module_part.strip()
        if not name or not module:
            return None
        return name, module
    return rest, None


def resolve_domain_idbasedon_target(
    value: str,
    domain_lookup: dict[str, str],
    domain_fqfn_by_name: dict[str, str | None],
) -> str | None:
    """Resolver for rule B (Attribute and the other types in scope).

    Without a module: lookup by short name (lower). With a module: only if
    lower(fqfn) == lower(module + '.' + name). Without fqfn or divergent: does not resolve.
    """
    parsed = parse_domain_idbasedon_value(value)
    if parsed is None:
        return None
    domain_name, module = parsed
    target_name = domain_lookup.get(domain_name.lower())
    if not target_name:
        return None
    if module is None:
        return target_name
    fqfn = domain_fqfn_by_name.get(target_name.lower())
    if not fqfn:
        return None
    expected = f"{module}.{domain_name}"
    if fqfn.lower() == expected.lower():
        return target_name
    return None


def dedup_based_on_domain_evidences(evidences: list[Evidence]) -> list[Evidence]:
    """Dedup by (typed source, typed target) within based_on_domain; first evidence wins."""
    seen: set[tuple[str, str, str, str]] = set()
    result: list[Evidence] = []
    for evidence in evidences:
        if evidence.relation_kind != "based_on_domain":
            result.append(evidence)
            continue
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
        )
        if key in seen:
            continue
        seen.add(key)
        result.append(evidence)
    return result


def extract_idbasedon_domain_evidence(
    source_objects: Iterable[ObjectInfo],
    domain_names: set[str],
    domain_fqfn_by_name: dict[str, str | None],
) -> list[Evidence]:
    """idBasedOn Domain:... in raw XML with CDATA/comment masked; snippet/line from the raw text."""
    evidences: list[Evidence] = []
    domain_lookup = case_insensitive_lookup(domain_names, "Domain")
    for source in source_objects:
        if source.object_type not in IDBASEDON_DOMAIN_SOURCE_TYPES:
            continue
        xml_text = read_text(source.path)
        masked = mask_xml_cdata_and_comments(xml_text)
        extractor_rule = (
            "attribute_idbasedon_domain"
            if source.object_type == "Attribute"
            else "object_idbasedon_domain"
        )
        for match in IDBASEDON_PROPERTY_RE.finditer(masked):
            raw_value = xml_text[match.start("value") : match.end("value")]
            target_name = resolve_domain_idbasedon_target(
                raw_value,
                domain_lookup,
                domain_fqfn_by_name,
            )
            if not target_name:
                continue
            raw_snippet = xml_text[match.start() : match.end()]
            add_evidence(
                evidences,
                source=source,
                target_type="Domain",
                target_name=target_name,
                relation_kind="based_on_domain",
                line=line_number_at(xml_text, match.start("value")),
                column=1,
                snippet=raw_snippet,
                extractor_rule=extractor_rule,
                evidence_role="Property idBasedOn",
            )
    return dedup_based_on_domain_evidences(evidences)


def extract_attribute_formula_call_evidence(
    source_objects: Iterable[ObjectInfo],
    procedure_names: set[str],
    webpanel_names: set[str],
    data_provider_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    procedure_lookup = case_insensitive_lookup(procedure_names, "Procedure")
    webpanel_lookup = case_insensitive_lookup(webpanel_names, "WebPanel")
    data_provider_lookup = case_insensitive_lookup(data_provider_names, "DataProvider")
    procedure_direct_re = direct_call_pattern(procedure_names)
    data_provider_direct_re = direct_call_pattern(data_provider_names)
    for source in source_objects:
        xml_text = read_text(source.path)
        for match in FORMULA_PROPERTY_RE.finditer(xml_text):
            raw_value = match.group("value")
            expression = html.unescape(raw_value).strip()
            if not expression:
                continue
            append_call_evidences_from_expression(
                evidences,
                source=source,
                xml_text=xml_text,
                expression=expression,
                expression_start=match.start("value"),
                evidence_role="Property Formula",
                procedure_lookup=procedure_lookup,
                webpanel_lookup=webpanel_lookup,
                data_provider_lookup=data_provider_lookup,
                data_provider_direct_re=data_provider_direct_re,
                procedure_direct_re=procedure_direct_re,
                relation_kind_procedure="formula_calls_procedure",
                relation_kind_webpanel_link="formula_calls_webpanel",
                relation_kind_webpanel_create="formula_creates_webcomponent",
                relation_kind_dataprovider="formula_calls_dataprovider",
                extractor_rule_procedure_direct="attribute_formula_procedure_direct_call",
                extractor_rule_procedure_dot="attribute_formula_procedure_dot_call",
                extractor_rule_procedure_dot_link="attribute_formula_procedure_dot_link",
                extractor_rule_webpanel_link="attribute_formula_webpanel_dot_link",
                extractor_rule_procedure_call_command="attribute_formula_procedure_call_command",
                extractor_rule_webpanel_create="attribute_formula_webpanel_dot_create",
                extractor_rule_dataprovider_direct="attribute_formula_dataprovider_direct_call",
                extractor_rule_procedure_udp_func="attribute_formula_procedure_udp_func",
                extractor_rule_procedure_dot_udp="attribute_formula_procedure_dot_udp",
            )
    return evidences


def extract_transaction_level_attribute_evidence(
    source_objects: Iterable[ObjectInfo],
    attribute_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    attribute_lookup = case_insensitive_lookup(attribute_names, "Attribute")
    for source in source_objects:
        xml_text = read_text(source.path)
        for level_match in LEVEL_RE.finditer(xml_text):
            level_body = level_match.group("body")
            for match in LEVEL_ATTRIBUTE_RE.finditer(level_body):
                raw_attribute_name = html.unescape(match.group("name")).strip()
                if not raw_attribute_name:
                    continue
                target_name = attribute_lookup.get(raw_attribute_name.lower())
                if not target_name:
                    continue
                match_start = level_match.start("body") + match.start()
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Attribute",
                    target_name=target_name,
                    relation_kind="has_level_attribute",
                    line=line_number_at(xml_text, match_start),
                    column=1,
                    snippet=match.group(0),
                    extractor_rule="transaction_level_attribute",
                    evidence_role="Level Attribute",
                )
    return evidences


def extract_transaction_level_table_evidence(
    source_objects: Iterable[ObjectInfo],
    table_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    table_lookup = case_insensitive_lookup(table_names, "Table")
    for source in source_objects:
        xml_text = read_text(source.path)
        for match in LEVEL_RE.finditer(xml_text):
            attrs = parse_attributes(match.group("attrs"))
            raw_table_name = attrs.get("Type", "").strip()
            if not raw_table_name:
                continue
            target_name = table_lookup.get(raw_table_name.lower())
            if not target_name:
                continue
            add_evidence(
                evidences,
                source=source,
                target_type="Table",
                target_name=target_name,
                relation_kind="has_level_table",
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0).split(">", 1)[0] + ">",
                extractor_rule="transaction_level_table",
                evidence_role="Level Type",
            )
    return evidences


def extract_table_key_attribute_evidence(
    source_objects: Iterable[ObjectInfo],
    attribute_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    attribute_lookup = case_insensitive_lookup(attribute_names, "Attribute")
    for source in source_objects:
        xml_text = read_text(source.path)
        for key_match in KEY_RE.finditer(xml_text):
            key_body = key_match.group("body")
            for match in KEY_ITEM_RE.finditer(key_body):
                raw_attribute_name = html.unescape(match.group("name")).strip()
                if not raw_attribute_name:
                    continue
                target_name = attribute_lookup.get(raw_attribute_name.lower())
                if not target_name:
                    continue
                match_start = key_match.start("body") + match.start()
                add_evidence(
                    evidences,
                    source=source,
                    target_type="Attribute",
                    target_name=target_name,
                    relation_kind="has_key_attribute",
                    line=line_number_at(xml_text, match_start),
                    column=1,
                    snippet=match.group(0),
                    extractor_rule="table_key_attribute",
                    evidence_role="Key Item",
                )
    return evidences


def extract_table_index_member_attribute_evidence(
    source_objects: Iterable[ObjectInfo],
    attribute_names: set[str],
) -> list[Evidence]:
    evidences: list[Evidence] = []
    seen: set[tuple[str, str]] = set()
    attribute_lookup = case_insensitive_lookup(attribute_names, "Attribute")
    for source in source_objects:
        xml_text = read_text(source.path)
        for match in INDEX_MEMBER_RE.finditer(xml_text):
            raw_attribute_name = html.unescape(match.group("name")).strip()
            if not raw_attribute_name:
                continue
            target_name = attribute_lookup.get(raw_attribute_name.lower())
            if not target_name:
                continue
            pair_key = (source.name.lower(), target_name.lower())
            if pair_key in seen:
                continue
            seen.add(pair_key)
            add_evidence(
                evidences,
                source=source,
                target_type="Attribute",
                target_name=target_name,
                relation_kind="has_index_member_attribute",
                line=line_number_at(xml_text, match.start()),
                column=1,
                snippet=match.group(0),
                extractor_rule="table_index_member_attribute",
                evidence_role="Index Member",
            )
    return evidences


def strip_scss_comments(text: str) -> str:
    """Removes SCSS/GeneXus comments (/* */ and //) while preserving the line count."""
    text = SCSS_BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    text = SCSS_LINE_COMMENT_RE.sub("", text)
    return text


def design_system_styles_scss(xml_text: str) -> Iterable[str]:
    """SCSS of the 'Styles' Parts (same type GUID in an authored DesignSystem and one nested in PackagedModule)."""
    for part_match in PART_RE.finditer(xml_text):
        if part_match.group("type").lower() != DESIGN_SYSTEM_STYLES_PART_GUID:
            continue
        for source_match in SOURCE_RE.finditer(part_match.group("body")):
            scss = unwrap_source_body(source_match.group("body"))
            if scss.strip():
                yield strip_scss_comments(scss)


def collect_legacy_theme_css_classes(theme_class_objects: Iterable[ObjectInfo]) -> list[CssClass]:
    rows: list[CssClass] = []
    seen: set[tuple[str, str]] = set()
    for source in theme_class_objects:
        xml_text = read_text(source.path)
        name_match = NAME_PROPERTY_RE.search(xml_text)
        class_name = html.unescape(name_match.group("value")).strip() if name_match else ""
        if not class_name:
            class_name = source.name
        parent_match = OBJECT_PARENT_ATTR_RE.search(xml_text)
        parent_class = None
        if parent_match:
            candidate = html.unescape(parent_match.group("value")).strip()
            parent_class = candidate or None
        key = (class_name, source.name)
        if key in seen:
            continue
        seen.add(key)
        rows.append(
            CssClass(
                class_name=class_name,
                model="legacy-theme",
                origin="kb-authored",
                defining_object_type="ThemeClass",
                defining_object_name=source.name,
                defining_file=source.rel_path,
                parent_class=parent_class,
                extractor_rule="theme_class_name_property",
            )
        )
    return rows


def collect_design_system_css_classes(
    objects: Iterable[ObjectInfo],
    *,
    defining_object_type: str,
    origin: str,
    extractor_rule: str,
) -> list[CssClass]:
    rows: list[CssClass] = []
    seen: set[tuple[str, str]] = set()
    for source in objects:
        xml_text = read_text(source.path)
        for scss in design_system_styles_scss(xml_text):
            for selector in CSS_SELECTOR_RE.finditer(scss):
                class_name = selector.group("name")
                key = (class_name, source.name)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(
                    CssClass(
                        class_name=class_name,
                        model="design-system",
                        origin=origin,
                        defining_object_type=defining_object_type,
                        defining_object_name=source.name,
                        defining_file=source.rel_path,
                        parent_class=None,
                        extractor_rule=extractor_rule,
                    )
                )
    return rows


def dedup_evidences(evidences: list[Evidence]) -> list[Evidence]:
    unique: dict[tuple[str, str, str, str, int, str, str], Evidence] = {}
    for evidence in evidences:
        key = (
            evidence.source_type,
            evidence.source_name,
            evidence.target_type,
            evidence.target_name,
            evidence.line,
            evidence.extractor_rule,
            evidence.evidence_role,
        )
        unique[key] = evidence
    return list(unique.values())


def extract_css_layout_usage_evidence(usage_objects: Iterable[ObjectInfo]) -> list[Evidence]:
    """Static class usage in the layout: attribute class="..." (one or more space-separated classes)."""
    evidences: list[Evidence] = []
    for source in usage_objects:
        xml_text = read_text(source.path)
        for match in LAYOUT_CLASS_ATTR_RE.finditer(xml_text):
            value = html.unescape(match.group("value"))
            if not value.strip():
                continue
            line_no = line_number_at(xml_text, match.start())
            for token in value.split():
                if not CSS_CLASS_NAME_RE.match(token):
                    continue
                add_evidence(
                    evidences,
                    source=source,
                    target_type="CssClass",
                    target_name=token,
                    relation_kind="uses_css_class",
                    line=line_no,
                    column=1,
                    snippet=match.group(0),
                    extractor_rule="css_layout_class_attribute",
                    evidence_role="css_layout",
                )
    return dedup_evidences(evidences)


def extract_css_event_usage_evidence(usage_objects: Iterable[ObjectInfo]) -> list[Evidence]:
    """Usage via code: Control.Class = <expr> assignment in events (Source). Covers the 7 forms of the matrix."""
    evidences: list[Evidence] = []
    for source in usage_objects:
        xml_text = read_text(source.path)
        for block in source_blocks(xml_text):
            block_text = strip_scss_comments(block.text)
            for offset, line in enumerate(block_text.splitlines()):
                if not line.strip():
                    continue
                line_no = block.start_line + offset
                for match in DOT_CLASS_ASSIGN_RE.finditer(line):
                    rhs = match.group("rhs").strip()
                    resolvable: set[str] = set()
                    for literal in CSS_QUOTED_LITERAL_RE.finditer(rhs):
                        for token in literal.group("value").split():
                            if CSS_CLASS_NAME_RE.match(token):
                                resolvable.add(token)
                    for prefix_match in CSS_PREFIX_CLASS_RE.finditer(rhs):
                        resolvable.add(prefix_match.group("name"))
                    for class_name in sorted(resolvable):
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="CssClass",
                            target_name=class_name,
                            relation_kind="uses_css_class",
                            line=line_no,
                            column=match.start("rhs") + 1,
                            snippet=line,
                            extractor_rule="css_event_class_assignment",
                            evidence_role="css_event",
                        )
                    is_dynamic = bool(CSS_DYNAMIC_HINT_RE.search(rhs)) or not resolvable
                    if is_dynamic:
                        add_evidence(
                            evidences,
                            source=source,
                            target_type="CssClass",
                            target_name=compact_snippet(rhs, 120),
                            relation_kind="uses_css_class_dynamic",
                            line=line_no,
                            column=match.start("rhs") + 1,
                            snippet=line,
                            extractor_rule="css_event_class_dynamic",
                            evidence_role="css_dynamic",
                        )
    return dedup_evidences(evidences)


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP TABLE IF EXISTS css_class;
        DROP TABLE IF EXISTS transaction_attribute_writability;
        DROP TABLE IF EXISTS relations;
        DROP TABLE IF EXISTS evidence;
        DROP TABLE IF EXISTS objects;
        DROP TABLE IF EXISTS metadata;

        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE objects (
            object_id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            guid TEXT,
            file_path TEXT NOT NULL,
            last_update TEXT,
            file_hash TEXT NOT NULL,
            is_generated_object INTEGER NOT NULL DEFAULT 0,
            pattern_object_id TEXT,
            instance_key TEXT,
            UNIQUE(type, name)
        );

        CREATE TABLE evidence (
            evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_file TEXT NOT NULL,
            line INTEGER NOT NULL,
            column INTEGER NOT NULL,
            snippet TEXT NOT NULL,
            evidence_role TEXT NOT NULL,
            extractor_rule TEXT NOT NULL
        );

        CREATE TABLE relations (
            relation_id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_object_id INTEGER NOT NULL,
            target_type TEXT NOT NULL,
            target_name TEXT NOT NULL,
            relation_kind TEXT NOT NULL,
            evidence_id INTEGER NOT NULL,
            confidence TEXT NOT NULL,
            FOREIGN KEY(source_object_id) REFERENCES objects(object_id),
            FOREIGN KEY(evidence_id) REFERENCES evidence(evidence_id)
        );

        CREATE INDEX idx_objects_type_name ON objects(type, name);
        CREATE INDEX idx_objects_is_generated ON objects(is_generated_object);
        CREATE INDEX idx_relations_target ON relations(target_type, target_name);
        CREATE INDEX idx_relations_source ON relations(source_object_id);

        CREATE TABLE transaction_attribute_writability (
            writability_id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_object_id INTEGER NOT NULL,
            transaction_name TEXT NOT NULL,
            level_name TEXT NOT NULL,
            attribute_name TEXT NOT NULL,
            key_in_level INTEGER NOT NULL,
            is_redundant INTEGER NOT NULL,
            classification TEXT NOT NULL,
            writable INTEGER,
            can_assign_in_new INTEGER,
            reason TEXT NOT NULL,
            evidence TEXT NOT NULL,
            writability_rule_version TEXT NOT NULL,
            FOREIGN KEY(transaction_object_id) REFERENCES objects(object_id)
        );

        CREATE INDEX idx_writability_transaction ON transaction_attribute_writability(transaction_name);
        CREATE INDEX idx_writability_transaction_object ON transaction_attribute_writability(transaction_object_id);
        CREATE INDEX idx_writability_attribute ON transaction_attribute_writability(attribute_name);

        CREATE TABLE css_class (
            css_class_id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            model TEXT NOT NULL,
            origin TEXT NOT NULL,
            defining_object_type TEXT,
            defining_object_name TEXT,
            defining_file TEXT,
            parent_class TEXT,
            extractor_rule TEXT NOT NULL,
            UNIQUE(model, class_name, defining_object_name)
        );

        CREATE INDEX idx_css_class_name ON css_class(class_name);
        CREATE INDEX idx_css_class_model ON css_class(model);
        CREATE INDEX idx_css_class_origin ON css_class(origin);
        """
    )


def resolve_transaction_object_id(
    object_ids: dict[tuple[str, str], int],
    transaction_objects: dict[str, ObjectInfo],
    transaction_name: str,
) -> int | None:
    direct = object_ids.get(("Transaction", transaction_name))
    if direct is not None:
        return direct
    for obj in transaction_objects.values():
        if obj.name.lower() == transaction_name.lower():
            return object_ids.get(("Transaction", obj.name))
    return None


def insert_corpus_writability(
    conn: sqlite3.Connection,
    source_root: Path,
    object_ids: dict[tuple[str, str], int],
    transaction_objects: dict[str, ObjectInfo],
) -> int:
    transaction_type_guid = get_transaction_type_guid(GX_TYPE_CATALOG_BY_NAME)
    writability_rows = build_corpus_writability(source_root, transaction_type_guid)
    inserted = 0
    for row in writability_rows:
        transaction_object_id = resolve_transaction_object_id(
            object_ids,
            transaction_objects,
            row.transaction_name,
        )
        if transaction_object_id is None:
            continue
        writable_value: int | None
        if row.writable is None:
            writable_value = None
        else:
            writable_value = 1 if row.writable else 0
        can_assign_value: int | None
        if row.can_assign_in_new is None:
            can_assign_value = None
        else:
            can_assign_value = 1 if row.can_assign_in_new else 0
        conn.execute(
            """
            INSERT INTO transaction_attribute_writability(
                transaction_object_id,
                transaction_name,
                level_name,
                attribute_name,
                key_in_level,
                is_redundant,
                classification,
                writable,
                can_assign_in_new,
                reason,
                evidence,
                writability_rule_version
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                transaction_object_id,
                row.transaction_name,
                row.level_name,
                row.attribute_name,
                1 if row.key else 0,
                1 if row.is_redundant else 0,
                row.classification,
                writable_value,
                can_assign_value,
                row.reason,
                row.evidence,
                WRITABILITY_RULE_VERSION,
            ),
        )
        inserted += 1
    return inserted


def write_index(
    output_path: Path,
    source_root: Path,
    objects: list[ObjectInfo],
    evidences: list[Evidence],
    css_classes: list[CssClass],
    index_build_run_at: str,
    inventory_semantics: dict[str, object],
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    extractor_signature_hash = compute_extractor_signature_hash()

    conn = sqlite3.connect(output_path)
    try:
        create_schema(conn)
        conn.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            [
                ("last_index_build_run_at", index_build_run_at),
                ("source_root", portable_source_root(source_root, output_path.parent)),
                ("schema_version", "5"),
                ("writability_rule_version", WRITABILITY_RULE_VERSION),
                ("extractor_signature_version", EXTRACTOR_SIGNATURE_VERSION),
                ("extractor_signature_hash", extractor_signature_hash),
                ("scope", ",".join(sorted(set(obj.object_type for obj in objects)))),
                ("inventory_catalog_version", str(inventory_semantics["catalog_version"])),
                ("inventory_validation_status", str(inventory_semantics["status"])),
                ("inventory_mismatch_count", str(inventory_semantics["mismatch_count"])),
                ("generated_objects_count", str(sum(1 for obj in objects if obj.is_generated_object))),
            ],
        )

        for obj in objects:
            conn.execute(
                """
                INSERT INTO objects(type, name, guid, file_path, last_update, file_hash, is_generated_object, pattern_object_id, instance_key)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    obj.object_type,
                    obj.name,
                    obj.guid,
                    obj.rel_path,
                    obj.last_update,
                    obj.file_hash,
                    obj.is_generated_object,
                    obj.pattern_object_id,
                    obj.instance_key,
                ),
            )

        object_ids = {
            (row[0], row[1]): row[2]
            for row in conn.execute("SELECT type, name, object_id FROM objects")
        }

        for evidence in evidences:
            cursor = conn.execute(
                """
                INSERT INTO evidence(source_file, line, column, snippet, evidence_role, extractor_rule)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    evidence.source_file,
                    evidence.line,
                    evidence.column,
                    evidence.snippet,
                    evidence.evidence_role,
                    evidence.extractor_rule,
                ),
            )
            evidence_id = cursor.lastrowid
            source_object_id = object_ids[(evidence.source_type, evidence.source_name)]
            conn.execute(
                """
                INSERT INTO relations(source_object_id, target_type, target_name, relation_kind, evidence_id, confidence)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    source_object_id,
                    evidence.target_type,
                    evidence.target_name,
                    evidence.relation_kind,
                    evidence_id,
                    evidence.confidence,
                ),
            )

        transaction_objects = {
            obj.name: obj for obj in objects if obj.object_type == "Transaction"
        }
        writability_written = insert_corpus_writability(
            conn,
            source_root.resolve(),
            object_ids,
            transaction_objects,
        )
        conn.execute(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            ("writability_rows_written", str(writability_written)),
        )

        css_classes_written = 0
        for css in css_classes:
            cursor = conn.execute(
                """
                INSERT OR IGNORE INTO css_class(
                    class_name, model, origin, defining_object_type,
                    defining_object_name, defining_file, parent_class, extractor_rule
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    css.class_name,
                    css.model,
                    css.origin,
                    css.defining_object_type,
                    css.defining_object_name,
                    css.defining_file,
                    css.parent_class,
                    css.extractor_rule,
                ),
            )
            css_classes_written += cursor.rowcount if cursor.rowcount and cursor.rowcount > 0 else 0
        conn.execute(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            ("css_class_rows_written", str(css_classes_written)),
        )

        conn.commit()
    finally:
        conn.close()


def validation_report(
    source_root: Path,
    objects_by_type: dict[str, dict[str, ObjectInfo]],
    evidences: list[Evidence],
    css_classes: list[CssClass],
    validation_cases_path: Path | None,
    index_build_run_at: str,
    inventory_semantics: dict[str, object],
) -> dict[str, object]:
    def has_relation(source_type: str, source_name: str, target_type: str, target_name: str, rule: str) -> bool:
        return any(
            evidence.source_type == source_type
            and evidence.source_name == source_name
            and evidence.target_type == target_type
            and evidence.target_name == target_name
            and evidence.extractor_rule == rule
            for evidence in evidences
        )

    def object_info_exists(object_type: str, object_name: str) -> ObjectInfo | None:
        return objects_by_type.get(object_type, {}).get(object_name)

    def count_impact_relations(object_type: str, object_name: str) -> tuple[int, int]:
        incoming = 0
        outgoing = 0
        for evidence in evidences:
            if evidence.source_type == object_type and evidence.source_name == object_name:
                outgoing += 1
            if evidence.target_type == object_type and evidence.target_name == object_name:
                incoming += 1
        return incoming, outgoing

    def source_has_idbasedon_value(info: ObjectInfo, expected_value: str) -> bool:
        # Parity with extract_idbasedon_domain_evidence: only counts Property outside CDATA/comment.
        xml_text = read_text(info.path)
        masked = mask_xml_cdata_and_comments(xml_text)
        expected_norm = normalize_custom_type(expected_value)
        for match in IDBASEDON_PROPERTY_RE.finditer(masked):
            raw_value = xml_text[match.start("value") : match.end("value")]
            if normalize_custom_type(raw_value) == expected_norm:
                return True
        return False

    def check_relation_preconditions(raw_case: dict[str, object]) -> list[str]:
        """G.0: optional backward-compatible preconditions for relation cases."""
        failures: list[str] = []
        source_raw = raw_case.get("source")
        target_raw = raw_case.get("target")
        source_info: ObjectInfo | None = None
        if source_raw is not None:
            source_type, source_name = split_typed_name(str(source_raw))
            source_info = object_info_exists(source_type, source_name)

        if raw_case.get("require_source_exists"):
            if source_raw is None:
                failures.append("require_source_exists set but source missing in case")
            elif source_info is None:
                failures.append(f"require_source_exists: {source_raw} not found")

        prop_req = raw_case.get("require_property_in_source")
        if prop_req is not None:
            if source_info is None:
                failures.append("require_property_in_source: source not found")
            else:
                if isinstance(prop_req, dict):
                    expected_value = str(prop_req.get("value", ""))
                else:
                    expected_value = str(prop_req)
                if not source_has_idbasedon_value(source_info, expected_value):
                    failures.append(
                        f"require_property_in_source: idBasedOn value {expected_value!r} not found in source"
                    )

        if raw_case.get("require_target_exists"):
            if target_raw is None:
                failures.append("require_target_exists set but target missing in case")
            else:
                target_type, target_name = split_typed_name(str(target_raw))
                target_info = object_info_exists(target_type, target_name)
                if target_info is None:
                    failures.append(f"require_target_exists: {target_raw} not found")
                else:
                    expected_fqfn = raw_case.get("require_target_fully_qualified_name")
                    if expected_fqfn is not None:
                        actual_fqfn = extract_root_fully_qualified_name(read_text(target_info.path))
                        if (actual_fqfn or "").lower() != str(expected_fqfn).lower():
                            failures.append(
                                f"require_target_fully_qualified_name: got {actual_fqfn!r} expected {expected_fqfn!r}"
                            )
        return failures

    cases: list[dict[str, object]] = []
    if validation_cases_path:
        raw_cases = json.loads(validation_cases_path.read_text(encoding="utf-8"))
        for raw_case in raw_cases.get("cases", []):
            case_result = dict(raw_case)
            query = str(raw_case.get("query", ""))
            failures: list[str] = []
            if query == "object-info":
                object_type, object_name = split_typed_name(raw_case["object"])
                should_exist = bool(raw_case.get("should_exist", True))
                info = object_info_exists(object_type, object_name)
                if bool(info is not None) != should_exist:
                    failures.append(f"found={info is not None} expected {should_exist}")
                if should_exist and info is not None:
                    expected_file_contains = raw_case.get("expected_file_contains")
                    if expected_file_contains and expected_file_contains not in str(info.file_path):
                        failures.append(f"file_path={info.file_path} does not contain {expected_file_contains}")
            elif query == "impact-basic":
                object_type, object_name = split_typed_name(raw_case["object"])
                should_exist = bool(raw_case.get("should_exist", True))
                info = object_info_exists(object_type, object_name)
                if bool(info is not None) != should_exist:
                    failures.append(f"found={info is not None} expected {should_exist}")
                if should_exist and info is not None:
                    incoming, outgoing = count_impact_relations(object_type, object_name)
                    min_incoming = int(raw_case.get("min_incoming_relations", 0))
                    min_outgoing = int(raw_case.get("min_outgoing_relations", 0))
                    if incoming < min_incoming:
                        failures.append(f"incoming_relations={incoming} below minimum {min_incoming}")
                    if outgoing < min_outgoing:
                        failures.append(f"outgoing_relations={outgoing} below minimum {min_outgoing}")
            elif {"source", "target", "expected_rule"} <= set(raw_case):
                failures.extend(check_relation_preconditions(raw_case))
                if not failures:
                    source_type, source_name = split_typed_name(raw_case["source"])
                    target_type, target_name = split_typed_name(raw_case["target"])
                    expected_rule = raw_case["expected_rule"]
                    should_exist = bool(raw_case.get("should_exist", True))
                    relation_exists = has_relation(source_type, source_name, target_type, target_name, expected_rule)
                    if (relation_exists if should_exist else not relation_exists) is False:
                        failures.append(
                            f"relation {source_type}:{source_name} -> {target_type}:{target_name} via {expected_rule} "
                            f"expected {should_exist} but got {relation_exists}"
                        )
            else:
                failures.append(f"Unsupported validation case format: {query or 'relation'}")

            case_result["status"] = "failed" if failures else "passed"
            if failures:
                case_result["failures"] = failures
            cases.append(case_result)

    css_classes_by_model: dict[str, int] = {}
    for css in css_classes:
        bucket = f"{css.model}/{css.origin}"
        css_classes_by_model[bucket] = css_classes_by_model.get(bucket, 0) + 1

    return {
        "last_index_build_run_at": index_build_run_at,
        "source_root": str(source_root),
        "objects_read_by_type": {key: len(value) for key, value in objects_by_type.items()},
        "objects_written": sum(len(value) for value in objects_by_type.values()),
        "relations_written": len(evidences),
        "css_classes_written": len(css_classes),
        "css_classes_by_model": dict(sorted(css_classes_by_model.items())),
        "inventory_semantics": inventory_semantics,
        "validation_cases_path": str(validation_cases_path) if validation_cases_path else None,
        "cases": cases,
    }


def split_typed_name(value: str) -> tuple[str, str]:
    if ":" not in value:
        raise ValueError(f"Expected typed name in Type:Name format: {value}")
    object_type, name = value.split(":", 1)
    return object_type, name


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a minimal KB intelligence SQLite index.")
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output-path", required=True, type=Path)
    parser.add_argument("--validation-report-path", type=Path)
    parser.add_argument("--validation-cases-path", type=Path)
    parser.add_argument("--fail-on-validation-failure", action="store_true")
    parser.add_argument(
        "--kb-workspace-root",
        type=Path,
        help="Root of the KB workspace folder; used to resolve scripts/gx-object-type-catalog.override.json.",
    )
    parser.add_argument(
        "--catalog-override-path",
        type=Path,
        help="Explicit path of the local override; takes precedence over automatic detection from the KB workspace folder.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_root = args.source_root.resolve()
    if not source_root.exists():
        raise SystemExit(f"SourceRoot not found: {source_root}")

    try:
        activate_object_type_catalog(
            source_root,
            kb_workspace_root=args.kb_workspace_root.resolve() if args.kb_workspace_root else None,
            catalog_override_path=args.catalog_override_path.resolve() if args.catalog_override_path else None,
        )
    except CatalogOverrideDiagnosticError as exc:
        print(json.dumps(build_catalog_override_blocked_result(exc), indent=2, ensure_ascii=False))
        return 2

    objects_by_type, scan_summary = collect_all_objects(source_root)
    inventory_semantics = validate_inventory_semantics(objects_by_type, scan_summary)
    procedures = objects_by_type.get("Procedure", {})
    webpanels = objects_by_type.get("WebPanel", {})
    data_providers = objects_by_type.get("DataProvider", {})
    apis = objects_by_type.get("API", {})
    data_selectors = objects_by_type.get("DataSelector", {})
    domains = objects_by_type.get("Domain", {})
    sdts = objects_by_type.get("SDT", {})
    workwith_objects = [
        *objects_by_type.get("WorkWith", {}).values(),
        *objects_by_type.get("WorkWithForWeb", {}).values(),
    ]
    transactions = objects_by_type.get("Transaction", {})
    attributes = objects_by_type.get("Attribute", {})
    tables = objects_by_type.get("Table", {})
    external_objects = objects_by_type.get("ExternalObject", {})
    objects = [obj for by_name in objects_by_type.values() for obj in by_name.values()]

    source_evidences = extract_evidence(
        source_root,
        [obj for obj in objects if obj.object_type in INDEXED_SOURCE_TYPES],
        procedure_names=set(procedures),
        webpanel_names=set(webpanels),
        data_provider_names=set(data_providers),
    )
    source_for_each_explicit_table_evidences = extract_source_for_each_explicit_table_evidence(
        [obj for obj in objects if obj.object_type in FOR_EACH_SOURCE_TYPES],
        table_names=set(tables),
    )
    source_for_each_qualified_table_prefix_evidences = extract_source_for_each_qualified_table_prefix_evidence(
        [obj for obj in objects if obj.object_type in FOR_EACH_SOURCE_TYPES],
        table_names=set(tables),
    )
    source_bc_load_transaction_evidences = extract_source_bc_load_transaction_evidence(
        [obj for obj in objects if obj.object_type in BC_LOAD_SOURCE_TYPES],
        transaction_names=set(transactions),
    )
    source_bc_save_transaction_evidences = extract_source_bc_save_transaction_evidence(
        [obj for obj in objects if obj.object_type in BC_LOAD_SOURCE_TYPES],
        transaction_names=set(transactions),
    )
    source_bc_delete_transaction_evidences = extract_source_bc_delete_transaction_evidence(
        [obj for obj in objects if obj.object_type in BC_LOAD_SOURCE_TYPES],
        transaction_names=set(transactions),
    )
    source_bc_check_transaction_evidences = extract_source_bc_check_transaction_evidence(
        [obj for obj in objects if obj.object_type in BC_LOAD_SOURCE_TYPES],
        transaction_names=set(transactions),
    )
    source_simple_bc_insert_update_transaction_evidences = (
        extract_source_simple_bc_insert_update_transaction_evidence(
            [obj for obj in objects if obj.object_type in BC_LOAD_SOURCE_TYPES],
            transaction_names=set(transactions),
        )
    )
    source_external_object_method_evidences = extract_source_external_object_method_evidence(
        [obj for obj in objects if obj.object_type in INDEXED_SOURCE_TYPES],
        external_object_names=set(external_objects),
    )
    workwith_evidences = extract_workwith_action_evidence(
        workwith_objects,
        procedure_names=set(procedures),
        webpanel_names=set(webpanels),
    )
    workwith_condition_evidences = extract_workwith_condition_evidence(
        workwith_objects,
        procedure_names=set(procedures),
    )
    workwith_condition_attribute_evidences = extract_workwith_condition_attribute_evidence(
        workwith_objects,
        procedure_names=set(procedures),
    )
    workwith_transaction_evidences = extract_workwith_transaction_evidence(
        workwith_objects,
        transaction_names=set(transactions),
    )
    workwith_webpanel_link_evidences = extract_workwith_webpanel_link_evidence(
        workwith_objects,
        webpanel_names=set(webpanels),
    )
    workwith_prompt_evidences = extract_workwith_prompt_evidence(
        workwith_objects,
        webpanel_names=set(webpanels),
    )
    workwith_for_web_attribute_evidences = extract_workwith_for_web_attribute_evidence(
        objects_by_type.get("WorkWithForWeb", {}).values(),
        attribute_names=set(attributes),
    )
    code_attribute_evidences = extract_code_attribute_evidence(
        [obj for obj in objects if obj.object_type in CODE_ATTRIBUTE_PART_NAMES],
        attribute_names=set(attributes),
        domain_names=set(domains),
        transaction_type_guid=get_transaction_type_guid(GX_TYPE_CATALOG_BY_NAME),
    )
    relation_scope_objects = [
        *procedures.values(),
        *webpanels.values(),
        *data_providers.values(),
        *apis.values(),
        *data_selectors.values(),
        *domains.values(),
        *sdts.values(),
        *workwith_objects,
        *transactions.values(),
    ]
    custom_type_evidences = extract_attcustomtype_evidence(relation_scope_objects)
    resolved_custom_type_evidences = extract_attcustomtype_resolved_evidence(
        relation_scope_objects,
        sdt_names=set(objects_by_type.get("SDT", {})),
        domain_names=set(objects_by_type.get("Domain", {})),
        external_object_names=set(external_objects),
    )
    sdt_item_attcustomtype_resolved_sdt_evidences = extract_sdt_item_attcustomtype_resolved_sdt_evidence(
        objects_by_type.get("SDT", {}).values(),
        sdt_names=set(objects_by_type.get("SDT", {})),
    )
    attribute_idbasedon_domain_evidences = extract_idbasedon_domain_evidence(
        [
            obj
            for obj in objects
            if obj.object_type in IDBASEDON_DOMAIN_SOURCE_TYPES
        ],
        domain_names=set(objects_by_type.get("Domain", {})),
        domain_fqfn_by_name={
            name.lower(): fqfn
            for (object_type, name), fqfn in collect_fully_qualified_names(
                {"Domain": objects_by_type.get("Domain", {})}
            ).items()
            if object_type == "domain"
        },
    )
    attribute_formula_call_evidences = extract_attribute_formula_call_evidence(
        attributes.values(),
        procedure_names=set(procedures),
        webpanel_names=set(webpanels),
        data_provider_names=set(data_providers),
    )
    transaction_level_attribute_evidences = extract_transaction_level_attribute_evidence(
        transactions.values(),
        attribute_names=set(attributes),
    )
    transaction_level_table_evidences = extract_transaction_level_table_evidence(
        transactions.values(),
        table_names=set(tables),
    )
    table_key_attribute_evidences = extract_table_key_attribute_evidence(
        tables.values(),
        attribute_names=set(attributes),
    )
    table_index_member_attribute_evidences = extract_table_index_member_attribute_evidence(
        tables.values(),
        attribute_names=set(attributes),
    )
    css_classes = (
        collect_legacy_theme_css_classes(objects_by_type.get("ThemeClass", {}).values())
        + collect_design_system_css_classes(
            objects_by_type.get("DesignSystem", {}).values(),
            defining_object_type="DesignSystem",
            origin="kb-authored",
            extractor_rule="design_system_scss_selector",
        )
        + collect_design_system_css_classes(
            objects_by_type.get("PackagedModule", {}).values(),
            defining_object_type="PackagedModule",
            origin="packaged-module",
            extractor_rule="packaged_module_scss_selector",
        )
    )
    css_usage_objects = [obj for obj in objects if obj.object_type in CSS_USAGE_SOURCE_TYPES]
    css_layout_usage_evidences = extract_css_layout_usage_evidence(css_usage_objects)
    css_event_usage_evidences = extract_css_event_usage_evidence(css_usage_objects)
    evidences = [
        *source_evidences,
        *source_for_each_explicit_table_evidences,
        *source_for_each_qualified_table_prefix_evidences,
        *source_bc_load_transaction_evidences,
        *source_bc_save_transaction_evidences,
        *source_bc_delete_transaction_evidences,
        *source_bc_check_transaction_evidences,
        *source_simple_bc_insert_update_transaction_evidences,
        *source_external_object_method_evidences,
        *workwith_evidences,
        *workwith_condition_evidences,
        *workwith_condition_attribute_evidences,
        *workwith_transaction_evidences,
        *workwith_webpanel_link_evidences,
        *workwith_prompt_evidences,
        *workwith_for_web_attribute_evidences,
        *code_attribute_evidences,
        *custom_type_evidences,
        *resolved_custom_type_evidences,
        *sdt_item_attcustomtype_resolved_sdt_evidences,
        *attribute_idbasedon_domain_evidences,
        *attribute_formula_call_evidences,
        *transaction_level_attribute_evidences,
        *transaction_level_table_evidences,
        *table_key_attribute_evidences,
        *table_index_member_attribute_evidences,
        *css_layout_usage_evidences,
        *css_event_usage_evidences,
    ]
    index_build_run_at = datetime.now(timezone.utc).isoformat()
    write_index(
        args.output_path.resolve(),
        source_root,
        objects,
        evidences,
        css_classes,
        index_build_run_at,
        inventory_semantics,
    )

    validation_cases_path = args.validation_cases_path.resolve() if args.validation_cases_path else None
    if validation_cases_path and not validation_cases_path.exists():
        raise SystemExit(f"ValidationCasesPath not found: {validation_cases_path}")

    report = validation_report(
        source_root,
        objects_by_type,
        evidences,
        css_classes,
        validation_cases_path,
        index_build_run_at,
        inventory_semantics,
    )
    if args.validation_report_path:
        report_path = args.validation_report_path.resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.fail_on_validation_failure:
        failed_cases = [case for case in report["cases"] if case.get("status") == "failed"]
        if failed_cases or inventory_semantics["status"] != "OK":
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
