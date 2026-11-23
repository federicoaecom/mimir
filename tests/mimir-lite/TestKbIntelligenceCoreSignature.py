#!/usr/bin/env python3
"""Shared engine core and the extractor signature that covers it.

GeneXusKbIntelligenceCore.py holds the schema version, the regular expressions, and the helpers
that Build-KbIntelligenceIndex.py and Query-KbIntelligenceIndex.py share, and the query's coverage
tables, so neither engine keeps its own copy. The extractor signature hash covers every module that shapes the index, in a fixed
order, and the Python (compute_extractor_signature_hash) and PowerShell
(GeneXusKbIntelligenceExtractorContract.ps1) implementations agree: an edit to any of those
modules changes both, and the freshness check then rejects an index built before the edit.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import ast  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
import sqlite3  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402

from _engine_loader import SCRIPT_DIR, load_build_module, load_query_module  # noqa: E402

BUILD = load_build_module()
QUERY = load_query_module()

import GeneXusKbIntelligenceCore as CORE  # noqa: E402
import GeneXusTransactionWritabilityCore as WRITABILITY  # noqa: E402

SIGNATURE_MODULES = (
    "Build-KbIntelligenceIndex.py",
    "GeneXusKbIntelligenceCore.py",
    "GeneXusObjectTypeCatalogCore.py",
    "GeneXusTransactionWritabilityCore.py",
)

# Prints the expected signature of the contract at -ContractPath and the reason the freshness
# check gives for the stored -StoredVersion/-StoredHash, as one JSON line.
SIGNATURE_PROBE_PS1 = """
param([string]$ContractPath, [string]$StoredVersion, [string]$StoredHash)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. $ContractPath
$expected = Get-GeneXusKbIntelligenceExpectedExtractorSignature
$check = Test-GeneXusKbIntelligenceExtractorSignatureFromMetadata -Metadata @{
    extractor_signature_version = $StoredVersion
    extractor_signature_hash    = $StoredHash
}
[ordered]@{
    version = $expected.extractor_signature_version
    hash    = $expected.extractor_signature_hash
    ok      = $check.ok
    reason  = $check.reason
} | ConvertTo-Json -Compress
"""


# The coverage tables of the query engine, held as data by the core.
COVERAGE_TABLES = (
    "UNEXTRACTED_CALL_SOURCE_TYPES",
    "CALL_SOURCE_TYPES_EXTRACTED_SINCE",
    "PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES",
    "UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES",
    "ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE",
    "IMPLICIT_TABLE_NAVIGATION_SOURCE_TYPES",
)


def module_level_names(source: str) -> set:
    """Names a module assigns or defines at its top level (imports excluded)."""
    names = set()
    for node in ast.parse(source).body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            names.update(target.id for target in node.targets if isinstance(target, ast.Name))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
    return names


class SharedCoreTests(unittest.TestCase):
    def test_both_engines_use_the_core_definitions(self) -> None:
        shared = (
            "SOURCE_RE",
            "CDATA_RE",
            "ATTR_RE",
            "LEVEL_RE",
            "LEVEL_ATTRIBUTE_RE",
            "CLASSIC_FORMULA_FOLDER",
            "CLASSIC_FORMULA_NAME_RE",
            "CLASSIC_FORMULA_END_RE",
        )
        for name in shared:
            with self.subTest(name=name):
                self.assertIs(getattr(BUILD, name), getattr(CORE, name))
        self.assertIs(BUILD.CLASSIC_FORMULA_SOURCE_RE, CORE.SOURCE_RE)
        self.assertIs(BUILD.OBJECT_MARKER_PROPERTY_RE, CORE.PROPERTY_RE)
        self.assertIs(BUILD.read_text, CORE.read_text)
        self.assertEqual(BUILD.SCHEMA_VERSION, "5")
        self.assertIs(BUILD.SCHEMA_VERSION, CORE.SCHEMA_VERSION)
        # The query keeps the names its code uses.
        for query_name, core_name in (
            ("LEVEL_RE", "LEVEL_RE"),
            ("LEVEL_ATTRIBUTE_RE", "LEVEL_ATTRIBUTE_RE"),
            ("XML_ATTR_RE", "ATTR_RE"),
            ("PROPERTY_RE", "PROPERTY_RE"),
            ("CLASSIC_CDATA_RE", "CDATA_RE"),
            ("CLASSIC_FORMULA_FOLDER", "CLASSIC_FORMULA_FOLDER"),
            ("CLASSIC_FORMULA_NAME_RE", "CLASSIC_FORMULA_NAME_RE"),
            ("CLASSIC_FORMULA_END_RE", "CLASSIC_FORMULA_END_RE"),
            ("CLASSIC_FORMULA_SOURCE_RE", "SOURCE_RE"),
            ("EXPECTED_SCHEMA_VERSION", "SCHEMA_VERSION"),
        ):
            with self.subTest(query_name=query_name):
                self.assertIs(getattr(QUERY, query_name), getattr(CORE, core_name))
        self.assertIs(WRITABILITY.read_text, CORE.read_text)

    def test_the_coverage_tables_are_core_data(self) -> None:
        # The query reports reverse-relation coverage from tables the core holds; it defines none.
        for name in COVERAGE_TABLES:
            with self.subTest(name=name):
                self.assertIs(getattr(QUERY, name), getattr(CORE, name))
        query_source = (SCRIPT_DIR / "Query-KbIntelligenceIndex.py").read_text(encoding="utf-8")
        defined = module_level_names(query_source)
        for name in COVERAGE_TABLES + ("ExtractedPart", "PartialAttributeUseExtraction"):
            with self.subTest(defined_in_query=name):
                self.assertNotIn(name, defined)
        self.assertEqual(CORE.CALL_SOURCE_TYPES_EXTRACTED_SINCE, {"WorkPanel": 20})
        self.assertEqual(CORE.ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE, {"Attribute": 21})

    def test_query_skips_an_empty_self_closing_source(self) -> None:
        root = Path(tempfile.mkdtemp(prefix="kb-core-source-"))
        try:
            (root / "Formula").mkdir()
            # write_bytes keeps LF on every OS; Path.write_text(newline=...) needs Python 3.10.
            (root / "Formula" / "Total.xml").write_bytes(
                (
                    "<Formula><Name>Total</Name><Source/><Type>SUM</Type>"
                    "<Source><![CDATA[Amount]]></Source></Formula>\n"
                ).encode("utf-8")
            )
            conn = sqlite3.connect(":memory:")
            try:
                conn.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
                conn.execute("INSERT INTO metadata VALUES ('source_root', ?)", (str(root.resolve()),))
                self.assertEqual(QUERY.classic_formula_expression(conn, "Total"), "sum(Amount)")
            finally:
                conn.close()
        finally:
            shutil.rmtree(root, ignore_errors=True)


class ExtractorSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pwsh = shutil.which("pwsh")
        cls.temp = Path(tempfile.mkdtemp(prefix="kb-core-signature-"))
        cls.scripts = cls.temp / "scripts"
        shutil.copytree(SCRIPT_DIR, cls.scripts, ignore=shutil.ignore_patterns("__pycache__"))
        cls.probe = cls.temp / "probe.ps1"
        cls.probe.write_bytes(SIGNATURE_PROBE_PS1.encode("utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.temp, ignore_errors=True)

    def powershell(self, stored_version: str = "", stored_hash: str = "", scripts: "Path | None" = None) -> dict:
        if not self.pwsh:
            self.skipTest("pwsh not found")
        completed = subprocess.run(
            [
                self.pwsh, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(self.probe),
                "-ContractPath", str((scripts or self.scripts) / "GeneXusKbIntelligenceExtractorContract.ps1"),
                "-StoredVersion", stored_version, "-StoredHash", stored_hash,
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout.strip().splitlines()[-1])

    def python_hash(self) -> str:
        return BUILD.compute_extractor_signature_hash(self.scripts)

    def test_module_list_and_order(self) -> None:
        self.assertEqual(tuple(BUILD.EXTRACTOR_SIGNATURE_MODULES), SIGNATURE_MODULES)

    def test_copy_has_the_same_signature_in_both_languages(self) -> None:
        python_hash = self.python_hash()
        self.assertEqual(python_hash, BUILD.compute_extractor_signature_hash())
        self.assertEqual(python_hash, BUILD.compute_extractor_signature_hash(SCRIPT_DIR))
        result = self.powershell(BUILD.EXTRACTOR_SIGNATURE_VERSION, python_hash)
        self.assertEqual(result["hash"], python_hash)
        self.assertEqual(result["version"], BUILD.EXTRACTOR_SIGNATURE_VERSION)
        self.assertTrue(result["ok"])

    def test_an_edit_to_any_module_changes_both_and_rejects_an_older_index(self) -> None:
        original_hash = self.python_hash()
        for module in SIGNATURE_MODULES:
            with self.subTest(module=module):
                path = self.scripts / module
                original = path.read_bytes()
                try:
                    path.write_bytes(original + b"\n# edited copy\n")
                    edited_hash = self.python_hash()
                    self.assertNotEqual(edited_hash, original_hash)
                    result = self.powershell(BUILD.EXTRACTOR_SIGNATURE_VERSION, original_hash)
                    self.assertEqual(result["hash"], edited_hash)
                    self.assertFalse(result["ok"])
                    self.assertEqual(result["reason"], "extrator_hash_defasado")
                finally:
                    path.write_bytes(original)
        self.assertEqual(self.python_hash(), original_hash)

    def test_both_languages_hash_the_same_bytes_whatever_the_path_and_line_endings(self) -> None:
        # Both sides must hash raw bytes: a path with spaces and non-ASCII characters, a module with
        # CRLF line endings and one with a UTF-8 BOM must still give one shared signature.
        odd = self.temp / ("dir with spaces " + chr(0xF1) + "and" + chr(0xFA)) / "scripts"
        shutil.copytree(self.scripts, odd)
        core = odd / SIGNATURE_MODULES[1]
        core.write_bytes(core.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        catalog = odd / SIGNATURE_MODULES[2]
        catalog.write_bytes(b"\xef\xbb\xbf" + catalog.read_bytes())
        python_hash = BUILD.compute_extractor_signature_hash(odd)
        self.assertNotEqual(python_hash, self.python_hash(), "changed bytes must change the signature")
        result = self.powershell(BUILD.EXTRACTOR_SIGNATURE_VERSION, python_hash, scripts=odd)
        self.assertEqual(result["hash"], python_hash)
        self.assertTrue(result["ok"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
