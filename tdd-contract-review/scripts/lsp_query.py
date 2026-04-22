#!/usr/bin/env python3
"""LSP query wrapper around multilspy.

First invocation creates a venv next to this script and pip-installs
multilspy, then re-execs inside it. Subsequent invocations just import.

Usage:
  lsp_query.py --lang LANG --project PATH [--run-dir DIR] definition FILE LINE COL
  lsp_query.py --lang LANG --project PATH [--run-dir DIR] document_symbols FILE
  lsp_query.py --lang LANG --project PATH [--run-dir DIR] references FILE LINE COL

LANG values: ruby, typescript, javascript, go, python, java, rust,
             csharp, dart, kotlin, php, cpp.

FILE is relative to --project. LINE and COL are 0-indexed (LSP convention).

Output:
  Without --run-dir: JSON to stdout.
  With --run-dir DIR: JSON written to DIR/lsp/<auto>.json; stdout prints
    `WROTE: <path>`. Filename is derived from op + file + line/col so
    repeat queries are idempotent (overwrite the same file = effective
    per-run cache). Bootstrap and LSP server log lines always go to stderr.
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
import re  # noqa: E402

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


def slugify_path(p):
    """app/controllers/api/v1/foo.rb -> app-controllers-api-v1-foo-rb"""
    return re.sub(r"[^A-Za-z0-9]+", "-", p).strip("-")


def auto_filename(op, file, line=None, col=None):
    slug = slugify_path(file)
    if line is not None:
        return f"{op}__{slug}__L{line}C{col}.json"
    return f"{op}__{slug}.json"


def build_parser():
    ap = argparse.ArgumentParser(description="LSP query wrapper")
    ap.add_argument("--lang", required=True, help="multilspy code_language")
    ap.add_argument("--project", required=True, help="repo root absolute path")
    ap.add_argument(
        "--run-dir",
        default=None,
        help="if set, write JSON to <run-dir>/lsp/<auto>.json and print WROTE: <path>",
    )
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

    ctx = lsp.start_server()
    ctx.__enter__()
    try:
        file_ctx = lsp.open_file(args.file)
        file_ctx.__enter__()
        try:
            if args.op == "definition":
                result = lsp.request_definition(args.file, args.line, args.col)
            elif args.op == "document_symbols":
                result = lsp.request_document_symbols(args.file)
            elif args.op == "references":
                result = lsp.request_references(args.file, args.line, args.col)
            else:
                sys.exit(f"unknown op: {args.op}")
        finally:
            try:
                file_ctx.__exit__(None, None, None)
            except Exception as exc:
                print(f"[lsp_query] file close warning (ignored): {exc}", file=sys.stderr)
    finally:
        try:
            ctx.__exit__(None, None, None)
        except Exception as exc:
            # gopls may exit cleanly before multilspy signals its children;
            # psutil.NoSuchProcess is benign — the query already completed.
            print(f"[lsp_query] server cleanup warning (ignored): {exc}", file=sys.stderr)

    if args.run_dir:
        out_dir = Path(args.run_dir).resolve() / "lsp"
        out_dir.mkdir(parents=True, exist_ok=True)
        line = getattr(args, "line", None)
        col = getattr(args, "col", None)
        out_path = out_dir / auto_filename(args.op, args.file, line, col)
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2, default=str)
            f.write("\n")
        sys.stdout.write(f"WROTE: {out_path}\n")
    else:
        json.dump(result, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
