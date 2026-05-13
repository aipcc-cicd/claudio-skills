"""Shared fixtures for google-drive-reader skill tests.

The mock ``gws`` binary intercepts all CLI calls without network access.

Environment variables read by the stub:
  GWS_MOCK_LOG        Path to append one JSON-encoded arg-list per call.
  GWS_MOCK_RESPONSES  Path to a JSON file mapping substring patterns to
                      [exit_code, response_body] pairs.  The first matching
                      pattern wins.
"""

import json
import os
import pathlib
import textwrap

import pytest

SKILL_ROOT = pathlib.Path(__file__).parent.parent
SCRIPTS = SKILL_ROOT / "scripts"

# ---------------------------------------------------------------------------
# Mock gws binary — written to a tmp bin/ dir and placed first on PATH.
# ---------------------------------------------------------------------------

GWS_STUB = textwrap.dedent("""\
    #!/usr/bin/env python3
    \"\"\"Mock gws CLI for testing.\"\"\"
    import json, os, sys

    args = sys.argv[1:]

    # Find -o flag (used by 'drive files export -o <path>')
    out_path = None
    for i, a in enumerate(args):
        if a == "-o" and i + 1 < len(args):
            out_path = args[i + 1]
            break

    # Log call as a JSON array so embedded newlines are preserved safely
    log_file = os.environ.get("GWS_MOCK_LOG", "")
    if log_file:
        with open(log_file, "a") as f:
            f.write(json.dumps(args) + "\\n")

    # Flatten args to a single string for pattern matching (collapse newlines)
    call_flat = " ".join(a.replace("\\n", " ").replace("\\r", " ") for a in args)

    # Find first matching response
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

    # Deliver response
    if out_path:
        with open(out_path, "w") as f:
            f.write(body)
    else:
        if body:
            print(body)

    sys.exit(exit_code)
""")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def read_log(log_file: pathlib.Path) -> list[list[str]]:
    """Return list of recorded gws calls (each call is a list of arg strings)."""
    if not log_file.exists():
        return []
    return [json.loads(line) for line in log_file.read_text().splitlines() if line.strip()]


def calls_contain(log_calls: list[list[str]], *substrings: str) -> bool:
    """Return True if any single call's flattened args contain all substrings."""
    for call in log_calls:
        flat = " ".join(call)
        if all(s in flat for s in substrings):
            return True
    return False


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def gws_env(tmp_path, monkeypatch):
    """Set up the mock gws binary and configure response/log files.

    Yields a namespace with:
      .tmp_path         - pytest tmp_path
      .log_file         - Path where call logs are written
      .responses_file   - Path to JSON responses file (write before running script)
      .set_responses()  - helper to write the responses dict
    """
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    jq_shim = bin_dir / "jq"
    jq_shim.write_text(textwrap.dedent("""\
        #!/usr/bin/env python3
        \"\"\"jq shim backed by the Python jq package.\"\"\"
        import json, sys
        import jq as _jq

        args = sys.argv[1:]
        raw = False
        null_input = False
        slurp = False
        variables = {}
        program = None
        files = []

        i = 0
        while i < len(args):
            a = args[i]
            if a in ('-r', '--raw-output'):
                raw = True
            elif a == '-n':
                null_input = True
            elif a == '-s':
                slurp = True
            elif a.startswith('-') and len(a) > 1 and not a.startswith('--'):
                # Combined short flags e.g. -rn, -rs, -rns
                if 'r' in a: raw = True
                if 'n' in a: null_input = True
                if 's' in a: slurp = True
            elif a == '--arg':
                variables[args[i + 1]] = args[i + 2]
                i += 2
            elif a == '--argjson':
                variables[args[i + 1]] = json.loads(args[i + 2])
                i += 2
            elif a == '--':
                pass
            elif not a.startswith('-'):
                if program is None:
                    program = a
                else:
                    files.append(a)
            i += 1

        if program is None:
            program = '.'

        compiled = _jq.compile(program, args=variables)

        if null_input:
            results = compiled.input_value(None).all()
        elif files:
            if slurp:
                items = [json.loads(line) for f in files for line in open(f) if line.strip()]
                results = compiled.input_value(items).all()
            else:
                results = []
                for f in files:
                    for line in open(f):
                        line = line.strip()
                        if line:
                            results.extend(compiled.input_text(line).all())
        else:
            data = sys.stdin.read()
            if slurp:
                items = [json.loads(line) for line in data.splitlines() if line.strip()]
                results = compiled.input_value(items).all()
            else:
                results = compiled.input_text(data).all()

        for item in results:
            if raw and isinstance(item, str):
                print(item)
            else:
                print(json.dumps(item, ensure_ascii=False))
    """))
    jq_shim.chmod(0o755)

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
            return read_log(self.log_file)

        def calls_contain(self, *substrings: str) -> bool:
            return calls_contain(self.read_log(), *substrings)

    return Env()
