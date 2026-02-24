# ICRC1.mo Cleanup Work Plan

**Created:** 2026-02-04  
**Status:** ✅ Complete (Phases 1-3)  
**Estimated Effort:** ~40-60 hours

---

## Overview

This plan addresses improvements to the ICRC1.mo library across documentation, testing, and benchmarking. Tasks are ordered by priority and dependency.

---

## Phase 1: Documentation Updates (Priority: HIGH)

### Task 1.1: Fix README Code Errors
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 30 min

**Issues to fix:**
1. Missing closing code block after `import ICRC1 "mo:icrc1.mo";` in Usage section
2. Typo in `icrc1()` function example - references `_icrc3` instead of `_icrc1`:
```motoko
// INCORRECT (current)
switch(_icrc3){

// CORRECT
switch(_icrc1){
```

**Acceptance Criteria:**
- [ ] Usage example has complete, valid code
- [ ] All code examples compile without errors

---

### Task 1.2: Add Security Notes for Admin Functions
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 1 hour

**Add implementation security note for these functions:**
- `update_ledger_info`
- `register_metadata`
- `register_supported_standards`

**Note to add:**
```markdown
> ⚠️ **Security Note:** These functions do not include authorization checks. 
> When exposing through an actor interface, you MUST implement proper access 
> control (e.g., controller-only, DAO governance, etc.).
```

**Acceptance Criteria:**
- [ ] Each function has a prominent security warning
- [ ] Example guard implementation provided

---

### Task 1.3: Document Account Pruning Strategy
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 1 hour

**Add new section documenting:**

```markdown
## Account Pruning

### Overview
When the ledger exceeds `max_accounts` (default: 5,000,000), it automatically 
prunes accounts down to `settle_to_accounts` (default: 4,990,000).

### Pruning Algorithm
Accounts are sorted by balance in ascending order. The smallest balances are 
burned first until the account count reaches `settle_to_accounts`.

### ⚠️ Important Considerations
- **Dust Attack Risk:** Attackers could create many small-balance accounts to 
  trigger pruning of legitimate small balances
- **No Minimum Protection:** Currently, there is no minimum balance threshold 
  that protects accounts from pruning
- **Burned Tokens:** Pruned balances are transferred to the minting account 
  (burned) and recorded in the transaction log with memo "clean"

### Configuration
| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_accounts` | 5,000,000 | Trigger threshold for pruning |
| `settle_to_accounts` | 4,990,000 | Target account count after pruning |

### Recommendations
1. Set `min_burn_amount` to a value that discourages dust attacks
2. Monitor account growth patterns
3. Consider the economic impact of your pruning thresholds
```

**Acceptance Criteria:**
- [ ] Pruning behavior is clearly documented
- [ ] Risks are highlighted
- [ ] Configuration options explained

---

### Task 1.4: Document Async can_transfer Reentrancy Risks
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 45 min

**Add warning in the Overrides section:**

```markdown
### ⚠️ Reentrancy Warning for Async can_transfer

When using `#Async` can_transfer handlers, be aware of potential reentrancy risks:

1. **State Changes:** The ledger state may change between validation and execution
2. **Re-validation:** After async operations, the transfer is re-validated against 
   current state
3. **Concurrent Transfers:** Multiple transfers may be in-flight simultaneously
4. **Best Practices:**
   - Keep async operations minimal
   - Avoid modifying ledger state within the handler
   - Consider using `#Sync` handlers when possible
   - If async is required, implement your own locking mechanism
```

**Acceptance Criteria:**
- [ ] Reentrancy risks documented
- [ ] Best practices provided
- [ ] Clear guidance on when to use Sync vs Async

---

### Task 1.5: Document Error Codes
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 1 hour

**Add comprehensive error documentation:**

```markdown
## Error Codes Reference

### TransferError Variants

| Error | Code | Description | Resolution |
|-------|------|-------------|------------|
| `#BadFee` | - | Fee doesn't match expected | Use `icrc1_fee()` to get correct fee |
| `#BadBurn` | - | Amount below `min_burn_amount` | Increase burn amount |
| `#InsufficientFunds` | - | Balance < amount + fee | Check balance first |
| `#Duplicate` | - | Transaction already exists | Use different `created_at_time` or memo |
| `#TooOld` | - | `created_at_time` outside window | Use current time |
| `#CreatedInFuture` | - | `created_at_time` in future | Use current time |
| `#TemporarilyUnavailable` | - | Ledger temporarily unavailable | Retry later |
| `#GenericError` | varies | See codes below | See specific code |

### GenericError Codes

| Code | Context | Message | Resolution |
|------|---------|---------|------------|
| 1 | Transfer | Self-transfer not allowed | Use different recipient |
| 2 | Transfer | Invalid sender account | Validate account format |
| 3 | Transfer | Invalid recipient account | Validate account format |
| 4 | Transfer | Memo too large | Reduce memo to ≤ `max_memo` bytes |
| 5 | Transfer | Amount must be > 0 | Use positive amount |
| 6 | Mint | Max supply exceeded | Cannot mint more tokens |
| 7 | Transfer | Both accounts are minting account | Invalid operation per ICRC-3 |
| 401 | Mint | Unauthorized minter | Only minting_account can mint |
| 6453 | Transfer | can_transfer rejection | Check custom validation |
```

**Acceptance Criteria:**
- [ ] All error variants documented
- [ ] Error codes explained
- [ ] Resolution guidance provided

---

### Task 1.6: Document ICRC Integration
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 1 hour

**Add section:**

```markdown
## Integration with Other ICRC Standards

### ICRC-2 (Approve/TransferFrom)
Use with [icrc2-mo](https://mops.one/icrc2-mo) for approval mechanics.
```motoko
// Wire up ICRC-2 to use ICRC-1's transfer
let icrc2_environment = {
  icrc1 = icrc1();
  // ... other config
};
```

### ICRC-3 (Transaction Log)
For scalable transaction history with archiving:
```motoko
get_icrc1_environment = func() : ICRC1.Environment {
  {
    add_ledger_transaction = ?(icrc3().add_record);
    // ... other config
  }
};
```

### ICRC-4 (Batch Transfers)
Use with [icrc4-mo](https://mops.one/icrc4-mo) for batch operations.

### ICRC-107 (Fee Collector)
This library supports ICRC-107 fee collection:
- Set via `update_ledger_info([#FeeCollector(?account)])`
- Remove via `update_ledger_info([#FeeCollector(null)])`
- When removed, fees are burned (per ICRC-107 spec)

### Complete Implementation Example
See [ICRC_fungible](https://github.com/icdevsorg/ICRC_fungible) for a 
full implementation combining ICRC-1, 2, 3, 4, 103, and 106.
```

**Acceptance Criteria:**
- [ ] Each integration documented
- [ ] Code examples provided
- [ ] Links to related libraries

---

### Task 1.7: Add API Reference
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 2 hours

Added comprehensive API reference section with:

```markdown
## API Reference

### Core Query Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `name()` | `Text` | Token name |
| `symbol()` | `Text` | Token symbol |
| `decimals()` | `Nat8` | Decimal places |
| `fee()` | `Balance` | Transfer fee |
| `metadata()` | `[MetaDatum]` | All metadata |
| `total_supply()` | `Balance` | Circulating supply |
| `minted_supply()` | `Balance` | Total ever minted |
| `burned_supply()` | `Balance` | Total ever burned |
| `max_supply()` | `?Balance` | Maximum supply cap |
| `minting_account()` | `Account` | Minting authority |
| `balance_of(Account)` | `Balance` | Account balance |
| `supported_standards()` | `[SupportedStandard]` | Supported ICRC standards |
| `get_state()` | `CurrentState` | Full internal state |
| `get_environment()` | `Environment` | Environment config |
| `get_local_transactions()` | `List<Transaction>` | Local tx log |
| `get_icrc85_stats()` | `{...}` | OVS statistics |

### Transfer Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `transfer_tokens(caller, args, system_override, can_transfer)` | `async* Star<TransferResult, Text>` | Primary transfer (recommended) |
| `transfer(caller, args)` | `async* TransferResult` | Simple transfer (traps on error) |
| `mint_tokens(caller, args)` | `async* Star<TransferResult, Text>` | Mint tokens (recommended) |
| `mint(caller, args)` | `async* TransferResult` | Simple mint (traps on error) |
| `burn_tokens(caller, args, system_override)` | `async* Star<TransferResult, Text>` | Burn tokens (recommended) |
| `burn(caller, args)` | `async* TransferResult` | Simple burn (traps on error) |

### Admin Functions (⚠️ Require Security Guards)

| Function | Returns | Description |
|----------|---------|-------------|
| `update_ledger_info([UpdateLedgerInfoRequest])` | `[Bool]` | Update ledger settings |
| `register_metadata([MetaDatum])` | `[MetaDatum]` | Add custom metadata |
| `register_supported_standards(SupportedStandard)` | `Bool` | Register standard support |

### Event Functions

| Function | Description |
|----------|-------------|
| `register_token_transferred_listener(namespace, callback)` | Subscribe to transfers |

### Utility Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `get_fee(TransferArgs)` | `Nat` | Calculate fee for transfer |
| `get_expected_fee(TransferArgs)` | `Nat` | Get base ledger fee |
| `validate_request(tx_req, fee, override)` | `Result<(), TransferError>` | Validate a request |
| `deduplicate(TransactionRequest)` | `Result<(), Nat>` | Check for duplicate |
| `testMemo(?Blob)` | `??Blob` | Validate memo size |
| `testCreatedAt(?Nat64)` | `{#ok; #Err}` | Validate timestamp |
| `find_dupe(Blob)` | `?Nat` | Find duplicate by hash |
| `get_time64()` | `Nat64` | Current time in ns |

### Full Type Documentation
See [types.mo](src/ICRC1/migrations/v000_002_000/types.mo) for complete type definitions.
```

**Acceptance Criteria:**
- [ ] All public functions documented
- [ ] Return types specified
- [ ] Organized by category

---

## Phase 2: New Tests (Priority: HIGH)

### Task 2.1: Deduplication Edge Cases Tests
**Status:** [x] Complete  
**File:** [tests/ICRC1/ICRC1.ActorTest.mo](../tests/ICRC1/ICRC1.ActorTest.mo)  
**Effort:** 2 hours

**Test cases added:**
- `Null created_at_time skips deduplication per ICRC-1 spec`
- `Same memo and created_at_time triggers deduplication`

**Acceptance Criteria:**
- [x] null created_at_time behavior tested
- [x] Cleanup after window tested
- [x] Edge cases covered

---

### Task 2.2: Account Pruning Tests
**Status:** [x] Complete  
**File:** [tests/ICRC1/ICRC1.ActorTest.mo](../tests/ICRC1/ICRC1.ActorTest.mo)  
**Effort:** 2 hours

**Test cases added:**
- `Pruning removes smallest balances first`
- `Pruning creates burn transactions with clean memo`

**Acceptance Criteria:**
- [x] Threshold behavior tested
- [x] Ordering verified
- [x] Transaction log entries checked

---

### Task 2.3: Fee Collector Tests (ICRC-107 Compliance)
**Status:** [x] Complete  
**File:** [tests/ICRC1/ICRC1.ActorTest.mo](../tests/ICRC1/ICRC1.ActorTest.mo)  
**Reference:** https://github.com/dfinity/ICRC/blob/main/ICRCs/ICRC-107/ICRC-107.md  
**Effort:** 3 hours

**Test cases added:**
- `Fee collector receives transfer fees`
- `Removing fee collector causes fees to be burned (ICRC-107)`

**Acceptance Criteria:**
- [x] Fee collection works
- [x] ICRC-107 removal behavior verified
- [x] fee_col/fee_col_block logic tested

---

### Task 2.4: Max Supply Enforcement Tests
**Status:** [x] Complete  
**File:** [tests/ICRC1/ICRC1.ActorTest.mo](../tests/ICRC1/ICRC1.ActorTest.mo)  
**Effort:** 1.5 hours

**Test cases added:**
- `Cannot mint beyond max_supply`
- `Burns allow re-minting up to max_supply`

**Acceptance Criteria:**
- [x] Max supply enforced on mint
- [x] Behavior at boundary tested
- [x] Burn/re-mint cycle tested

---

### Task 2.5: Async can_transfer Cancellation Tests
**Status:** [x] Complete  
**File:** [tests/ICRC1/ICRC1.ActorTest.mo](../tests/ICRC1/ICRC1.ActorTest.mo)  
**Effort:** 2 hours

**Test cases added:**
- `Async can_transfer rejection preserves state`

**Acceptance Criteria:**
- [x] Cancellation works correctly
- [x] State preserved on cancel
- [x] Re-validation tested

---

### Task 2.6: Concurrent Transfer Race Condition Tests
**Status:** [x] Complete  
**File:** [pic/icrc1.dfinity.test.ts](../pic/icrc1.dfinity.test.ts)  
**Effort:** 3 hours

**Test cases added:**
- `concurrent transfers should not double-spend`
- `concurrent mints at max_supply boundary should not exceed limit`
- `concurrent transfer and burn should not over-spend`
- `identical concurrent requests should be deduplicated`
- `many concurrent small transfers should maintain balance invariants`

**Acceptance Criteria:**
- [x] No double-spending possible
- [x] Concurrent operations safe
- [x] Deduplication works under load

---

## Phase 3: Benchmarks (Priority: MEDIUM)

### Task 3.1: Set Up Mops Benchmarks Infrastructure
**Status:** [x] Complete  
**File:** Create [bench/](../bench/) directory  
**Effort:** 1 hour

**Steps:**
1. Add bench package: `mops add bench --dev`
2. Create bench directory structure
3. Create initial benchmark template

**mops.toml addition:**
```toml
[dev-dependencies]
bench = "2.0.1"
```

**Acceptance Criteria:**
- [x] `mops bench` runs successfully
- [x] Benchmark infrastructure in place

---

### Task 3.2: Transfer Benchmarks
**Status:** [x] Complete (merged into balance.bench.mo)  
**File:** [bench/balance.bench.mo](../bench/balance.bench.mo)  
**Effort:** 2 hours

Benchmarks `transfer_balance` which is the core synchronous balance update operation.

**Acceptance Criteria:**
- [x] Transfer benchmark runs
- [x] Results in markdown table format

---

### Task 3.3: Balance Lookup Benchmarks
**Status:** [x] Complete  
**File:** [bench/balance.bench.mo](../bench/balance.bench.mo)  
**Effort:** 1.5 hours

Benchmarks `get_balance` and `update_balance` at different account scales (100, 1000, 10000).

**Acceptance Criteria:**
- [x] O(log n) lookup verified at scale

---

### Task 3.4: Add Benchmark Results to README
**Status:** [x] Complete  
**File:** [readme.md](../readme.md)  
**Effort:** 30 min

Benchmark results added for Account Operations and Balance Operations.

After running benchmarks, add results section:

```markdown
## Performance Benchmarks

Run `mops bench` to reproduce.

### Transfer Operations

| Operation | 1 | 100 | 1000 |
|-----------|---|-----|------|
| transfer | X instructions | Y instructions | Z instructions |
| mint | ... | ... | ... |
| burn | ... | ... | ... |

### Memory Usage

| Accounts | Heap Size |
|----------|-----------|
| 1,000 | X bytes |
| 100,000 | Y bytes |
| 1,000,000 | Z bytes |
```

**Acceptance Criteria:**
- [ ] Benchmark results documented
- [ ] Reproducibility instructions provided

---

## Phase 4: Code Improvements (Priority: LOW)

### Task 4.1: Consider Minimum Balance Protection for Pruning
**Status:** [ ] Deferred  
**File:** [src/ICRC1/lib.mo](../src/ICRC1/lib.mo)  
**Effort:** 2-4 hours

**Potential Enhancement:**
Add optional `min_protected_balance` that exempts accounts from pruning.

```motoko
// In State
var min_protected_balance : ?Nat; // Accounts >= this balance won't be pruned

// In checkAccounts
if(thisItem.1 >= min_protected_balance) continue clean;
```

**Note:** This is a potential future enhancement, not a current bug.

---

### Task 4.2: Add can_update Authorization Callback
**Status:** [ ] Deferred  
**File:** [src/ICRC1/lib.mo](../src/ICRC1/lib.mo)  
**Effort:** 2-3 hours

**Potential Enhancement:**
Add optional authorization hook in Environment for admin functions.

```motoko
// In Environment
can_update : ?((caller: Principal, operation: UpdateOperation) -> Bool);
```

**Note:** This would provide library-level security rather than requiring implementation-level guards.

---

## Checklist Summary

### Phase 1: Documentation
- [x] 1.1 Fix README code errors
- [x] 1.2 Add security notes for admin functions
- [x] 1.3 Document account pruning strategy
- [x] 1.4 Document async can_transfer reentrancy risks
- [x] 1.5 Document error codes
- [x] 1.6 Document ICRC integration
- [x] 1.7 Add API reference

### Phase 2: Tests
- [x] 2.1 Deduplication edge cases
- [x] 2.2 Account pruning tests
- [x] 2.3 Fee collector tests (ICRC-107)
- [x] 2.4 Max supply enforcement tests
- [x] 2.5 Async can_transfer cancellation tests
- [x] 2.6 Concurrent transfer race condition tests (PocketIC)

### Phase 3: Benchmarks
- [x] 3.1 Set up mops bench infrastructure
- [x] 3.2 Balance operations benchmarks (balance.bench.mo)
- [x] 3.3 Account operations benchmarks (account.bench.mo)
- [x] 3.4 Add benchmark results to README

### Phase 4: Code Improvements (Deferred)
- [ ] 4.1 Minimum balance protection
- [ ] 4.2 can_update authorization callback

---

## Execution Order

**Recommended order for implementation:**

1. **Quick Wins (1-2 hours)**
   - Task 1.1: Fix README code errors
   - Task 1.2: Add security notes

2. **Core Documentation (3-4 hours)**
   - Task 1.3: Account pruning
   - Task 1.4: Reentrancy risks
   - Task 1.5: Error codes

3. **Critical Tests (8-10 hours)**
   - Task 2.3: Fee collector (ICRC-107)
   - Task 2.2: Account pruning
   - Task 2.1: Deduplication
   - Task 2.4: Max supply

4. **Extended Testing (5 hours)**
   - Task 2.5: Async cancellation
   - Task 2.6: Concurrency tests

5. **Benchmarks (6-8 hours)**
   - Tasks 3.1-3.6

6. **Final Documentation (3 hours)**
   - Task 1.6: ICRC integration
   - Task 1.7: API reference

---

## Notes for LLM Agents

When working on this plan:

1. **Before editing any file:**
   - Read the current file content
   - Understand existing patterns and style
   - Check for related code that might need updates

2. **For test files:**
   - Follow existing test patterns in ICRC1.ActorTest.mo
   - Use the `get_icrc<system>()` helper
   - Use `assertAllTrue([...])` for multiple assertions

3. **For documentation:**
   - Maintain existing README structure
   - Use consistent markdown formatting
   - Include code examples where helpful

4. **For benchmarks:**
   - Follow mops bench package conventions
   - Create one `.bench.mo` file per category
   - Output should be markdown tables

5. **Mark tasks complete** by changing `[ ]` to `[x]` in this file after each task.
