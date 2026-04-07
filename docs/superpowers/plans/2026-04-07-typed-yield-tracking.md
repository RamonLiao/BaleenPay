# Per-Coin-Type Yield Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `accrued_yield: u64` struct field with per-coin-type dynamic fields (`AccruedYieldKey<phantom T>`) so that `claim_yield_v2<T>` only drains yield matching the vault's coin type.

**Architecture:** Add `AccruedYieldKey<phantom T>` dynamic field to `MerchantAccount` (same pattern as `FarmingPrincipalKey`). Update `keeper_deposit_yield<T>` and `claim_yield_v2<T>` to use typed functions. Old struct field kept (compatible upgrade constraint) but set to 0 after migration.

**Tech Stack:** SUI Move 2024 edition, @baleenpay/sdk TypeScript

**Spec:** `docs/superpowers/specs/2026-04-07-typed-yield-tracking-design.md`

---

### Task 1: Add `AccruedYieldKey<T>` struct and typed functions to merchant.move

**Files:**
- Modify: `move/baleenpay/sources/merchant.move`

- [ ] **Step 1: Add error constant and struct**

Add after `FarmingPrincipalKey` (line 29):

```move
/// Dynamic field key for per-type accrued yield tracking.
public struct AccruedYieldKey<phantom T> has copy, drop, store {}

#[error]
const EAlreadyMigrated: u64 = 28; // admin_migrate_yield already called for this type
```

Add `EAlreadyMigrated` after the existing error constants block (after line 24).

- [ ] **Step 2: Add `credit_external_yield_typed<T>`**

Add after `credit_external_yield` (line 202):

```move
/// Credit yield per coin type — writes to dynamic field.
/// Used by router::keeper_deposit_yield<T> post-upgrade.
public(package) fun credit_external_yield_typed<T>(
    account: &mut MerchantAccount,
    amount: u64,
) {
    let key = AccruedYieldKey<T> {};
    if (dynamic_field::exists_(&account.id, key)) {
        let current = dynamic_field::borrow_mut<AccruedYieldKey<T>, u64>(&mut account.id, key);
        *current = *current + amount;
    } else {
        dynamic_field::add(&mut account.id, key, amount);
    };
}
```

- [ ] **Step 3: Add `reset_accrued_yield_typed<T>`**

Add after `reset_accrued_yield` (line 248):

```move
/// Reset yield for specific coin type — removes df, returns amount.
/// Used by router::claim_yield_v2<T> post-upgrade.
public(package) fun reset_accrued_yield_typed<T>(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
): u64 {
    assert!(!account.paused_by_admin && !account.paused_by_self, EPaused);
    assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
    let key = AccruedYieldKey<T> {};
    assert!(dynamic_field::exists_(&account.id, key), EZeroYield);
    let amount = dynamic_field::remove<AccruedYieldKey<T>, u64>(&mut account.id, key);
    assert!(amount > 0, EZeroYield);
    amount
}
```

- [ ] **Step 4: Add `get_accrued_yield_typed<T>`**

Add after `get_accrued_yield` getter (line 273):

```move
/// Returns accrued yield for a specific coin type (from dynamic field).
public fun get_accrued_yield_typed<T>(account: &MerchantAccount): u64 {
    let key = AccruedYieldKey<T> {};
    if (dynamic_field::exists_(&account.id, key)) {
        *dynamic_field::borrow<AccruedYieldKey<T>, u64>(&account.id, key)
    } else {
        0
    }
}
```

- [ ] **Step 5: Add `admin_migrate_yield<T>` and `admin_set_yield<T>`**

Add as public functions in the admin section (after `self_unpause`, around line 163):

```move
/// One-time migration: move accrued_yield struct field value into AccruedYieldKey<T> df.
/// Guard: asserts df does NOT already exist to prevent double-call.
public fun admin_migrate_yield<T>(
    _admin: &AdminCap,
    account: &mut MerchantAccount,
) {
    let key = AccruedYieldKey<T> {};
    assert!(!dynamic_field::exists_(&account.id, key), EAlreadyMigrated);
    let amount = account.accrued_yield;
    if (amount > 0) {
        dynamic_field::add(&mut account.id, key, amount);
    };
    account.accrued_yield = 0;
}

/// Admin sets accrued yield for a specific type. For fixing accounting errors.
public fun admin_set_yield<T>(
    _admin: &AdminCap,
    account: &mut MerchantAccount,
    new_amount: u64,
) {
    let key = AccruedYieldKey<T> {};
    if (dynamic_field::exists_(&account.id, key)) {
        if (new_amount == 0) {
            dynamic_field::remove<AccruedYieldKey<T>, u64>(&mut account.id, key);
        } else {
            *dynamic_field::borrow_mut<AccruedYieldKey<T>, u64>(&mut account.id, key) = new_amount;
        };
    } else if (new_amount > 0) {
        dynamic_field::add(&mut account.id, key, new_amount);
    };
    account.accrued_yield = 0;
    events::emit_yield_corrected(object::id(account), new_amount);
}
```

- [ ] **Step 6: Add test helpers**

Add in the `#[test_only]` section (after existing test helpers):

```move
#[test_only]
public fun credit_external_yield_typed_for_testing<T>(account: &mut MerchantAccount, amount: u64) {
    credit_external_yield_typed<T>(account, amount);
}
```

- [ ] **Step 7: Build to verify compilation**

Run: `sui move build`
Expected: Build succeeds with no new errors (linter warnings OK).

- [ ] **Step 8: Commit**

```bash
git add move/baleenpay/sources/merchant.move
git commit -m "feat(merchant): add AccruedYieldKey<T> typed yield tracking"
```

---

### Task 2: Add `YieldCorrected` event to events.move

**Files:**
- Modify: `move/baleenpay/sources/events.move`

- [ ] **Step 1: Add event struct and emitter**

Add at the end of events.move (before closing `}`):

```move
public struct YieldCorrected has copy, drop {
    merchant_id: ID,
    new_amount: u64,
}

public(package) fun emit_yield_corrected(merchant_id: ID, new_amount: u64) {
    event::emit(YieldCorrected { merchant_id, new_amount });
}
```

- [ ] **Step 2: Build to verify**

Run: `sui move build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add move/baleenpay/sources/events.move
git commit -m "feat(events): add YieldCorrected event for admin_set_yield audit trail"
```

---

### Task 3: Update router.move to use typed functions

**Files:**
- Modify: `move/baleenpay/sources/router.move`

- [ ] **Step 1: Update `keeper_deposit_yield<T>`**

Change line 207 from:
```move
merchant::credit_external_yield(account, amount);
```
to:
```move
merchant::credit_external_yield_typed<T>(account, amount);
```

- [ ] **Step 2: Update `claim_yield_v2<T>`**

Change line 234 from:
```move
let amount = merchant::reset_accrued_yield(cap, account);
```
to:
```move
let amount = merchant::reset_accrued_yield_typed<T>(cap, account);
```

- [ ] **Step 3: Build to verify**

Run: `sui move build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add move/baleenpay/sources/router.move
git commit -m "feat(router): use typed yield functions in keeper_deposit_yield and claim_yield_v2"
```

---

### Task 4: Update existing tests for typed yield

**Files:**
- Modify: `move/baleenpay/tests/yield_claim_v2_tests.move`
- Modify: `move/baleenpay/tests/vault_tests.move`

The existing tests use `keeper_deposit_yield<USDB>` which now calls `credit_external_yield_typed<USDB>` internally. The tests should pass without changes because:
- `keeper_deposit_yield` writes yield to `AccruedYieldKey<USDB>` df
- `claim_yield_v2<USDB>` reads from `AccruedYieldKey<USDB>` df

However, tests that use `credit_external_yield_for_testing` (which writes to the **old struct field**) will break because `claim_yield_v2` now reads from df. These tests need updating.

- [ ] **Step 1: Fix `test_credit_external_yield_does_not_deduct_principal`**

In `yield_claim_v2_tests.move`, update the test (line 29-50). Change:
```move
merchant::credit_external_yield_for_testing(&mut account, 500);
assert!(merchant::get_idle_principal(&account) == 1000); // unchanged!
assert!(merchant::get_accrued_yield(&account) == 500);
```
to:
```move
merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 500);
assert!(merchant::get_idle_principal(&account) == 1000); // unchanged!
assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 500);
```

- [ ] **Step 2: Fix `test_claim_yield_from_vault`**

In `yield_claim_v2_tests.move`, update assertion on line 78 and line 94. Change:
```move
assert!(merchant::get_accrued_yield(&account) == 500);
```
to:
```move
assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 500);
```

And line 94:
```move
assert!(merchant::get_accrued_yield(&account) == 0);
```
to:
```move
assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);
```

- [ ] **Step 3: Fix `test_claim_yield_insufficient_vault_balance`**

In `yield_claim_v2_tests.move`, line 126. Change:
```move
merchant::credit_external_yield_for_testing(&mut account, 1000);
```
to:
```move
merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 1000);
```

- [ ] **Step 4: Fix `test_claim_yield_v2_paused`**

No change needed — this test uses `keeper_deposit_yield` which now correctly writes to df.

- [ ] **Step 5: Fix `test_claim_yield_v2_zero`**

No change needed — `reset_accrued_yield_typed<USDB>` checks `df::exists_` and asserts `EZeroYield` when df doesn't exist (same behavior as before).

- [ ] **Step 6: Check vault_tests.move `test_keeper_deposit_yield`**

Read the test to see if it asserts `get_accrued_yield`. If yes, update to `get_accrued_yield_typed<USDB>`.

- [ ] **Step 7: Run all tests**

Run: `sui move test`
Expected: All 176 tests pass.

- [ ] **Step 8: Commit**

```bash
git add move/baleenpay/tests/
git commit -m "fix(tests): update yield tests for typed AccruedYieldKey<T>"
```

---

### Task 5: Write new tests for typed yield tracking

**Files:**
- Create: `move/baleenpay/tests/typed_yield_tests.move`

- [ ] **Step 1: Write test for multi-type yield isolation**

```move
#[test_only]
module baleenpay::typed_yield_tests {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
    use baleenpay::router::{Self, YieldVault};

    public struct USDB has drop {}
    public struct REWARD_A has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestMerchant".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    /// Two yield types credited independently — claiming one does not affect the other.
    #[test]
    fun test_multi_type_yield_isolation() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Credit two types of yield
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
        merchant::credit_external_yield_typed_for_testing<REWARD_A>(&mut account, 200);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);
        assert!(merchant::get_accrued_yield_typed<REWARD_A>(&account) == 200);
        test_scenario::return_shared(account);

        // Create YieldVault<USDB> + seed
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let usdb_coin = coin::mint_for_testing<USDB>(100, scenario.ctx());
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, usdb_coin);
        test_scenario::return_shared(yield_vault);

        // Claim USDB yield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yield_vault, scenario.ctx());

        // USDB yield gone, REWARD_A untouched
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);
        assert!(merchant::get_accrued_yield_typed<REWARD_A>(&account) == 200);

        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
```

- [ ] **Step 2: Write test for `admin_migrate_yield` happy path**

Add to `typed_yield_tests.move`:

```move
#[test]
fun test_admin_migrate_yield() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Simulate legacy state: accrued_yield = 50 (struct field)
    scenario.next_tx(admin);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_for_testing(&mut account, 50);
    assert!(merchant::get_accrued_yield(&account) == 50);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);
    test_scenario::return_shared(account);

    // Admin migrates
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);

    // Struct field = 0, df = 50
    assert!(merchant::get_accrued_yield(&account) == 0);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 50);

    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
```

- [ ] **Step 3: Write test for `admin_migrate_yield` double-call guard**

```move
#[test]
#[expected_failure] // EAlreadyMigrated
fun test_admin_migrate_yield_double_call() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(admin);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_for_testing(&mut account, 50);
    test_scenario::return_shared(account);

    // First migration — OK
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Second migration — should abort (EAlreadyMigrated)
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
```

- [ ] **Step 4: Write test for `admin_set_yield`**

```move
#[test]
fun test_admin_set_yield() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Set yield to 100
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 100);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);
    assert!(merchant::get_accrued_yield(&account) == 0); // struct field zeroed

    // Set yield to 0 — df removed
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 0);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);

    // Set yield again — df re-created
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 42);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 42);

    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
```

- [ ] **Step 5: Write test for claim with no yield of that type**

```move
#[test]
#[expected_failure] // EZeroYield
fun test_claim_typed_yield_nonexistent_type() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Credit USDB yield only
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
    test_scenario::return_shared(account);

    // Create YieldVault<REWARD_A> (different type)
    router::create_yield_vault<REWARD_A>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Try claim REWARD_A — should abort (no df for REWARD_A)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<REWARD_A>>();
    router::claim_yield_v2<REWARD_A>(&cap, &mut account, &mut yield_vault, scenario.ctx());
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
```

- [ ] **Step 6: Run all tests**

Run: `sui move test`
Expected: All tests pass (176 existing + 5 new = 181).

- [ ] **Step 7: Commit**

```bash
git add move/baleenpay/tests/typed_yield_tests.move
git commit -m "test: add typed yield tracking tests (isolation, migration, admin_set, edge cases)"
```

---

### Task 6: Update SDK types and client

**Files:**
- Modify: `packages/sdk/src/types.ts`
- Modify: `packages/sdk/src/client.ts`

- [ ] **Step 1: Add `accruedYieldByType` to `MerchantInfo` (deprecated annotation for `accruedYield`)**

In `packages/sdk/src/types.ts`, update `MerchantInfo` interface:

```typescript
export interface MerchantInfo {
  merchantId: ObjectId
  owner: string
  brandName: string
  totalReceived: bigint
  idlePrincipal: bigint
  /** @deprecated Use BaleenPayClient.getAccruedYieldTyped() instead. Always 0 after migration. */
  accruedYield: bigint
  activeSubscriptions: number
  pausedByAdmin: boolean
  pausedBySelf: boolean
}
```

- [ ] **Step 2: Add `getAccruedYieldTyped` method to `BaleenPayClient`**

In `packages/sdk/src/client.ts`, add after the existing `getMerchantInfo` method:

```typescript
/**
 * Get accrued yield for a specific coin type (reads dynamic field).
 * Returns 0 if no yield of this type has been credited.
 */
async getAccruedYieldTyped(merchantId: string, coinType: string): Promise<bigint> {
  const tx = new Transaction()
  tx.moveCall({
    target: `${this.config.packageId}::merchant::get_accrued_yield_typed`,
    typeArguments: [coinType],
    arguments: [tx.object(merchantId)],
  })
  const result = await this.grpcClient.devInspectTransactionBlock({
    sender: '0x0000000000000000000000000000000000000000000000000000000000000000',
    transactionBlock: tx,
  })
  const returnValue = result.results?.[0]?.returnValues?.[0]
  if (!returnValue) return 0n
  const bytes = new Uint8Array(returnValue[0])
  return new DataView(bytes.buffer).getBigUint64(0, true)
}
```

Note: Import `Transaction` is already imported in client.ts.

- [ ] **Step 3: Build SDK**

Run: `cd packages/sdk && pnpm build`
Expected: Build succeeds.

- [ ] **Step 4: Run SDK tests**

Run: `cd packages/sdk && pnpm test`
Expected: All tests pass. (Existing tests use mocked data with `accrued_yield` struct field — they don't call `getAccruedYieldTyped` so no changes needed.)

- [ ] **Step 5: Commit**

```bash
git add packages/sdk/src/types.ts packages/sdk/src/client.ts
git commit -m "feat(sdk): add getAccruedYieldTyped() for per-type yield query"
```

---

### Task 7: Upgrade, migrate, and verify on testnet

**Files:**
- Modify: `deployments/testnet-2026-04-07.json`
- Modify: `tasks/progress.md`

- [ ] **Step 1: Run Move tests one final time**

Run: `sui move test`
Expected: All tests pass.

- [ ] **Step 2: Build for upgrade**

Run: `sui move build`
Expected: Build succeeds.

- [ ] **Step 3: Upgrade package on testnet**

```bash
sui client upgrade \
  --upgrade-capability 0xa0a2f41e7c70d25ce3ba54c10b90939dfae7b47de6fce28b4e3c822ddf87e731 \
  --json
```

Record new packageId from output (version 3).

- [ ] **Step 4: Run migration + correction in single PTB**

Using the new package ID (`$NEW_PKG`):

```bash
USDB_TYPE="0x673d4118c17de717b0b90c326f8f52f87b5fff8678f513edd2ae575a55175954::usdb::USDB"
ADMIN="0x140c6a1721434374f3ca6c1c5d80e6bcaa67cebfcd55c7b1ffb758bbd3d3650e"
MERCHANT="0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b"

sui client ptb \
  --move-call "${NEW_PKG}::merchant::admin_set_yield<${USDB_TYPE}>" \
    @${ADMIN} @${MERCHANT} <YIELD_VAULT_USDB_BALANCE> \
  --json
```

Where `<YIELD_VAULT_USDB_BALANCE>` is the current balance of `YieldVault<USDB>` (`0xe90a...3775`). Query it first:

```bash
sui client object 0xe90a8e473936b8d920afb5c5a793181a0fc8d7a62a9021f4d270205e69b23775 --json | jq '.content.balance'
```

Use `admin_set_yield` instead of `admin_migrate_yield` because we need to correct the 1-unit historical mismatch. `admin_set_yield` both sets the df and zeros the struct field.

- [ ] **Step 5: Verify on-chain state**

```bash
# Check struct field is 0
sui client object $MERCHANT --json | jq '.content.accrued_yield'
# Expected: "0"

# Check typed yield matches vault balance
# Use devInspect or just proceed to claim test
```

- [ ] **Step 6: Test claim_yield_v2 on testnet**

```bash
MERCHANT_CAP="0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f"
YIELD_VAULT_USDB="0xe90a8e473936b8d920afb5c5a793181a0fc8d7a62a9021f4d270205e69b23775"

sui client ptb \
  --move-call "${NEW_PKG}::router::claim_yield_v2<${USDB_TYPE}>" \
    @${MERCHANT_CAP} @${MERCHANT} @${YIELD_VAULT_USDB} \
  --json | jq '.effects.status'
```

Expected: `"success"` — merchant receives USDB, accrued_yield_typed<USDB> reset to 0.

- [ ] **Step 7: Update deployment record**

Update `deployments/testnet-2026-04-07.json` with:
- New package v3 ID
- `YieldVault_USDB` object ID
- Migration tx digest

- [ ] **Step 8: Update progress.md**

Mark typed yield tracking as completed.

- [ ] **Step 9: Commit**

```bash
git add deployments/ tasks/progress.md move/baleenpay/Published.toml move/baleenpay/Move.lock
git commit -m "feat: deploy typed yield tracking v3 + migrate testnet"
```
