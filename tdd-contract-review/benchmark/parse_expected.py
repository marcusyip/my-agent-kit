#!/usr/bin/env python3
"""Parse expected_gaps.yaml for the benchmark scripts.

Single source of truth for the two parses the shell scripts need:

    parse_expected.py units <yaml>         -> newline-separated unit slugs
    parse_expected.py gaps  <yaml> <slug>  -> TSV rows: id\\tpriority\\tmatch1^match2...\\tdescription

Used by grade-content.sh (gaps) and run-matrix.sh (units). Keep the two in
lockstep by going through this one parser.
"""
import re
import sys


def load(path):
    with open(path) as f:
        txt = f.read()
    m = re.search(r"^units:\s*$", txt, re.MULTILINE)
    if not m:
        sys.exit("no 'units:' section in yaml")
    return txt[m.end():]


def cmd_units(yaml_path):
    body = load(yaml_path)
    for sm in re.finditer(r"^  ([a-zA-Z0-9_\-]+):\s*$", body, re.MULTILINE):
        print(sm.group(1))


def cmd_gaps(yaml_path, slug):
    body = load(yaml_path)
    slug_pat = re.compile(rf"^  {re.escape(slug)}:\s*$", re.MULTILINE)
    sm = slug_pat.search(body)
    if not sm:
        sys.exit(f"unit '{slug}' not found in {yaml_path}")

    rest = body[sm.end():]
    next_key = re.search(r"^  [a-zA-Z0-9_\-]+:\s*$", rest, re.MULTILINE)
    block = rest[: next_key.start()] if next_key else rest

    for gm in re.finditer(r"-\s+id:\s*([^\s#]+)\s*\n((?:\s{8,}.*\n?)+)", block):
        gid = gm.group(1).strip()
        inner = gm.group(2)
        pri = re.search(r"priority:\s*([A-Z]+)", inner)
        matches = []
        ml = re.search(r"match:\s*\[([^\]]*)\]", inner)
        if ml:
            matches = [s.strip().strip('"').strip("'") for s in ml.group(1).split(",") if s.strip()]
        desc = re.search(r"description:\s*(.*)", inner)
        print(
            f"{gid}\t{pri.group(1) if pri else 'LOW'}\t{'^'.join(matches)}\t"
            f"{desc.group(1).strip() if desc else ''}"
        )


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip())
    cmd = sys.argv[1]
    if cmd == "units":
        cmd_units(sys.argv[2])
    elif cmd == "gaps":
        if len(sys.argv) != 4:
            sys.exit("usage: parse_expected.py gaps <yaml> <slug>")
        cmd_gaps(sys.argv[2], sys.argv[3])
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
