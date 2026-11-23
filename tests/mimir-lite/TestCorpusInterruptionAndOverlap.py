#!/usr/bin/env python3
"""Deterministic interruption and overlap of the XPZ sync, the index build and the queries.

Every engine runs as a real child process (the sync through pwsh, the build and the query
through Python). The test-only stop points (MIMIR_TEST_STOP_AT and MIMIR_TEST_STOP_MODE, see
GeneXusCorpusState.py and GeneXusCorpusStateSupport.ps1) kill an engine, or pause it while it
holds the corpus lock, at an exact point:
- a sync killed before its first change, after its first XML file, or right before it publishes
  the state leaves the corpus incomplete: the build refuses it and queries block with
  corpus-incomplete; re-running the same package recovers it with a new generation;
- a build killed right before it publishes keeps the previous index byte for byte, publishes no
  generation, and the next build succeeds;
- a sync started while a build or a query holds the corpus lock fails fast and changes nothing,
  and a build or a query started while a sync holds it exits 13 and changes nothing.
Every corpus and index lives in a temporary folder outside the repository.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import sqlite3  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402

from _engine_loader import BUILD_SCRIPT, QUERY_SCRIPT, SCRIPT_DIR  # noqa: E402

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from GeneXusCorpusLock import corpus_lock  # noqa: E402

SYNC_SCRIPT = SCRIPT_DIR / "Sync-GeneXusXpzToXml.ps1"
STATE_FILE_NAME = ".mimir-sync-state.json"
PAUSED_MARKER = "MIMIR_TEST_PAUSED"
PYTHON = [sys.executable, "-B"]
TIMEOUT = 180


def package_text(attributes: list) -> str:
    nodes = "".join(
        f'<Attribute name="{name}" guid="" lastUpdate="{stamp}" description="{description}" />'
        for name, stamp, description in attributes
    )
    return f"<ExportFile><Attributes>{nodes}</Attributes></ExportFile>"


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CorpusInterruptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="mimir-interruption-"))
        self.corpus = self.root / "KbObjectsXml"
        self.index = self.root / "KbIntelligence" / "kb-intelligence.sqlite"
        self.paused = []
        self.base = self.write_package("base", [
            ("Alpha", "2026-01-01T00:00:00Z", "a1"),
            ("Beta", "2026-01-01T00:00:00Z", "b1"),
            ("Gamma", "2026-01-01T00:00:00Z", "g1"),
        ])
        self.delta = self.write_package("delta", [
            ("Alpha", "2026-02-01T00:00:00Z", "a2"),
            ("Beta", "2026-02-01T00:00:00Z", "b2"),
            ("Gamma", "2026-02-01T00:00:00Z", "g2"),
        ])
        first = self.sync(self.base)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(self.state().get("state"), "complete", self.state())
        built = self.build()
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assert_query_ok()

    def tearDown(self) -> None:
        for proc in self.paused:
            if proc.poll() is None:
                proc.kill()
            proc.communicate(timeout=30)
        shutil.rmtree(str(self.root), ignore_errors=True)

    # --- helpers -----------------------------------------------------------------------------

    def write_package(self, name: str, attributes: list) -> Path:
        path = self.root / f"{name}.xml"
        path.write_bytes(package_text(attributes).encode("utf-8"))
        return path

    def env(self, stop_at: str = "", mode: str = "") -> dict:
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        env.pop("MIMIR_TEST_STOP_AT", None)
        env.pop("MIMIR_TEST_STOP_MODE", None)
        if stop_at:
            env.update(MIMIR_TEST_STOP_AT=stop_at, MIMIR_TEST_STOP_MODE=mode)
        return env

    def sync_command(self, package: Path) -> list:
        return ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(SYNC_SCRIPT),
                "-InputPath", str(package), "-DestinationRoot", str(self.corpus)]

    def build_command(self) -> list:
        return PYTHON + [str(BUILD_SCRIPT), "--source-root", str(self.corpus), "--output-path", str(self.index)]

    def query_command(self, query: str = "list-by-type", *extra: str) -> list:
        if query == "list-by-type" and not extra:
            extra = ("--object-type", "Attribute")
        return PYTHON + [str(QUERY_SCRIPT), "--index-path", str(self.index), "--query", query] + list(extra)

    def run_command(self, command: list, stop_at: str = "") -> subprocess.CompletedProcess:
        return subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL,
            env=self.env(stop_at, "kill" if stop_at else ""), timeout=TIMEOUT,
            universal_newlines=True, encoding="utf-8", errors="replace",
        )

    def sync(self, package: Path, stop_at: str = "") -> subprocess.CompletedProcess:
        return self.run_command(self.sync_command(package), stop_at)

    def build(self, stop_at: str = "") -> subprocess.CompletedProcess:
        return self.run_command(self.build_command(), stop_at)

    def query(self, query: str = "list-by-type", *extra: str) -> subprocess.CompletedProcess:
        return self.run_command(self.query_command(query, *extra))

    def start_paused(self, command: list, stop_at: str) -> subprocess.Popen:
        proc = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=self.env(stop_at, "pause"), universal_newlines=True, encoding="utf-8", errors="replace",
        )
        self.paused.append(proc)
        seen = []
        for line in proc.stderr:  # an engine may write other stderr lines before it pauses
            if line.strip() == f"{PAUSED_MARKER} {stop_at}":
                return proc
            seen.append(line)
        out, err = proc.communicate(timeout=30)
        self.fail(f"{stop_at} did not pause: {''.join(seen)}{err}{out}")

    def resume(self, proc: subprocess.Popen) -> tuple:
        out, err = proc.communicate(input="\n", timeout=TIMEOUT)
        return proc.returncode, out, err

    def state(self) -> dict:
        path = self.corpus / STATE_FILE_NAME
        return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}

    def xml_text(self, name: str) -> str:
        return (self.corpus / "Attribute" / f"{name}.xml").read_text(encoding="utf-8")

    def corpus_snapshot(self) -> dict:
        return {
            str(path.relative_to(self.corpus)): file_sha256(path)
            for path in sorted(self.corpus.rglob("*"))
            if path.is_file() and path.name != ".mimir-sync.lock"
        }

    def index_generation(self):
        conn = sqlite3.connect(str(self.index))
        try:
            row = conn.execute("SELECT value FROM metadata WHERE key = 'corpus_generation'").fetchone()
        finally:
            conn.close()
        return None if row is None else row[0]

    def assert_query_ok(self) -> None:
        result = self.query()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_query_blocked(self, exit_code: int, reason: str) -> None:
        result = self.query()
        self.assertEqual(result.returncode, exit_code, result.stdout + result.stderr)
        envelope = json.loads(result.stdout)
        self.assertEqual(envelope.get("reason"), reason, envelope)

    def assert_lock_free(self) -> None:
        with corpus_lock(self.corpus):
            pass

    # --- interrupted sync --------------------------------------------------------------------

    def check_killed_sync(self, stop_at: str, descriptions: tuple) -> None:
        previous_generation = self.state()["generation"]
        killed = self.sync(self.delta, stop_at)
        self.assertNotEqual(killed.returncode, 0, killed.stdout + killed.stderr)
        state = self.state()
        self.assertEqual(state.get("state"), "incomplete", state)
        self.assertIsNone(state.get("generation"), state)
        for name, description in zip(("Alpha", "Beta", "Gamma"), descriptions):
            self.assertIn(f'description="{description}"', self.xml_text(name), name)
        self.assertEqual([], list(self.corpus.rglob(".mimir-*.tmp")), "no temporary file may be left")
        self.assert_lock_free()

        self.assert_query_blocked(12, "corpus-incomplete")
        refused = self.build()
        self.assertEqual(refused.returncode, 12, refused.stdout + refused.stderr)

        recovered = self.sync(self.delta)
        self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
        state = self.state()
        self.assertEqual(state.get("state"), "complete", state)
        self.assertNotEqual(state.get("generation"), previous_generation)
        for name in ("Alpha", "Beta", "Gamma"):
            self.assertIn(f'description="{name[0].lower()}2"', self.xml_text(name))
        self.assert_query_blocked(12, "index-generation-mismatch")
        rebuilt = self.build()
        self.assertEqual(rebuilt.returncode, 0, rebuilt.stdout + rebuilt.stderr)
        self.assert_query_ok()

    def test_a_sync_killed_before_its_first_change_leaves_the_corpus_incomplete(self) -> None:
        self.check_killed_sync("sync:after-mark-incomplete", ("a1", "b1", "g1"))

    def test_a_sync_killed_after_its_first_xml_leaves_the_corpus_incomplete(self) -> None:
        self.check_killed_sync("sync:after-xml:1", ("a2", "b1", "g1"))

    def test_a_sync_killed_right_before_publishing_leaves_the_corpus_incomplete(self) -> None:
        self.check_killed_sync("sync:before-publish", ("a2", "b2", "g2"))

    # --- interrupted build -------------------------------------------------------------------

    def test_a_killed_build_keeps_the_previous_index_and_publishes_no_generation(self) -> None:
        old_generation = self.index_generation()
        old_index = file_sha256(self.index)
        synced = self.sync(self.delta)
        self.assertEqual(synced.returncode, 0, synced.stderr)
        new_generation = self.state()["generation"]
        self.assertNotEqual(new_generation, old_generation)

        killed = self.build("build:before-publish")
        self.assertNotEqual(killed.returncode, 0, killed.stdout + killed.stderr)
        self.assertEqual(file_sha256(self.index), old_index, "a killed build must not touch the index")
        self.assertEqual(self.index_generation(), old_generation)
        self.assert_lock_free()
        self.assert_query_blocked(12, "index-generation-mismatch")

        rebuilt = self.build()
        self.assertEqual(rebuilt.returncode, 0, rebuilt.stdout + rebuilt.stderr)
        self.assertEqual(self.index_generation(), new_generation)
        self.assertFalse(self.index.with_name(self.index.name + ".tmp").exists(), "the leftover temporary index must be gone")
        self.assert_query_ok()

    # --- overlap -----------------------------------------------------------------------------

    def test_a_sync_fails_fast_while_a_build_or_a_query_holds_the_lock(self) -> None:
        holders = [
            ("build:before-publish", self.build_command()),
            ("query:after-lock", self.query_command()),
        ]
        for stop_at, command in holders:
            with self.subTest(holder=stop_at):
                before = self.corpus_snapshot()
                holder = self.start_paused(command, stop_at)
                try:
                    blocked = self.sync(self.delta)
                    snapshot = self.corpus_snapshot()
                finally:
                    code, out, err = self.resume(holder)
                self.assertNotEqual(blocked.returncode, 0, blocked.stdout)
                self.assertIn("corpus is locked by another process", blocked.stderr)
                self.assertEqual(snapshot, before, "a refused sync must change nothing")
                self.assertEqual(code, 0, out + err)
                self.assert_query_ok()

    def test_a_build_and_a_query_exit_13_while_a_sync_holds_the_lock(self) -> None:
        old_index = file_sha256(self.index)
        sync = self.start_paused(self.sync_command(self.delta), "sync:after-xml:1")
        during = self.corpus_snapshot()

        build = self.build()
        self.assertEqual(build.returncode, 13, build.stdout + build.stderr)
        self.assertIn("corpus lock", build.stderr.lower())
        self.assertEqual(file_sha256(self.index), old_index)
        self.assert_query_blocked(13, "corpus-lock-busy")
        self.assertEqual(self.corpus_snapshot(), during, "the refused build and query must change nothing")

        code, out, err = self.resume(sync)
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.state().get("state"), "complete")
        self.assertEqual(self.build().returncode, 0)
        self.assert_query_ok()


if __name__ == "__main__":
    unittest.main()
