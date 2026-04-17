# Scenario Checklist Reference

Loaded by every per-type gap agent (A/B/C) in Step 6b. Defines the scenario
enumeration matrix for per-field gap analysis.

## How to apply

For every field in the Test Structure Tree:
- Enumerate every applicable scenario from the matrix below.
- Applicability is determined by the field's type + constraints (e.g., decimal
  types trigger `precision`; string fields reaching DB/SQL/shell/external
  trigger `injection strings`; columns with NOT NULL trigger `NOT NULL enforcement`).
- Do NOT collapse assertion fields into a "HAPPY PATH assertions" group. Each
  assertion field gets its own branch.
- Every enum value is its own scenario (e.g., status enum with 4 values = 4
  scenarios), never grouped as "enum values covered".
- Status per scenario: ✓ covered (cite test file:line) | ✗ missing | PARTIAL
  (weak assertion — explain why).

## Input field scenarios

Applies to: request field, request header, DB field (input), outbound response
field (when consumed as input), UI prop.

- **nullability:** null / empty string / missing / whitespace-only
- **type violation:** wrong type (string where int expected, etc.)
- **boundary values:** min, max, just-under-min, just-over-max
- **format constraints:** encoding (UTF-8 vs latin1), case sensitivity,
  leading/trailing whitespace
- **enum values:** each enum value as its own scenario (NOT grouped)
- **injection strings** (for strings that reach DB / SQL / shell / external):
  SQL injection, XSS, command injection, NULL byte
- **concurrency:** race condition / TOCTOU (only if field mutates shared state)
- **precision:** decimal precision boundary (for decimal types)
- **length:** over-max, exactly-max boundary (for string types)
- **cross-field interactions:** combinations with other fields (e.g., currency
  mismatch, amount vs balance)

## Assertion field scenarios

Applies to: response field, DB field (assertion), outbound request field.

- **presence** in response / DB / outbound payload
- **value correctness:** matches input or expected derived state
- **type correctness:** integer stays integer, string stays string
- **format:** ISO8601 for timestamps, decimal-as-string for money, etc.
- **NOT NULL enforcement** (for DB fields with NOT NULL constraint)
- **DEFAULT behavior** (for DB fields with DEFAULT clause)
- **FK integrity** (for FK columns)
- **nullability in response:** field present vs omitted when null
