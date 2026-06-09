"""Tests for analyze_its_failure.sh using a mock kubectl-ka binary.

All tests are fully offline — the mock script intercepts every kubectl-ka call
and returns canned JSON responses.
"""

import json

from helpers import (
    create_mock_kubectl_ka,
    make_pipelinerun_item,
    make_taskrun_item,
    read_log,
    run_script,
    run_script_without_kubectl_ka,
)

SCRIPT_NAME = "analyze_its_failure.sh"

FAILED_PLR = make_pipelinerun_item(
    name="test-plr-abc123",
    event_type="Merge_Request",
    pr_number="351",
)

SUCCEEDED_PLR = make_pipelinerun_item(
    name="test-plr-ok",
    succeeded_status="True",
    succeeded_reason="Succeeded",
)

PUSH_PLR = make_pipelinerun_item(
    name="test-plr-push",
    event_type="push",
    pr_number="",
)

FAILED_TASKRUN = make_taskrun_item()

FAILED_TASKRUN_2 = make_taskrun_item(
    name="test-plr-abc123-build-image",
    task="build-image",
    steps=[
        {
            "name": "build",
            "terminated": {"exitCode": 2, "reason": "Error"},
        }
    ],
)

TASKRUN_NO_FAILED_STEPS = make_taskrun_item(
    name="test-plr-abc123-setup",
    task="setup",
    steps=[
        {
            "name": "init",
            "terminated": {"exitCode": 0, "reason": "Completed"},
        }
    ],
    succeeded_status="True",
)

PLR_RESPONSE_FAILED = json.dumps({"items": [FAILED_PLR]})
PLR_RESPONSE_SUCCEEDED = json.dumps({"items": [SUCCEEDED_PLR]})
PLR_RESPONSE_PUSH = json.dumps({"items": [PUSH_PLR]})
PLR_RESPONSE_EMPTY = json.dumps({"items": []})

TR_RESPONSE_ONE_FAILED = json.dumps({"items": [FAILED_TASKRUN]})
TR_RESPONSE_TWO_FAILED = json.dumps({"items": [FAILED_TASKRUN, FAILED_TASKRUN_2]})
TR_RESPONSE_NONE_FAILED = json.dumps({"items": [TASKRUN_NO_FAILED_STEPS]})
TR_RESPONSE_EMPTY = json.dumps({"items": []})


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
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "test-plr", "--verbose"],
        )
        assert result.returncode == 1
        assert "Unknown option" in result.stderr


class TestEnvChecks:
    def test_missing_kubeconfig(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "test-plr"],
            env_extras={"KUBECONFIG": ""},
        )
        assert result.returncode == 1
        assert "KUBECONFIG" in result.stderr

    def test_missing_kubearchive_host(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {})
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "test-plr"],
            env_extras={"KUBEARCHIVE_HOST": ""},
        )
        assert result.returncode == 1
        assert "KUBEARCHIVE_HOST" in result.stderr

    def test_missing_kubectl_ka(self):
        result = run_script_without_kubectl_ka(SCRIPT_NAME, ["ai-tenant", "test-plr"])
        assert result.returncode == 1
        assert "kubectl-ka" in result.stderr


class TestPipelineRunNotFound:
    def test_empty_items(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_EMPTY),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-missing"],
        )
        assert result.returncode == 1
        assert "not found" in result.stderr


class TestPipelineRunNotFailed:
    def test_succeeded_plr(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_SUCCEEDED),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-ok"],
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["status"] == "not failed"
        assert "not failed" in result.stderr


class TestSuccessfulAnalysis:
    def test_one_failed_task(self, tmp_path):
        mock_dir, log_file = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "ERROR: test-inference failed at step 42\nAssertionError: expected 200 got 500"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert output["pipelinerun"] == "test-plr-abc123"
        assert output["namespace"] == "ai-tenant"
        assert output["status"] == "Failed"
        assert output["application"] == "rhaiis"
        assert output["component"] == "rhaiis-cuda-ubi9"
        assert output["scenario"] == "rhaiis-test-vllm-podman-cuda-x86-64"
        assert len(output["failed_tasks"]) == 1
        assert output["failed_tasks"][0]["task"] == "test-inference"
        assert output["failed_tasks"][0]["exit_code"] == 1
        assert "test-inference" in output["analysis"]

    def test_multiple_failed_tasks(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_TWO_FAILED),
            "logs taskrun/": (0, "some error log output"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert len(output["failed_tasks"]) == 2
        task_names = {t["task"] for t in output["failed_tasks"]}
        assert "test-inference" in task_names
        assert "build-image" in task_names

    def test_no_failed_tasks(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_NONE_FAILED),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert output["failed_tasks"] == []
        assert "No failed tasks" in output["analysis"]

    def test_unauthorized_logs(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "unauthorized"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert "unavailable" in output["analysis"].lower()


class TestOutputFields:
    def test_all_expected_fields(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "error log"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        output = json.loads(result.stdout)

        expected_keys = {
            "pipelinerun", "namespace", "status", "summary",
            "event_type", "commit_sha", "application", "component",
            "scenario", "optional", "repo_url", "log_url",
            "failed_tasks", "analysis",
        }
        assert expected_keys.issubset(set(output.keys()))

    def test_merge_request_url_present(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "error log"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"],
        )
        output = json.loads(result.stdout)

        assert "merge_request" in output
        assert "/-/merge_requests/351" in output["merge_request"]

    def test_no_merge_request_for_push(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_PUSH),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "error log"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-push"],
        )
        output = json.loads(result.stdout)

        assert "merge_request" not in output


class TestHumanOutput:
    def test_human_flag_produces_report(self, tmp_path):
        mock_dir, _ = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "error log"),
        })
        result = run_script(
            mock_dir, SCRIPT_NAME,
            ["ai-tenant", "test-plr-abc123", "--human"],
        )
        assert result.returncode == 0
        assert "ITS Failure Analysis Report" in result.stdout
        assert "test-plr-abc123" in result.stdout
        assert "rhaiis" in result.stdout


class TestKubectlKaCalls:
    def test_fetches_plr_then_taskruns_then_logs(self, tmp_path):
        mock_dir, log_file = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_ONE_FAILED),
            "logs taskrun/": (0, "error output"),
        })
        run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"])

        calls = read_log(log_file)
        assert len(calls) == 3
        assert "get pipelineruns" in calls[0]
        assert "get taskruns" in calls[1]
        assert "logs taskrun/" in calls[2]

    def test_taskrun_label_selector(self, tmp_path):
        mock_dir, log_file = create_mock_kubectl_ka(tmp_path, {
            "get pipelineruns": (0, PLR_RESPONSE_FAILED),
            "get taskruns": (0, TR_RESPONSE_EMPTY),
        })
        run_script(mock_dir, SCRIPT_NAME, ["ai-tenant", "test-plr-abc123"])

        calls = read_log(log_file)
        tr_call = next((c for c in calls if "get taskruns" in c), None)
        assert tr_call is not None, "expected a 'get taskruns' call in kubectl log"
        assert "tekton.dev/pipelineRun=test-plr-abc123" in tr_call
