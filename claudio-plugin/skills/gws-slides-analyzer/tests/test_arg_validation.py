"""Argument validation tests for gws-slides-analyzer scripts.

All tests exercise argument-parsing only — no ``gws`` call is made because
the scripts exit before reaching network operations.
"""

import pathlib
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
READ_SLIDE = _SCRIPTS / "read_slide.sh"
SEARCH_SLIDES = _SCRIPTS / "search_slides.sh"


def run(script, *args):
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# read_slide.sh
# ---------------------------------------------------------------------------


class TestReadSlideArgValidation:

    def test_no_args_exits_1(self):
        r = run(READ_SLIDE)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(READ_SLIDE, "PRES_ID_123", "--bogus-flag")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_presentation_id_accepted(self):
        """A presentation ID alone must pass arg parsing (may fail at gws)."""
        r = run(READ_SLIDE, "PRES_ID_123")
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(READ_SLIDE, "PRES_ID_123", "--human")
        assert "Unknown option" not in r.stderr


# ---------------------------------------------------------------------------
# search_slides.sh
# ---------------------------------------------------------------------------


class TestSearchSlidesArgValidation:

    def test_no_args_exits_1(self):
        r = run(SEARCH_SLIDES)
        assert r.returncode == 1
        assert "Missing required argument" in r.stderr

    def test_unknown_flag_exits_1(self):
        r = run(SEARCH_SLIDES, "my query", "--bogus-flag")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_query_accepted(self):
        """A query term must pass arg parsing (may fail at gws)."""
        r = run(SEARCH_SLIDES, "roadmap slides")
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(SEARCH_SLIDES, "roadmap", "--human")
        assert "Unknown option" not in r.stderr

    def test_limit_flag_accepted(self):
        r = run(SEARCH_SLIDES, "roadmap", "--limit", "10")
        assert "Unknown option" not in r.stderr

    @pytest.mark.parametrize("bad_limit", ["abc", "0", "-1"])
    def test_limit_invalid_values_exits_1(self, bad_limit):
        r = run(SEARCH_SLIDES, "roadmap", "--limit", bad_limit)
        assert r.returncode == 1
        assert "--limit" in r.stderr

    def test_limit_missing_value_exits_1(self):
        r = run(SEARCH_SLIDES, "roadmap", "--limit")
        assert r.returncode == 1
        assert "--limit" in r.stderr

    @pytest.mark.parametrize("query", [
        "Q1 roadmap",
        "architecture overview",
        "release 1.2.3",
        '"Q1 2026" roadmap',
    ])
    def test_various_queries_accepted(self, query):
        r = run(SEARCH_SLIDES, query)
        assert "Missing required argument" not in r.stderr
        assert "Unknown option" not in r.stderr
