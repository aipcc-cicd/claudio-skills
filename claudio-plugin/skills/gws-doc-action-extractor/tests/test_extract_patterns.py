"""Pattern-extraction tests for extract_actions.sh.

The mock ``gws`` binary returns pre-crafted document text so we can verify
that every action-detection regex works correctly — without any Google
Workspace connection.

Requires:
  - jq binary (standard DevOps tooling, available in the test environment)
  - bash 4+ (mapfile, [[ ]])
"""

import json
import pathlib
import subprocess

import pytest

_SCRIPTS = pathlib.Path(__file__).parent.parent / "scripts"
EXTRACT_ACTIONS = _SCRIPTS / "extract_actions.sh"

FILE_ID = "test-doc-id-001"


def run_extractor(gws_env, doc_content, extra_args=None):
    """Run extract_actions.sh against mock doc content, return CompletedProcess."""
    import os
    gws_env.set_doc_content(doc_content)
    env = os.environ.copy()
    env["PATH"] = f"{gws_env.tmp_path / 'bin'}:{env['PATH']}"
    env["GWS_MOCK_LOG"] = str(gws_env.log_file)
    env["GWS_MOCK_RESPONSES"] = str(gws_env.responses_file)
    cmd = ["bash", str(EXTRACT_ACTIONS), FILE_ID] + (extra_args or [])
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(gws_env.tmp_path),   # mktemp ./gws-* runs here
        timeout=30,
    )


def parse_actions(result) -> list[dict]:
    """Parse the JSON output from extract_actions.sh."""
    data = json.loads(result.stdout)
    return data.get("actions", [])


# ---------------------------------------------------------------------------
# Action items section
# ---------------------------------------------------------------------------


class TestActionItemsSection:

    def test_section_header_triggers_extraction(self, gws_env):
        doc = (
            "Meeting summary\n"
            "\n"
            "Action items:\n"
            "* Fix the CI pipeline\n"
            "* Update documentation\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        texts = [a["text"] for a in actions]
        assert any("Fix the CI pipeline" in t for t in texts)
        assert any("Update documentation" in t for t in texts)

    def test_section_items_have_correct_type(self, gws_env):
        doc = (
            "Action items:\n"
            "* Deploy the service\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        action_item_types = [a["type"] for a in actions if "Deploy" in a["text"]]
        assert action_item_types and action_item_types[0] == "action_item"

    def test_section_ends_at_separator(self, gws_env):
        """Items after a separator line must NOT be included in the action section."""
        doc = (
            "Action items:\n"
            "* Real action\n"
            "______________________________\n"
            "* Not an action\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        texts = " ".join(a["text"] for a in actions if a["type"] == "action_item")
        assert "Real action" in texts
        assert "Not an action" not in texts

    def test_assignee_extracted_from_bracket_prefix(self, gws_env):
        """'[Alice] to ...' in action section should set assignee = 'Alice'."""
        doc = (
            "Action items:\n"
            "* [Alice] to review the PR\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        alice_actions = [a for a in actions if "Alice" in a.get("assignee", "")]
        assert alice_actions, "Expected assignee 'Alice' to be extracted"


# ---------------------------------------------------------------------------
# TODO / ACTION / FOLLOW UP markers
# ---------------------------------------------------------------------------


class TestTodoMarkers:

    @pytest.mark.parametrize("prefix,text", [
        ("TODO", "Refactor the auth module"),
        ("ACTION", "Send the release email"),
        ("FOLLOW UP", "Check with the QA team"),
        ("FOLLOWUP", "Verify staging deploy"),
    ])
    def test_marker_prefix_detected(self, gws_env, prefix, text):
        doc = f"{prefix}: {text}\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        matched = [a for a in actions if text in a["text"]]
        assert matched, f"Expected to extract text from '{prefix}: {text}'"

    def test_todo_action_type_is_todo(self, gws_env):
        doc = "TODO: Write unit tests\n"
        r = run_extractor(gws_env, doc)
        actions = parse_actions(r)
        todo_actions = [a for a in actions if a["type"] == "todo"]
        assert todo_actions


# ---------------------------------------------------------------------------
# [Name] to ... assignee-action pattern
# ---------------------------------------------------------------------------


class TestAssigneeActionPattern:

    def test_bracket_name_to_pattern(self, gws_env):
        doc = "[Bob] to schedule the retrospective\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        bob_actions = [a for a in actions if "Bob" in a.get("assignee", "")]
        assert bob_actions, "Expected [Bob] assignee action to be extracted"

    def test_bracket_name_will_pattern(self, gws_env):
        doc = "[Carol] will update the runbook\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        carol_actions = [a for a in actions if "Carol" in a.get("assignee", "")]
        assert carol_actions

    def test_create_card_pattern(self, gws_env):
        doc = "We should create a card for the observability spike\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        create_card_types = [a for a in actions if a["type"] == "create_card"]
        assert create_card_types

    def test_open_a_ticket_pattern(self, gws_env):
        doc = "Someone needs to open a ticket for the performance regression\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        create_card_types = [a for a in actions if a["type"] == "create_card"]
        assert create_card_types

    def test_file_a_bug_pattern(self, gws_env):
        doc = "file a bug for the login failure\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        assert any(a["type"] == "create_card" for a in actions)


# ---------------------------------------------------------------------------
# Inline doc comments ([a]text, [b]text, ...)
# ---------------------------------------------------------------------------


class TestInlineDocComments:

    def test_create_ticket_comment_extracted(self, gws_env):
        doc = "[a]create a ticket for this\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        comment_actions = [a for a in actions if a["type"] == "doc_comment"]
        assert comment_actions

    def test_action_comment_extracted(self, gws_env):
        doc = "[b]action needed: follow up with vendor\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        assert any(a["type"] == "doc_comment" for a in actions)

    def test_non_actionable_comment_skipped(self, gws_env):
        # Text must contain none of: create, ticket, card, jira, bug, open,
        # action, TODO, follow-up — the inline comment filter uses these keywords
        doc = "[c]just a general observation about the quarterly numbers\n"
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        comment_actions = [a for a in actions if a["type"] == "doc_comment"]
        assert not comment_actions


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------


class TestDeduplication:

    def test_same_text_deduplicated(self, gws_env):
        """The same action text matched by multiple patterns must appear only once."""
        # This line matches both the action_item section and the create_card pattern
        doc = (
            "Action items:\n"
            "* create a card for the onboarding flow\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        texts = [a["text"] for a in actions]
        # Should not appear more than once
        assert len(texts) == len(set(texts)), f"Duplicates found: {texts}"


# ---------------------------------------------------------------------------
# Empty document
# ---------------------------------------------------------------------------


class TestEmptyDocument:

    def test_empty_doc_returns_empty_actions(self, gws_env):
        r = run_extractor(gws_env, "")
        assert r.returncode == 0
        actions = parse_actions(r)
        assert actions == []

    def test_doc_with_no_action_patterns_returns_empty(self, gws_env):
        doc = (
            "This is a regular meeting summary.\n"
            "We discussed quarterly goals.\n"
            "The team had a productive session.\n"
        )
        r = run_extractor(gws_env, doc)
        assert r.returncode == 0
        actions = parse_actions(r)
        assert actions == []
