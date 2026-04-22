#!/usr/bin/env python3
"""LSP benchmark driver for sample-app-go.

Reads targets.json, resolves each target's (line, col) via a bounded text search
inside the enclosing Go symbol, invokes lsp_query.py per target, and either
records (--record) or verifies (default) the response against golden/.

Position resolution is intentionally LSP-free: the driver does not ask gopls
for the symbol range. The LSP is the thing being measured, not a dependency of
the driver. This keeps the bench a clean signal on gopls behaviour.

Usage:
  lsp-bench.py [--project PATH] [--record] [--target ID]

Exit codes:
  0  all targets pass (or --record completes)
  1  at least one verification failure
  2  bad CLI input
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAMPLE_APP = HERE.parent
LSP_QUERY = SAMPLE_APP.parent.parent / "scripts" / "lsp_query.py"
TARGETS_FILE = SAMPLE_APP / "targets.json"
GOLDEN_DIR = SAMPLE_APP / "golden"


def load_targets():
    data = json.loads(TARGETS_FILE.read_text())
    return data["targets"]


def build_symbol_regex(in_symbol: str):
    """Compile a regex that matches the declaration line for in_symbol.

    Grammar:
      "(*Type).Method"   — pointer-receiver method
      "(Type).Method"    — value-receiver method
      "Name"             — free function OR type declaration
    """
    if ")." in in_symbol:
        recv_raw, method = in_symbol.split(").", 1)
        recv = recv_raw.lstrip("(")
        if recv.startswith("*"):
            type_name = re.escape(recv[1:])
            return re.compile(
                rf"^func\s+\(\w+\s+\*{type_name}\)\s+{re.escape(method)}\b",
                re.MULTILINE,
            )
        return re.compile(
            rf"^func\s+\(\w+\s+{re.escape(recv)}\)\s+{re.escape(method)}\b",
            re.MULTILINE,
        )
    esc = re.escape(in_symbol)
    return re.compile(rf"^(?:func|type)\s+{esc}\b", re.MULTILINE)


def find_symbol_body(source: str, in_symbol: str):
    """Return (body_start_offset, body_end_offset) for in_symbol.

    body_start is the offset of the opening brace; body_end is one past the
    matching close brace.
    """
    pat = build_symbol_regex(in_symbol)
    m = pat.search(source)
    if not m:
        raise LookupError(f"symbol not found: {in_symbol}")
    brace_start = source.index("{", m.start())
    depth = 0
    i = brace_start
    while i < len(source):
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return brace_start, i + 1
        i += 1
    raise RuntimeError(f"unterminated symbol body: {in_symbol}")


def resolve_position(source: str, body_start: int, body_end: int,
                     call_text: str, match_index: int = 0):
    """Locate call_text inside [body_start, body_end) and return (line, col).

    LSP position is at the start of the final dot-segment of call_text
    (so "h.service.Call" resolves to the `C` in `Call`). If call_text has no
    dot, position is at the start of the match.
    """
    body = source[body_start:body_end]
    pos = -1
    search_from = 0
    for _ in range(match_index + 1):
        pos = body.index(call_text, search_from)
        search_from = pos + 1
    absolute = body_start + pos
    if "." in call_text:
        absolute += call_text.rfind(".") + 1

    line = source.count("\n", 0, absolute)
    last_newline = source.rfind("\n", 0, absolute)
    col = absolute - (last_newline + 1 if last_newline >= 0 else 0)
    return line, col


def run_lsp(project: Path, op: str, file: str, line=None, col=None):
    cmd = [
        sys.executable, str(LSP_QUERY),
        "--lang", "go",
        "--project", str(project),
        op, file,
    ]
    if line is not None:
        cmd += [str(line), str(col)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"lsp_query failed ({op} {file}): {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def normalize(data, project: Path):
    """Strip absolute paths for stable diffs across checkouts."""
    s = json.dumps(data)
    s = s.replace(f"file://{project}/", "file://./")
    s = s.replace(f"{project}/", "./")
    return json.loads(s)


def process_target(project: Path, target: dict, record: bool) -> bool:
    file_path = project / target["file"]
    source = file_path.read_text()

    line = col = None
    if target["op"] != "document_symbols":
        body_start, body_end = find_symbol_body(source, target["in_symbol"])
        line, col = resolve_position(
            source, body_start, body_end,
            target["call_text"],
            target.get("match_index", 0),
        )

    response = run_lsp(project, target["op"], target["file"], line, col)
    normalized = normalize(response, project)

    golden_path = GOLDEN_DIR / f"{target['id']}.json"
    pos_note = f" @ {line}:{col}" if line is not None else ""

    if record:
        GOLDEN_DIR.mkdir(exist_ok=True)
        golden_path.write_text(
            json.dumps(normalized, indent=2, sort_keys=True) + "\n"
        )
        print(f"RECORD  {target['id']}{pos_note}")
        return True

    if not golden_path.exists():
        print(f"MISSING {target['id']}: no golden at {golden_path.name}",
              file=sys.stderr)
        return False

    expected = json.loads(golden_path.read_text())
    if expected != normalized:
        print(f"DRIFT   {target['id']}{pos_note}", file=sys.stderr)
        return False

    print(f"OK      {target['id']}{pos_note}")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=str(SAMPLE_APP),
                        help="Go module root (default: sample-app-go)")
    parser.add_argument("--record", action="store_true",
                        help="Overwrite golden/ with current LSP responses")
    parser.add_argument("--target", default=None,
                        help="Run a single target by id")
    args = parser.parse_args()
    project = Path(args.project).resolve()

    targets = load_targets()
    if args.target:
        targets = [t for t in targets if t["id"] == args.target]
        if not targets:
            print(f"no target: {args.target}", file=sys.stderr)
            sys.exit(2)

    failures = 0
    for t in targets:
        try:
            if not process_target(project, t, args.record):
                failures += 1
        except Exception as exc:
            print(f"ERROR   {t['id']}: {exc}", file=sys.stderr)
            failures += 1

    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
