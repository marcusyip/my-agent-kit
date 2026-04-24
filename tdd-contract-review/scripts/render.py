#!/usr/bin/env python3
"""Render JSON artifacts to their markdown views.

Usage:
  render.py --kind <extraction|audit|gaps-per-type|report|call-tree> \
            --input <path.json> [--output <path.md>] [--no-validate]

Reads the JSON, validates against the matching schema (unless --no-validate),
renders through the matching Jinja2 template, and writes the result.

The renderer is the ONLY way to produce MD views of JSON-first artifacts.
Hand-editing the MD is a correctness bug — use the JSON + re-render.
"""
import os
import subprocess
import sys
from pathlib import Path

VENV_DIR = Path(__file__).resolve().parent / ".venv"
VENV_PY = VENV_DIR / "bin" / "python"


def ensure_venv():
    if sys.prefix == str(VENV_DIR):
        return
    if not VENV_PY.exists():
        print(f"[render] bootstrapping venv at {VENV_DIR}", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)])
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet", "--upgrade", "pip"]
        )
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet",
             "jinja2", "jsonschema", "referencing"]
        )
    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve()), *sys.argv[1:]])


ensure_venv()

import argparse  # noqa: E402
import json  # noqa: E402

from jinja2 import Environment, FileSystemLoader, StrictUndefined  # noqa: E402
from jsonschema import Draft202012Validator  # noqa: E402
from referencing import Registry, Resource  # noqa: E402


ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
TEMPLATES = ROOT / "templates"

KIND_TO_SCHEMA = {
    "extraction": "extraction.schema.json",
    "audit": "audit.schema.json",
    "gaps-per-type": "gaps-per-type.schema.json",
    "findings": "findings.schema.json",
    "report": "report.schema.json",
    "call-tree": "call-tree.schema.json",
}

KIND_TO_TEMPLATE = {
    "extraction": "extraction.md.j2",
    "audit": "audit.md.j2",
    "gaps-per-type": "gaps-per-type.md.j2",
    "report": "report.md.j2",
    "call-tree": "call-tree.md.j2",
}


def build_registry() -> Registry:
    registry = Registry()
    for schema_file in SCHEMAS.glob("*.schema.json"):
        data = json.loads(schema_file.read_text())
        resource = Resource.from_contents(data)
        registry = registry.with_resource(uri=schema_file.name, resource=resource)
    return registry


def validate(kind: str, doc: dict) -> list[str]:
    schema_name = KIND_TO_SCHEMA[kind]
    schema = json.loads((SCHEMAS / schema_name).read_text())
    validator = Draft202012Validator(schema, registry=build_registry())
    errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path))
    out = []
    for e in errors:
        loc = "/".join(str(p) for p in e.absolute_path) or "(root)"
        out.append(f"at {loc}: {e.message}")
    return out


def make_env() -> Environment:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES)),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )

    def priority_badge(p: str) -> str:
        return f"[{p}]" if p else ""

    def check(covered: bool) -> str:
        return "✓" if covered else "✗"

    def _format_range(start, end):
        if start is None:
            return ""
        if end is None or end == start:
            return f":{start}"
        return f":{start}-{end}"

    def _render_tree_node(node, indent=0):
        parts = [node.get("call_name") or node.get("symbol") or "?"]
        sym = node.get("symbol")
        if sym and sym != node.get("call_name"):
            parts.append(f"→ {sym}")
        if node.get("file"):
            parts.append(f"@ {node['file']}{_format_range(node.get('start_line'), node.get('end_line'))}")
        if node.get("tag"):
            parts.append(f"[{node['tag']}]")
        lines = ["  " * indent + "- " + " ".join(parts)]
        for child in node.get("children", []):
            lines.append(_render_tree_node(child, indent + 1))
        return "\n".join(lines)

    env.filters["priority_badge"] = priority_badge
    env.filters["check"] = check
    env.filters["render_tree"] = _render_tree_node
    return env


def _compose_extraction_extras(input_path: Path, doc: dict, env: Environment) -> dict:
    """For kind=extraction, compose the summary and call-trees sections from
    sibling artifacts in $RUN_DIR (the input file's parent). Keeps
    extraction.schema.json lean — these are rendered views, not structured data.
    """
    run_dir = input_path.parent

    lsp_dir = run_dir / "lsp"
    doc_sym = def_ct = ref_ct = 0
    if lsp_dir.is_dir():
        for f in lsp_dir.glob("*.json"):
            if f.name.startswith("document_symbols__"):
                doc_sym += 1
            elif f.name.startswith("definition__"):
                def_ct += 1
            elif f.name.startswith("references__"):
                ref_ct += 1

    critical_mode = "ON" if (doc.get("fintech_dimensions_md") or "").strip() else "OFF"
    files_src_n = len(doc.get("files_examined", {}).get("source", []) or [])
    files_db_n = len(doc.get("files_examined", {}).get("db_schema", []) or [])
    files_out_n = len(doc.get("files_examined", {}).get("outbound_clients", []) or [])

    summary_lines = [
        f"- Framework: {doc.get('framework', '(unknown)')}",
        f"- Critical mode: {critical_mode}",
        f"- LSP calls: {doc_sym} document_symbols, {def_ct} definitions, {ref_ct} references",
        f"- Files examined: {files_src_n} source, {files_db_n} db_schema, {files_out_n} outbound_clients",
    ]
    summary_md = "\n".join(summary_lines)

    tree_files = sorted(run_dir.glob("tree__*.json"))
    call_trees_parts: list[str] = []
    if tree_files:
        tree_tmpl = env.get_template(KIND_TO_TEMPLATE["call-tree"])
        for tf in tree_files:
            try:
                tree_doc = json.loads(tf.read_text())
            except Exception as exc:
                call_trees_parts.append(f"_(failed to read {tf.name}: {exc})_")
                continue
            heading = tf.stem.replace("tree__", "").replace("__", " — ")
            rendered = tree_tmpl.render(doc=tree_doc).rstrip()
            call_trees_parts.append(f"#### {heading}\n\n```\n{rendered}\n```")
        call_trees_md = "\n\n".join(call_trees_parts)
    else:
        call_trees_md = "_(no tree__*.json files found in run directory)_"

    return {"summary_md": summary_md, "call_trees_md": call_trees_md}


def render(kind: str, doc: dict, input_path: Path | None = None) -> str:
    if kind not in KIND_TO_TEMPLATE:
        raise ValueError(f"no template defined for kind: {kind}")
    env = make_env()
    tmpl = env.get_template(KIND_TO_TEMPLATE[kind])
    ctx = {"doc": doc}
    if kind == "extraction" and input_path is not None:
        ctx.update(_compose_extraction_extras(input_path, doc, env))
    elif kind == "extraction":
        ctx.update({"summary_md": "_(run dir unknown — input path not passed to render)_",
                    "call_trees_md": "_(run dir unknown — input path not passed to render)_"})
    return tmpl.render(**ctx)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kind", required=True, choices=sorted(KIND_TO_TEMPLATE.keys()))
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=None,
                        help="Output path. Defaults to stdin.json → same-name .md.")
    parser.add_argument("--no-validate", action="store_true",
                        help="Skip schema validation (use only for debugging).")
    args = parser.parse_args()

    if not args.input.exists():
        sys.exit(f"input not found: {args.input}")

    doc = json.loads(args.input.read_text())

    if not args.no_validate:
        errors = validate(args.kind, doc)
        if errors:
            print(f"✗ schema validation failed ({args.input}):", file=sys.stderr)
            for e in errors[:20]:
                print(f"    {e}", file=sys.stderr)
            if len(errors) > 20:
                print(f"    ... {len(errors) - 20} more", file=sys.stderr)
            sys.exit(2)

    body = render(args.kind, doc, input_path=args.input)

    if args.output:
        args.output.write_text(body)
        print(f"WROTE: {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(body)


if __name__ == "__main__":
    main()
