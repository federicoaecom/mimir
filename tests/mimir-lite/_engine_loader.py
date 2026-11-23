"""Shared loader for the hyphenated engine scripts under skills/mimir-lite/scripts/.

Not a test file (its name does not start with ``Test``), so tests/Invoke-Tests.ps1
does not run it. A test sets ``sys.dont_write_bytecode = True`` before importing
this module, so neither this helper nor the engine leaves a ``__pycache__`` behind.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = REPO_ROOT / "skills" / "mimir-lite" / "scripts"
BUILD_SCRIPT = SCRIPT_DIR / "Build-KbIntelligenceIndex.py"
BUILD_MODULE_NAME = "kb_intelligence_build"
QUERY_SCRIPT = SCRIPT_DIR / "Query-KbIntelligenceIndex.py"
QUERY_MODULE_NAME = "kb_intelligence_query"


def load_build_module() -> Any:
    """Load Build-KbIntelligenceIndex.py once per process and return the module."""
    return _load_script_module(BUILD_MODULE_NAME, BUILD_SCRIPT)


def load_query_module() -> Any:
    """Load Query-KbIntelligenceIndex.py once per process and return the module."""
    return _load_script_module(QUERY_MODULE_NAME, QUERY_SCRIPT)


def _load_script_module(module_name: str, script: Path) -> Any:
    loaded = sys.modules.get(module_name)
    if loaded is not None:
        return loaded
    # The engine scripts import sibling core modules by name.
    if str(SCRIPT_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location(module_name, script)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Unable to load engine script: {script}")
    module = importlib.util.module_from_spec(spec)
    # Its dataclasses resolve their annotations through sys.modules.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module
