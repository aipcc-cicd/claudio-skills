"""Tests for create_and_protect_branch.sh using a mock glab binary.

All tests are fully offline — the mock glab script intercepts every API call
and returns canned JSON responses. No real GitLab branches are created.
"""

import json
import os
import stat
import subprocess
import textwrap

import pytest

SCRIPT_DIR = os.path.join(os.path.dirname(__file__), "..", "scripts")
SCRIPT_PATH = os.path.join(SCRIPT_DIR, "create_and_protect_branch.sh")


def _create_mock_glab(tmp_path, behavior):
    """Create a mock glab script that returns predefined responses.

    Args:
        tmp_path: pytest tmp_path fixture for temp files
        behavior: dict mapping endpoint patterns to (exit_code, stdout) tuples.
            Keys are substring-matched against the glab arguments.
    """
    log_file = tmp_path / "glab_calls.log"
    mock_script = tmp_path / "glab"

    # Write behavior to a responses file, matched by line-by-line substring search
    responses_file = tmp_path / "glab_responses.txt"
    lines = []
    for pattern, (exit_code, response) in behavior.items():
        # Format: PATTERN\tEXIT_CODE\tRESPONSE (tab-separated)
        # Escape newlines in response
        escaped_response = response.replace("\n", "\\n")
        lines.append(f"{pattern}\t{exit_code}\t{escaped_response}")
    responses_file.write_text("\n".join(lines) + "\n" if lines else "")

    mock_content = f"""#!/usr/bin/env bash
# Mock glab - logs calls and returns predefined responses
ARGS="$*"
echo "$ARGS" >> "{log_file}"

while IFS=$'\\t' read -r pattern exit_code response; do
    [ -z "$pattern" ] && continue
    if echo "$ARGS" | grep -qF -- "$pattern"; then
        printf '%b\\n' "$response"
        exit "$exit_code"
    fi
done < "{responses_file}"

echo '{{"error": "mock glab: unhandled call"}}' >&2
exit 1
"""

    mock_script.write_text(mock_content)
    mock_script.chmod(mock_script.stat().st_mode | stat.S_IEXEC)

    return str(tmp_path), str(log_file)


def _run_script(mock_dir, args, env_extras=None):
    """Run create_and_protect_branch.sh with mock glab on PATH."""
    env = os.environ.copy()
    env["PATH"] = f"{mock_dir}:{env['PATH']}"
    if env_extras:
        env.update(env_extras)

    result = subprocess.run(
        ["bash", SCRIPT_PATH] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    return result


def _read_log(log_file):
    """Read the glab call log and return list of calls."""
    if not os.path.exists(log_file):
        return []
    with open(log_file) as f:
        return [line.strip() for line in f.readlines() if line.strip()]


# --- Fixtures ---


BRANCH_JSON = json.dumps({
    "name": "release-1.5",
    "commit": {"id": "abc123", "short_id": "abc123"},
    "protected": False,
    "default": False,
})

PROTECTION_JSON_DEFAULT = json.dumps({
    "name": "release-1.5",
    "push_access_levels": [{"access_level": 0, "access_level_description": "No one"}],
    "merge_access_levels": [{"access_level": 40, "access_level_description": "Maintainers"}],
    "allow_force_push": False,
    "code_owner_approval_required": False,
})

PROTECTION_JSON_DIFFERENT = json.dumps({
    "name": "release-1.5",
    "push_access_levels": [{"access_level": 30, "access_level_description": "Developers + Maintainers"}],
    "merge_access_levels": [{"access_level": 30, "access_level_description": "Developers + Maintainers"}],
    "allow_force_push": False,
    "code_owner_approval_required": False,
})

PROJECT_JSON = json.dumps({
    "id": 123,
    "path": "repo",
    "path_with_namespace": "owner/repo",
})

PROJECT_JSON_DEEP = json.dumps({
    "id": 456,
    "path": "my-project",
    "path_with_namespace": "acme/platform/ci-cd/my-project",
})

SEARCH_RESULT_SINGLE = json.dumps([{
    "id": 123,
    "path": "my-project",
    "path_with_namespace": "acme/platform/ci-cd/my-project",
}])

SEARCH_RESULT_MULTIPLE = json.dumps([
    {"id": 123, "path": "myrepo", "path_with_namespace": "group-a/myrepo"},
    {"id": 456, "path": "myrepo", "path_with_namespace": "group-b/myrepo"},
])


# --- Tests ---


class TestHappyPath:
    """Branch doesn't exist, not protected — creates and protects."""

    def test_creates_branch_and_protects(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # Specific patterns first (matched before generic project validation)
            # GET branch → 404 (doesn't exist)
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404 Not Found"}'),
            # POST create branch → success
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            # GET protected branch → 404 (not protected)
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (1, '{"error": "404 Not Found"}'),
            # POST protect → success
            "--method POST projects/owner%2Frepo/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation, matched last)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, ["owner/repo", "release-1.5", "main"])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["repository"] == "owner/repo"
        assert output["branch"] == "release-1.5"
        assert output["ref"] == "main"
        assert output["branch_created"] is True
        assert output["protection_applied"] is True
        assert output["protection_rules"]["push_access_level"] == 0
        assert output["protection_rules"]["merge_access_level"] == 40
        assert output["protection_rules"]["allow_force_push"] is False
        assert output["protection_rules"]["code_owner_approval_required"] is False
        assert "unprotect_access_level" not in output["protection_rules"]

        # Verify API calls were made
        calls = _read_log(log_file)
        assert any("--method POST" in c and "repository/branches" in c for c in calls)
        assert any("--method POST" in c and "protected_branches" in c for c in calls)


class TestBranchExists:
    """Branch already exists — should fail."""

    def test_fails_if_branch_exists(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # GET branch → 200 (exists)
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (0, BRANCH_JSON),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, ["owner/repo", "release-1.5", "main"])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "already exists" in output["error"]
        assert output["branch"] == "release-1.5"

        # Verify no POST calls were made
        calls = _read_log(log_file)
        assert not any("--method POST" in c for c in calls)


class TestProtectionIdempotency:
    """Protection already exists with matching or different rules."""

    def test_protection_already_matches(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            # GET protected → 200 with matching rules
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, ["owner/repo", "release-1.5", "main"])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["branch_created"] is True
        assert output["protection_applied"] is False
        assert output["protection_already_existed"] is True
        assert "already protected" in result.stderr

        # No POST to protected_branches
        calls = _read_log(log_file)
        assert not any(
            "--method POST" in c and "protected_branches" in c for c in calls
        )

    def test_fails_if_protection_differs(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            # GET protected → 200 with DIFFERENT rules
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (0, PROTECTION_JSON_DIFFERENT),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, ["owner/repo", "release-1.5", "main"])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "different rules" in output["error"]
        assert "current_rules" in output
        assert "requested_rules" in output


class TestCustomProtection:
    """Custom protection levels via flags."""

    def test_custom_protection_levels(self, tmp_path):
        custom_protection = json.dumps({
            "name": "release-1.5",
            "push_access_levels": [{"access_level": 30, "access_level_description": "Developers + Maintainers"}],
            "merge_access_levels": [{"access_level": 30, "access_level_description": "Developers + Maintainers"}],
            "allow_force_push": False,
            "code_owner_approval_required": False,
        })

        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/protected_branches":
                (0, custom_protection),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "main",
            "--push-level", "30",
            "--merge-level", "30",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["protection_rules"]["push_access_level"] == 30
        assert output["protection_rules"]["merge_access_level"] == 30

        # Verify the POST included correct values
        calls = _read_log(log_file)
        protect_call = [c for c in calls if "--method POST" in c and "protected_branches" in c]
        assert len(protect_call) == 1
        assert "push_access_level=30" in protect_call[0]
        assert "merge_access_level=30" in protect_call[0]


class TestDryRun:
    """Dry run mode — no API calls."""

    def test_dry_run_no_mutation_calls(self, tmp_path):
        # Dry run validates repo exists but makes no mutation (POST) calls
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # GET project → 200 (repo validation still runs in dry-run)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "main", "--dry-run",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["dry_run"] is True
        assert output["repository"] == "owner/repo"
        assert output["branch"] == "release-1.5"
        assert output["ref"] == "main"
        assert "planned_protection_rules" in output
        assert output["planned_protection_rules"]["push_access_level"] == 0
        assert output["planned_protection_rules"]["merge_access_level"] == 40

        # Only validation call — no POST (mutation) calls
        calls = _read_log(log_file)
        assert not any("--method POST" in c for c in calls)


class TestMissingArgs:
    """Missing required arguments."""

    def test_missing_repo(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {})
        result = _run_script(mock_dir, [])
        assert result.returncode == 1

    def test_missing_branch(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {})
        result = _run_script(mock_dir, ["owner/repo"])
        assert result.returncode == 1

    def test_missing_ref(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {})
        result = _run_script(mock_dir, ["owner/repo", "release-1.5"])
        assert result.returncode == 1


class TestRepoResolution:
    """Repo input format resolution."""

    def test_short_repo_name_resolved(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # Search API
            "projects?search=my-project":
                (0, SEARCH_RESULT_SINGLE),
            "--method GET projects/acme%2Fplatform%2Fci-cd%2Fmy-project/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/acme%2Fplatform%2Fci-cd%2Fmy-project/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/acme%2Fplatform%2Fci-cd%2Fmy-project/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/acme%2Fplatform%2Fci-cd%2Fmy-project/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
        })

        result = _run_script(mock_dir, ["my-project", "release-1.5", "main"])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["repository"] == "acme/platform/ci-cd/my-project"
        assert "Resolved to" in result.stderr

    def test_full_url_parsed(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/acme%2Fplatform%2Fci-cd%2Fmy-project/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/acme%2Fplatform%2Fci-cd%2Fmy-project/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/acme%2Fplatform%2Fci-cd%2Fmy-project/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/acme%2Fplatform%2Fci-cd%2Fmy-project/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/acme%2Fplatform%2Fci-cd%2Fmy-project":
                (0, PROJECT_JSON_DEEP),
        })

        result = _run_script(mock_dir, [
            "https://gitlab.com/acme/platform/ci-cd/my-project.git",
            "release-1.5", "main",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["repository"] == "acme/platform/ci-cd/my-project"

    def test_git_ssh_url_parsed(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/group%2Frepo/repository/branches/feature-1":
                (1, '{"error": "404"}'),
            "--method POST projects/group%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/group%2Frepo/protected_branches/feature-1":
                (1, '{"error": "404"}'),
            "--method POST projects/group%2Frepo/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/group%2Frepo":
                (0, '{"id": 789, "path": "repo", "path_with_namespace": "group/repo"}'),
        })

        result = _run_script(mock_dir, [
            "git@gitlab.com:group/repo.git",
            "feature-1", "main",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["repository"] == "group/repo"

    def test_short_name_multiple_matches_fails(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {
            "projects?search=myrepo":
                (0, SEARCH_RESULT_MULTIPLE),
        })

        result = _run_script(mock_dir, ["myrepo", "release-1.5", "main"])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "Multiple" in output["error"]


class TestRepoValidation:
    """Repo validation — checks repo exists on GitLab."""

    def test_full_path_repo_not_found(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # GET project → 404 (repo doesn't exist)
            "--method GET projects/owner%2Fbogus-repo":
                (1, '{"error": "404 Not Found"}'),
        })

        result = _run_script(mock_dir, ["owner/bogus-repo", "release-1.5", "main"])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "not found" in output["error"].lower()
        assert output["repository"] == "owner/bogus-repo"

        # No POST calls — failed before branch creation
        calls = _read_log(log_file)
        assert not any("--method POST" in c for c in calls)

    def test_url_repo_not_found(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # GET project → 404 (repo doesn't exist)
            "--method GET projects/group%2Fnonexistent":
                (1, '{"error": "404 Not Found"}'),
        })

        result = _run_script(mock_dir, [
            "https://gitlab.com/group/nonexistent.git",
            "release-1.5", "main",
        ])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "not found" in output["error"].lower()
        assert output["repository"] == "group/nonexistent"

    def test_ssh_repo_not_found(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            # GET project → 404 (repo doesn't exist)
            "--method GET projects/org%2Fmissing":
                (1, '{"error": "404 Not Found"}'),
        })

        result = _run_script(mock_dir, [
            "git@gitlab.com:org/missing.git",
            "feature-1", "main",
        ])

        assert result.returncode == 1
        output = json.loads(result.stdout)
        assert "not found" in output["error"].lower()


class TestCustomRef:
    """Branching from a specific ref (tag, SHA, etc.)."""

    def test_custom_ref(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "v1.4.0",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["ref"] == "v1.4.0"

        # Verify ref was passed to create branch call
        calls = _read_log(log_file)
        create_call = [c for c in calls if "--method POST" in c and "repository/branches" in c]
        assert len(create_call) == 1
        assert "ref=v1.4.0" in create_call[0]


class TestHumanReadable:
    """Human-readable output mode."""

    def test_human_readable_output(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "main", "--human-readable",
        ])

        assert result.returncode == 0
        assert "Branch Operation Complete" in result.stdout
        assert "owner/repo" in result.stdout
        assert "release-1.5" in result.stdout
        assert "push_access_level" in result.stdout

    def test_dry_run_human_readable(self, tmp_path):
        mock_dir, _ = _create_mock_glab(tmp_path, {
            # GET project → 200 (repo validation still runs in dry-run)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "main", "--dry-run", "--human-readable",
        ])

        assert result.returncode == 0
        assert "Dry Run" in result.stdout
        assert "release-1.5" in result.stdout


class TestRuleOverride:
    """Generic --rule KEY=VALUE override."""

    def test_rule_override(self, tmp_path):
        mock_dir, log_file = _create_mock_glab(tmp_path, {
            "--method GET projects/owner%2Frepo/repository/branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/repository/branches":
                (0, BRANCH_JSON),
            "--method GET projects/owner%2Frepo/protected_branches/release-1.5":
                (1, '{"error": "404"}'),
            "--method POST projects/owner%2Frepo/protected_branches":
                (0, PROTECTION_JSON_DEFAULT),
            # GET project → 200 (repo validation)
            "--method GET projects/owner%2Frepo":
                (0, PROJECT_JSON),
        })

        result = _run_script(mock_dir, [
            "owner/repo", "release-1.5", "main",
            "--rule", "merge_access_level=30",
        ])

        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["protection_rules"]["merge_access_level"] == 30

        calls = _read_log(log_file)
        protect_call = [c for c in calls if "--method POST" in c and "protected_branches" in c]
        assert "merge_access_level=30" in protect_call[0]
