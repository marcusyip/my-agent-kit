#!/usr/bin/env bash
# Regression check for scripts/lsp_tree.py against sample-app-go.
#
# Seed: (*TransactionService).chargePaymentGateway, which calls
# s.gateway.Charge(...). `gateway` has interface type payment.Gateway, so
# the walk MUST hop through the interface to reach (*StubGateway).Charge.
# Before the Go interface-hop fix, the tree dead-ended at
# `Charge @ internal/payment/gateway.go [symbol-not-found]` and the
# concrete impl was invisible — this script re-runs that exact scenario
# and fails if the dead-end ever comes back.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
PROJECT="$HERE/sample-app-go"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

python3 "$PLUGIN/scripts/lsp_tree.py" \
  --lang go \
  --project "$PROJECT" \
  --file internal/service/transaction_service.go \
  --symbol '(*TransactionService).chargePaymentGateway' \
  --depth 5 --scope local --run-dir "$OUT" > /dev/null

TREE_FILE="$(ls "$OUT"/tree__*.md 2>/dev/null | head -n1 || true)"
if [[ -z "$TREE_FILE" ]]; then
  echo "FAIL: lsp_tree.py produced no tree__*.md under $OUT" >&2
  exit 1
fi
TREE="$(cat "$TREE_FILE")"

fail() {
  echo "FAIL: $1" >&2
  echo "--- tree ---" >&2
  echo "$TREE" >&2
  exit 1
}

echo "$TREE" | grep -qF '[interface]' \
  || fail "expected [interface] tag on Gateway.Charge line"
echo "$TREE" | grep -qF '(*StubGateway).Charge' \
  || fail "expected concrete impl (*StubGateway).Charge reached via interface hop"
if echo "$TREE" | grep -qF '[symbol-not-found]'; then
  fail "tree still contains [symbol-not-found] — interface hop regressed"
fi

# Also assert gopls produced an implementation artifact at the call site —
# artifacts under $RUN_DIR/lsp/ are the audit trail for scripted LSP calls,
# so losing them would be a silent regression even if the tree still renders.
[[ -f "$OUT/lsp/implementation__internal-service-transaction-service-go__L120C24.json" ]] \
  || fail "missing implementation artifact — request_implementation did not fire"

echo "PASS: Go interface hop walks chargePaymentGateway → Gateway → (*StubGateway).Charge"
