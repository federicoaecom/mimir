#!/usr/bin/env python3
"""Build and query read a classic Formula file the same way.

The build (extract_classic_formula_evidence) and the query (classic_formula_expression behind
attribute-info) each parse Formula/<name>.xml with their own regular expressions. Both must
agree on which attribute the formula computes (its <Formula><Name>, XML text: surrounding
whitespace ignored, character references decoded) and on its expression (the <Source> child of
that <Formula> element, never a <Source> elsewhere in the file). Each case asserts both sides.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import shutil  # noqa: E402
import sqlite3  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402

from _engine_loader import load_build_module, load_query_module  # noqa: E402

BUILD = load_build_module()
QUERY = load_query_module()

ATTRIBUTES = ("PaddedTotal", "OrphanTotal", "EncodedTotal", "NestedTotal", "LineAmount", "OtherAmount")


def formula_file(name_xml: str, payload: str) -> str:
    return (
        '<Object type="gxlegacy/Formula" name="F" guid="" '
        'lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">\n'
        "  <GxLegacyPayload>\n"
        f"<Formula><Name>{name_xml}</Name>{payload}\n"
        "  </GxLegacyPayload>\n"
        "</Object>\n"
    )


class ClassicFormulaBuildQueryParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="kb-formula-drift-"))
        folder = cls.root / "Formula"
        folder.mkdir()
        files = {
            # Name with surrounding whitespace and a line break.
            "PaddedTotal": formula_file(
                "  PaddedTotal\n ", "<Type></Type><Source><![CDATA[LineAmount]]></Source></Formula>"
            ),
            # No <Source> in the <Formula>; a <Source> after the element is not its expression.
            "OrphanTotal": formula_file(
                "OrphanTotal", "<Type>SUM</Type></Formula>\n<Note><Source>OtherAmount</Source></Note>"
            ),
            # Name written with a character reference: E is &#69;.
            "EncodedTotal": formula_file(
                "&#69;ncodedTotal", "<Type>SUM</Type><Source>LineAmount</Source></Formula>"
            ),
            # An empty, self-closing <Source/> followed by a nested <Source> inside the element.
            "NestedTotal": formula_file(
                "NestedTotal", "<Type></Type><Source/><Note><Source>LineAmount</Source></Note></Formula>"
            ),
        }
        for name, text in files.items():
            # write_bytes keeps LF on every OS; Path.write_text(newline=...) needs Python 3.10.
            (folder / f"{name}.xml").write_bytes(text.encode("utf-8"))
        cls.attributes = {
            name: BUILD.ObjectInfo(
                object_type="Attribute",
                name=name,
                guid=None,
                path=cls.root / "Attribute" / f"{name}.xml",
                rel_path=f"Attribute/{name}.xml",
                last_update=None,
                file_hash="",
                is_generated_object=0,
                pattern_object_id=None,
                instance_key=None,
            )
            for name in ATTRIBUTES
        }
        cls.evidences = BUILD.extract_classic_formula_evidence(cls.root, cls.attributes, set(), set())
        cls.conn = sqlite3.connect(":memory:")
        cls.conn.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
        cls.conn.execute("INSERT INTO metadata VALUES ('source_root', ?)", (str(cls.root.resolve()),))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.conn.close()
        shutil.rmtree(cls.root, ignore_errors=True)

    def build_reads(self, attribute: str) -> set:
        """Attributes the build says the formula of `attribute` reads."""
        return {
            evidence.target_name
            for evidence in self.evidences
            if evidence.source_name == attribute and evidence.evidence_role == "Formula read"
        }

    def query_expression(self, attribute: str):
        return QUERY.classic_formula_expression(self.conn, attribute)

    def test_name_with_surrounding_whitespace(self) -> None:
        self.assertEqual(self.build_reads("PaddedTotal"), {"LineAmount"})
        self.assertEqual(self.query_expression("PaddedTotal"), "LineAmount")

    def test_source_outside_the_formula_element_is_not_its_expression(self) -> None:
        self.assertIsNone(self.query_expression("OrphanTotal"))
        self.assertEqual(self.build_reads("OrphanTotal"), set())

    def test_name_with_a_character_reference(self) -> None:
        self.assertEqual(self.query_expression("EncodedTotal"), "sum(LineAmount)")
        self.assertEqual(self.build_reads("EncodedTotal"), {"LineAmount"})

    def test_empty_self_closing_source_is_skipped_by_both(self) -> None:
        self.assertEqual(self.build_reads("NestedTotal"), {"LineAmount"})
        self.assertEqual(self.query_expression("NestedTotal"), "LineAmount")


if __name__ == "__main__":
    unittest.main(verbosity=2)
