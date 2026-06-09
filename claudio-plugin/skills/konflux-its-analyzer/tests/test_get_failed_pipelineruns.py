"""Tests for get_failed_pipelineruns.sh using a mock kubectl-ka binary.

All tests are fully offline — the mock script intercepts every kubectl-ka call
and returns canned JSON responses.
"""

import json

from helpers import (
    create_mock_kubectl_ka,
    make_pipelinerun_item,
    read_log,
    run_script,
    run_script_without_kubectl_ka,
)

SCRIPT_NAME = "get_failed_pipelineruns.sh"

PLR_FAILED_1 = make_pipelinerun_item(
    name="plr-failed-cuda-abc",
    created="2026-04-16T10:00:00Z",
    component="rhaiis-cuda-ubi9",
    scenario="rhaiis-test-vllm-podman-cuda-x86-64",
)

PLR_FAILED_2 = make_pipelinerun_item(
    name="plr-failed-neuron-def",
    created="2026-04-16T14:00:00Z",
    component="rhaiis-neuron-ubi9",
    scenario="rhaiis-test-vllm-podman-neuron-x86-64",
    succeeded_reason="CouldntGetTask",
)

PLR_SUCCEEDED = make_pipelinerun_item(
    name="plr-succeeded-xyz",
    created="2026-04-16T12:00:00Z",
    succeeded_status="True",
    succeeded_reason="Succeeded",
)

PLR_LIST_MIXED = json.dumps({"items": [PLR_FAILED_1, PLR_SUCCEEDED, PLR_FAILED_2]})
PLR_LIST_EMPTY = json.dumps({"items": []})
PLR_LIST_ONE = json.dumps({"items": [PLR_FAILED_1]})


class TestMissingArgs:
    def test_no_args(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(mock_dir, SCRIPT_NAME, [])
        assert result.returncode == 1
        assert "Usage" in result.stderr

    def test_one_arg(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant"])
        assert result.returncode == 1

    def test_unknown_option(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "1d", "--verbose"])
        assert result.returncode == 1
        assert "Unknown option" in result.stderr


class TestEnvChecks:
    def test_missing_kubeconfig(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "1d"],
            env_extras={"KUBECONFIG": ""},
        )
        assert result.returncode == 1
        assert "KUBECONFIG" in result.stderr

    def test_missing_kubearchive_host(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "1d"],
            env_extras={"KUBEARCHIVE_HOST": ""},
        )
        assert result.returncode == 1
        assert "KUBEARCHIVE_HOST" in result.stderr

    def test_missing_kubectl_ka(self):
        result = run_script_without_kubectl_ka(SCRIPT_NAME, ["ai-tenant", "1d"])
        assert result.returncode == 1
        assert "kubectl-ka" in result.stderr


class TestInvalidTimeSpec:
    def test_invalid_format(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "abc"])
        assert result.returncode == 1
        assert "Invalid time-spec" in result.stderr

    def test_invalid_unit(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "5m"])
        assert result.returncode == 1
        assert "Invalid time-spec" in result.stderr


class TestSuccessfulQuery:
    def test_returns_failed_pipelineruns_json(self, tmp_path):
        mock_dir, log_file = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_MIXED),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2026-04-16"])
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert len(output) == 2
        assert output[0]["name"] == "plr-failed-cuda-abc"
        assert output[1]["name"] == "plr-failed-neuron-def"

    def test_sorted_by_creation_time(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_MIXED),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2026-04-16"])
        output = json.loads(result.stdout)
        assert output[0]["created"] < output[1]["created"]

    def test_output_fields(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_ONE),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2026-04-16"])
        output = json.loads(result.stdout)
        assert len(output) == 1
        item = output[0]

        expected_keys = {
            "name", "namespace", "created", "application", "component",
            "scenario", "optional", "event_type", "reason",
        }
        assert set(item.keys()) == expected_keys
        assert item["namespace"] == "ai-tenant"
        assert item["application"] == "rhaiis"
        assert item["reason"] == "Failed"

    def test_empty_results(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2026-04-16"])
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output == []

    def test_filters_by_date_range(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_MIXED),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "2026-04-14..2026-04-16"],
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert len(output) == 2

    def test_relative_hours(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "4h"])
        assert result.returncode == 0

    def test_relative_days(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2d"])
        assert result.returncode == 0

    def test_relative_weeks(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        result = run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "1w"])
        assert result.returncode == 0


class TestHumanOutput:
    def test_human_flag_produces_table(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_MIXED),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "2026-04-16", "--human"],
        )
        assert result.returncode == 0
        assert "NAME" in result.stdout
        assert "SCENARIO" in result.stdout
        assert "plr-failed-cuda-abc" in result.stdout

    def test_human_empty_results(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "2026-04-16", "--human"],
        )
        assert result.returncode == 0
        assert "No failed" in result.stdout


class TestKubectlKaCalls:
    def test_passes_correct_args(self, tmp_path):
        mock_dir, log_file = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_LIST_EMPTY),
        })
        run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "2026-04-16"])

        calls = read_log(log_file)
        assert len(calls) == 1
        assert "-n ai-tenant" in calls[0]
        assert "--kubeconfig /tmp/fake-kubeconfig" in calls[0]
        assert "--host https://fake-kubearchive.example.com" in calls[0]
        assert "-l pipelines.appstudio.openshift.io/type=test" in calls[0]
