# Partial Yield Claim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow merchants to claim a specific amount of accrued yield instead of all-or-nothing.

**Architecture:** New `claim_yield_partial<T>` in router.move delegates to `debit_accrued_yield_typed<T>` in merchant.move (partial debit from AccruedYieldKey df). Existing `claim_yield_v2<T>` becomes a wrapper calling partial with the full amount. SDK adds `claimYieldPartial()` method + `buildClaimYieldPartial` transaction builder.

**Tech Stack:** Move 2024 Edition, @mysten/sui v2, TypeScript, Vitest

**Spec:** `docs/superpowers/specs/2026-04-07-partial-yield-claim-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `move/baleenpay/sources/merchant.move` | New error const + `debit_accrued_yield_typed<T>` + test helper |
| Modify | `move/baleenpay/sources/router.move` | New error const + `claim_yield_partial<T>` + refactor `claim_yield_v2<T>` |
| Modify | `move/baleenpay/sources/events.move` | New `YieldClaimedPartial` struct + emit fn |
| Create | `move/baleenpay/tests/partial_yield_claim_tests.move` | All Move tests for partial claim |
| Modify | `packages/sdk/src/transactions/yield.ts` | New `buildClaimYieldPartial` |
| Modify | `packages/sdk/src/transactions/index.ts` | Re-export |
| Modify | `packages/sdk/src/index.ts` | Re-export |
| Modify | `packages/sdk/src/client.ts` | New `claimYieldPartial()` method |
| Modify | `packages/sdk/test/client.test.ts` | SDK tests |

---

### Task 1: Add `YieldClaimedPartial` event

**Files:**
- Modify: `move/baleenpay/sources/events.move` (after line 131)

- [ ] **Step 1: Add event struct and emit function**

Add after the `emit_router_mode_changed` function (line 131):

```move
public struct YieldClaimedPartial has copy, drop {
    merchant_id: ID,
    claimed: u64,
    remaining: u64,
}

public(package) fun emit_yield_claimed_partial(merchant_id: ID, claimed: u64, remaining: u64) {
    event::emit(YieldClaimedPartial { merchant_id, claimed, remaining });
}
```

- [ ] **Step 2: Verify build**

Run: `sui move build --path move/baleenpay`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add move/baleenpay/sources/events.move
git commit -m "feat(move): add YieldClaimedPartial event struct"
```

---

### Task 2: Add `debit_accrued_yield_typed<T>` to merchant.move

**Files:**
- Modify: `move/baleenpay/sources/merchant.move`

- [ ] **Step 1: Add error constant**

Add after `EAlreadyMigrated` (line 26):

```move
#[error]
const EExceedsAccrued: u64 = 29;    // amount > accrued yield for this type
```

- [ ] **Step 2: Add `debit_accrued_yield_typed<T>` function**

Add after `reset_accrued_yield_typed<T>` (after line 315):

```move
/// Debit a specific amount from typed accrued yield. Returns the debited amount.
/// Removes the df entirely if remaining is zero (no zombie dynamic fields).
/// Uses immutable borrow first to avoid borrow checker conflict between borrow_mut and remove.
public(package) fun debit_accrued_yield_typed<T>(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    amount: u64,
): u64 {
    assert!(!account.paused_by_admin && !account.paused_by_self, EPaused);
    assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
    assert!(amount > 0, EZeroAmount);
    let key = AccruedYieldKey<T> {};
    assert!(dynamic_field::exists_(&account.id, key), EZeroYield);
    let current_val = *dynamic_field::borrow<AccruedYieldKey<T>, u64>(&account.id, key);
    assert!(amount <= current_val, EExceedsAccrued);
    if (amount == current_val) {
        dynamic_field::remove<AccruedYieldKey<T>, u64>(&mut account.id, key);
    } else {
        let current = dynamic_field::borrow_mut<AccruedYieldKey<T>, u64>(&mut account.id, key);
        *current = current_val - amount;
    };
    amount
}
```

Note: `EZeroAmount` is not defined in merchant.move. Add it if missing:

```move
#[error]
const EZeroAmount: u64 = 10;        // amount must be > 0
```

Check if `EZeroAmount` already exists in merchant.move before adding (it exists in router.move and payment.move with value 10, but not in merchant.move).

- [ ] **Step 3: Add test helper**

Add after existing test helpers (after `credit_external_yield_typed_for_testing`, around line 381):

```move
#[test_only]
public fun debit_accrued_yield_typed_for_testing<T>(
    cap: &MerchantCap, account: &mut MerchantAccount, amount: u64,
): u64 {
    debit_accrued_yield_typed<T>(cap, account, amount)
}
```

- [ ] **Step 4: Verify build**

Run: `sui move build --path move/baleenpay`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add move/baleenpay/sources/merchant.move
git commit -m "feat(move): add debit_accrued_yield_typed for partial yield claim"
```

---

### Task 3: Add `claim_yield_partial<T>` and refactor `claim_yield_v2<T>`

**Files:**
- Modify: `move/baleenpay/sources/router.move`

- [ ] **Step 1: Add error constant**

Add after `EPaused` (line 26):

```move
#[error]
const EInsufficientVaultBalance: u64 = 30;
```

- [ ] **Step 2: Add `claim_yield_partial<T>`**

Add before `claim_yield_v2<T>` (before line 228):

```move
public fun claim_yield_partial<T>(
    cap: &merchant::MerchantCap,
    account: &mut MerchantAccount,
    yield_vault: &mut YieldVault<T>,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(yield_vault.balance.value() >= amount, EInsufficientVaultBalance);
    let claimed = merchant::debit_accrued_yield_typed<T>(cap, account, amount);
    let remaining = merchant::get_accrued_yield_typed<T>(account);
    let coin = yield_vault.balance.split(claimed).into_coin(ctx);
    transfer::public_transfer(coin, merchant::get_owner(account));
    events::emit_yield_claimed_partial(object::id(account), claimed, remaining);
}
```

- [ ] **Step 3: Refactor `claim_yield_v2<T>` to wrapper**

Replace the body of `claim_yield_v2<T>` (lines 228-238) with:

```move
public fun claim_yield_v2<T>(
    cap: &merchant::MerchantCap,
    account: &mut MerchantAccount,
    yield_vault: &mut YieldVault<T>,
    ctx: &mut TxContext,
) {
    let amount = merchant::get_accrued_yield_typed<T>(account);
    claim_yield_partial<T>(cap, account, yield_vault, amount, ctx);
}
```

- [ ] **Step 4: Verify build**

Run: `sui move build --path move/baleenpay`
Expected: Build succeeds

- [ ] **Step 5: Run existing tests to verify v2 wrapper doesn't break anything**

Run: `sui move test --path move/baleenpay`
Expected: All 193+ tests pass (v2 wrapper should be transparent to existing tests)

- [ ] **Step 6: Commit**

```bash
git add move/baleenpay/sources/router.move
git commit -m "feat(move): add claim_yield_partial + refactor v2 as wrapper"
```

---

### Task 4: Move tests — happy path and edge cases

**Files:**
- Create: `move/baleenpay/tests/partial_yield_claim_tests.move`

- [ ] **Step 1: Write test file with setup helpers and happy path tests**

```move
#[test_only]
module baleenpay::partial_yield_claim_tests;
use sui::test_scenario;
use sui::coin::{Self, Coin};
use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
use baleenpay::router::{Self, YieldVault};

public struct USDB has drop {}
public struct STABLE has drop {}

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
}

fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(
        &mut registry,
        b"TestMerchant".to_string(),
        scenario.ctx(),
    );
    test_scenario::return_shared(registry);
}

fun seed_yield_vault(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    amount: u64,
) {
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let usdb_coin = coin::mint_for_testing<USDB>(amount, scenario.ctx());
    router::keeper_deposit_yield<USDB>(
        &admin_cap,
        &mut yield_vault,
        &mut account,
        usdb_coin,
    );
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(yield_vault);
}

fun create_yield_vault_usdb(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);
}

// ── Happy path ──

#[test]
fun partial_claim_basic() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim 40 out of 100
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 60);
    assert_eq!(router::yield_vault_balance<USDB>(&yield_vault), 60);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Verify merchant received 40
    scenario.next_tx(merchant_addr);
    let usdb: Coin<USDB> = scenario.take_from_sender();
    assert_eq!(usdb.value(), 40);
    scenario.return_to_sender(usdb);

    scenario.end();
}

#[test]
fun partial_claim_all_removes_df() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim exactly 100 (full amount via partial)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 100, scenario.ctx(),
    );
    // df should be removed → getter returns 0
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 0);
    assert_eq!(router::yield_vault_balance<USDB>(&yield_vault), 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

#[test]
fun v2_wrapper_still_works() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 500);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_v2<USDB>(
        &cap, &mut account, &mut yield_vault, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.next_tx(merchant_addr);
    let usdb: Coin<USDB> = scenario.take_from_sender();
    assert_eq!(usdb.value(), 500);
    scenario.return_to_sender(usdb);

    scenario.end();
}

#[test]
fun multiple_partial_claims() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim 30
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 30, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 70);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Claim 30 more
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 30, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 40);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Claim remaining 40
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

// ── Abort tests ──

#[test, expected_failure]
fun abort_zero_amount() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 0, scenario.ctx(),
    );
    abort 0 // unreachable
}

#[test, expected_failure]
fun abort_exceeds_accrued() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 101, scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure]
fun abort_no_accrued_yield() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    // No yield seeded

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 50, scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure]
fun abort_vault_balance_insufficient() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);

    // Manually credit accrued yield without actually depositing to vault
    scenario.next_tx(admin);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 1000);
    test_scenario::return_shared(account);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 500, scenario.ctx(),
    );
    abort 0
}

// ── Monkey tests ──

#[test]
fun claim_1_mist() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 1, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 99);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

#[test]
fun multi_type_interleave() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Create YieldVault<USDB>
    create_yield_vault_usdb(&mut scenario, admin);

    // Create YieldVault<STABLE>
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_yield_vault<STABLE>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Seed USDB 100
    seed_yield_vault(&mut scenario, admin, 100);

    // Seed STABLE 50
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut yield_vault_stable = scenario.take_shared<YieldVault<STABLE>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let stable_coin = coin::mint_for_testing<STABLE>(50, scenario.ctx());
    router::keeper_deposit_yield<STABLE>(
        &admin_cap,
        &mut yield_vault_stable,
        &mut account,
        stable_coin,
    );
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(yield_vault_stable);

    // Partial claim USDB 40
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert_eq!(merchant::get_accrued_yield_typed<USDB>(&account), 60);
    // STABLE untouched
    assert_eq!(merchant::get_accrued_yield_typed<STABLE>(&account), 50);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}
```

- [ ] **Step 2: Run tests**

Run: `sui move test --path move/baleenpay --filter partial_yield_claim`
Expected: All tests pass

- [ ] **Step 3: Run full test suite to check no regressions**

Run: `sui move test --path move/baleenpay`
Expected: All 193+ tests still pass (plus new ones)

- [ ] **Step 4: Commit**

```bash
git add move/baleenpay/tests/partial_yield_claim_tests.move
git commit -m "test(move): add partial yield claim tests + monkey tests"
```

---

### Task 5: SDK — `buildClaimYieldPartial` + `claimYieldPartial`

**Files:**
- Modify: `packages/sdk/src/transactions/yield.ts`
- Modify: `packages/sdk/src/transactions/index.ts`
- Modify: `packages/sdk/src/index.ts`
- Modify: `packages/sdk/src/client.ts`

- [ ] **Step 1: Add `buildClaimYieldPartial` to `yield.ts`**

Add after `buildClaimYield` (after line 29):

```ts
/**
 * Build claim_yield_partial PTB (router module, with YieldVault).
 * Requires yieldVaultId in config and coinType. Amount in MIST.
 */
export function buildClaimYieldPartial(
  config: BaleenPayConfig,
  merchantCapId: string,
  coinType: string,
  amount: bigint,
): Transaction {
  if (!config.yieldVaultId) {
    throw new Error('yieldVaultId is required in config for claim_yield')
  }
  if (amount <= 0n) {
    throw new Error('amount must be > 0')
  }
  const resolved = resolveCoin(config.network, coinType)
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::claim_yield_partial`,
    typeArguments: [coinTypeArg(resolved.type)],
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.yieldVaultId),
      tx.pure.u64(amount),
    ],
  })
  return tx
}
```

- [ ] **Step 2: Update `transactions/index.ts`**

Change line 5 from:
```ts
export { buildClaimYield } from './yield.js'
```
to:
```ts
export { buildClaimYield, buildClaimYieldPartial } from './yield.js'
```

- [ ] **Step 3: Update `src/index.ts`**

Add `buildClaimYieldPartial` to the transactions re-export block (around line 67):

```ts
  buildClaimYield,
  buildClaimYieldPartial,
```

- [ ] **Step 4: Add `claimYieldPartial` method to `client.ts`**

Add after the `claimYield` method (after line 160):

```ts
  /** Build a claim_yield_partial transaction. Amount in MIST. */
  claimYieldPartial(merchantCapId: string, coinType: string, amount: bigint): TransactionResult {
    return { tx: buildClaimYieldPartial(this.config, merchantCapId, coinType, amount) }
  }
```

Also add the import at the top of `client.ts` — update the import from `./transactions/yield.js`:

```ts
import { buildClaimYield, buildClaimYieldPartial } from './transactions/yield.js'
```

(Check existing import style — it may import from `./transactions/index.js` instead.)

- [ ] **Step 5: Build SDK**

Run: `pnpm --filter @baleenpay/sdk build`
Expected: Build succeeds, no type errors

- [ ] **Step 6: Commit**

```bash
git add packages/sdk/src/transactions/yield.ts packages/sdk/src/transactions/index.ts packages/sdk/src/index.ts packages/sdk/src/client.ts
git commit -m "feat(sdk): add claimYieldPartial transaction builder + client method"
```

---

### Task 6: SDK tests

**Files:**
- Modify: `packages/sdk/test/client.test.ts`

- [ ] **Step 1: Add tests**

Add after the existing `claimYield` test (after line 74):

```ts
    it('claimYieldPartial returns tx', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      const result = c.claimYieldPartial('0xcap', 'USDC', 100n)
      expect(result.tx).toBeDefined()
    })

    it('claimYieldPartial throws on zero amount', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      expect(() => c.claimYieldPartial('0xcap', 'USDC', 0n)).toThrow('amount must be > 0')
    })

    it('claimYieldPartial throws on negative amount', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      expect(() => c.claimYieldPartial('0xcap', 'USDC', -1n)).toThrow('amount must be > 0')
    })

    it('claimYieldPartial throws without yieldVaultId', () => {
      const c = new BaleenPay(baseConfig) // no yieldVaultId
      expect(() => c.claimYieldPartial('0xcap', 'USDC', 100n)).toThrow('yieldVaultId is required')
    })
```

- [ ] **Step 2: Run SDK tests**

Run: `pnpm --filter @baleenpay/sdk test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add packages/sdk/test/client.test.ts
git commit -m "test(sdk): add claimYieldPartial client tests"
```

---

### Task 7: Final verification

- [ ] **Step 1: Full Move test suite**

Run: `sui move test --path move/baleenpay`
Expected: All tests pass (193+ existing + ~10 new)

- [ ] **Step 2: SDK type check**

Run: `cd packages/sdk && npx tsc --noEmit`
Expected: No type errors

- [ ] **Step 3: SDK full test suite**

Run: `pnpm --filter @baleenpay/sdk test`
Expected: All tests pass

- [ ] **Step 4: Update progress.md**

Update `tasks/progress.md` to mark partial yield claim as completed.
