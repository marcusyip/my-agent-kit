# Cross-cutting Fintech Gaps — POST /api/v1/transactions

## Cross-cutting Fintech Gaps

### 1. Money & Precision
**Assessment:** No systemic precision leaks detected across boundaries.

- API inbound: `amount` arrives as string/decimal, converted via `BigDecimal(@params[:amount].to_s)` in `validate_sufficient_balance!` — avoids Float trap.
- DB: `transactions.amount` and `wallets.balance` are both `decimal(20,8)` — matched precision on both sides.
- Outbound: `PaymentGateway.charge(amount:, currency:, ...)` receives `transaction.amount` directly (BigDecimal), no intermediate Float coercion observed.
- Response body serializes `amount.to_s` — preserves precision for clients.

One latent concern: no explicit test asserts that an incoming high-precision string (e.g. `0.000000001` — 9 decimals, beyond the 8-scale column) is either truncated, rounded, or rejected consistently. This is a per-field `amount` gap handled by 03a, not a cross-type systemic gap. **No cross-cutting gaps detected.**

---

### 2. Idempotency
**Assessment:** Idempotency is entirely absent from this state-mutating money-moving endpoint.

Gaps (cross-cuts API + DB):
- **No `Idempotency-Key` / `X-Idempotency-Key` header** read anywhere in controller or service.
- **No `idempotency_key` / `client_reference_id` column** on the `transactions` migration (db/migrate/003_create_transactions.rb does not declare it).
- **No unique index** on the transactions table that would prevent duplicate inserts at the DB layer as a safety net.
- **Why it matters in production:** A retried HTTP POST (network blip, client retry library, double-clicked submit, NAT/load-balancer retransmit) will create a second transaction row AND trigger a second `wallet.withdraw!` AND a second `PaymentGateway.charge` call. Users get double-debited and double-charged with no safeguard. This is the single highest-value fintech defense for any POST-money endpoint.

---

### 3. Transaction State Machine
**Assessment:** Multiple transition and terminal-state integrity gaps (cross-cuts DB + Outbound).

Gaps:
- **Terminal state `reversed` has no guard.** The enum defines `reversed` but no code path transitions to it and no test verifies that a `completed`/`failed`/`reversed` transaction cannot be re-submitted or re-charged. A second POST with the same transaction ID surface (or a recreate-with-same-wallet flow) has no guard preventing re-entering the `pending → completed` path.
- **No guard on invalid transitions.** Nothing in code or tests asserts that `completed → pending`, `failed → completed`, `reversed → pending` are blocked. Rails enum does not enforce transition validity by itself.
- **Dual write path leaves status ambiguous.** `Transaction#notify_payment_gateway` fires in the `after_create` callback (line 28), BEFORE `TransactionService#charge_payment_gateway` runs (line 78). The callback's charge result is not wired to a status update, so the subsequent service call may set `completed` while the callback already fired a separate (unobserved) side-effect — status reflects only the second call.
- **Stuck-state detection missing.** If `PaymentGateway.charge` raises a network timeout mid-call, the `pending` row persists with the wallet already debited via `withdraw!` and no reconciliation/sweeper job to detect stuck `pending` transactions.
- **Why it matters in production:** Stuck `pending` rows silently represent money that left the wallet but whose charge outcome is unknown — the worst reconciliation class. A missing transition guard enables replay attacks that promote a `failed` to `completed` on retry.

---

### 4. Balance/Ledger — Multi-step Atomicity
**Assessment:** The happy path is a three-step non-atomic sequence with no DB transaction wrapper and no compensating rollback.

Gaps (cross-cuts DB + Outbound):
- **No `ActiveRecord::Base.transaction do ... end` wrapping the full flow.** Observed sequence in `TransactionService#call`: (1) `@transaction.save!` creates the row in `pending`, (2) `wallet.withdraw!` (separate statement, inside its own `with_lock`) debits balance, (3) `PaymentGateway.charge` fires, (4) `@transaction.update!(status: ...)` updates status. These are independent DB writes plus one network call — any failure between (2) and (4) leaves the wallet debited but the transaction stuck in `pending` with no audit trail of the outcome.
- **No compensating rollback on `ChargeError`.** When `PaymentGateway::ChargeError` is rescued, the code returns a `Result` with status marked `failed`, but `wallet.balance` was already decremented by step (2) and is never re-credited. Real money is lost from the wallet view, despite the API returning a 422.
- **No compensating rollback on `success? == false`.** Same pattern: transaction status → `failed`, balance already debited, no deposit-back to wallet.
- **No double-entry ledger.** Single balance field is mutated directly; no immutable ledger entries mean a failed audit/reconciliation cannot reconstruct the intended vs. actual state.
- **Why it matters in production:** This is a direct-money-loss bug. Every gateway failure (network, card decline, 5xx) silently debits the user's wallet without crediting it back. At any scale this produces support tickets, manual refund work, and if the gateway is timing out at volume, real balance-sheet exposure.

---

### 5. External Integration — Double-charge and Reconciliation
**Assessment:** Critical double-charge path present; retry/webhook/reconciliation machinery absent.

Gaps:
- **Double-charge risk (CRITICAL).** `PaymentGateway.charge` is invoked from TWO code paths for the same transaction:
  1. `Transaction#notify_payment_gateway` (model `after_create` callback, `app/models/transaction.rb:28`) — fires on every `save!`.
  2. `TransactionService#charge_payment_gateway` (service, `app/services/transaction_service.rb:78`) — fires when category is `payment`.
  For `category: 'payment'`, BOTH paths execute on a single request. The gateway is billed twice, and only the service-path result is recorded to `transaction.status`. Customer is double-charged.
- **No retry logic.** A transient 5xx or timeout from `PaymentGateway.charge` becomes an immediate `failed` with no exponential backoff, no retry budget, no dead-letter handling.
- **No webhook/callback endpoint.** No async settlement handler to reconcile gateway state with local transaction status when in-line call fails.
- **No reconciliation field.** The extraction notes no external reference (`gateway_transaction_id`, `charge_id`, `provider_reference`) is parsed from the gateway response. Without an external handle, a later reconciliation job cannot map local rows to gateway records.
- **Why it matters in production:** Double-charge is a direct fraud/refund event — customer sees two charges on their statement, chargeback risk, PSP dispute. Reconciliation absence means every stuck transaction requires manual operator investigation through gateway dashboards.

---

### 6. Compliance — Audit Trail, KYC/AML Hooks
**Assessment:** No audit trail, no regulatory hooks, no regulatory-limit enforcement beyond a single hard-coded cap.

Gaps:
- **No audit log table or append-only event stream.** No `transaction_events`, `audit_log`, or similar. Financial mutations are only represented by the mutable `transactions` row itself — any `update!` on status overwrites history, and there is no actor (`created_by_id`, `approved_by_id`), no IP (`client_ip`), no user-agent, no request ID captured.
- **No KYC/AML hook point.** No check against a risk score, no KYC verification status gate, no sanctions/OFAC screening call before `PaymentGateway.charge`.
- **Transaction limit is a single hard-coded constant (`<= 1_000_000`)** in the model — no per-user daily/monthly velocity limits, no currency-specific limits, no velocity check across recent transactions.
- **Why it matters in production:** Regulators (PCI DSS, PSD2, Reg E in the US, FCA in UK) require demonstrable audit trails and actor attribution on money movements. Chargeback defense, fraud investigation, and SAR filings all depend on this. Missing KYC gates expose the platform to sanctions violations.

---

### 7. Concurrency — TOCTOU, Lock Placement, Race Conditions
**Assessment:** Classic TOCTOU pattern on the balance check, plus unserialized multi-step flow.

Gaps:
- **TOCTOU on balance check.** `TransactionService#validate_sufficient_balance!` reads `wallet.balance` OUTSIDE any lock. Only `wallet.withdraw!` later acquires `with_lock`. The race window:
  ```
  Thread A: reads balance=100, passes check for amount=80
  Thread B: reads balance=100, passes check for amount=80
  Thread A: acquires lock, withdraws 80, balance=20
  Thread B: acquires lock, withdraws 80 → balance=-60 (OR wallet.withdraw! raises if guarded, but either way one of the two has already been persisted to `transactions`)
  ```
  Two concurrent debits that individually pass the check can together overdraw the wallet, or one must fail AFTER its transaction row has been committed — leaving an orphan `pending` row.
- **Balance check should be INSIDE `with_lock` or the flow should use an atomic `UPDATE wallets SET balance = balance - ? WHERE balance >= ?` guard.** Neither pattern is present.
- **No DB transaction around save! + withdraw! + gateway call + update!.** Each step is independently committed — concurrent requests on the same wallet can interleave and produce inconsistent state even if each individual step holds its own lock.
- **No advisory lock or unique constraint to prevent simultaneous submits of the same logical operation** (related to idempotency gap above).
- **Why it matters in production:** Under load — especially during payment bursts, promo events, or wallet top-ups — concurrent requests from the same user (double-clicked UI, mobile retry, API script) can bypass the balance guard. Result: negative balance rows, overdrawn wallets, and reconciliation nightmares. This is the #1 fintech bug class.

---

### 8. Security — Auth, IDOR, Data Leak, Rate Limit
**Assessment:** Wallet IDOR is handled via scoping; sensitive data leak in error response is present; rate limiting and systemic leak prevention are absent.

Gaps:
- **Sensitive data leak in error response (HIGH).** `InsufficientBalanceError` serializes details as `["Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"]`. Returning the wallet's current balance in a 422 response body lets any authenticated user (or attacker with a stolen token) probe exact wallet balances by trial transactions. Balance is PII-adjacent financial data and should never be echoed in error bodies.
- **No rate limiting.** No Rack::Attack, throttle middleware, or per-user request budget on `POST /api/v1/transactions`. A compromised token can drain a wallet as fast as HTTP can complete. Rate limiting is a must-have control on money-mutating endpoints.
- **Wallet-ID IDOR is scoped (positive), but transaction-level authorization is not verified in this unit.** `current_user.wallets.find_by(id: ...)` correctly scopes the wallet lookup. However, no test in this unit verifies the negative case (another user's `wallet_id` returns 422 without revealing existence) — an error-message distinction between "not found" and "not owned" could still enable enumeration.
- **No input sanitization on `description`.** The free-text 500-char `description` field flows into the DB and is echoed back in the response; no HTML sanitization or script stripping. If any downstream surface (admin panel, email receipt, statement PDF) renders this field without escaping, it's an XSS vector. Controller/service does not sanitize.
- **Authentication failure path untested.** `before_action :authenticate_user!` exists but no test verifies 401 on missing/expired/malformed token. A regression that disables the filter would ship silently.
- **Why it matters in production:** Balance leakage through errors is a privacy/compliance issue (GDPR, CCPA) and a direct enumeration vector for fraudsters. Missing rate limit on a money endpoint is catastrophic if a token is ever compromised.

---

## Gap List

| id | priority | field | type | description |
|---|---|---|---|---|
| GFIN-001 | CRITICAL | unit-level | Fintech:ExternalIntegration | Double-charge: `PaymentGateway.charge` invoked in BOTH `Transaction#notify_payment_gateway` after_create (model:28) AND `TransactionService#charge_payment_gateway` (service:78). For `category: 'payment'` a single request bills the gateway twice. |
| GFIN-002 | CRITICAL | unit-level | Fintech:BalanceLedger | No DB transaction wraps `save! → withdraw! → PaymentGateway.charge → update!`. On gateway failure or exception, wallet is debited but transaction ends `failed` with no compensating credit — direct money loss. |
| GFIN-003 | CRITICAL | unit-level | Fintech:Concurrency | TOCTOU on balance: `validate_sufficient_balance!` reads `wallet.balance` outside `with_lock`. Two concurrent requests can both pass the check and overdraw the wallet. |
| GFIN-004 | HIGH | request header: Idempotency-Key | Fintech:Idempotency | No `Idempotency-Key` header read by controller; no `idempotency_key` column on `transactions`; no DB unique constraint. Retried POSTs create duplicate transactions and duplicate charges. |
| GFIN-005 | HIGH | response field: details | Fintech:Security | Insufficient-balance error body leaks `Current balance: X` — authenticated probe reveals exact wallet balance. Remove balance from error response. |
| GFIN-006 | HIGH | db field: transaction.status | Fintech:StateMachine | No guard on invalid transitions (`completed → pending`, `failed → completed`, `reversed → *`). Enum alone does not enforce. |
| GFIN-007 | HIGH | unit-level | Fintech:StateMachine | Stuck-`pending` detection absent: on exception between `withdraw!` and `update!`, row stays `pending` with wallet already debited and no reconciliation sweeper. |
| GFIN-008 | HIGH | unit-level | Fintech:Security | No rate limiting on `POST /api/v1/transactions`. Compromised token can drain wallet at HTTP speed. |
| GFIN-009 | HIGH | unit-level | Fintech:ExternalIntegration | No reconciliation field: `PaymentGateway.charge` response is not parsed for an external reference (`gateway_transaction_id`/`charge_id`), so local rows cannot be reconciled against the gateway. |
| GFIN-010 | HIGH | unit-level | Fintech:ExternalIntegration | No retry/backoff on transient gateway failures; every 5xx/timeout becomes immediate `failed` with wallet debited (couples to GFIN-002). |
| GFIN-011 | MEDIUM | unit-level | Fintech:Compliance | No audit trail: no `audit_log`/event stream; no `created_by_id` actor, no `client_ip`, no `request_id` captured on the transaction row. |
| GFIN-012 | MEDIUM | unit-level | Fintech:Compliance | No KYC/AML hook: no sanctions/risk-score check before `PaymentGateway.charge`. |
| GFIN-013 | MEDIUM | unit-level | Fintech:Compliance | Only a single hard-coded cap (`<= 1_000_000`) — no per-user velocity limits (daily/monthly/per-currency). |
| GFIN-014 | MEDIUM | request field: transaction.description | Fintech:Security | No HTML/script sanitization on `description` before persist/echo — XSS vector if rendered in any downstream admin/receipt surface. |
| GFIN-015 | MEDIUM | request header: Authorization | Fintech:Security | No test exercises missing/expired/malformed bearer — a regression that disables `authenticate_user!` would ship silently. |

---

## Test Stubs

### GFIN-001 — Double-charge via dual call path (CRITICAL)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'when category is payment' do
  it 'invokes PaymentGateway.charge exactly once per request (no double-charge)' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(response).to have_http_status(:created)
    # Critical: must be called exactly once, not once from after_create AND once from service
    expect(PaymentGateway).to have_received(:charge).once
  end

  it 'does not invoke PaymentGateway.charge from model after_create when service path owns the charge' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    # Exactly one charge; both paths currently fire → this test will fail until one is removed
    expect(PaymentGateway).to have_received(:charge).with(
      hash_including(transaction_id: Transaction.last.id)
    ).once
  end
end
```

### GFIN-002 — Missing DB transaction / compensating rollback (CRITICAL)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'when PaymentGateway raises ChargeError after wallet has been debited' do
  it 'rolls back wallet.balance to its pre-request value' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(PaymentGateway::ChargeError.new('boom'))

    expect {
      post '/api/v1/transactions',
        params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
        headers: auth_headers
    }.not_to change { wallet.reload.balance }

    expect(response).to have_http_status(:unprocessable_entity)
    # Either no transaction row, or a row with status: failed AND no net wallet debit
    expect(Transaction.where(wallet_id: wallet.id, status: 'completed').count).to eq(0)
  end

  it 'does not leave a pending transaction with a debited wallet (no orphan state)' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(StandardError.new('network timeout'))

    expect {
      post '/api/v1/transactions',
        params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
        headers: auth_headers
    rescue StandardError
      nil
    }.not_to change { wallet.reload.balance }

    # Must not end in pending with balance debited
    orphan = Transaction.where(wallet_id: wallet.id, status: 'pending').any?
    expect(orphan && wallet.balance < 100).to be false
  end
end
```

### GFIN-003 — TOCTOU on balance check (CRITICAL)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'under concurrent debit requests' do
  it 'rejects the second request when two simultaneous debits would overdraw the wallet' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')

    results = Parallel.map([60, 60], in_threads: 2) do |amount|
      post '/api/v1/transactions',
        params: { transaction: { amount: amount, currency: 'USD', wallet_id: wallet.id, category: 'transfer' } },
        headers: auth_headers
      response.status
    end

    # Exactly one must succeed, one must fail — total debits cannot exceed 100
    expect(results.count(201)).to eq(1)
    expect(results.count(422)).to eq(1)
    expect(wallet.reload.balance).to be >= 0
    expect(Transaction.where(wallet_id: wallet.id, status: 'completed').sum(:amount)).to be <= 100
  end
end
```

### GFIN-004 — Idempotency-Key absent (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'with repeated requests carrying the same Idempotency-Key' do
  it 'creates only one transaction and charges the gateway only once' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
    headers_with_key = auth_headers.merge('Idempotency-Key' => 'client-req-abc-123')

    2.times do
      post '/api/v1/transactions',
        params: { transaction: valid_params.merge(category: 'payment') },
        headers: headers_with_key
    end

    expect(Transaction.count).to eq(1)
    expect(PaymentGateway).to have_received(:charge).once
  end

  it 'rejects a request with same key but different params' do
    headers_with_key = auth_headers.merge('Idempotency-Key' => 'client-req-xyz')

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(amount: 10) },
      headers: headers_with_key
    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(amount: 999) },
      headers: headers_with_key

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

### GFIN-005 — Balance leak in error body (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'when balance is insufficient' do
  it 'returns 422 without leaking wallet balance in response body' do
    wallet = create(:wallet, user: user, balance: 50, currency: 'USD', status: 'active')

    post '/api/v1/transactions',
      params: { transaction: { amount: 1000, currency: 'USD', wallet_id: wallet.id } },
      headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity)
    body = response.body
    expect(body).not_to include('50')       # exact balance
    expect(body).not_to match(/current balance/i)
    expect(body).not_to match(/balance:\s*\d/i)
  end
end
```

### GFIN-006 — Invalid state transitions (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'state machine integrity' do
  it 'cannot transition a completed transaction back to pending via direct update' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'completed')
    expect { txn.update!(status: 'pending') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'cannot transition a failed transaction to completed' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'failed')
    expect { txn.update!(status: 'completed') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'cannot transition from a reversed terminal state' do
    txn = create(:transaction, user: user, wallet: wallet, status: 'reversed')
    %w[pending completed failed].each do |target|
      expect { txn.update!(status: target) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
```

### GFIN-007 — Stuck-pending detection (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'when gateway call raises an unexpected exception' do
  it 'does not leave the transaction in pending with wallet debited' do
    wallet = create(:wallet, user: user, balance: 100, currency: 'USD', status: 'active')
    allow(PaymentGateway).to receive(:charge).and_raise(Net::ReadTimeout.new)

    post '/api/v1/transactions',
      params: { transaction: { amount: 30, currency: 'USD', wallet_id: wallet.id, category: 'payment' } },
      headers: auth_headers
    rescue StandardError
      nil

    pending_orphan = Transaction.where(wallet_id: wallet.id, status: 'pending').last
    if pending_orphan
      # Acceptable only if wallet was NOT debited (i.e., rollback occurred)
      expect(wallet.reload.balance).to eq(100)
    end
  end
end
```

### GFIN-008 — Rate limiting (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'rate limiting on money-mutating endpoint' do
  it 'returns 429 after exceeding the per-user rate threshold' do
    threshold = 60  # placeholder — must match configured limit
    (threshold + 1).times do
      post '/api/v1/transactions', params: { transaction: valid_params }, headers: auth_headers
    end
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'applies the limit per user, not per IP' do
    other_user_headers = auth_headers_for(create(:user))
    60.times { post '/api/v1/transactions', params: { transaction: valid_params }, headers: auth_headers }
    post '/api/v1/transactions', params: { transaction: valid_params }, headers: other_user_headers
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
```

### GFIN-009 — Reconciliation reference missing (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'when PaymentGateway.charge succeeds' do
  it 'persists the external gateway reference for reconciliation' do
    allow(PaymentGateway).to receive(:charge).and_return(
      double(success?: true, transaction_id: 'pg_ref_abc123')
    )

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(Transaction.last.gateway_reference).to eq('pg_ref_abc123')
  end

  it 'flags transactions missing a gateway reference as a reconciliation risk' do
    allow(PaymentGateway).to receive(:charge).and_return(double(success?: true, transaction_id: nil))

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:accepted)
    # Either reject (safer) or mark for reconciliation — current code silently accepts nil reference
  end
end
```

### GFIN-010 — Retry absent on transient gateway failure (HIGH)

```ruby
# spec/requests/api/v1/post_transactions_spec.rb
context 'transient gateway 5xx' do
  it 'retries with backoff before marking the transaction failed' do
    call_count = 0
    allow(PaymentGateway).to receive(:charge) do
      call_count += 1
      call_count < 3 ? raise(PaymentGateway::ChargeError.new('503')) : double(success?: true)
    end

    post '/api/v1/transactions',
      params: { transaction: valid_params.merge(category: 'payment') },
      headers: auth_headers

    expect(response).to have_http_status(:created)
    expect(call_count).to eq(3)
    expect(Transaction.last.status).to eq('completed')
  end
end
```
