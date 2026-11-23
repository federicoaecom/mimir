#!/usr/bin/env python3
"""Atomic index write of Build-KbIntelligenceIndex.py.

A build that fails while writing must leave the previous index untouched and no
temporary file behind; a successful build must leave no temporary file either.
The build module is loaded through importlib (its file name has hyphens) and run
in process against a scratch copy of the synthetic fixture tests/fixtures/sample-kb/ (the build
takes the corpus lock, which creates a lock file in the corpus).
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import contextlib  # noqa: E402
import io  # noqa: E402
import shutil  # noqa: E402
import sqlite3  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402
from unittest import mock  # noqa: E402

from _corpus_state_support import copy_corpus  # noqa: E402
from _engine_loader import BUILD_SCRIPT, REPO_ROOT, load_build_module  # noqa: E402

SAMPLE_KB = REPO_ROOT / "tests" / "fixtures" / "sample-kb"


BUILD = load_build_module()


class AtomicIndexWriteTests(unittest.TestCase):
    def setUp(self) -> None:
        # Resolved: a TEMP given as an 8.3 short path (as on hosted Windows runners) must match the
        # long path the build reports.
        self.temp_root = Path(tempfile.mkdtemp(prefix="kb-intel-atomic-write-")).resolve()
        self.corpus = copy_corpus(SAMPLE_KB, self.temp_root / "KbObjectsXml")
        self.output_path = self.temp_root / "KbIntelligence" / "kb-intelligence.sqlite"
        self.temp_path = self.output_path.with_name(self.output_path.name + ".tmp")

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_root, ignore_errors=True)

    def run_build(self) -> int:
        argv = [
            str(BUILD_SCRIPT),
            "--source-root",
            str(self.corpus),
            "--output-path",
            str(self.output_path),
        ]
        with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
            return BUILD.main()

    def build_good_index(self) -> bytes:
        self.assertEqual(self.run_build(), 0)
        self.assertTrue(self.output_path.is_file())
        return self.output_path.read_bytes()

    def assert_previous_index_kept(self, previous_bytes: bytes) -> None:
        self.assertTrue(self.output_path.is_file(), "the previous index was deleted")
        self.assertEqual(self.output_path.read_bytes(), previous_bytes, "the previous index bytes changed")
        self.assertFalse(self.temp_path.exists(), f"temporary file left behind: {self.temp_path}")
        conn = sqlite3.connect(self.output_path)
        try:
            row = conn.execute(
                "SELECT value FROM metadata WHERE key = 'extractor_signature_hash'"
            ).fetchone()
        finally:
            conn.close()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], BUILD.compute_extractor_signature_hash())

    def test_failed_write_keeps_previous_index_and_removes_temp_file(self) -> None:
        previous_bytes = self.build_good_index()

        with mock.patch.object(BUILD, "create_schema", side_effect=RuntimeError("simulated write failure")):
            with self.assertRaises(RuntimeError):
                self.run_build()

        self.assert_previous_index_kept(previous_bytes)

    def test_locked_destination_reports_clear_error_and_keeps_previous_index(self) -> None:
        previous_bytes = self.build_good_index()

        with mock.patch.object(BUILD.os, "replace", side_effect=PermissionError("simulated lock")):
            with self.assertRaises(SystemExit) as raised:
                self.run_build()

        message = str(raised.exception.code)
        self.assertIn(str(self.output_path), message)
        self.assertIn("previous index was kept", message)
        self.assert_previous_index_kept(previous_bytes)

    def test_successful_build_removes_leftover_temp_file(self) -> None:
        self.temp_path.parent.mkdir(parents=True, exist_ok=True)
        self.temp_path.write_bytes(b"leftover from a killed build")

        self.build_good_index()

        self.assertFalse(self.temp_path.exists(), f"temporary file left behind: {self.temp_path}")
        conn = sqlite3.connect(self.output_path)
        try:
            object_count = conn.execute("SELECT COUNT(*) FROM objects").fetchone()[0]
        finally:
            conn.close()
        self.assertGreater(object_count, 0)


if __name__ == "__main__":
    unittest.main()
