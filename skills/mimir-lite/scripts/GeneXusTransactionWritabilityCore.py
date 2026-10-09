#!/usr/bin/env python3
"""Canonical Transaction attribute writability classification for KbIntelligence (imported by Build-KbIntelligenceIndex.py)."""

from __future__ import annotations

import functools
import os
import re
from dataclasses import dataclass
from pathlib import Path

WRITABILITY_RULE_VERSION = "1"

LEVEL_OPEN_RE = re.compile(
    r'<Level\s+[^>]*name="(?P<name>[^"]+)"[^>]*>',
    re.IGNORECASE,
)
ATTRIBUTE_RE = re.compile(
    r"<Attribute\s+(?P<attrs>[^>]*?)>(?P<name>[^<]+)</Attribute>",
    re.IGNORECASE,
)
KEY_ATTR_RE = re.compile(r'\bkey\s*=\s*"(?P<v>[^"]*)"', re.IGNORECASE)
IS_REDUNDANT_RE = re.compile(r'\bisRedundant\s*=\s*"(?P<v>[^"]*)"', re.IGNORECASE)
FORMULA_PROPERTY_RE = re.compile(
    r"<Property>\s*<Name>Formula</Name>\s*<Value>(?P<v>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)
SUBTYPE_BLOCK_RE = re.compile(
    r"<Subtype\b[^>]*>\s*<Name>(?P<sub>[^<]+)</Name>\s*<Supertype\b[^>]*>(?P<sup>[^<]+)</Supertype>\s*</Subtype>",
    re.IGNORECASE | re.DOTALL,
)
DUPLICATE_INDEX_RE = re.compile(
    r'<Index\b[^>]*\bType\s*=\s*"Duplicate"[^>]*>(?P<body>.*?)</Index>',
    re.IGNORECASE | re.DOTALL,
)
MEMBER_RE = re.compile(r"<Member\b[^>]*>(?P<n>[^<]+)</Member>", re.IGNORECASE)
OBJECT_TYPE_GUID_RE = re.compile(r'<Object\b[^>]*\btype="([^"]+)"', re.IGNORECASE)
OBJECT_NAME_ATTR_RE = re.compile(r'<Object\b[^>]*\bname="(?P<name>[^"]+)"', re.IGNORECASE)
OBJECT_LEVEL_PROPERTIES_RE = re.compile(
    r"</Part>\s*<Properties>(?P<body>.*?)</Properties>\s*</Object>",
    re.IGNORECASE | re.DOTALL,
)
TRANSACTION_NAME_RE = re.compile(
    r"<Property>\s*<Name>Name</Name>\s*<Value>(?P<value>.*?)</Value>\s*</Property>",
    re.IGNORECASE | re.DOTALL,
)


@dataclass(frozen=True)
class LevelAttributeRef:
    level_name: str
    attribute_name: str
    key: bool
    is_redundant: bool


@dataclass(frozen=True)
class AttributeWritability:
    transaction_name: str
    level_name: str
    attribute_name: str
    key: bool
    is_redundant: bool
    classification: str
    writable: bool | None
    can_assign_in_new: bool | None
    reason: str
    evidence: str


@dataclass
class _TransactionLevelEntry:
    name: str
    pk_attrs: list[str]
    non_key_attrs: set[str]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="replace")


def get_transaction_type_guid(catalog_types: dict[str, dict[str, object]]) -> str:
    entry = catalog_types.get("Transaction", {})
    guid = entry.get("objectTypeGuid")
    if not isinstance(guid, str) or not guid:
        raise ValueError("Transaction objectTypeGuid missing in catalog")
    return guid


def resolve_transaction_name(text: str, fallback: str) -> str:
    """Read the name from Object/Properties/Property Name, not from nested Variable names."""
    props_match = OBJECT_LEVEL_PROPERTIES_RE.search(text)
    if props_match:
        name_match = TRANSACTION_NAME_RE.search(props_match.group("body"))
        if name_match:
            value = name_match.group("value").strip()
            if value:
                return value
    object_name_match = OBJECT_NAME_ATTR_RE.search(text)
    if object_name_match:
        value = object_name_match.group("name").strip()
        if value:
            return value
    return fallback


def get_transaction_metadata(path: Path, transaction_type_guid: str) -> tuple[str, str] | None:
    text = read_text(path)
    type_match = OBJECT_TYPE_GUID_RE.search(text)
    if not type_match or type_match.group(1) != transaction_type_guid:
        return None
    name = resolve_transaction_name(text, path.stem)
    return name, text


def get_levels_and_attributes(transaction_xml: str) -> list[LevelAttributeRef]:
    results: list[LevelAttributeRef] = []
    level_matches = list(LEVEL_OPEN_RE.finditer(transaction_xml))
    if not level_matches:
        return results
    for index, level_match in enumerate(level_matches):
        start = level_match.end()
        end = level_matches[index + 1].start() if index + 1 < len(level_matches) else len(transaction_xml)
        chunk = transaction_xml[start:end]
        level_name = level_match.group("name")
        for attr_match in ATTRIBUTE_RE.finditer(chunk):
            attrs_str = attr_match.group("attrs")
            name = attr_match.group("name").strip()
            if not name:
                continue
            key_match = KEY_ATTR_RE.search(attrs_str)
            key = bool(key_match and key_match.group("v") == "True")
            red_match = IS_REDUNDANT_RE.search(attrs_str)
            is_redundant = bool(red_match and red_match.group("v") == "True")
            results.append(
                LevelAttributeRef(
                    level_name=level_name,
                    attribute_name=name,
                    key=key,
                    is_redundant=is_redundant,
                )
            )
    return results


def build_subtype_index(corpus_folder: Path) -> dict[str, str]:
    index: dict[str, str] = {}
    folder = corpus_folder / "SubTypeGroup"
    if not folder.is_dir():
        return index
    for path in folder.glob("*.xml"):
        text = read_text(path)
        for match in SUBTYPE_BLOCK_RE.finditer(text):
            sub_name = match.group("sub").strip()
            sup_name = match.group("sup").strip()
            if sub_name and sup_name:
                index.setdefault(sub_name.lower(), sup_name)
    return index


def first_level_attributes(transaction_xml: str) -> list[LevelAttributeRef]:
    """Attributes of the first Level only."""
    level_matches = list(LEVEL_OPEN_RE.finditer(transaction_xml))
    if not level_matches:
        return []
    first = level_matches[0]
    start = first.end()
    end = level_matches[1].start() if len(level_matches) > 1 else len(transaction_xml)
    chunk = transaction_xml[start:end]
    results: list[LevelAttributeRef] = []
    level_name = first.group("name")
    for attr_match in ATTRIBUTE_RE.finditer(chunk):
        attrs_str = attr_match.group("attrs")
        name = attr_match.group("name").strip()
        if not name:
            continue
        key_match = KEY_ATTR_RE.search(attrs_str)
        key = bool(key_match and key_match.group("v") == "True")
        red_match = IS_REDUNDANT_RE.search(attrs_str)
        is_redundant = bool(red_match and red_match.group("v") == "True")
        results.append(
            LevelAttributeRef(
                level_name=level_name,
                attribute_name=name,
                key=key,
                is_redundant=is_redundant,
            )
        )
    return results


def build_transaction_level_index(corpus_folder: Path, transaction_type_guid: str) -> dict[str, _TransactionLevelEntry]:
    index: dict[str, _TransactionLevelEntry] = {}
    folder = corpus_folder / "Transaction"
    if not folder.is_dir():
        return index
    for path in folder.glob("*.xml"):
        meta = get_transaction_metadata(path, transaction_type_guid)
        if meta is None:
            continue
        tx_name, text = meta
        level_attrs = first_level_attributes(text)
        pk_attrs: list[str] = []
        non_key_attrs: set[str] = set()
        for la in level_attrs:
            if la.key:
                pk_attrs.append(la.attribute_name)
            else:
                non_key_attrs.add(la.attribute_name)
        index[tx_name.lower()] = _TransactionLevelEntry(name=tx_name, pk_attrs=pk_attrs, non_key_attrs=non_key_attrs)
    return index


def build_primary_key_attribute_set(corpus_folder: Path, transaction_type_guid: str) -> set[str]:
    pk_set: set[str] = set()
    folder = corpus_folder / "Transaction"
    if not folder.is_dir():
        return pk_set
    for path in folder.glob("*.xml"):
        meta = get_transaction_metadata(path, transaction_type_guid)
        if meta is None:
            continue
        _, text = meta
        for la in get_levels_and_attributes(text):
            if la.key:
                pk_set.add(la.attribute_name)
    return pk_set


@functools.lru_cache(maxsize=64)
def _file_names_by_lower_name(folder: str, folder_mtime_ns: int) -> dict[str, tuple[str, ...]]:
    # Keyed by the folder's mtime so that a listing is rebuilt when files are added or removed.
    names: dict[str, list[str]] = {}
    with os.scandir(folder) as entries:
        for entry in entries:
            if entry.is_file():
                names.setdefault(entry.name.lower(), []).append(entry.name)
    return {key: tuple(sorted(value)) for key, value in names.items()}


def _find_corpus_xml_path(corpus_folder: Path, folder_type: str, object_name: str) -> Path | None:
    """Corpus file of a GeneXus object, matching the file name case-insensitively.

    GeneXus names are case-insensitive, and a reference can differ in case from the object's own
    file name. The exact path is tried first, so a case-insensitive file system (Windows) behaves as
    before; otherwise a single case-insensitive match is used. Two files that differ only in case
    (possible on a case-sensitive file system only) are ambiguous and give None.
    """
    folder = corpus_folder / folder_type
    candidate = folder / f"{object_name}.xml"
    if candidate.is_file():
        return candidate
    try:
        folder_mtime_ns = folder.stat().st_mtime_ns
    except OSError:
        return None
    if not folder.is_dir():
        return None
    matches = _file_names_by_lower_name(str(folder), folder_mtime_ns).get(candidate.name.lower(), ())
    return folder / matches[0] if len(matches) == 1 else None


def find_attribute_xml_path(attribute_name: str, corpus_folder: Path) -> Path | None:
    return _find_corpus_xml_path(corpus_folder, "Attribute", attribute_name)


def attribute_has_formula(attribute_xml_path: Path) -> bool:
    return bool(FORMULA_PROPERTY_RE.search(read_text(attribute_xml_path)))


def find_table_xml_path(transaction_name: str, corpus_folder: Path) -> Path | None:
    return _find_corpus_xml_path(corpus_folder, "Table", transaction_name)


def get_duplicate_indexes_from_table(table_xml_path: Path) -> list[list[str]]:
    text = read_text(table_xml_path)
    result: list[list[str]] = []
    for idx_match in DUPLICATE_INDEX_RE.finditer(text):
        members = [member_match.group("n").strip() for member_match in MEMBER_RE.finditer(idx_match.group("body"))]
        members = [member for member in members if member]
        if members:
            result.append(members)
    return result


def find_fk_entity_for_index(
    members: list[str],
    transaction_level_index: dict[str, _TransactionLevelEntry],
) -> _TransactionLevelEntry | None:
    for entry in transaction_level_index.values():
        pk = entry.pk_attrs
        if len(pk) != len(members):
            continue
        if all(pk[i].lower() == members[i].lower() for i in range(len(pk))):
            return entry
    return None


def attribute_in_fk_entity_recursive(
    attribute_name: str,
    table_xml_path: Path,
    transaction_level_index: dict[str, _TransactionLevelEntry],
    corpus_folder: Path,
    max_depth: int,
    visited_tables: set[str],
) -> bool:
    if max_depth <= 0:
        return False
    table_key = str(table_xml_path.resolve()).lower()
    if table_key in visited_tables:
        return False
    visited_tables.add(table_key)
    for members in get_duplicate_indexes_from_table(table_xml_path):
        fk_entity = find_fk_entity_for_index(members, transaction_level_index)
        if fk_entity is None:
            continue
        if attribute_name.lower() in {name.lower() for name in fk_entity.non_key_attrs}:
            return True
        fk_table_path = find_table_xml_path(fk_entity.name, corpus_folder)
        if fk_table_path is None:
            continue
        if attribute_in_fk_entity_recursive(
            attribute_name,
            fk_table_path,
            transaction_level_index,
            corpus_folder,
            max_depth - 1,
            visited_tables,
        ):
            return True
    return False


def classify_transaction_attributes(
    transaction_path: Path,
    corpus_folder: Path,
    transaction_type_guid: str,
    *,
    subtype_index: dict[str, str] | None = None,
    pk_attr_set: set[str] | None = None,
    transaction_level_index: dict[str, _TransactionLevelEntry] | None = None,
) -> list[AttributeWritability]:
    meta = get_transaction_metadata(transaction_path, transaction_type_guid)
    if meta is None:
        raise ValueError(f"Not a Transaction XML: {transaction_path}")
    tx_name, tx_text = meta
    level_attrs = get_levels_and_attributes(tx_text)

    if subtype_index is None:
        subtype_index = build_subtype_index(corpus_folder)
    if pk_attr_set is None:
        pk_attr_set = build_primary_key_attribute_set(corpus_folder, transaction_type_guid)
    if transaction_level_index is None:
        transaction_level_index = build_transaction_level_index(corpus_folder, transaction_type_guid)

    table_xml_path = find_table_xml_path(tx_name, corpus_folder)
    dup_indexes = get_duplicate_indexes_from_table(table_xml_path) if table_xml_path else []

    results: list[AttributeWritability] = []
    for la in level_attrs:
        if la.key:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=True,
                    is_redundant=la.is_redundant,
                    classification="key-attribute",
                    writable=True,
                    can_assign_in_new=True,
                    reason="key-attribute",
                    evidence=f'key="True" no Level \'{la.level_name}\'',
                )
            )
            continue
        if la.is_redundant:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=True,
                    classification="extended-parent-fk",
                    writable=False,
                    can_assign_in_new=False,
                    reason="extended-parent-fk",
                    evidence=f'isRedundant="True" no Level \'{la.level_name}\'',
                )
            )
            continue
        attr_path = find_attribute_xml_path(la.attribute_name, corpus_folder)
        if attr_path is None:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=False,
                    classification="unclassified-attribute-not-found",
                    writable=None,
                    can_assign_in_new=None,
                    reason="unclassified-attribute-not-found",
                    evidence=f"Attribute XML '{la.attribute_name}.xml' not found in CorpusFolder/Attribute/",
                )
            )
            continue
        if attribute_has_formula(attr_path):
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=False,
                    classification="formula",
                    writable=False,
                    can_assign_in_new=False,
                    reason="formula",
                    evidence=f"Property Formula present in {attr_path}",
                )
            )
            continue
        subtype_key = la.attribute_name.lower()
        if subtype_key in subtype_index:
            supertype_name = subtype_index[subtype_key]
            if supertype_name in pk_attr_set:
                results.append(
                    AttributeWritability(
                        transaction_name=tx_name,
                        level_name=la.level_name,
                        attribute_name=la.attribute_name,
                        key=False,
                        is_redundant=False,
                        classification="extended-subtype-key",
                        writable=True,
                        can_assign_in_new=True,
                        reason="extended-subtype-key",
                        evidence=(
                            f"member of SubTypeGroup with Supertype '{supertype_name}' "
                            "which is PK in some Transaction"
                        ),
                    )
                )
            else:
                results.append(
                    AttributeWritability(
                        transaction_name=tx_name,
                        level_name=la.level_name,
                        attribute_name=la.attribute_name,
                        key=False,
                        is_redundant=False,
                        classification="extended-subtype-descriptive",
                        writable=False,
                        can_assign_in_new=False,
                        reason="extended-subtype-descriptive",
                        evidence=(
                            f"member of SubTypeGroup with Supertype '{supertype_name}' "
                            "which is not PK in any Transaction"
                        ),
                    )
                )
            continue
        if table_xml_path is None:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=False,
                    classification="unclassified-table-not-found",
                    writable=None,
                    can_assign_in_new=None,
                    reason="unclassified-table-not-found",
                    evidence=(
                        f"Corresponding Table XML ('{tx_name}.xml') not found in "
                        "CorpusFolder/Table/; signals 5/6/7 cannot be evaluated"
                    ),
                )
            )
            continue
        found_in_duplicate = any(
            la.attribute_name.lower() == member.lower()
            for dup in dup_indexes
            for member in dup
        )
        if found_in_duplicate:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=False,
                    classification="extended-fk-key",
                    writable=True,
                    can_assign_in_new=True,
                    reason="extended-fk-key",
                    evidence=(
                        f"attribute appears as a Member in a Duplicate index of Table '{tx_name}'; "
                        "FK column stored in this table"
                    ),
                )
            )
            continue
        visited_tables: set[str] = set()
        is_fk_descriptive = attribute_in_fk_entity_recursive(
            la.attribute_name,
            table_xml_path,
            transaction_level_index,
            corpus_folder,
            10,
            visited_tables,
        )
        if is_fk_descriptive:
            results.append(
                AttributeWritability(
                    transaction_name=tx_name,
                    level_name=la.level_name,
                    attribute_name=la.attribute_name,
                    key=False,
                    is_redundant=False,
                    classification="extended-fk-descriptive",
                    writable=False,
                    can_assign_in_new=False,
                    reason="extended-fk-descriptive",
                    evidence=(
                        f"attribute appears as key=False in some FK entity (recursive resolution "
                        f"up to depth 10 starting from Table '{tx_name}')"
                    ),
                )
            )
            continue
        results.append(
            AttributeWritability(
                transaction_name=tx_name,
                level_name=la.level_name,
                attribute_name=la.attribute_name,
                key=False,
                is_redundant=False,
                classification="own-physical",
                writable=True,
                can_assign_in_new=True,
                reason="own-physical",
                evidence=(
                    "attribute absent from FK entities at every explored depth (max 10); "
                    "own to the physical table of this Transaction"
                ),
            )
        )
    return results


def build_corpus_writability(
    corpus_folder: Path,
    transaction_type_guid: str,
) -> list[AttributeWritability]:
    subtype_index = build_subtype_index(corpus_folder)
    pk_attr_set = build_primary_key_attribute_set(corpus_folder, transaction_type_guid)
    transaction_level_index = build_transaction_level_index(corpus_folder, transaction_type_guid)
    rows: list[AttributeWritability] = []
    tx_folder = corpus_folder / "Transaction"
    if not tx_folder.is_dir():
        return rows
    for path in sorted(tx_folder.glob("*.xml")):
        if get_transaction_metadata(path, transaction_type_guid) is None:
            continue
        rows.extend(
            classify_transaction_attributes(
                path,
                corpus_folder,
                transaction_type_guid,
                subtype_index=subtype_index,
                pk_attr_set=pk_attr_set,
                transaction_level_index=transaction_level_index,
            )
        )
    return rows
