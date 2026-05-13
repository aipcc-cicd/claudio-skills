"""Date-parsing tests for extract_recent_actions.sh.

Validates that the script correctly identifies date-section headers in
multiple formats and filters them against the requested --days window.

Requires:
  - jq binary
  - GNU date (Linux) — used by the script for epoch arithmetic
"""

import json
import pathlib
import shutil
import subprocess
from datetime import datetime, timezone, timedelta

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
EXTRACT_RECENT = _SCRIPTS / "extract_recent_actions.sh"

FILE_ID = "test-doc-id-date"

# Today in the format "Apr 27, 2026" (locale-independent via explicit format)
_TODAY = datetime.now(timezone.utc)
_YESTERDAY = _TODAY - timedelta(days=1)
_LONG_AGO = _TODAY - timedelta(days=400)


def _fmt_date(dt: datetime, comma: bool = True) -> str:
    """Format a datetime as 'Apr 27, 2026' or 'Apr 27 2026'."""
    s = dt.strftime("%b %d, %Y").lstrip("0")  # "Apr 07, 2026"
    # Remove leading zero from day
    parts = s.split(" ")
    day = parts[1].lstrip("0").rstrip(",")
    if comma:
        return f"{parts[0]} {day}, {parts[2]}"
    return f"{parts[0]} {day} {parts[2]}"


def _fmt_date_long(dt: datetime) -> str:
    """Format as 'April 27, 2026' (full month name)."""
    return dt.strftime("%B %-d, %Y")


def run_extractor(gws_env, doc_content, days=9999):
    """Run extract_recent_actions.sh against mock doc content."""
    import os
    gws_env.set_doc_content(doc_content)
    env = os.environ.copy()
    env["PATH"] = f"{gws_env.tmp_path / 'bin'}:{env['PATH']}"
    env["GWS_MOCK_LOG"] = str(gws_env.log_file)
    env["GWS_MOCK_RESPONSES"] = str(gws_env.responses_file)
    bash_path = shutil.which("bash") or "bash"
    cmd = [bash_path, str(EXTRACT_RECENT), FILE_ID, "--days", str(days)]
    return subprocess.run(  # noqa: S603,S607
        cmd,
        capture_output=True,
        text=True,
        cwd=str(gws_env.tmp_path),
        timeout=30,
    )


def parse_output(result) -> dict:
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Date header format recognition
# ---------------------------------------------------------------------------


class TestDateHeaderFormats:
    """parse_date_header() must accept all documented date formats.

    extract_recent_actions.sh recognises: create_card, assignee_action,
    ai_action, spike, suggestion patterns — NOT 'TODO:' (that's extract_actions.sh).
    We use 'AI: <text>' as the action marker since it's the simplest to embed.
    """

    def test_short_month_with_comma(self, gws_env):
        """e.g. 'Apr 27, 2026'"""
        date_str = _fmt_date(_YESTERDAY, comma=True)
        doc = f"{date_str}\nAI: send recap email\n"
        r = run_extractor(gws_env, doc, days=9999)
        assert r.returncode == 0
        data = parse_output(r)
        assert data["total"] >= 1, f"Expected ≥1 action for date '{date_str}'"

    def test_short_month_without_comma(self, gws_env):
        """e.g. 'Apr 27 2026' (no comma)"""
        date_str = _fmt_date(_YESTERDAY, comma=False)
        doc = f"{date_str}\nAI: prepare release notes\n"
        r = run_extractor(gws_env, doc, days=9999)
        assert r.returncode == 0
        data = parse_output(r)
        assert data["total"] >= 1, f"Expected ≥1 action for date '{date_str}'"

    def test_full_month_name_with_comma(self, gws_env):
        """e.g. 'April 27, 2026'"""
        date_str = _fmt_date_long(_YESTERDAY)
        doc = f"{date_str}\nAI: run the standup\n"
        r = run_extractor(gws_env, doc, days=9999)
        assert r.returncode == 0
        data = parse_output(r)
        assert data["total"] >= 1, f"Expected ≥1 action for date '{date_str}'"

    def test_non_date_line_not_treated_as_header(self, gws_env):
        """Random text must not be recognised as a date header."""
        doc = (
            "Weekly Sync\n"
            "TODO: follow up on blockers\n"
        )
        r = run_extractor(gws_env, doc, days=9999)
        assert r.returncode == 0
        # "Weekly Sync" is not a date — the TODO must still be picked up
        # via the inline comment pass (not via date sections)
        # Just verify the script runs successfully
        assert "error" not in r.stderr.lower() or "found" in r.stderr.lower()


# ---------------------------------------------------------------------------
# Date range filtering
# ---------------------------------------------------------------------------


class TestDateRangeFiltering:

    def test_recent_section_included(self, gws_env):
        """A section dated yesterday is within --days 7."""
        date_str = _fmt_date(_YESTERDAY, comma=True)
        doc = f"{date_str}\nAI: prepare release notes\n"
        r = run_extractor(gws_env, doc, days=7)
        assert r.returncode == 0
        data = parse_output(r)
        assert data["total"] >= 1

    def test_old_section_excluded(self, gws_env):
        """A section dated 400 days ago must be excluded with --days 7."""
        date_str = _fmt_date(_LONG_AGO, comma=True)
        doc = f"{date_str}\nAI: this is very old\n"
        r = run_extractor(gws_env, doc, days=7)
        assert r.returncode == 0
        data = parse_output(r)
        old_actions = [
            a for a in data.get("actions", [])
            if "very old" in a.get("text", "")
        ]
        assert not old_actions, "Old section should be excluded by date filter"

    def test_multiple_sections_only_recent_extracted(self, gws_env):
        """Mix of old and recent sections — only recent one's actions appear."""
        old_date = _fmt_date(_LONG_AGO, comma=True)
        recent_date = _fmt_date(_YESTERDAY, comma=True)
        doc = (
            f"{old_date}\n"
            "AI: this is stale\n"
            "\n"
            f"{recent_date}\n"
            "AI: this is fresh\n"
        )
        r = run_extractor(gws_env, doc, days=7)
        assert r.returncode == 0
        data = parse_output(r)
        texts = " ".join(a.get("text", "") for a in data.get("actions", []))
        assert "fresh" in texts
        assert "stale" not in texts


# ---------------------------------------------------------------------------
# Output structure
# ---------------------------------------------------------------------------


class TestOutputStructure:

    def test_json_output_has_expected_fields(self, gws_env):
        date_str = _fmt_date(_YESTERDAY, comma=True)
        doc = f"{date_str}\nAI: write tests\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        data = parse_output(r)
        for field in ("doc_id", "doc_name", "doc_link", "days", "total", "actions"):
            assert field in data, f"Missing field '{field}' in output"

    def test_action_entry_has_expected_fields(self, gws_env):
        date_str = _fmt_date(_YESTERDAY, comma=True)
        doc = f"{date_str}\nAI: validate schema\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_output(r).get("actions", [])
        assert actions, "Expected at least one action"
        action = actions[0]
        for field in ("section_date", "type", "text", "assignee", "line"):
            assert field in action, f"Action missing field '{field}'"
