#!/usr/bin/env python3
"""Corpus state and generation enforcement of the KB Intelligence engines.

Through the public interfaces (engine processes and GeneXusCorpusState.read_corpus_state):
- the builder refuses a corpus whose state is not complete (exit 12), records the generation it
  read, and exits 13 while another process (a query included) holds the corpus lock;
- the query blocks an incomplete/unknown/invalid corpus, an index without a recorded generation
  and an index whose generation differs from the corpus (exit 12, JSON envelope), retries a busy
  lock and then exits 13, and succeeds when the holder releases within the retry window;
- a query runs at once while another query holds the shared corpus lock;
- index-metadata reports the state and the match without enforcing it;
- the KbIntelligenceQueryCases.py path applies the same check;
- schemaVersion must be the integer 1.
Every corpus is a scratch copy of tests/fixtures/sample-kb, so no lock file lands in the repository.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import json  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import sqlite3  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import time  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402

from _corpus_state_support import (  # noqa: E402
    SAMPLE_KB_GENERATION,
    STATE_FILE_NAME,
    TEST_GENERATION,
    copy_corpus,
    write_corpus_state,
)
from _engine_loader import BUILD_SCRIPT, QUERY_SCRIPT, REPO_ROOT, SCRIPT_DIR  # noqa: E402

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

SAMPLE_KB = REPO_ROOT / "tests" / "fixtures" / "sample-kb"
QUERY_CASES_SCRIPT = SCRIPT_DIR / "KbIntelligenceQueryCases.py"
QUERY_CASES_FIXTURE = REPO_ROOT / "tests" / "fixtures" / "kb-intelligence-sample-kb.validation-queries.json"
PYTHON = [sys.executable, "-B"]
ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
HOLDER_CODE = (
    "import sys, time; sys.path.insert(0, sys.argv[1]); "
    "from GeneXusCorpusLock import corpus_lock; "
    "c = corpus_lock(sys.argv[2], **({'shared': True} if sys.argv[4] == '1' else {})); "
    "c.__enter__(); print('held', flush=True); "
    "delay = float(sys.argv[3]); "
    "sys.stdin.readline() if delay < 0 else time.sleep(delay); "
    "c.__exit__(None, None, None)"
)


def run(command: list, timeout: float = 120) -> subprocess.CompletedProcess:
    return subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL,
        env=ENV, timeout=timeout, universal_newlines=True, encoding="utf-8",
    )


class CorpusGenerationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_root = Path(tempfile.mkdtemp(prefix="kb-intel-corpus-generation-"))
        self.corpus = copy_corpus(SAMPLE_KB, self.temp_root / "KbObjectsXml")
        self.index_path = self.temp_root / "KbIntelligence" / "kb-intelligence.sqlite"
        self.holder = None

    def tearDown(self) -> None:
        if self.holder is not None:
            if self.holder.poll() is None:
                self.holder.kill()
            self.holder.communicate(timeout=10)
        shutil.rmtree(str(self.temp_root), ignore_errors=True)

    # --- helpers -----------------------------------------------------------------------------

    def build(self) -> subprocess.CompletedProcess:
        return run(PYTHON + [str(BUILD_SCRIPT), "--source-root", str(self.corpus), "--output-path", str(self.index_path)])

    def build_ok(self) -> None:
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)

    def query(self, query: str, *extra: str) -> subprocess.CompletedProcess:
        return run(PYTHON + [str(QUERY_SCRIPT), "--index-path", str(self.index_path), "--query", query] + list(extra))

    def index_metadata_value(self, key: str):
        conn = sqlite3.connect(str(self.index_path))
        try:
            row = conn.execute("SELECT value FROM metadata WHERE key = ?", (key,)).fetchone()
        finally:
            conn.close()
        return None if row is None else row[0]

    def hold_lock(self, delay: float = -1, shared: bool = False) -> None:
        self.holder = subprocess.Popen(
            PYTHON + ["-c", HOLDER_CODE, str(SCRIPT_DIR), str(self.corpus), str(delay), "1" if shared else "0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV, universal_newlines=True,
        )
        self.assertEqual(self.holder.stdout.readline().strip(), "held", "the lock holder did not start")

    def release_lock(self) -> None:
        self.holder.communicate(input="\n", timeout=10)

    def assert_envelope(self, result: subprocess.CompletedProcess, exit_code: int, reason: str) -> dict:
        self.assertEqual(result.returncode, exit_code, result.stdout + result.stderr)
        envelope = json.loads(result.stdout)
        self.assertEqual(envelope.get("status"), "BLOCKED", envelope)
        self.assertIs(envelope.get("blocked"), True, envelope)
        self.assertEqual(envelope.get("reason"), reason, envelope)
        self.assertTrue(envelope.get("message"), envelope)
        self.assertTrue(envelope.get("recovery"), envelope)
        return envelope

    # --- read_corpus_state --------------------------------------------------------------------

    def test_read_corpus_state_requires_integer_schema_version_one(self) -> None:
        from GeneXusCorpusState import read_corpus_state

        self.assertEqual(tuple(read_corpus_state(self.corpus)), ("complete", SAMPLE_KB_GENERATION))
        for bad_version in ("1", 1.0, True, 2, None):
            with self.subTest(schema_version=bad_version):
                write_corpus_state(self.corpus, schema_version=bad_version)
                self.assertEqual(tuple(read_corpus_state(self.corpus)), ("invalid", None))
        write_corpus_state(self.corpus, state="incomplete")
        self.assertEqual(tuple(read_corpus_state(self.corpus)), ("incomplete", None))
        write_corpus_state(self.corpus, generation="NOT-A-GENERATION")
        self.assertEqual(tuple(read_corpus_state(self.corpus)), ("invalid", None))
        (self.corpus / STATE_FILE_NAME).write_text("{not json", encoding="utf-8")
        self.assertEqual(tuple(read_corpus_state(self.corpus)), ("invalid", None))
        (self.corpus / STATE_FILE_NAME).unlink()
        self.assertEqual(tuple(read_corpus_state(self.corpus)), ("unknown", None))

    # --- builder -----------------------------------------------------------------------------

    def test_builder_records_the_generation_of_a_complete_corpus(self) -> None:
        self.build_ok()
        self.assertEqual(self.index_metadata_value("corpus_generation"), SAMPLE_KB_GENERATION)
        self.assertEqual(self.index_metadata_value("corpus_state_schema_version"), "1")

    def test_builder_refuses_a_corpus_that_is_not_complete(self) -> None:
        cases = {
            "incomplete": lambda: write_corpus_state(self.corpus, state="incomplete"),
            "unknown": lambda: (self.corpus / STATE_FILE_NAME).unlink(),
            "invalid": lambda: write_corpus_state(self.corpus, schema_version="1"),
        }
        for state, prepare in cases.items():
            with self.subTest(state=state):
                write_corpus_state(self.corpus)
                prepare()
                result = self.build()
                self.assertEqual(result.returncode, 12, result.stdout + result.stderr)
                self.assertIn(f"BLOCK: corpus state is {state};", result.stderr)
                self.assertIn("sync", result.stderr)
                self.assertFalse(self.index_path.exists(), "a refused build must not write an index")

    def test_builder_exits_13_while_another_process_holds_the_lock(self) -> None:
        self.hold_lock()
        result = self.build()
        self.release_lock()
        self.assertEqual(result.returncode, 13, result.stdout + result.stderr)
        self.assertIn("corpus lock", result.stderr.lower())
        self.assertFalse(self.index_path.exists())

    def test_builder_exits_13_while_a_query_holds_the_shared_lock(self) -> None:
        self.hold_lock(shared=True)
        result = self.build()
        self.release_lock()
        self.assertEqual(result.returncode, 13, result.stdout + result.stderr)
        self.assertIn("corpus lock", result.stderr.lower())
        self.assertFalse(self.index_path.exists())

    # --- query -------------------------------------------------------------------------------

    def test_query_blocks_each_corpus_and_index_mismatch(self) -> None:
        self.build_ok()
        ok = self.query("list-by-type", "--object-type", "Procedure")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)

        write_corpus_state(self.corpus, state="incomplete")
        self.assert_envelope(self.query("list-by-type", "--object-type", "Procedure"), 12, "corpus-incomplete")

        (self.corpus / STATE_FILE_NAME).unlink()
        self.assert_envelope(self.query("list-by-type", "--object-type", "Procedure"), 12, "corpus-unknown")

        write_corpus_state(self.corpus, schema_version="1")
        self.assert_envelope(self.query("list-by-type", "--object-type", "Procedure"), 12, "corpus-invalid")

        write_corpus_state(self.corpus, generation=TEST_GENERATION)
        envelope = self.assert_envelope(
            self.query("list-by-type", "--object-type", "Procedure"), 12, "index-generation-mismatch"
        )
        self.assertEqual(envelope.get("corpus_generation"), TEST_GENERATION)
        self.assertEqual(envelope.get("index_corpus_generation"), SAMPLE_KB_GENERATION)

        write_corpus_state(self.corpus, generation=SAMPLE_KB_GENERATION)
        conn = sqlite3.connect(str(self.index_path))
        conn.execute("DELETE FROM metadata WHERE key = 'corpus_generation'")
        conn.commit()
        conn.close()
        self.assert_envelope(self.query("list-by-type", "--object-type", "Procedure"), 12, "index-generation-missing")

    def test_query_retries_a_busy_lock_then_exits_13(self) -> None:
        self.build_ok()
        self.hold_lock()
        started = time.monotonic()
        result = self.query("list-by-type", "--object-type", "Procedure")
        elapsed = time.monotonic() - started
        self.release_lock()
        envelope = self.assert_envelope(result, 13, "corpus-lock-busy")
        self.assertNotIn("query", envelope["recovery"], "queries share the lock, so another query never blocks one")
        self.assertGreaterEqual(elapsed, 4.0, "the query should retry for about 5 seconds before giving up")

    def test_query_succeeds_when_the_holder_releases_within_the_window(self) -> None:
        self.build_ok()
        self.hold_lock(delay=1.0)
        result = self.query("list-by-type", "--object-type", "Procedure")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout).get("query"), "list-by-type")

    def test_query_runs_at_once_while_another_query_holds_the_shared_lock(self) -> None:
        self.build_ok()
        self.hold_lock(shared=True)
        started = time.monotonic()
        result = self.query("list-by-type", "--object-type", "Procedure")
        elapsed = time.monotonic() - started
        metadata = self.query("index-metadata")
        self.release_lock()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout).get("query"), "list-by-type")
        self.assertLess(elapsed, 4.0, "a query must not wait for another query's lock")
        self.assertEqual(metadata.returncode, 0, metadata.stdout + metadata.stderr)
        self.assertIs(json.loads(metadata.stdout).get("corpus_generation_match"), True, metadata.stdout)

    def test_index_metadata_reports_without_enforcing(self) -> None:
        self.build_ok()
        result = self.query("index-metadata")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["corpus_state"], "complete")
        self.assertEqual(payload["corpus_generation"], SAMPLE_KB_GENERATION)
        self.assertEqual(payload["index_corpus_generation"], SAMPLE_KB_GENERATION)
        self.assertIs(payload["corpus_generation_match"], True)

        write_corpus_state(self.corpus, generation=TEST_GENERATION)
        result = self.query("index-metadata")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["corpus_generation"], TEST_GENERATION)
        self.assertIs(payload["corpus_generation_match"], False)
        self.assertEqual(payload["corpus_block_reason"], "index-generation-mismatch")

        write_corpus_state(self.corpus, state="incomplete")
        payload = json.loads(self.query("index-metadata").stdout)
        self.assertEqual(payload["corpus_state"], "incomplete")
        self.assertIs(payload["corpus_generation_match"], False)

        self.hold_lock()
        result = self.query("index-metadata")
        self.release_lock()
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIs(payload["corpus_generation_match"], False)
        self.assertEqual(payload["corpus_block_reason"], "corpus-lock-busy")

    def test_query_cases_runner_applies_the_same_check(self) -> None:
        self.build_ok()
        command = PYTHON + [
            str(QUERY_CASES_SCRIPT), "--index-path", str(self.index_path),
            "--validation-cases-path", str(QUERY_CASES_FIXTURE),
        ]
        passing = run(command)
        self.assertEqual(passing.returncode, 0, passing.stdout + passing.stderr)
        write_corpus_state(self.corpus, generation=TEST_GENERATION)
        self.assert_envelope(run(command), 12, "index-generation-mismatch")


if __name__ == "__main__":
    unittest.main()
