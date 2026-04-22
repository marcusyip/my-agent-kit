#!/usr/bin/env python3
"""LSP query wrapper around multilspy.

First invocation creates a venv next to this script and pip-installs
multilspy, then re-execs inside it. Subsequent invocations just import.

Usage:
  lsp_query.py --lang LANG --project PATH definition FILE LINE COL
  lsp_query.py --lang LANG --project PATH document_symbols FILE
  lsp_query.py --lang LANG --project PATH references FILE LINE COL

LANG values: ruby, typescript, javascript, go, python, java, rust,
             csharp, dart, kotlin, php, cpp.

FILE is relative to --project. LINE and COL are 0-indexed (LSP convention).

Output: JSON to stdout. Bootstrap and LSP server log lines go to stderr.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

VENV_DIR = Path(__file__).resolve().parent / ".venv"
VENV_PY = VENV_DIR / "bin" / "python"
REQUIREMENTS = ["multilspy"]


def ensure_venv():
    if sys.prefix == str(VENV_DIR):
        return
    if not VENV_PY.exists():
        print(f"[lsp_query] bootstrapping venv at {VENV_DIR}", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)])
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet", "--upgrade", "pip"]
        )
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet", *REQUIREMENTS]
        )
    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve()), *sys.argv[1:]])


ensure_venv()

import argparse  # noqa: E402
import glob  # noqa: E402

from multilspy import SyncLanguageServer  # noqa: E402
from multilspy.multilspy_config import MultilspyConfig  # noqa: E402
from multilspy.multilspy_logger import MultilspyLogger  # noqa: E402


def prepend_path(*dirs):
    existing = os.environ.get("PATH", "").split(os.pathsep)
    new = [d for d in dirs if d and Path(d).is_dir() and d not in existing]
    if new:
        os.environ["PATH"] = os.pathsep.join(new + existing)


def setup_lang_toolchain(lang):
    """Make per-language tools discoverable by multilspy's `which` calls.

    multilspy resolves language-server binaries via shell `which`, so the
    binary must be on PATH. macOS ships an old system Ruby that solargraph
    won't install against; prefer the brewed Ruby and its gem bin.
    """
    if lang == "ruby":
        prepend_path("/opt/homebrew/opt/ruby/bin")
        for gem_bin in glob.glob("/opt/homebrew/lib/ruby/gems/*/bin"):
            prepend_path(gem_bin)


def build_parser():
    ap = argparse.ArgumentParser(description="LSP query wrapper")
    ap.add_argument("--lang", required=True, help="multilspy code_language")
    ap.add_argument("--project", required=True, help="repo root absolute path")
    sub = ap.add_subparsers(dest="op", required=True)

    p_def = sub.add_parser("definition", help="resolve symbol at FILE:LINE:COL")
    p_def.add_argument("file")
    p_def.add_argument("line", type=int)
    p_def.add_argument("col", type=int)

    p_sym = sub.add_parser("document_symbols", help="list symbols in FILE")
    p_sym.add_argument("file")

    p_ref = sub.add_parser("references", help="find references to symbol at FILE:LINE:COL")
    p_ref.add_argument("file")
    p_ref.add_argument("line", type=int)
    p_ref.add_argument("col", type=int)

    return ap


def main():
    args = build_parser().parse_args()

    project = Path(args.project).resolve()
    if not project.is_dir():
        sys.exit(f"--project not a directory: {project}")

    setup_lang_toolchain(args.lang)

    config = MultilspyConfig.from_dict({"code_language": args.lang})
    logger = MultilspyLogger()
    lsp = SyncLanguageServer.create(config, logger, str(project))

    with lsp.start_server():
        if args.op == "definition":
            result = lsp.request_definition(args.file, args.line, args.col)
        elif args.op == "document_symbols":
            result = lsp.request_document_symbols(args.file)
        elif args.op == "references":
            result = lsp.request_references(args.file, args.line, args.col)
        else:
            sys.exit(f"unknown op: {args.op}")

    json.dump(result, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
