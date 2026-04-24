#!/usr/bin/env python3
"""Deterministic scoring helper for tdd-contract-review report.json.

The LLM authors category scores (0-10) and rationale_md strings. This script
computes the derived numbers (weight per category, weighted = score*weight,
overall_score = sum(weighted), verdict band) so the narrative cannot drift
from the number the grader reads.

Usage:
    python3 score.py --input <draft.json> --output <report.json>

Input  (draft.json) — LLM-authored, may omit weight/weighted/overall/verdict:
    {
      "unit": "...",
      "categories": [
        {"name": "Contract Coverage",    "score": 1, "rationale_md": "..."},
        {"name": "Test Grouping",        "score": 2, "rationale_md": "..."},
        {"name": "Scenario Depth",       "score": 1, "rationale_md": "..."},
        {"name": "Test Case Quality",    "score": 1, "rationale_md": "..."},
        {"name": "Isolation & Flakiness","score": 4, "rationale_md": "..."},
        {"name": "Anti-Patterns",        "score": 0, "rationale_md": "..."}
      ],
      "top_priority_actions": [...]
    }

Output (report.json) — validates against report.schema.json.

Category weights (hardcoded; must sum to 1.0):
    Contract Coverage     0.25
    Test Grouping         0.15
    Scenario Depth        0.20
    Test Case Quality     0.15
    Isolation & Flakiness 0.15
    Anti-Patterns         0.10

Verdict bands (aligned with report.schema.json verdict enum):
    WEAK    overall_score < 4
    OK      overall_score < 7
    STRONG  overall_score >= 7
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CATEGORY_WEIGHTS: dict[str, float] = {
    "Contract Coverage": 0.25,
    "Test Grouping": 0.15,
    "Scenario Depth": 0.20,
    "Test Case Quality": 0.15,
    "Isolation & Flakiness": 0.15,
    "Anti-Patterns": 0.10,
}

CATEGORY_ORDER: list[str] = list(CATEGORY_WEIGHTS.keys())

SUB_FILE_ORDER: list[str] = [
    "03a-gaps-api.json",
    "03b-gaps-db.json",
    "03c-gaps-outbound.json",
    "03d-gaps-money.json",
    "03e-gaps-security.json",
]


def _merge_field_status(scenarios: list[dict]) -> str:
    if not scenarios:
        return "MISSING"
    covered_count = sum(1 for s in scenarios if s.get("covered"))
    if covered_count == 0:
        return "MISSING"
    if covered_count == len(scenarios):
        return "COVERED"
    return "PARTIAL"


def _merge_scenario(into: dict, other: dict) -> dict:
    merged = dict(into)
    merged["covered"] = bool(into.get("covered")) or bool(other.get("covered"))
    ref_a, ref_b = into.get("test_ref"), other.get("test_ref")
    merged["test_ref"] = ref_a or ref_b
    note_a, note_b = into.get("partial_note"), other.get("partial_note")
    if note_a and note_b and note_a != note_b:
        merged["partial_note"] = f"{note_a}; {note_b}"
    else:
        merged["partial_note"] = note_a or note_b
    return merged


def _render_tree_md(root: str, fields: list[dict]) -> str:
    lines: list[str] = ["```", root, "│"]
    for i, fld in enumerate(fields):
        is_last_field = i == len(fields) - 1
        field_prefix = "└──" if is_last_field else "├──"
        child_indent = "    " if is_last_field else "│   "
        lines.append(f"{field_prefix} {fld['field']} — {fld['status']}")
        scenarios = fld.get("scenarios", [])
        for j, sc in enumerate(scenarios):
            sc_prefix = "└──" if j == len(scenarios) - 1 else "├──"
            mark = "✓" if sc.get("covered") else "✗"
            ref_text = ""
            if sc.get("covered") and sc.get("test_ref"):
                ref = sc["test_ref"]
                if isinstance(ref, dict) and ref.get("path"):
                    ref_text = f" ({ref['path']}"
                    if ref.get("line"):
                        ref_text += f":{ref['line']}"
                    ref_text += ")"
            partial_text = f"  [{sc['partial_note']}]" if sc.get("partial_note") else ""
            lines.append(f"{child_indent}{sc_prefix} {mark} {sc['description']}{ref_text}{partial_text}")
        if not is_last_field:
            lines.append("│")
    lines.append("```")
    return "\n".join(lines)


def _merge_trees(run_dir: Path) -> str | None:
    """Read all 03*-gaps-*.json under run_dir, merge their test_tree into one tree.

    Merging rules:
    - Fields dedupe by field name (preserving first-seen insertion order across
      sub-files scanned in SUB_FILE_ORDER: API → DB → Outbound → Money → Security).
    - Scenarios within a merged field dedupe by description; covered=OR, test_ref
      prefers non-null, partial_note concatenates unique notes.
    - Field status is recomputed from merged scenarios (MISSING/PARTIAL/COVERED).
    - Root label: first non-empty test_tree.root encountered (03a wins if present).
    Returns rendered MD string, or None if no sub-files exist.
    """
    merged_fields: dict[str, dict] = {}
    field_order: list[str] = []
    root: str | None = None
    found = False

    for name in SUB_FILE_ORDER:
        path = run_dir / name
        if not path.exists():
            continue
        try:
            sub = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        tree = sub.get("test_tree") or {}
        if not isinstance(tree, dict):
            continue
        found = True
        if root is None and tree.get("root"):
            root = tree["root"]
        for fld in tree.get("fields", []) or []:
            field_name = fld.get("field")
            if not field_name:
                continue
            scenarios = fld.get("scenarios", []) or []
            if field_name not in merged_fields:
                merged_fields[field_name] = {
                    "field": field_name,
                    "scenarios_by_desc": {},
                    "scenarios_order": [],
                }
                field_order.append(field_name)
            bucket = merged_fields[field_name]
            for sc in scenarios:
                desc = sc.get("description")
                if not desc:
                    continue
                if desc in bucket["scenarios_by_desc"]:
                    bucket["scenarios_by_desc"][desc] = _merge_scenario(
                        bucket["scenarios_by_desc"][desc], sc
                    )
                else:
                    bucket["scenarios_by_desc"][desc] = dict(sc)
                    bucket["scenarios_order"].append(desc)

    if not found:
        return None

    final_fields: list[dict] = []
    for name in field_order:
        bucket = merged_fields[name]
        scenarios = [bucket["scenarios_by_desc"][d] for d in bucket["scenarios_order"]]
        final_fields.append({
            "field": name,
            "status": _merge_field_status(scenarios),
            "scenarios": scenarios,
        })

    return _render_tree_md(root or "(unit)", final_fields)


def _escape_md_cell(s: str) -> str:
    if s is None:
        return ""
    return str(s).replace("|", "\\|").replace("\n", " ").strip()


def _merge_contract_map(run_dir: Path) -> str | None:
    """Merge contract_map[] from all per-type sub-files into one markdown table.

    Dedupe key: (field_kind, field). When duplicates appear across sub-files,
    keep first-seen role/scenarios_needed/current_coverage/gap_count.
    Returns rendered MD table, or None if no sub-files exist.
    """
    seen: set[tuple[str, str]] = set()
    rows: list[dict] = []
    found = False

    for name in SUB_FILE_ORDER:
        path = run_dir / name
        if not path.exists():
            continue
        try:
            sub = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        found = True
        for row in sub.get("contract_map", []) or []:
            key = (row.get("field_kind", ""), row.get("field", ""))
            if key in seen:
                continue
            seen.add(key)
            rows.append(row)

    if not found or not rows:
        return None

    lines = [
        "| Typed Prefix | Field | Role | Scenarios Required | Scenarios Covered | Gap Count |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append(
            "| {kind} | {field} | {role} | {need} | {cov} | {gap} |".format(
                kind=_escape_md_cell(r.get("field_kind", "")),
                field=_escape_md_cell(r.get("field", "")),
                role=_escape_md_cell(r.get("role", "")),
                need=_escape_md_cell(r.get("scenarios_needed", "")),
                cov=_escape_md_cell(r.get("current_coverage", "0")),
                gap=_escape_md_cell(r.get("gap_count", "")),
            )
        )
    return "\n".join(lines)


def _load_anti_patterns(run_dir: Path) -> str | None:
    """Render 02-audit.json.anti_patterns[] as a markdown table.

    Columns: ID | Anti-Pattern | Location | Fix. Returns None if audit file
    is absent or has no anti_patterns.
    """
    audit_path = run_dir / "02-audit.json"
    if not audit_path.exists():
        return None
    try:
        audit = json.loads(audit_path.read_text())
    except json.JSONDecodeError:
        return None
    aps = audit.get("anti_patterns") or []
    if not aps:
        return None

    lines = [
        "| ID | Anti-Pattern | Location | Fix |",
        "|---|---|---|---|",
    ]
    for ap in aps:
        locs = []
        for f in ap.get("files", []) or []:
            path = f.get("path", "")
            line_no = f.get("line")
            end_line = f.get("end_line")
            loc = path
            if line_no:
                loc += f":{line_no}"
                if end_line and end_line != line_no:
                    loc += f"-{end_line}"
            if loc:
                locs.append(loc)
        location = ", ".join(locs) if locs else "—"
        lines.append(
            "| {id} | {title} | {loc} | {fix} |".format(
                id=_escape_md_cell(ap.get("id", "")),
                title=_escape_md_cell(ap.get("title", "")),
                loc=_escape_md_cell(location),
                fix=_escape_md_cell(ap.get("recommendation", "")),
            )
        )
    return "\n".join(lines)


PRIORITY_ORDER: list[str] = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]

PRIORITY_BLURBS: dict[str, str] = {
    "CRITICAL": "immediate risk — money, security, data integrity",
    "HIGH": "core contract fields missing tests",
    "MEDIUM": "edge cases, boundary conditions, nice-to-have assertions",
    "LOW": "documentation, infra-level observations, non-unit-testable",
}


def _render_gap_analysis(run_dir: Path) -> str | None:
    """Render findings.json gaps grouped by priority. CRITICAL gaps include stubs.

    Returns MD string or None if findings.json absent/empty.
    """
    findings_path = run_dir / "findings.json"
    if not findings_path.exists():
        return None
    try:
        findings = json.loads(findings_path.read_text())
    except json.JSONDecodeError:
        return None
    gaps = findings.get("gaps") or []
    if not gaps:
        return None

    buckets: dict[str, list[dict]] = {p: [] for p in PRIORITY_ORDER}
    for g in gaps:
        pri = g.get("priority")
        if pri in buckets:
            buckets[pri].append(g)

    lines: list[str] = []
    for pri in PRIORITY_ORDER:
        bucket = buckets[pri]
        if not bucket:
            continue
        blurb = PRIORITY_BLURBS.get(pri, "")
        blurb_text = f" ({blurb})" if blurb else ""
        lines.append(f"**{pri}** ({len(bucket)} gap{'s' if len(bucket) != 1 else ''}){blurb_text}")
        lines.append("")
        for g in bucket:
            gid = g.get("id", "")
            field = g.get("field", "")
            gtype = g.get("type", "")
            desc = g.get("description", "").strip()
            lines.append(f"- **{gid}** — `{field}` — **{gtype}**")
            if desc:
                for para in desc.split("\n\n"):
                    lines.append(f"  {para.strip()}")
            stub = g.get("stub")
            if pri == "CRITICAL" and stub:
                lines.append("")
                lines.append("  Suggested test:")
                lines.append("")
                lines.append("  ````")
                for stub_line in stub.rstrip().split("\n"):
                    lines.append(f"  {stub_line}" if stub_line else "")
                lines.append("  ````")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _render_hygiene(run_dir: Path) -> str | None:
    """Render audit.json.anti_patterns[] as a prose 'Hygiene' section.

    Each anti-pattern becomes a `#### {id}: {title}` subsection with files,
    recommendation, and full rationale_md (verbatim). Returns None if absent.
    """
    audit_path = run_dir / "02-audit.json"
    if not audit_path.exists():
        return None
    try:
        audit = json.loads(audit_path.read_text())
    except json.JSONDecodeError:
        return None
    aps = audit.get("anti_patterns") or []
    if not aps:
        return None

    lines: list[str] = [
        "The following structural anti-patterns were identified during the audit. They must be addressed before contract gaps can be efficiently filled — adding tests into the current structure will not produce auditable coverage.",
        "",
    ]
    for i, ap in enumerate(aps):
        ap_id = ap.get("id", "")
        title = ap.get("title", "").strip()
        lines.append(f"#### {ap_id}: {title}")
        lines.append("")
        files = ap.get("files") or []
        if files:
            parts = []
            for f in files:
                path = f.get("path", "")
                line_no = f.get("line")
                end_line = f.get("end_line")
                loc = f"`{path}`"
                if line_no:
                    loc += f" lines {line_no}"
                    if end_line and end_line != line_no:
                        loc += f"–{end_line}"
                parts.append(loc)
            lines.append(f"**Files:** {', '.join(parts)}")
            lines.append("")
        rationale = ap.get("rationale_md", "").rstrip()
        if rationale:
            lines.append(rationale)
            lines.append("")
        rec = ap.get("recommendation", "").strip()
        if rec:
            lines.append(f"**Recommendation:** {rec}")
            lines.append("")
        if i != len(aps) - 1:
            lines.append("---")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _verdict(overall: float) -> str:
    if overall < 4:
        return "WEAK"
    if overall < 7:
        return "OK"
    return "STRONG"


def _score_categories(draft_cats: list[dict]) -> tuple[list[dict], float]:
    by_name = {c["name"]: c for c in draft_cats}
    missing = [n for n in CATEGORY_ORDER if n not in by_name]
    if missing:
        raise SystemExit(f"score.py: missing categories in draft: {missing}")
    extra = [c["name"] for c in draft_cats if c["name"] not in CATEGORY_WEIGHTS]
    if extra:
        raise SystemExit(f"score.py: unexpected categories in draft: {extra}")

    scored: list[dict] = []
    overall = 0.0
    for name in CATEGORY_ORDER:
        cat = by_name[name]
        score = cat.get("score")
        if score is None or not isinstance(score, (int, float)) or not (0 <= score <= 10):
            raise SystemExit(
                f"score.py: category '{name}' score must be a number in [0, 10] (got {score!r})"
            )
        weight = CATEGORY_WEIGHTS[name]
        weighted = round(float(score) * weight, 4)
        overall += weighted
        entry = {
            "name": name,
            "score": score,
            "weight": weight,
            "weighted": weighted,
        }
        if "rationale_md" in cat and cat["rationale_md"]:
            entry["rationale_md"] = cat["rationale_md"]
        scored.append(entry)

    return scored, round(overall, 2)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--input", required=True, help="Draft report.json path (LLM-authored).")
    p.add_argument("--output", required=True, help="Final report.json path (schema-valid).")
    args = p.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output)
    if not in_path.exists():
        print(f"score.py: input not found: {in_path}", file=sys.stderr)
        return 1

    try:
        draft = json.loads(in_path.read_text())
    except json.JSONDecodeError as exc:
        print(f"score.py: invalid JSON in {in_path}: {exc}", file=sys.stderr)
        return 1

    if "categories" not in draft or not isinstance(draft["categories"], list):
        print("score.py: draft missing 'categories' array", file=sys.stderr)
        return 1

    scored_cats, overall = _score_categories(draft["categories"])
    verdict = _verdict(overall)

    final = {**draft, "categories": scored_cats, "overall_score": overall, "verdict": verdict}

    tree_md = _merge_trees(out_path.parent)
    if tree_md:
        final["test_structure_tree_md"] = tree_md

    contract_map_md = _merge_contract_map(out_path.parent)
    if contract_map_md:
        final["contract_map_md"] = contract_map_md

    anti_patterns_md = _load_anti_patterns(out_path.parent)
    if anti_patterns_md:
        final["anti_patterns_md"] = anti_patterns_md

    gap_analysis_md = _render_gap_analysis(out_path.parent)
    if gap_analysis_md:
        final["gap_analysis_md"] = gap_analysis_md

    hygiene_md = _render_hygiene(out_path.parent)
    if hygiene_md:
        final["hygiene_md"] = hygiene_md

    out_path.write_text(json.dumps(final, indent=2) + "\n")
    print(f"WROTE: {out_path} (overall_score={overall}, verdict={verdict})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
