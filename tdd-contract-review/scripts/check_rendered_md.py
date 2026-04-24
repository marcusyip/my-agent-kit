#!/usr/bin/env python3
"""Verify rendered MD views match their JSON sources.

Every numbered artifact in a tdd-contract-review run (01-extraction, 02-audit,
03x-gaps-*, report, tree__*) is JSON-first: the `.json` is the source of
truth; the `.md` is a derived view produced by `scripts/render.py`. Hand-
editing the MD is a correctness bug — it drifts silently from the JSON that
the grader reads.

This script re-renders every committed JSON artifact and diffs the output
against the on-disk MD sibling. Any mismatch is a failure; the script
prints a unified diff and exits 1.

Usage:
  check_rendered_md.py [--staged]                 # default: git ls-files
  check_rendered_md.py --files a.json b.json ...  # explicit set
  check_rendered_md.py --all                      # walk the whole tree

Intended use: as a pre-commit hook (--staged) and in CI (default).
"""
from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
RENDER = HERE / "render.py"

# (regex on the JSON basename)  →  --kind argument for render.py
FILENAME_KIND_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^01-extraction\.json$"), "extraction"),
    (re.compile(r"^02-audit\.json$"), "audit"),
    (re.compile(r"^03[a-f]-gaps-[a-z]+\.json$"), "gaps-per-type"),
    (re.compile(r"^report\.json$"), "report"),
    (re.compile(r"^tree__.+\.json$"), "call-tree"),
]

# Paths to always skip even if they look like a rendered artifact.
SKIP_PATH_FRAGMENTS = (
    "/schemas/fixtures/",   # self-contained fixtures, no MD sibling required
    "/schemas/",            # schema JSON, not a rendered artifact
    "/lsp/",                # LSP query artifacts
    "/templates/",
)


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def _kind_for(path: Path) -> str | None:
    if any(frag in str(path).replace("\\", "/") for frag in SKIP_PATH_FRAGMENTS):
        return None
    name = path.name
    for pattern, kind in FILENAME_KIND_PATTERNS:
        if pattern.match(name):
            return kind
    return None


def _staged_files() -> list[Path]:
    out = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=REPO_ROOT, text=True,
    )
    return [REPO_ROOT / p for p in out.splitlines() if p.strip()]


def _tracked_files() -> list[Path]:
    out = subprocess.check_output(
        ["git", "ls-files", "tdd-contract-review"], cwd=REPO_ROOT, text=True,
    )
    return [REPO_ROOT / p for p in out.splitlines() if p.strip()]


def _all_files() -> list[Path]:
    walked: list[Path] = []
    for root, _, files in os.walk(REPO_ROOT / "tdd-contract-review"):
        for name in files:
            walked.append(Path(root) / name)
    return walked


def _render(json_path: Path, kind: str) -> str:
    # Render to stdout via a temp path; capture content in memory.
    import tempfile
    with tempfile.NamedTemporaryFile(mode="r", suffix=".md", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        subprocess.check_output(
            [sys.executable, str(RENDER),
             "--kind", kind,
             "--input", str(json_path),
             "--output", str(tmp_path)],
            cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT,
        )
        return tmp_path.read_text()
    finally:
        tmp_path.unlink(missing_ok=True)


def _check_one(json_path: Path, kind: str) -> tuple[bool, str]:
    md_path = json_path.with_suffix(".md")
    if not md_path.exists():
        return True, f"  · {_rel(json_path)} — MD sibling absent (skipped)"
    try:
        rendered = _render(json_path, kind)
    except subprocess.CalledProcessError as exc:
        return False, (
            f"  ✗ {_rel(json_path)} — render failed\n"
            f"    {exc.output.strip()}"
        )

    on_disk = md_path.read_text()
    if rendered == on_disk:
        return True, f"  ✓ {_rel(md_path)} matches render"

    diff = "".join(
        difflib.unified_diff(
            on_disk.splitlines(keepends=True),
            rendered.splitlines(keepends=True),
            fromfile=f"{_rel(md_path)} (on disk)",
            tofile=f"{_rel(md_path)} (rendered)",
            n=2,
        )
    )
    return False, (
        f"  ✗ {_rel(md_path)} drifted from {json_path.name}\n"
        f"{diff}"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    grp = ap.add_mutually_exclusive_group()
    grp.add_argument("--staged", action="store_true", help="Check only staged files (pre-commit).")
    grp.add_argument("--all", action="store_true", help="Walk the whole tdd-contract-review/ tree.")
    grp.add_argument("--files", nargs="+", help="Explicit list of JSON paths to check.")
    args = ap.parse_args()

    if args.files:
        candidates = [Path(f).resolve() for f in args.files]
    elif args.staged:
        candidates = _staged_files()
    elif args.all:
        candidates = _all_files()
    else:
        candidates = _tracked_files()

    work: list[tuple[Path, str]] = []
    for p in candidates:
        if not p.exists() or p.suffix != ".json":
            continue
        kind = _kind_for(p)
        if kind is None:
            continue
        work.append((p, kind))

    if not work:
        print("check_rendered_md: no rendered-artifact JSONs in scope")
        return 0

    failed = 0
    for json_path, kind in sorted(work):
        ok, msg = _check_one(json_path, kind)
        print(msg)
        if not ok:
            failed += 1

    print()
    print(f"check_rendered_md: {len(work) - failed} ok, {failed} drifted")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
