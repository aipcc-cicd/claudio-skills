"""Query construction tests for gws-drive-reader scripts.

These tests use the mock ``gws`` binary (via the ``gws_env`` fixture) to
capture the Drive API parameters that list_files.sh and search_files.sh
build — without making any real network calls.
"""

import json
import pathlib
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
LIST_FILES = _SCRIPTS / "list_files.sh"
SEARCH_FILES = _SCRIPTS / "search_files.sh"

_EMPTY_FILES_RESPONSE = json.dumps({"files": []})


def run(script, *args, env_extras=None, cwd=None):
    import os
    env = os.environ.copy()
    if env_extras:
        env.update(env_extras)
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# list_files.sh — query construction
# ---------------------------------------------------------------------------


class TestListFilesQueryConstruction:
    """Verify build_params() emits correct Drive API query parameters."""

    def test_default_query_includes_trashed_false(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES)
        assert gws_env.calls_contain("trashed = false")

    def test_default_page_size_is_50(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES)
        # jq outputs "pageSize": 50 in the params JSON
        assert gws_env.calls_contain('"pageSize": 50')

    @pytest.mark.parametrize("alias,expected_mime", [
        ("doc",    "application/vnd.google-apps.document"),
        ("sheet",  "application/vnd.google-apps.spreadsheet"),
        ("slide",  "application/vnd.google-apps.presentation"),
        ("folder", "application/vnd.google-apps.folder"),
    ])
    def test_type_alias_resolved_to_mime(self, gws_env, alias, expected_mime):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--type", alias)
        assert gws_env.calls_contain(expected_mime), \
            f"Expected MIME {expected_mime!r} in logged call for --type {alias}"

    def test_full_mime_type_passed_through(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        mime = "application/vnd.google-apps.document"
        run(LIST_FILES, "--type", mime)
        assert gws_env.calls_contain(mime)

    def test_folder_id_appended_to_query(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--folder-id", "TESTFOLDER123")
        assert gws_env.calls_contain("TESTFOLDER123")

    def test_folder_id_uses_in_parents_syntax(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--folder-id", "FOLDERID456")
        assert gws_env.calls_contain("in parents")

    def test_shared_with_me_adds_filter(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--shared-with-me")
        assert gws_env.calls_contain("sharedWithMe = true")

    def test_limit_sets_page_size(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--limit", "5")
        assert gws_env.calls_contain('"pageSize": 5')

    def test_combined_type_and_folder_both_present(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--type", "doc", "--folder-id", "MYFOLDERID")
        assert gws_env.calls_contain("application/vnd.google-apps.document")
        assert gws_env.calls_contain("MYFOLDERID")

    def test_fields_includes_required_metadata(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES)
        assert gws_env.calls_contain("id,name,mimeType,modifiedTime")

    def test_ordered_by_modified_time(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES)
        assert gws_env.calls_contain("modifiedTime desc")

    def test_since_adds_modified_time_filter(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(LIST_FILES, "--since", "7")
        assert gws_env.calls_contain("modifiedTime >")


# ---------------------------------------------------------------------------
# search_files.sh — query construction
# ---------------------------------------------------------------------------


class TestSearchFilesQueryConstruction:
    """Verify search_files.sh embeds the query term in the Drive API params."""

    def test_query_term_in_name_contains_clause(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "quarterly report")
        assert gws_env.calls_contain("quarterly report")

    def test_search_excludes_trashed(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "budget")
        assert gws_env.calls_contain("trashed = false")

    def test_search_includes_full_text_clause(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "budget")
        assert gws_env.calls_contain("fullText contains")

    def test_search_includes_name_contains_clause(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "release notes")
        assert gws_env.calls_contain("name contains")

    def test_type_filter_adds_mime_type(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "budget", "--type", "sheet")
        assert gws_env.calls_contain("application/vnd.google-apps.spreadsheet")

    def test_limit_sets_page_size(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "notes", "--limit", "5")
        assert gws_env.calls_contain('"pageSize": 5')

    def test_query_with_special_characters(self, gws_env):
        """Search term with embedded quotes must be passed safely to the Drive query."""
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, '"Q1 2026" report')
        assert "Q1 2026" in " ".join(
            " ".join(call) for call in gws_env.read_log()
        )

    def test_ordered_by_modified_time(self, gws_env):
        gws_env.set_responses({"drive files list": [0, _EMPTY_FILES_RESPONSE]})
        run(SEARCH_FILES, "notes")
        assert gws_env.calls_contain("modifiedTime desc")
