<!-- version: 0.29.0 -->
# API Security Checklists — Contract Extraction & Gap Analysis

Reference file loaded on demand when `critical` mode is detected. Covers the "is access controlled?" domain: authentication, authorization (IDOR), rate limits, audit trail, webhook trust, sensitive-data handling, regulatory/compliance.

Companion file: `money-correctness-checklists.md` covers amounts, state, concurrency, and money lifecycle.

## Contract Extraction Details

### Security & Access Control
- Extract authentication requirements per endpoint: which endpoints require auth? What auth method (JWT, API key, session, OAuth)?
- Extract authorization rules: who can access which resources? Map resource ownership — user can only access their own wallets/transactions. Look for: `current_user`, `authorize!`, policy objects, middleware guards, `@login_required`, role checks
- Identify IDOR-vulnerable endpoints: any endpoint that accepts a resource ID in params (GET/PATCH/DELETE `/transactions/:id`, `/wallets/:id`). Check if the code verifies ownership/permission before acting
- Extract rate limiting configuration: which endpoints have rate limits? What are the thresholds? Is it per-user, per-IP, or per-API-key?
- Identify sensitive data in responses: do error messages leak account numbers, balances, internal IDs, or stack traces? Do list endpoints expose other users' data?
- Extract input sanitization: are financial fields (amount, currency, description) validated against injection? Is the description field HTML-sanitized for XSS?
- Identify payment credential handling: does the system touch raw card numbers (PAN), or use tokenization (Stripe tokens, vault references)? Raw PANs in the codebase are a critical finding
- Extract API key scoping: are there different permission levels for API keys (read-only vs. read-write vs. admin)? Are financial mutation endpoints restricted to appropriate scopes?
- Identify multi-factor/approval flows for high-value operations: large transfers, withdrawal to new address, adding new beneficiary. Extract the threshold and approval mechanism

### Audit Trail & Immutable Records
- Extract audit trail fields present on financial mutations: `created_by`, `approved_by`, `ip_address`, `user_agent`, `request_id`, timestamps, old value / new value
- Check audit table immutability: no `UPDATE` or `DELETE` on audit records. Verify with DB constraints, append-only table patterns, or row-level triggers
- Identify PII that must be redacted in logs and in audit trail output (SSN, full card numbers, account numbers, raw bearer tokens)
- Check for audit completeness: every state-mutating financial endpoint has a corresponding audit path

### Regulatory & Compliance (access-facing)
- Extract KYC/AML-related fields: verification status, risk score, identity document references. These are gating fields for certain operations
- Identify operations gated by KYC status: withdrawals to new beneficiary, transfers above threshold, international transfers
- Extract sanctions/OFAC screening triggers: which operations call the screening service? What blocks on a hit?
- Identify PCI scope: does the system touch raw card numbers or only tokens? The tokenization boundary is the PCI boundary
- Identify high-value operation thresholds: above which amount does the system require MFA, manual review, or approval?
- Extract PII fields that need careful handling in test data: SSN, bank account numbers, card numbers. Tests must not use real PII
- (Numeric transaction limits — per-transaction, daily, monthly — are extracted in `money-correctness-checklists.md` under Transaction Limits. Only the KYC/AML gating and compliance triggers belong here.)

### Webhook & Callback Trust
- Extract webhook/callback endpoint contracts: event types handled, signature verification method, payload fields
- Identify signature verification library/method: HMAC-SHA256, JWT, provider-specific (Stripe `Webhook.construct_event`). Check signing secret management — env var, KMS, hardcoded (gap)
- Extract replay protection: event ID deduplication (DB unique constraint or cache) + timestamp tolerance window (e.g. Stripe accepts signatures within ±5 minutes of the signed timestamp)
- Identify webhook source validation beyond signature: IP allowlist, mutual TLS, or signature-only
- Extract event-type allowlist: does the handler enumerate known events, or does it trust any event the provider sends?
- Identify what the webhook mutates: if it updates financial state (payment status, refund status), every mutation path is a contract surface

## Gap Analysis Scenario Checklists

For each field type below, check every scenario. Tag all findings with `[SECURITY]`.

### For security & access control (every endpoint handling financial data)
- Authentication required: unauthenticated request to a protected endpoint must return 401. Test with missing token, expired token, malformed token
- Authorization / ownership: accessing another user's resource must return 403 or 404. Test with valid auth but wrong user's wallet ID, transaction ID, account ID. This is IDOR testing — the #1 security bug for any system that exposes resource IDs in URLs
- Privilege escalation: regular user calling admin-only endpoints (e.g. manual credit, override limit) must be rejected. Test each role boundary
- Resource enumeration: sequential IDs allow guessing other resources. Test that accessing `transaction_id + 1` belonging to another user returns 403/404, not the other user's data. If UUIDs are used, note as a positive finding
- Amount tampering: test that the server recomputes totals (amount + fee = total) rather than trusting client-submitted totals. Submit a request where amount + fee ≠ total — must be rejected or server must override
- Negative amount bypass: test that submitting a negative amount to a credit/deposit endpoint does not reverse into a debit. Negative amounts on transfer endpoints must be explicitly rejected
- Rate limiting on financial endpoints: test that exceeding the rate limit returns 429. Test that rate limits are per-user (not just per-IP), so one user cannot exhaust limits for another
- Sensitive data in error responses: test that 422/500 responses do not leak account numbers, balances, internal user IDs, SQL errors, or stack traces. Error body should contain only the error code and a generic message
- Sensitive data in list responses: test that `GET /transactions` only returns the authenticated user's transactions, not all transactions. Test pagination boundaries
- API key scope enforcement: if the API supports scoped keys, test that a read-only key cannot create transactions (403). Test that a key scoped to one merchant cannot access another merchant's data
- High-value operation approval: if the system requires MFA/approval for transfers above a threshold, test at threshold (succeeds without approval), above threshold (requires approval), and that bypassing the approval step is not possible via direct API call
- Injection: for string fields reaching DB/logs/HTML, test SQL injection payloads, XSS payloads, NULL bytes, and very long strings. Financial descriptions and memos are common attack surfaces

### For audit trail fields
- Every financial mutation creates an audit record with: actor, action, timestamp, IP, old value, new value
- Audit records are immutable: no `UPDATE` or `DELETE` on audit table (check DB constraints or test that attempts fail)
- Audit trail surfaces sensitive data safely: test that PII is redacted in log output and in any audit-retrieval endpoint response
- Failed mutations are also audited: a rejected transaction (422) still logs the attempt with the actor and reason — not just successes

### For KYC/AML/compliance fields
- Operations blocked by KYC status: test that an operation gated on KYC (e.g. withdrawal) returns the documented error when status is `pending`, `rejected`, or `expired` — not a generic 500
- Sanctions hit: if the system integrates with a sanctions screening service, test that a hit blocks the operation and records the hit. Mock the screening response
- PII in test data: assert tests do not use real SSNs, real card numbers, real bank accounts. Check fixtures for plausibly-real values (common anti-pattern)
- High-value MFA trigger: at-threshold amount must succeed without MFA; above-threshold must require MFA. Bypass attempt (submitting without the MFA token when required) must be rejected

### For webhook/callback endpoints
- Signature verification: invalid signature must be rejected (401/403)
- Missing signature header: must be rejected (do not default-allow)
- Tampered payload: valid signature for a different body — must be rejected (tests that signature is computed over the actual body, not just present)
- Replay attack: duplicate event ID must be idempotent (not process twice). Test with the same event delivered twice
- Timestamp replay window: signed timestamp outside tolerance (e.g. > 5 min old) must be rejected even with a valid signature. Test at boundary
- Unknown event type: must return 200 (acknowledge) but not process — prevents provider from retrying indefinitely on an event we don't handle
- Out-of-order events: e.g. `payment_intent.succeeded` arriving before `payment_intent.created` — must handle gracefully (either process correctly or queue for later)
- Webhook source IP: if IP allowlist is used, test rejection from non-allowlisted source
- Signing secret rotation: if the system supports key rotation, test that signatures signed with a previous key within the grace window are still accepted (or rejected per contract)
- Webhook-triggered mutation has audit: webhook processing that updates financial state must produce an audit record (who: webhook-source, what: event-type, when, signed payload hash)
