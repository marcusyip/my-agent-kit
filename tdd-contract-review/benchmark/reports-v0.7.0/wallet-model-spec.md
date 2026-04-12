## TDD Contract Review: spec/models/wallet_spec.rb

**Test file:** `spec/models/wallet_spec.rb`
**Contract boundary:** `Wallet#deposit!` and `Wallet#withdraw!` (model public API methods)
**Source files:** `app/models/wallet.rb`
**Framework:** Rails 7.1 / RSpec (model spec)

### Overall Score: 6.5 / 10

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Contract Coverage | 6/10 | 25% | 1.50 |
| Test Grouping | 7/10 | 15% | 1.05 |
| Scenario Depth | 5/10 | 20% | 1.00 |
| Test Case Quality | 7/10 | 15% | 1.05 |
| Isolation & Flakiness | 7/10 | 15% | 1.05 |
| Anti-Patterns | 8/10 | 10% | 0.80 |
| **Overall** | | | **6.45** |

### Verdict: ADEQUATE

### Contract Extraction Summary

```
CONTRACT EXTRACTION SUMMARY
============================
Source: app/models/wallet.rb
Framework: Rails 7.1 / RSpec

Wallet#deposit!(amount):
  - amount must be positive (raises ArgumentError) [HIGH confidence]
  - wallet must be active (raises 'Wallet is not active') [HIGH confidence]
  - increases balance by amount (with_lock) [HIGH confidence]

Wallet#withdraw!(amount):
  - amount must be positive (raises ArgumentError) [HIGH confidence]
  - wallet must be active (raises 'Wallet is not active') [HIGH confidence]
  - balance must be >= amount (raises 'Insufficient balance') [HIGH confidence]
  - decreases balance by amount (with_lock) [HIGH confidence]

Wallet status enum: active, suspended, closed [HIGH confidence]
============================
```

### Test Structure Tree

```
Wallet#deposit!
├── ✓ positive amount → increases balance
├── ✓ negative amount → raises ArgumentError
├── ✓ zero amount → raises ArgumentError
├── field: wallet status
│   ├── ✓ suspended → raises 'Wallet is not active'
│   └── ✗ closed → raises 'Wallet is not active'
└── ✗ concurrent deposits (with_lock behavior)

Wallet#withdraw!
├── ✓ positive amount → decreases balance
├── ✓ negative amount → raises ArgumentError
├── ✗ zero amount → raises ArgumentError
├── ✓ insufficient balance → raises 'Insufficient balance'
├── ✗ exact balance (boundary) → should succeed, balance = 0
├── field: wallet status — NO TESTS
│   ├── ✗ suspended → raises 'Wallet is not active'
│   └── ✗ closed → raises 'Wallet is not active'
└── ✗ concurrent withdrawals (with_lock behavior)
```

### Contract Map

| Contract | Field | Confidence | Test Group | Scenarios Covered | Gaps |
|---|---|---|---|---|---|
| deposit! | amount (positive) | HIGH | Yes | positive, negative, zero | -- |
| deposit! | wallet status | HIGH | Yes | suspended | missing: closed |
| withdraw! | amount (positive) | HIGH | Yes | positive, negative | missing: zero |
| withdraw! | balance check | HIGH | Yes | insufficient | missing: exact boundary |
| withdraw! | wallet status | HIGH | No | -- | HIGH: no status tests |

### Gap Analysis by Priority

**HIGH** (core contract fields with no tests)

- [ ] `Wallet#withdraw!` wallet status — no test for suspended or closed wallet (`wallet.rb:27`)

  Suggested test:
  ```ruby
  describe '#withdraw!' do
    context 'when wallet is suspended' do
      before { wallet.update!(status: 'suspended') }

      it 'raises error' do
        expect { wallet.withdraw!(100) }.to raise_error('Wallet is not active')
      end
    end

    context 'when wallet is closed' do
      before { wallet.update!(status: 'closed') }

      it 'raises error' do
        expect { wallet.withdraw!(100) }.to raise_error('Wallet is not active')
      end
    end
  end
  ```

**MEDIUM** (tested but missing scenarios)

- [ ] `Wallet#deposit!` — missing closed wallet scenario (only suspended tested)

  Suggested test:
  ```ruby
  context 'when wallet is closed' do
    before { wallet.update!(status: 'closed') }

    it 'raises error' do
      expect { wallet.deposit!(100) }.to raise_error('Wallet is not active')
    end
  end
  ```

- [ ] `Wallet#withdraw!` — missing zero amount and exact balance boundary

  Suggested test:
  ```ruby
  it 'raises on zero amount' do
    expect { wallet.withdraw!(0) }.to raise_error(ArgumentError)
  end

  it 'succeeds when withdrawing exact balance' do
    wallet.withdraw!(1000)
    expect(wallet.reload.balance).to eq(0)
  end
  ```

**LOW** (rare corner cases)

- [ ] Concurrent deposit/withdraw safety (requires integration-level test with threads)

### Anti-Patterns Detected

| Anti-Pattern | Location | Severity | Fix |
|---|---|---|---|
| Incomplete enum coverage | `wallet_spec.rb` | MEDIUM | Test all 3 status values (active, suspended, closed) for both methods |

### Top 5 Priority Actions

1. **Add wallet status tests for `withdraw!`** — suspended and closed states completely untested
2. **Add closed wallet test for `deposit!`** — only suspended is tested, closed is missing
3. **Add zero amount test for `withdraw!`** — boundary case untested
4. **Add exact balance boundary test for `withdraw!`** — `balance == amount` path untested
5. **Consider adding concurrent access tests** — `with_lock` is used but never exercised under contention

---
