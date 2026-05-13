"""Argument validation tests for gws-calendar-reader scripts.

All tests exercise argument-parsing only — no ``gws`` call is made because
the scripts exit before reaching network operations.
"""

import pathlib
import shutil
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
TEAM_AGENDA = _SCRIPTS / "team_agenda.sh"
CHECK_FREEBUSY = _SCRIPTS / "check_freebusy.sh"


def run(script, *args):
    bash_path = shutil.which("bash") or "bash"
    return subprocess.run(  # noqa: S603,S607
        [bash_path, str(script), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# team_agenda.sh
# ---------------------------------------------------------------------------


class TestTeamAgendaArgValidation:

    def test_unknown_flag_exits_1(self):
        r = run(TEAM_AGENDA, "--bogus")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_email_missing_value_exits_1(self):
        r = run(TEAM_AGENDA, "--email")
        assert r.returncode == 1
        assert "--email" in r.stderr

    def test_days_missing_value_exits_1(self):
        r = run(TEAM_AGENDA, "--days")
        assert r.returncode == 1
        assert "--days" in r.stderr

    def test_days_non_numeric_exits_1(self):
        r = run(TEAM_AGENDA, "--email", "me", "--days", "abc")
        assert r.returncode == 1
        assert "positive integer" in r.stderr

    def test_days_negative_exits_1(self):
        """Negative values are not positive integers."""
        r = run(TEAM_AGENDA, "--email", "me", "--days", "-3")
        assert r.returncode == 1
        assert "positive integer" in r.stderr

    def test_timezone_missing_value_exits_1(self):
        r = run(TEAM_AGENDA, "--email", "me", "--timezone")
        assert r.returncode == 1
        assert "--timezone" in r.stderr

    def test_no_team_json_and_no_email_exits_1(self):
        """Without --email and without team.json, script must exit 1."""
        # SKILL_ROOT/team.json does not exist (only team.json.example)
        r = run(TEAM_AGENDA)
        assert r.returncode == 1
        assert "team.json" in r.stderr

    def test_email_me_passes_arg_parsing(self):
        """'--email me' is a special alias — must pass validation."""
        r = run(TEAM_AGENDA, "--email", "me")
        assert "Unknown option" not in r.stderr
        assert "--email requires" not in r.stderr

    def test_email_address_passes_arg_parsing(self):
        r = run(TEAM_AGENDA, "--email", "alice@example.com")
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(TEAM_AGENDA, "--email", "me", "--human")
        assert "Unknown option" not in r.stderr

    @pytest.mark.parametrize("valid_days", ["1", "7", "30"])
    def test_valid_days_accepted(self, valid_days):
        r = run(TEAM_AGENDA, "--email", "me", "--days", valid_days)
        assert "positive integer" not in r.stderr
        assert "Unknown option" not in r.stderr


# ---------------------------------------------------------------------------
# check_freebusy.sh
# ---------------------------------------------------------------------------


class TestCheckFreebusyArgValidation:

    def test_unknown_flag_exits_1(self):
        r = run(CHECK_FREEBUSY, "--bogus")
        assert r.returncode == 1
        assert "Unknown option" in r.stderr

    def test_emails_missing_value_exits_1(self):
        r = run(CHECK_FREEBUSY, "--emails")
        assert r.returncode == 1
        assert "--emails" in r.stderr

    def test_hours_missing_value_exits_1(self):
        r = run(CHECK_FREEBUSY, "--hours")
        assert r.returncode == 1
        assert "--hours" in r.stderr

    def test_hours_non_numeric_exits_1(self):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--hours", "many")
        assert r.returncode == 1
        assert "positive integer" in r.stderr

    def test_hours_negative_exits_1(self):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--hours", "-2")
        assert r.returncode == 1
        assert "positive integer" in r.stderr

    def test_date_missing_value_exits_1(self):
        r = run(CHECK_FREEBUSY, "--date")
        assert r.returncode == 1
        assert "--date" in r.stderr

    @pytest.mark.parametrize("bad_date", [
        "2026-5-8",       # missing leading zeros
        "08-05-2026",     # wrong order
        "2026/05/08",     # slashes instead of dashes
        "not-a-date",
        "20260508",       # no separators
    ])
    def test_invalid_date_format_exits_1(self, bad_date):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--date", bad_date)
        assert r.returncode == 1
        assert "YYYY-MM-DD" in r.stderr

    def test_valid_date_format_passes(self):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--date", "2026-05-08")
        assert "YYYY-MM-DD" not in r.stderr
        assert "Unknown option" not in r.stderr

    def test_timezone_missing_value_exits_1(self):
        r = run(CHECK_FREEBUSY, "--timezone")
        assert r.returncode == 1
        assert "--timezone" in r.stderr

    def test_today_flag_accepted(self):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--today")
        assert "Unknown option" not in r.stderr

    def test_human_flag_accepted(self):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--human")
        assert "Unknown option" not in r.stderr

    def test_no_team_json_and_no_emails_exits_1(self):
        """Without --emails and without team.json, script must exit 1."""
        r = run(CHECK_FREEBUSY)
        assert r.returncode == 1
        assert "team.json" in r.stderr

    @pytest.mark.parametrize("valid_hours", ["1", "8", "24"])
    def test_valid_hours_accepted(self, valid_hours):
        r = run(CHECK_FREEBUSY, "--emails", "a@b.com", "--hours", valid_hours)
        assert "positive integer" not in r.stderr
        assert "Unknown option" not in r.stderr
