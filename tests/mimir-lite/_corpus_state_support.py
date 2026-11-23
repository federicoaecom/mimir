"""Test helper: write a corpus synchronization state file the way the XPZ sync writes it.

Not a test file (its name does not start with ``Test``). The shape follows
Write-GeneXusCorpusSyncState in skills/mimir-lite/scripts/GeneXusCorpusStateSupport.ps1.
PowerShell tests use tests/mimir-lite/CorpusStateTestSupport.ps1, which calls that writer.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Optional

STATE_FILE_NAME = ".mimir-sync-state.json"
# The generation recorded in tests/fixtures/sample-kb/.mimir-sync-state.json.
SAMPLE_KB_GENERATION = "5a3b0c0de5a3b0c0de5a3b0c0de5a3b0"
TEST_GENERATION = "0123456789abcdef0123456789abcdef"
_ZERO_PACKAGE = "0" * 64


def write_corpus_state(
    corpus_root: Path,
    state: str = "complete",
    generation: Optional[str] = TEST_GENERATION,
    schema_version: object = 1,
) -> Path:
    """Write <corpus_root>/.mimir-sync-state.json (UTF-8 without BOM, LF) and return its path."""
    payload = {
        "schemaVersion": schema_version,
        "state": state,
        "generation": generation if state == "complete" else None,
        "updatedAt": "2026-11-22T00:00:00.000Z",
        "packageSha256": _ZERO_PACKAGE,
        "recoveryPackageSha256": None,
    }
    path = Path(corpus_root) / STATE_FILE_NAME
    path.write_bytes((json.dumps(payload, indent=2) + "\n").encode("utf-8"))
    return path


def copy_corpus(source: Path, destination: Path) -> Path:
    """Copy a corpus (its state file included) to a scratch folder and return the copy."""
    shutil.copytree(str(source), str(destination))
    return destination
