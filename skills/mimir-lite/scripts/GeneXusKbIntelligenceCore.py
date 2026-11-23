#!/usr/bin/env python3
"""Definitions shared by the KB Intelligence engines (Build-KbIntelligenceIndex.py and
Query-KbIntelligenceIndex.py): the index schema version, the regular expressions both engines
parse the corpus with, the helpers both use, the extractor registry (EXTRACTOR_RECORDS: one record
per extractor call of the build, in call order), and the coverage tables (what the extractor reads,
by object type and extractor version) the query reports a reverse-relation answer's coverage from.
Each is defined here once; an engine imports it under the name its code uses. This module shapes
the index, so it is part of the extractor signature hash (EXTRACTOR_SIGNATURE_MODULES in
Build-KbIntelligenceIndex.py)."""

from __future__ import annotations

import re
from pathlib import Path
from typing import NamedTuple

# Version of the SQLite schema the build writes (metadata schema_version) and the query expects.
SCHEMA_VERSION = "5"

# A <Source> element and its text; a self-closing <Source/> is not one.
SOURCE_RE = re.compile(r"<Source(?:\s[^>]*)?>(?P<body>.*?)</Source>", re.IGNORECASE | re.DOTALL)
# A text that is one CDATA section, possibly surrounded by whitespace.
CDATA_RE = re.compile(r"^\s*<!\[CDATA\[(?P<body>.*)\]\]>\s*$", re.DOTALL)
# One XML attribute name="value".
ATTR_RE = re.compile(r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)="(?P<value>[^"]*)"')
# One <Property><Name>..</Name><Value>..</Value></Property> of an object's properties.
PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>(?P<name>.*?)</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
# A Transaction level and its attributes.
LEVEL_RE = re.compile(r"<Level\b(?P<attrs>[^>]*)>(?P<body>.*?)</Level>", re.IGNORECASE | re.DOTALL)
LEVEL_ATTRIBUTE_RE = re.compile(
    r"<Attribute\b(?P<attrs>[^>]*)>(?P<name>.*?)</Attribute>",
    re.IGNORECASE | re.DOTALL,
)

# A classic formula (GeneXus 7.0 and earlier, .xpw) is its own block, synced to the Formula folder
# and named after the attribute it computes: <Formula><Name>, <Type>, <Source>. Its name is XML
# text (decoded, then trimmed) and its expression is the <Source> (SOURCE_RE) inside that
# <Formula> element, between the end of CLASSIC_FORMULA_NAME_RE and CLASSIC_FORMULA_END_RE.
CLASSIC_FORMULA_FOLDER = "Formula"
CLASSIC_FORMULA_NAME_RE = re.compile(r"<Formula\b[^>]*>\s*<Name>(?P<name>[^<]*)</Name>", re.IGNORECASE)
CLASSIC_FORMULA_END_RE = re.compile(r"</Formula>", re.IGNORECASE)


def read_text(path: Path) -> str:
    """A corpus XML file as text: UTF-8, an optional BOM dropped, undecodable bytes replaced."""
    return path.read_text(encoding="utf-8-sig", errors="replace")


# The extractor registry: one record per extractor call of Build-KbIntelligenceIndex.py, in the
# order its main runs them (the order is part of the index contract until proven otherwise). The
# build keeps, under each record's name, the function, its arguments, and where its evidence goes
# among the index rows (EXTRACTOR_CALLS); to add an extractor, add its record here and its call
# there. The coverage tables below are derived from the records where the records carry the
# information that defines them (ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE).
class ExtractorRecord(NamedTuple):
    """One extractor call: what it writes and what it reads.

    rules: the extractor_rule values the call can write. first_version: the
    extractor_signature_version that first ran the call (FIRST_RECORDED_EXTRACTOR_VERSION for a
    call at least that old). source_types: the object types whose objects are the sources of its
    relations. target_types: the object types its relations point to.
    """

    name: str
    rules: tuple[str, ...]
    first_version: int
    source_types: tuple[str, ...]
    target_types: tuple[str, ...]


# The oldest extractor_signature_version the repository history records; a record with it may be
# older. Every index that has a version holds what that version extracted.
FIRST_RECORDED_EXTRACTOR_VERSION = 12

# Source types shared by several records; the build selects its objects with the same tuples.
# The Source scope: objects whose code is read for calls (Procedure, WebPanel and DataProvider
# calls, Work Panel calls, links and web components, and the prefixed calls of classic code:
# call(PAGO) is Procedure AGO) and for external object methods. Equal to INDEXED_SOURCE_TYPES of
# Build-KbIntelligenceIndex.py, which keeps it as a literal (a self-test reads it from that file).
SOURCE_SCOPE_TYPES = (
    "Procedure",
    "WebPanel",
    "DataProvider",
    "Transaction",
    "API",
    "DataSelector",
    "Report",
    "WorkPanel",
)
FOR_EACH_SOURCE_TYPES = ("Procedure", "WebPanel")
BC_LOAD_SOURCE_TYPES = ("Procedure", "WebPanel", "DataProvider")
WORKWITH_SOURCE_TYPES = ("WorkWith", "WorkWithForWeb")
# Objects whose properties can name a custom type (ATTCUSTOMTYPE).
CUSTOM_TYPE_SOURCE_TYPES = (
    "Procedure",
    "WebPanel",
    "DataProvider",
    "API",
    "DataSelector",
    "Domain",
    "SDT",
    "WorkWith",
    "WorkWithForWeb",
    "Transaction",
)
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
# Objects whose code Parts (modern) or code sections (classic) are read for attribute uses.
CODE_ATTRIBUTE_SOURCE_TYPES = ("Procedure", "WebPanel", "Transaction", "WorkPanel", "DataProvider", "Report")
# Classic objects whose code is read for the base table of a for each.
CLASSIC_CODE_SOURCE_TYPES = ("Report", "Procedure", "WebPanel", "Transaction", "WorkPanel")
CSS_USAGE_SOURCE_TYPES = ("WebPanel", "Panel", "Transaction")
CALL_TARGET_TYPES = ("Procedure", "WebPanel", "DataProvider", "WorkPanel", "Report", "Transaction")
WORKWITH_CONDITION_SUFFIXES = ("", "_dot_call", "_call_command", "_udp_func", "_dot_udp")

EXTRACTOR_RECORDS: tuple[ExtractorRecord, ...] = (
    ExtractorRecord(
        "evidence",
        (
            "procedure_dot_call",
            "workpanel_dot_call",
            "procedure_direct_call",
            "procedure_call_command",
            "workpanel_call_command",
            "procedure_udp_func",
            "procedure_dot_udp",
            "procedure_dot_link",
            "webpanel_dot_link",
            "webpanel_dot_create",
            "dataprovider_direct_call",
            "classic_call_command",
            "classic_udp_func",
            "classic_link",
        ),
        12,
        SOURCE_SCOPE_TYPES,
        CALL_TARGET_TYPES,
    ),
    ExtractorRecord(
        "source_for_each_explicit_table", ("source_for_each_explicit_table",), 12, FOR_EACH_SOURCE_TYPES, ("Table",)
    ),
    ExtractorRecord(
        "source_for_each_qualified_table_prefix",
        ("source_for_each_qualified_table_prefix",),
        12,
        FOR_EACH_SOURCE_TYPES,
        ("Table",),
    ),
    ExtractorRecord(
        "source_bc_load_transaction", ("source_bc_load_transaction",), 12, BC_LOAD_SOURCE_TYPES, ("Transaction",)
    ),
    ExtractorRecord(
        "source_bc_save_transaction", ("source_bc_save_transaction",), 12, BC_LOAD_SOURCE_TYPES, ("Transaction",)
    ),
    ExtractorRecord(
        "source_bc_delete_transaction", ("source_bc_delete_transaction",), 12, BC_LOAD_SOURCE_TYPES, ("Transaction",)
    ),
    ExtractorRecord(
        "source_bc_check_transaction", ("source_bc_check_transaction",), 12, BC_LOAD_SOURCE_TYPES, ("Transaction",)
    ),
    ExtractorRecord(
        "source_simple_bc_insert_update_transaction",
        ("source_simple_bc_insert_transaction", "source_simple_bc_update_transaction"),
        12,
        BC_LOAD_SOURCE_TYPES,
        ("Transaction",),
    ),
    ExtractorRecord(
        "source_external_object_method",
        ("source_external_object_method",),
        12,
        SOURCE_SCOPE_TYPES,
        ("ExternalObject",),
    ),
    ExtractorRecord(
        "workwith_action",
        ("workwith_action_gxobject", "workwith_action_parameter_procedure_dot_link"),
        12,
        WORKWITH_SOURCE_TYPES,
        ("Procedure", "WebPanel"),
    ),
    ExtractorRecord(
        "workwith_condition",
        tuple("workwith_condition_procedure" + suffix for suffix in WORKWITH_CONDITION_SUFFIXES),
        12,
        WORKWITH_SOURCE_TYPES,
        ("Procedure",),
    ),
    ExtractorRecord(
        "workwith_condition_attribute",
        tuple("workwith_condition_attribute_procedure" + suffix for suffix in WORKWITH_CONDITION_SUFFIXES),
        12,
        WORKWITH_SOURCE_TYPES,
        ("Procedure",),
    ),
    ExtractorRecord(
        "workwith_transaction", ("workwith_transaction_binding",), 12, WORKWITH_SOURCE_TYPES, ("Transaction",)
    ),
    ExtractorRecord("workwith_webpanel_link", ("workwith_link_webpanel",), 12, WORKWITH_SOURCE_TYPES, ("WebPanel",)),
    ExtractorRecord("workwith_prompt", ("workwith_prompt_webpanel",), 12, WORKWITH_SOURCE_TYPES, ("WebPanel",)),
    ExtractorRecord(
        "workwith_for_web_attribute",
        ("workwith_for_web_attribute_reference",),
        13,
        ("WorkWithForWeb",),
        ("Attribute",),
    ),
    ExtractorRecord("workwith_sd_attribute", ("workwith_sd_attribute_reference",), 18, ("WorkWith",), ("Attribute",)),
    ExtractorRecord("panel_attribute", ("sd_panel_attribute_reference",), 23, ("Panel",), ("Attribute",)),
    ExtractorRecord("code_attribute", ("code_attribute_reference",), 15, CODE_ATTRIBUTE_SOURCE_TYPES, ("Attribute",)),
    ExtractorRecord("attcustomtype", ("attcustomtype_property",), 12, CUSTOM_TYPE_SOURCE_TYPES, ("CustomType",)),
    ExtractorRecord(
        "attcustomtype_resolved",
        ("attcustomtype_resolved_object",),
        12,
        CUSTOM_TYPE_SOURCE_TYPES,
        ("SDT", "Domain", "ExternalObject"),
    ),
    ExtractorRecord(
        "sdt_item_attcustomtype_resolved_sdt", ("sdt_item_attcustomtype_resolved_sdt",), 12, ("SDT",), ("SDT",)
    ),
    ExtractorRecord(
        "idbasedon_domain",
        ("attribute_idbasedon_domain", "object_idbasedon_domain"),
        12,
        IDBASEDON_DOMAIN_SOURCE_TYPES,
        ("Domain",),
    ),
    ExtractorRecord(
        "classic_formula",
        ("code_attribute_reference", "classic_formula_call_command", "classic_formula_udp_func", "classic_formula_link"),
        21,
        ("Attribute",),
        ("Attribute", "Procedure"),
    ),
    ExtractorRecord("attribute_formula_attribute", ("code_attribute_reference",), 21, ("Attribute",), ("Attribute",)),
    ExtractorRecord(
        "classic_menu_option",
        ("classic_menu_option",),
        21,
        ("Menu",),
        ("Menu", "WorkPanel", "Transaction", "Report"),
    ),
    ExtractorRecord(
        "attribute_formula_call",
        (
            "attribute_formula_procedure_direct_call",
            "attribute_formula_procedure_dot_call",
            "attribute_formula_procedure_dot_link",
            "attribute_formula_procedure_call_command",
            "attribute_formula_procedure_udp_func",
            "attribute_formula_procedure_dot_udp",
            "attribute_formula_webpanel_dot_link",
            "attribute_formula_webpanel_dot_create",
            "attribute_formula_dataprovider_direct_call",
        ),
        12,
        ("Attribute",),
        ("Procedure", "WebPanel", "DataProvider"),
    ),
    ExtractorRecord(
        "transaction_level_attribute", ("transaction_level_attribute",), 12, ("Transaction",), ("Attribute",)
    ),
    ExtractorRecord("transaction_level_table", ("transaction_level_table",), 12, ("Transaction",), ("Table",)),
    ExtractorRecord("table_key_attribute", ("table_key_attribute",), 12, ("Table",), ("Attribute",)),
    ExtractorRecord("table_index_member_attribute", ("table_index_member_attribute",), 12, ("Table",), ("Attribute",)),
    ExtractorRecord(
        "classic_table_structure",
        ("classic_table_key_attribute", "classic_table_index_member_attribute"),
        22,
        ("Table",),
        ("Attribute",),
    ),
    ExtractorRecord(
        "classic_transaction_level",
        ("classic_transaction_level_attribute", "classic_transaction_level_table"),
        22,
        ("Transaction",),
        ("Attribute", "Table"),
    ),
    ExtractorRecord(
        "classic_for_each_base_table", ("classic_for_each_base_table",), 24, CLASSIC_CODE_SOURCE_TYPES, ("Table",)
    ),
    ExtractorRecord("css_layout_usage", ("css_layout_class_attribute",), 12, CSS_USAGE_SOURCE_TYPES, ("CssClass",)),
    ExtractorRecord(
        "css_event_usage",
        ("css_event_class_assignment", "css_event_class_dynamic"),
        12,
        CSS_USAGE_SOURCE_TYPES,
        ("CssClass",),
    ),
)


# Coverage tables. Query-KbIntelligenceIndex.py reports the coverage of an incoming-relation
# answer (reverse_relation_coverage) from them: the object types whose references the extractor
# does not read, reads only in part, or reads since a given extractor_signature_version.
# ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE is derived from EXTRACTOR_RECORDS. The others are
# explicit, because they record judgments the records cannot express: a type whose code an
# extractor receives but does not read (WorkWith reaches the WorkWithForWeb action extractors),
# a type added to an existing call's sources at a later version (WorkPanel, since 20), the named
# parts of a partly extracted type and the parts no version reads, and where GeneXus navigates a
# table implicitly.
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
    "WorkWith",
)
# Types whose calls an extractor version first indexed: an index built by an older extractor
# (extractor_signature_version below the value, or none) reports the type as an unextracted
# call source. A Work Panel's Rules and Events are read since 20, classic and modern.
CALL_SOURCE_TYPES_EXTRACTED_SINCE: dict[str, int] = {"WorkPanel": 20}


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
# Transaction). Since 21 the Conditions Part of a Procedure, WebPanel and WorkPanel, and the
# <Conditions> of a classic object, are read too ("condition reads": a condition only reads).
# Not read: other assignment targets (ambiguous writes, reported as reads),
# Procedure Layout and WebForm Parts, the items of an SDT-output DataProvider,
# Business Component members (&bc.Attribute) and code in a <Source> outside any <Part>. A classic
# Report (GeneXus 7.5 to 9 export) emits code_references_attribute since 19 from its
# Layout/Block/CodeBlock/Source, Rules and Events, read like a Procedure's; its layout print
# blocks are not read. A Work Panel, classic or modern, emits code_references_attribute since 20
# from its Rules and Events, read like a WebPanel's; its Windows form is not read. The mobile
# WorkWith emits workwith_references_attribute since 18 from its pattern instance: layout
# <data attribute>, order, search and break by attributes, and advanced filter attributes; grid
# conditions, rules, events and captions are not read. A Smart Devices Panel emits
# panel_references_attribute since 23 from the same pattern instance, read the same way.
PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES: dict[str, PartialAttributeUseExtraction] = {
    "DataProvider": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 15),
            ExtractedPart("rule reads", 15),
            ExtractedPart("Transaction item writes", 15),
        ),
        missing=("SDT output items", "Business Component members", "code outside a Part"),
    ),
    "Panel": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("layouts", 23),
            ExtractedPart("orders", 23),
            ExtractedPart("search", 23),
            ExtractedPart("break by", 23),
            ExtractedPart("filters", 23),
        ),
        missing=("grid conditions", "rules", "events", "captions"),
    ),
    "Procedure": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 15),
            ExtractedPart("rule reads", 15),
            ExtractedPart("block writes", 15),
            ExtractedPart("condition reads", 21),
        ),
        missing=("ambiguous writes", "layout", "Business Component members", "code outside a Part"),
    ),
    "Report": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("Source reads", 19),
            ExtractedPart("rule reads", 19),
            ExtractedPart("block writes", 19),
            ExtractedPart("condition reads", 21),
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
            ExtractedPart("condition reads", 21),
        ),
        missing=(
            "ambiguous writes",
            "WebForm bindings",
            "Business Component members",
            "code outside a Part",
        ),
    ),
    "WorkPanel": PartialAttributeUseExtraction(
        extracted=(
            ExtractedPart("rule reads", 20),
            ExtractedPart("event reads", 20),
            ExtractedPart("block writes", 20),
            ExtractedPart("condition reads", 21),
        ),
        missing=(
            "ambiguous writes",
            "Windows form bindings",
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
# of them. Besides workwith_references_attribute (WorkWithForWeb, WorkWith),
# panel_references_attribute (Panel, since 23) and
# code_references_attribute (Procedure, WebPanel, Transaction, DataProvider, Report, WorkPanel, and
# since 21 Attribute, from its formula: ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE), see
# PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES, the relations that target an Attribute are
# structural: has_level_attribute (Transaction levels), has_key_attribute and
# has_index_member_attribute (Table keys and indexes). Chosen from the object type catalog: the
# rest of the Source scope (INDEXED_SOURCE_TYPES: API, DataSelector), SDT
# (items based on an attribute), DataView and Query (attribute lists), the web pattern
# WorkWithPlusInstance (grid, filter, order and view attributes), and every type of
# UNEXTRACTED_CALL_SOURCE_TYPES that is not partly extracted for attribute uses (the mobile
# WorkWith and the Panel are). Table is left out: its attributes come from Transaction levels and its keys and
# indexes are extracted. Every UNEXTRACTED_CALL_SOURCE_TYPES type must be here or in
# PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES, and the two stay disjoint (checked by
# tests/mimir-lite/Test-KbIntelligenceReverseCoverageSelfTest.ps1).
UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES = tuple(
    sorted(
        (
            set(UNEXTRACTED_CALL_SOURCE_TYPES)
            | {
                "API",
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


def attribute_use_source_types_extracted_since(
    records: tuple[ExtractorRecord, ...],
    partially_extracted: dict[str, PartialAttributeUseExtraction],
) -> dict[str, int]:
    """Types whose attribute uses an extractor version first indexed in full, from the records.

    For each source type of a record whose relations target an Attribute, the first version of
    those records. A partly extracted type is left out (its parts carry their own versions), and
    so is a type read since FIRST_RECORDED_EXTRACTOR_VERSION, which every versioned index holds.
    """
    first: dict[str, int] = {}
    for record in records:
        if "Attribute" not in record.target_types:
            continue
        for object_type in record.source_types:
            first[object_type] = min(first.get(object_type, record.first_version), record.first_version)
    return {
        object_type: version
        for object_type, version in sorted(first.items())
        if object_type not in partially_extracted and version > FIRST_RECORDED_EXTRACTOR_VERSION
    }


# Types whose attribute uses an extractor version first indexed in full: an index built by an
# older extractor (extractor_signature_version below the value, or none) reports the type as not
# extracted for attribute uses. Derived from EXTRACTOR_RECORDS: an Attribute's formula (the modern
# Formula property and the classic Formula block named after it) is read since 21.
ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE: dict[str, int] = attribute_use_source_types_extracted_since(
    EXTRACTOR_RECORDS, PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES
)
# Types whose objects can navigate a table with no extracted relation: a grid or form (Web Panel,
# Work Panel, Transaction, the Work With and Smart Devices Panel patterns) navigates the table of
# its attributes, and a for each or Data Provider group that names no table navigates the base
# table GeneXus infers (a modern one is never related; a classic for each is related only when one
# table fits, see navigates_inferred_table). The index relates a table only to the for each blocks
# that name it or its prefix, to inferred classic base tables, and to Transaction levels.
IMPLICIT_TABLE_NAVIGATION_SOURCE_TYPES = (
    "DataProvider",
    "Panel",
    "Procedure",
    "Report",
    "Transaction",
    "WebPanel",
    "WorkPanel",
    "WorkWith",
    "WorkWithForWeb",
)
