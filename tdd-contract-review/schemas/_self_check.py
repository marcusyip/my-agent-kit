#!/usr/bin/env python3
"""Validate every schema in this directory is itself valid JSON Schema draft 2020-12,
then validate sample fixtures (where available) against their schemas.

Run from repo root:
  scripts/.venv/bin/python tdd-contract-review/schemas/_self_check.py
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent

SCHEMAS = sorted(HERE.glob("*.schema.json"))

# Build a registry so cross-file $ref (e.g., _defs.schema.json#/$defs/...) resolves.
registry = Registry()
for s in SCHEMAS:
    data = json.loads(s.read_text())
    resource = Resource.from_contents(data)
    registry = registry.with_resource(uri=s.name, resource=resource)

failures = 0

# Step 1: meta-validate each schema against draft 2020-12.
for s in SCHEMAS:
    data = json.loads(s.read_text())
    try:
        Draft202012Validator.check_schema(data)
        print(f"✓ schema valid: {s.name}")
    except Exception as exc:
        print(f"✗ schema INVALID: {s.name} — {exc}")
        failures += 1

# Step 2: validate sample fixtures against their schemas.
SAMPLE_RUN = REPO_ROOT / "tdd-contract-review/benchmark/sample-app/tdd-contract-review/20260417-1408-post-api-v1-transactions"

FIXTURE_DIR = HERE / "fixtures"
fixtures = [
    (SAMPLE_RUN / "findings.json", "findings.schema.json"),
    (FIXTURE_DIR / "extraction.sample.json", "extraction.schema.json"),
    (FIXTURE_DIR / "audit.sample.json", "audit.schema.json"),
    (FIXTURE_DIR / "gaps-per-type.sample.json", "gaps-per-type.schema.json"),
    (FIXTURE_DIR / "report.sample.json", "report.schema.json"),
    (FIXTURE_DIR / "call-tree.sample.json", "call-tree.schema.json"),
]

# Also pick up any real tree__*.json output from an existing run.
tree_candidates = list((REPO_ROOT / "tdd-contract-review/benchmark/sample-app/tdd-contract-review").rglob("tree__*.json"))
if tree_candidates:
    fixtures.append((tree_candidates[0], "call-tree.schema.json"))

for fixture_path, schema_name in fixtures:
    if not fixture_path.exists():
        print(f"· fixture skipped (missing): {fixture_path}")
        continue
    schema = json.loads((HERE / schema_name).read_text())
    validator = Draft202012Validator(schema, registry=registry)
    doc = json.loads(fixture_path.read_text())
    errors = sorted(validator.iter_errors(doc), key=lambda e: e.path)
    if errors:
        print(f"✗ fixture fails {schema_name}: {fixture_path.name}")
        for e in errors[:10]:
            loc = "/".join(str(p) for p in e.absolute_path) or "(root)"
            print(f"    at {loc}: {e.message}")
        if len(errors) > 10:
            print(f"    ... {len(errors) - 10} more")
        failures += 1
    else:
        print(f"✓ fixture passes {schema_name}: {fixture_path.name}")

sys.exit(1 if failures else 0)
