"""Argument validation tests for gws-doc-action-extractor scripts.

All checks here fail before any ``gws`` call, so no mock binary is needed.
"""

import pathlib
import shutil
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
EXTRACT_ACTIONS = _SCRIPTS / "extract_actions.sh"
EXTRACT_RECENT = _SCRIPTS / "extract_recent_actions.sh"
SCAN_DOCS = _SCRIPTS / "scan_docs.sh"


def run(script, *args):
    bash_path = shutil.which("bash") or "bash"
    return subprocess.run(  # noqa: S603,S607
        [bash_path, str(script), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# extract_actions.sh
# ---------------------------------------------------------------------------


class TestExtractActionsArgValidation:

    def test_no_args_exits_1(self):
        r = run(EXTRACT_ACTIONS)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(EXTRACT_ACTIONS, "FILE_ID_123", "--bogus")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_human_flag_accepted(self):
        """--human must be recognised (may fail later at gws, not at arg parsing)."""
        r = run(EXTRACT_ACTIONS, "FILE_ID_123", "--human")
        assert "Unknown option" not in r.stderr

    def test_file_id_accepted(self):
        """A file-id alone must pass arg parsing."""
        r = run(EXTRACT_ACTIONS, "FILE_ID_123")
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr


# ---------------------------------------------------------------------------
# extract_recent_actions.sh
# ---------------------------------------------------------------------------


class TestExtractRecentActionsArgValidation:

    def test_no_args_exits_1(self):
        r = run(EXTRACT_RECENT)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(EXTRACT_RECENT, "FILE_ID_123", "--bogus")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_days_flag_accepted(self):
        r = run(EXTRACT_RECENT, "FILE_ID_123", "--days", "14")
        assert "Unknown option" not in r.stderr
        assert "Missing required argument" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(EXTRACT_RECENT, "FILE_ID_123", "--human")
        assert "Unknown option" not in r.stderr


# ---------------------------------------------------------------------------
# scan_docs.sh
# ---------------------------------------------------------------------------


class TestScanDocsArgValidation:

    def test_unknown_flag_exits_1(self):
        r = run(SCAN_DOCS, "--bogus-flag")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_limit_missing_value_exits_1(self):
        """--limit with no following value must fail with a clear error."""
        r = run(SCAN_DOCS, "--limit")
        assert r.returncode == 1
        assert "--limit" in r.stderr

    def test_limit_flag_value_accepted(self):
        """--limit N must pass arg parsing (may fail later at gws)."""
        r = run(SCAN_DOCS, "--limit", "10")
        assert "Unknown option" not in r.stderr
        assert not ("--limit" in r.stderr and "requires" in r.stderr)

    def test_human_flag_accepted(self):
        r = run(SCAN_DOCS, "--human")
        assert "Unknown option" not in r.stderr
