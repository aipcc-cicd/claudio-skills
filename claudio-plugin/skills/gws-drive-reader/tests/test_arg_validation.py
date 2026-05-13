"""Argument validation tests for gws-drive-reader scripts.

All tests here exercise the argument-parsing layer only — no ``gws`` call
is needed because the scripts exit before reaching network operations.
"""

import pathlib
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
LIST_FILES = _SCRIPTS / "list_files.sh"
SEARCH_FILES = _SCRIPTS / "search_files.sh"
READ_DOC = _SCRIPTS / "read_document.sh"


def run(script, *args):
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# list_files.sh
# ---------------------------------------------------------------------------


class TestListFilesArgValidation:

    def test_unknown_flag_exits_1(self):
        r = run(LIST_FILES, "--bogus-flag")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_folder_id_missing_value_exits_1(self):
        r = run(LIST_FILES, "--folder-id")
        assert r.returncode == 1
        assert "--folder-id" in r.stderr

    def test_limit_missing_value_exits_1(self):
        r = run(LIST_FILES, "--limit")
        assert r.returncode == 1
        assert "--limit" in r.stderr

    def test_type_missing_value_exits_1(self):
        r = run(LIST_FILES, "--type")
        assert r.returncode == 1
        assert "--type" in r.stderr

    def test_no_args_succeeds_arg_parsing(self):
        """list_files.sh has no required args — arg parsing should pass.
        Failure at gws call is expected (no mock), but not at arg parsing."""
        r = run(LIST_FILES)
        # Must not fail with "Unknown option" or missing-arg message
        assert "Unknown option" not in r.stderr
        assert "--folder-id requires" not in r.stderr
        assert "--limit requires" not in r.stderr

    def test_shared_with_me_flag_accepted(self):
        r = run(LIST_FILES, "--shared-with-me")
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(LIST_FILES, "--human")
        assert "Unknown option" not in r.stderr

    def test_since_missing_value_exits_1(self):
        r = run(LIST_FILES, "--since")
        assert r.returncode == 1
        assert "--since" in r.stderr

    def test_since_flag_accepted(self):
        r = run(LIST_FILES, "--since", "7")
        assert "Unknown option" not in r.stderr
        assert "--since" not in r.stderr

    @pytest.mark.parametrize("bad_limit", ["abc", "0", "-1", "1.5"])
    def test_limit_invalid_values_exits_1(self, bad_limit):
        r = run(LIST_FILES, "--limit", bad_limit)
        assert r.returncode == 1
        assert "--limit" in r.stderr

    @pytest.mark.parametrize("bad_since", ["abc", "0", "-1", "1.5"])
    def test_since_invalid_values_exits_1(self, bad_since):
        r = run(LIST_FILES, "--since", bad_since)
        assert r.returncode == 1
        assert "--since" in r.stderr


# ---------------------------------------------------------------------------
# search_files.sh
# ---------------------------------------------------------------------------


class TestSearchFilesArgValidation:

    def test_no_args_exits_1(self):
        r = run(SEARCH_FILES)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(SEARCH_FILES, "my query", "--bogus-flag")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_limit_missing_value_exits_1(self):
        r = run(SEARCH_FILES, "report", "--limit")
        assert r.returncode == 1
        assert "--limit" in r.stderr

    def test_type_missing_value_exits_1(self):
        r = run(SEARCH_FILES, "report", "--type")
        assert r.returncode == 1
        assert "--type" in r.stderr

    def test_query_accepted(self):
        """Providing a query string must pass arg parsing (may fail at gws)."""
        r = run(SEARCH_FILES, "quarterly report")
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr

    def test_query_with_type_accepted(self):
        r = run(SEARCH_FILES, "budget", "--type", "sheet")
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(SEARCH_FILES, "notes", "--human")
        assert "Unknown option" not in r.stderr

    @pytest.mark.parametrize("bad_limit", ["abc", "0", "-1", "1.5"])
    def test_limit_invalid_values_exits_1(self, bad_limit):
        r = run(SEARCH_FILES, "report", "--limit", bad_limit)
        assert r.returncode == 1
        assert "--limit" in r.stderr


# ---------------------------------------------------------------------------
# read_document.sh
# ---------------------------------------------------------------------------


class TestReadDocumentArgValidation:

    def test_no_args_exits_1(self):
        r = run(READ_DOC)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(READ_DOC, "FILE_ID_123", "--bogus")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_invalid_format_exits_1(self):
        r = run(READ_DOC, "FILE_ID_123", "--format", "pdf")
        assert r.returncode == 1
        assert "Unsupported format" in r.stderr

    @pytest.mark.parametrize("fmt", ["text", "html"])
    def test_valid_format_passes_validation(self, fmt):
        """Valid formats must not fail at the format-validation step."""
        r = run(READ_DOC, "FILE_ID_123", "--format", fmt)
        assert "Unsupported format" not in r.stderr

    def test_format_missing_value_exits_1(self):
        r = run(READ_DOC, "FILE_ID_123", "--format")
        assert r.returncode == 1
        assert "--format" in r.stderr

    def test_human_flag_accepted(self):
        r = run(READ_DOC, "FILE_ID_123", "--human")
        assert "Unknown option" not in r.stderr
