"""Shared helpers for konflux-its-analyzer tests.

Provides mock kubectl-ka binary creation, jq shim, script runner,
and canned data builders. All tests are fully offline.
"""

import json
import os
import shutil
import stat
import subprocess
import textwrap

SKILL_DIR = os.path.join(os.path.dirname(__file__), "..")
SCRIPTS_DIR = os.path.join(SKILL_DIR, "scripts")


def _create_jq_shim(directory):
    """Create a jq CLI shim backed by the Python jq library."""
    jq_shim = directory / "jq"
    jq_shim.write_text(textwrap.dedent("""\
        #!/usr/bin/env python3
        import sys, json
        import jq as _jq

        raw_output = False
        no_input = False
        args = {}
        argjson = {}
        filter_expr = None

        i = 1
        while i < len(sys.argv):
            a = sys.argv[i]
            if a == "-r":
                raw_output = True
            elif a == "-n":
                no_input = True
            elif a == "-e":
                pass
            elif a == "--arg":
                args[sys.argv[i+1]] = sys.argv[i+2]
                i += 2
            elif a == "--argjson":
                argjson[sys.argv[i+1]] = json.loads(sys.argv[i+2])
                i += 2
            elif filter_expr is None:
                filter_expr = a
            i += 1

        if filter_expr is None:
            filter_expr = "."

        jq_args = {**args}
        for k, v in argjson.items():
            jq_args[k] = v

        if no_input:
            data = None
        else:
            data = sys.stdin.read()

        prog = _jq.compile(filter_expr, args=jq_args)
        if no_input:
            results = prog.input_value(None).all()
        else:
            results = prog.input_text(data).all()

        for r in results:
            if raw_output and isinstance(r, str):
                print(r)
            else:
                print(json.dumps(r, ensure_ascii=False))
    """))
    jq_shim.chmod(0o755)


def create_mock_kubectl_ka(tmp_path, behaviors):
    """Create mock kubectl, kubectl-ka, and jq shim scripts.

    The scripts call ``command -v kubectl-ka`` to check the plugin exists,
    then invoke ``kubectl ka ...`` (space-separated).  We therefore need:
      - ``kubectl-ka`` — no-op stub so the existence check passes
      - ``kubectl``    — the real mock that intercepts ``kubectl ka ...``
                         calls, strips the leading ``ka`` arg, then matches
                         the remainder against *behaviors* patterns.

    Args:
        tmp_path: pytest tmp_path fixture
        behaviors: dict mapping argument substrings to (exit_code, stdout)
            tuples.  Patterns are matched against the args **after** the
            leading ``ka`` is stripped, e.g. ``"get pipelineruns"`` matches
            ``kubectl ka get pipelineruns -n ai-tenant ...``.

    Returns:
        (mock_dir, log_file) tuple
    """
    log_file = tmp_path / "kubectl_ka_calls.log"

    responses_file = tmp_path / "kubectl_ka_responses.txt"
    lines = []
    for pattern, (exit_code, response) in behaviors.items():
        escaped = response.replace("\n", "\\n")
        lines.append(f"{pattern}\t{exit_code}\t{escaped}")
    responses_file.write_text("\n".join(lines) + "\n" if lines else "")

    # kubectl-ka — satisfies ``command -v kubectl-ka``
    stub = tmp_path / "kubectl-ka"
    stub.write_text("#!/usr/bin/env bash\nexit 0\n")
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

    # kubectl — intercepts ``kubectl ka ...`` calls
    mock_kubectl = tmp_path / "kubectl"
    mock_kubectl.write_text(f"""#!/usr/bin/env bash
# Strip the leading "ka" subcommand so patterns match the rest
shift  # drop "ka"
ARGS="$*"
echo "$ARGS" >> "{log_file}"

while IFS=$'\\t' read -r pattern exit_code response; do
    [ -z "$pattern" ] && continue
    if echo "$ARGS" | grep -qF -- "$pattern"; then
        printf '%b\\n' "$response"
        exit "$exit_code"
    fi
done < "{responses_file}"

echo '{{"error": "mock kubectl: unhandled call"}}' >&2
exit 1
""")
    mock_kubectl.chmod(mock_kubectl.stat().st_mode | stat.S_IEXEC)

    _create_jq_shim(tmp_path)

    return str(tmp_path), str(log_file)


def _path_without(command):
    """Return PATH with directories containing command removed."""
    cmd_path = shutil.which(command)
    if not cmd_path:
        return os.environ.get("PATH", "")
    exclude_dir = os.path.dirname(cmd_path)
    return ":".join(
        d for d in os.environ.get("PATH", "").split(":")
        if d != exclude_dir
    )


def run_script(mock_dir, script_name, args, env_extras=None):
    """Run a skill script with mocked kubectl-ka on PATH."""
    script_path = os.path.join(SCRIPTS_DIR, script_name)
    env = os.environ.copy()
    env["PATH"] = f"{mock_dir}:{env['PATH']}"
    env["KUBECONFIG"] = "/tmp/fake-kubeconfig"
    env["KUBEARCHIVE_HOST"] = "https://fake-kubearchive.example.com"
    if env_extras:
        env.update(env_extras)

    return subprocess.run(
        ["bash", script_path] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


def run_script_without_kubectl_ka(script_name, args, env_extras=None):
    """Run a skill script with kubectl-ka removed from PATH."""
    script_path = os.path.join(SCRIPTS_DIR, script_name)
    env = os.environ.copy()
    env["PATH"] = _path_without("kubectl-ka")
    env["KUBECONFIG"] = "/tmp/fake-kubeconfig"
    env["KUBEARCHIVE_HOST"] = "https://fake-kubearchive.example.com"
    if env_extras:
        env.update(env_extras)

    return subprocess.run(
        ["bash", script_path] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


def read_log(log_file):
    """Read the kubectl-ka call log."""
    if not os.path.exists(log_file):
        return []
    with open(log_file) as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def make_pipelinerun_item(
    name="test-plr-abc123",
    namespace="ai-tenant",
    created="2026-04-16T10:00:00Z",
    succeeded_status="False",
    succeeded_reason="Failed",
    succeeded_message="Tasks Completed: 5 (Failed: 1, Cancelled 0), Skipped: 2",
    application="rhaiis",
    component="rhaiis-cuda-ubi9",
    scenario="rhaiis-test-vllm-podman-cuda-x86-64",
    optional="true",
    event_type="Merge_Request",
    commit_sha="abc123def456",
    repo_url="https://gitlab.com/redhat/rhel-ai/rhaiis/containers",
    pr_number="351",
    log_url="https://konflux-ui.apps.example.com/pipelinerun/test-plr-abc123",
):
    return {
        "metadata": {
            "name": name,
            "namespace": namespace,
            "creationTimestamp": created,
            "labels": {
                "pipelines.appstudio.openshift.io/type": "test",
                "appstudio.openshift.io/application": application,
                "appstudio.openshift.io/component": component,
                "test.appstudio.openshift.io/scenario": scenario,
                "test.appstudio.openshift.io/optional": optional,
                "pac.test.appstudio.openshift.io/event-type": event_type,
                "pac.test.appstudio.openshift.io/sha": commit_sha,
            },
            "annotations": {
                "pac.test.appstudio.openshift.io/repo-url": repo_url,
                "build.appstudio.redhat.com/pull_request_number": pr_number,
                "pac.test.appstudio.openshift.io/log-url": log_url,
            },
        },
        "status": {
            "conditions": [
                {
                    "type": "Succeeded",
                    "status": succeeded_status,
                    "reason": succeeded_reason,
                    "message": succeeded_message,
                }
            ],
        },
    }


def make_taskrun_item(
    name="test-plr-abc123-test-inference",
    pipelinerun="test-plr-abc123",
    task="test-inference",
    succeeded_status="False",
    steps=None,
):
    if steps is None:
        steps = [
            {
                "name": "run-test",
                "terminated": {
                    "exitCode": 1,
                    "reason": "Error",
                },
            }
        ]

    return {
        "metadata": {
            "name": name,
            "labels": {
                "tekton.dev/pipelineRun": pipelinerun,
                "tekton.dev/pipelineTask": task,
            },
        },
        "status": {
            "conditions": [
                {
                    "type": "Succeeded",
                    "status": succeeded_status,
                }
            ],
            "steps": steps,
        },
    }
