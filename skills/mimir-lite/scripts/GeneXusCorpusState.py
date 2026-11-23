"""Read the synchronization state of an XML corpus and take its lock with a bounded retry.

The state lives in ``<corpus>/.mimir-sync-state.json``, written by the XPZ sync
(GeneXusCorpusStateSupport.ps1). ``read_corpus_state`` returns one of:

- ``complete`` with its generation (32 lowercase hex characters);
- ``incomplete`` (a sync started mutating the corpus and did not publish it);
- ``unknown`` (no state file);
- ``invalid`` (unreadable file, wrong shape, or ``schemaVersion`` other than the integer 1).

Callers hold the corpus lock (``corpus_lock_with_retry`` or GeneXusCorpusLock.corpus_lock)
around every read that decides: queries hold it shared, the index build exclusive. This module is not part of the extractor signature.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Iterator, NamedTuple, Optional

from GeneXusCorpusLock import corpus_lock

STATE_FILE_NAME = ".mimir-sync-state.json"
STATE_SCHEMA_VERSION = 1
# Stored in the index metadata as corpus_state_schema_version.
CORPUS_STATE_SCHEMA_VERSION = str(STATE_SCHEMA_VERSION)
# Exit codes shared by the index builder and the query engine.
EXIT_CORPUS_NOT_COMPLETE = 12
EXIT_CORPUS_LOCK_BUSY = 13
LOCK_RETRY_SECONDS = 5.0
LOCK_RETRY_INTERVAL_SECONDS = 0.1
_GENERATION_RE = re.compile(r"[0-9a-f]{32}")
_SEE_SYNC = "See the sync workflow (workflows/sync.md)."
_NOT_A_FIX = "Deleting or editing the state file does not recover the corpus."
_STATE_RECOVERY = {
    "incomplete": (
        "The last XPZ sync of this corpus did not finish. Complete it by re-running the sync of the "
        "package that left it incomplete, or run a verified -FullSnapshot sync of a full KB export; "
        "then rebuild the index."
    ),
    "unknown": (
        "No synchronization state is recorded for this corpus (.mimir-sync-state.json is missing). "
        "Run a verified -FullSnapshot sync of a full KB export; then rebuild the index."
    ),
    "invalid": (
        "The corpus synchronization state (.mimir-sync-state.json) cannot be read or does not match "
        "its schema. Run a verified -FullSnapshot sync of a full KB export; then rebuild the index."
    ),
}


class CorpusState(NamedTuple):
    state: str
    generation: Optional[str]


class CorpusLockBusy(Exception):
    """The corpus lock stayed busy (or unavailable) for the whole retry window."""


def read_corpus_state(corpus_root: Path | str) -> CorpusState:
    path = Path(corpus_root) / STATE_FILE_NAME
    if not path.is_file():
        return CorpusState("unknown", None)
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return CorpusState("invalid", None)
    if not isinstance(data, dict):
        return CorpusState("invalid", None)
    version = data.get("schemaVersion")
    # Strictly the integer 1: not "1", 1.0, or true.
    if type(version) is not int or version != STATE_SCHEMA_VERSION:
        return CorpusState("invalid", None)
    state = data.get("state")
    if state == "complete":
        generation = data.get("generation")
        if isinstance(generation, str) and _GENERATION_RE.fullmatch(generation):
            return CorpusState("complete", generation)
        return CorpusState("invalid", None)
    if state == "incomplete":
        return CorpusState("incomplete", None)
    return CorpusState("invalid", None)


def stop_point_for_tests(point: str) -> None:
    """Test-only stop point, shared with Invoke-GeneXusTestStopPoint (GeneXusCorpusStateSupport.ps1).

    When MIMIR_TEST_STOP_AT equals ``point``, MIMIR_TEST_STOP_MODE ``kill`` ends the process at once
    (no finally block or context exit runs; the OS releases the corpus lock), and ``pause`` writes
    ``MIMIR_TEST_PAUSED <point>`` to stderr and waits for a line on stdin. Unset, it does nothing.
    """
    if os.environ.get("MIMIR_TEST_STOP_AT") != point:
        return
    mode = os.environ.get("MIMIR_TEST_STOP_MODE")
    if mode == "kill":
        os._exit(137)
    if mode == "pause":
        print(f"MIMIR_TEST_PAUSED {point}", file=sys.stderr, flush=True)
        sys.stdin.readline()


def corpus_state_recovery(state: str) -> str:
    """How to recover a corpus whose state is not complete."""
    return f"{_STATE_RECOVERY[state]} {_NOT_A_FIX} {_SEE_SYNC}"


def corpus_lock_busy_recovery(shared: bool = False) -> str:
    """Recovery text for a busy lock; a shared (query) contender is never blocked by a query."""
    holders = "an XPZ sync or an index build" if shared else "an XPZ sync, an index build, or a query"
    return f"Another process ({holders}) holds the corpus lock. Wait for it to finish and run the command again."


@contextlib.contextmanager
def corpus_lock_with_retry(
    corpus_root: Path | str,
    timeout: float = LOCK_RETRY_SECONDS,
    interval: float = LOCK_RETRY_INTERVAL_SECONDS,
    *,
    shared: bool = False,
) -> Iterator[None]:
    """Hold the corpus lock, retrying contention for up to ``timeout`` seconds.

    ``shared=True`` takes the read lock that queries share with each other; the default is the
    exclusive lock that the sync and the index build take.

    A missing corpus folder raises FileNotFoundError or NotADirectoryError at once. Any other
    failure to take the lock (contention, an unwritable lock file, a lock already held in this
    process) is retried and then raised as CorpusLockBusy.
    """
    deadline = time.monotonic() + timeout
    with contextlib.ExitStack() as stack:
        while True:
            try:
                stack.enter_context(corpus_lock(corpus_root, shared=shared))
                break
            except (FileNotFoundError, NotADirectoryError):
                raise
            except (OSError, RuntimeError) as exc:
                if time.monotonic() >= deadline:
                    raise CorpusLockBusy(str(exc)) from exc
                time.sleep(interval)
        yield
