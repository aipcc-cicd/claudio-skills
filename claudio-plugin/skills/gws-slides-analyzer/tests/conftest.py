"""Shared fixtures for gws-slides-analyzer skill tests.

The mock ``gws`` binary intercepts all CLI calls without network access.

Environment variables read by the stub:
  GWS_MOCK_LOG        Path to append one JSON-encoded arg-list per call.
  GWS_MOCK_RESPONSES  Path to a JSON file mapping substring patterns to
                      [exit_code, response_body] pairs.
"""

import json
import os
import pathlib
import textwrap

import pytest

SKILL_ROOT = pathlib.Path(__file__).parent.parent
SCRIPTS = SKILL_ROOT / "scripts"

GWS_STUB = textwrap.dedent("""\
    #!/usr/bin/env python3
    \"\"\"Mock gws CLI for testing.\"\"\"
    import json, os, sys

    args = sys.argv[1:]

    out_path = None
    for i, a in enumerate(args):
        if a == "-o" and i + 1 < len(args):
            out_path = args[i + 1]
            break

    log_file = os.environ.get("GWS_MOCK_LOG", "")
    if log_file:
        with open(log_file, "a") as f:
            f.write(json.dumps(args) + "\\n")

    call_flat = " ".join(a.replace("\\n", " ").replace("\\r", " ") for a in args)

    body = ""
    exit_code = 0
    rf = os.environ.get("GWS_MOCK_RESPONSES", "")
    if rf and os.path.exists(rf):
        with open(rf) as f:
            responses = json.load(f)
        for pattern, (code, resp_body) in responses.items():
            if pattern in call_flat:
                exit_code = code
                body = resp_body
                break

    if out_path:
        with open(out_path, "w") as f:
            f.write(body)
    else:
        if body:
            print(body)

    sys.exit(exit_code)
""")


@pytest.fixture
def gws_env(tmp_path, monkeypatch):
    """Set up mock gws binary and environment for slides tests."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    stub = bin_dir / "gws"
    stub.write_text(GWS_STUB)
    stub.chmod(0o755)

    log_file = tmp_path / "gws_calls.log"
    responses_file = tmp_path / "gws_responses.json"
    responses_file.write_text("{}")

    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("GWS_MOCK_LOG", str(log_file))
    monkeypatch.setenv("GWS_MOCK_RESPONSES", str(responses_file))

    class Env:
        def __init__(self):
            self.tmp_path = tmp_path
            self.log_file = log_file
            self.responses_file = responses_file

        def set_responses(self, responses: dict) -> None:
            self.responses_file.write_text(json.dumps(responses))

        def read_log(self) -> list[list[str]]:
            if not self.log_file.exists():
                return []
            return [json.loads(l) for l in self.log_file.read_text().splitlines() if l.strip()]

    return Env()
