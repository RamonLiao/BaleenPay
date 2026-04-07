# Merchant Self-Service Redeem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable merchants to redeem principal from StableLayer farming back to USDC, with smart SDK that wraps PTB complexity for Web2 developers.

**Architecture:** Dynamic field `FarmingPrincipalKey` on MerchantAccount tracks farming amounts (Option B — no migration). New `StablecoinVault<T>` holds minted Stablecoin receipts. Merchant calls `take_stablecoin` (Move) which the SDK composes with StableLayer `request_burn → farm::pay → fulfill_burn` in a single PTB. Keeper operations updated to properly track idle→farming transitions.

**Tech Stack:** Move (SUI), TypeScript SDK, vitest

**Spec:** `docs/superpowers/specs/2026-04-07-merchant-redeem-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `move/baleenpay/sources/merchant.move` | Add `FarmingPrincipalKey`, `move_to_farming`, `return_from_farming`, `get_farming_principal` |
| Modify | `move/baleenpay/sources/router.move` | Add `StablecoinVault<T>`, `create_stablecoin_vault`, `keeper_deposit_to_farm`, `take_stablecoin`; deprecate raw `keeper_withdraw` |
| Modify | `move/baleenpay/sources/events.move` | Add `FarmDeposited`, `FarmRedeemed` events + emit helpers |
| Create | `move/baleenpay/tests/farming_tests.move` | Tests for farming accounting + take_stablecoin |
| Create | `move/baleenpay/tests/merchant_withdraw_tests.move` | Tests for merchant_withdraw (idle USDC) |
| Modify | `packages/sdk/src/stablelayer/client.ts` | Add `buildRedeemTx` method |
| Modify | `packages/sdk/src/transactions/keeper.ts` | Fix `buildKeeperDeposit` to store Stablecoin in StablecoinVault + update merchant accounting |
| Create | `packages/sdk/src/transactions/redeem.ts` | `buildMerchantRedeem` — composite PTB: take_stablecoin + StableLayer burn |
| Modify | `packages/sdk/src/transactions/merchant.ts` | Add `buildMerchantWithdraw` |
| Modify | `packages/sdk/src/types.ts` | Add `stablecoinVaultId` to config, `MerchantBalance`, `RedeemParams` |
| Modify | `packages/sdk/src/transactions/index.ts` | Re-export new builders |
| Modify | `packages/sdk/test/stablelayer.test.ts` | Add `buildRedeemTx` tests |
| Create | `packages/sdk/test/redeem.test.ts` | Tests for `buildMerchantRedeem` composite PTB |
| Create | `packages/sdk/test/merchant-withdraw.test.ts` | Tests for `buildMerchantWithdraw` |

---

### Task 1: Move — farming_principal dynamic field on MerchantAccount

**Files:**
- Modify: `move/baleenpay/sources/merchant.move`

- [ ] **Step 1: Add FarmingPrincipalKey struct and imports**

Add after the `MerchantAccount` struct definition in `merchant.move`:

```move
/// Dynamic field key for farming_principal (Option B — no struct migration).
public struct FarmingPrincipalKey has copy, drop, store {}
```

Add `use sui::dynamic_field;` to the imports at the top of the module.

- [ ] **Step 2: Add move_to_farming function**

Add after the `credit_external_yield` function:

```move
/// Move idle principal to farming. Called by router when keeper deposits to StableLayer.
public(package) fun move_to_farming(account: &mut MerchantAccount, amount: u64) {
    assert!(account.idle_principal >= amount, EInsufficientPrincipal);
    account.idle_principal = account.idle_principal - amount;
    let farming = get_farming_principal_internal(&account.id);
    if (dynamic_field::exists_(&account.id, FarmingPrincipalKey {})) {
        *dynamic_field::borrow_mut(&mut account.id, FarmingPrincipalKey {}) = farming + amount;
    } else {
        dynamic_field::add(&mut account.id, FarmingPrincipalKey {}, farming + amount);
    };
}
```

- [ ] **Step 3: Add return_from_farming function**

Add after `move_to_farming`:

```move
/// Return farming principal (merchant redeems from StableLayer).
public(package) fun return_from_farming(account: &mut MerchantAccount, amount: u64) {
    let farming = get_farming_principal_internal(&account.id);
    assert!(farming >= amount, EInsufficientPrincipal);
    *dynamic_field::borrow_mut(&mut account.id, FarmingPrincipalKey {}) = farming - amount;
}
```

- [ ] **Step 4: Add getter functions**

Add to the getters section:

```move
public fun get_farming_principal(account: &MerchantAccount): u64 {
    get_farming_principal_internal(&account.id)
}

fun get_farming_principal_internal(uid: &UID): u64 {
    if (dynamic_field::exists_(uid, FarmingPrincipalKey {})) {
        *dynamic_field::borrow(uid, FarmingPrincipalKey {})
    } else {
        0
    }
}
```

- [ ] **Step 5: Add test helpers**

Add to the `#[test_only]` section:

```move
#[test_only]
public fun move_to_farming_for_testing(account: &mut MerchantAccount, amount: u64) {
    move_to_farming(account, amount);
}

#[test_only]
public fun return_from_farming_for_testing(account: &mut MerchantAccount, amount: u64) {
    return_from_farming(account, amount);
}
```

- [ ] **Step 6: Build**

Run: `cd move/baleenpay && sui move build`
Expected: Build succeeds with 0 errors

- [ ] **Step 7: Run existing tests**

Run: `cd move/baleenpay && sui move test`
Expected: All existing tests still pass (142+)

- [ ] **Step 8: Commit**

```bash
git add move/baleenpay/sources/merchant.move
git commit -m "feat(move): add farming_principal dynamic field to MerchantAccount"
```

---

### Task 2: Move — events for farming and redeem

**Files:**
- Modify: `move/baleenpay/sources/events.move`

- [ ] **Step 1: Add FarmDeposited event struct and emitter**

Add before the `emit_vault_deposited` function:

```move
public struct FarmDeposited has copy, drop {
    merchant_id: ID,
    amount: u64,
    stablecoin_vault_id: ID,
}

public(package) fun emit_farm_deposited(
    merchant_id: ID,
    amount: u64,
    stablecoin_vault_id: ID,
) {
    event::emit(FarmDeposited { merchant_id, amount, stablecoin_vault_id });
}
```

- [ ] **Step 2: Add FarmRedeemed event struct and emitter**

Add after `emit_farm_deposited`:

```move
public struct FarmRedeemed has copy, drop {
    merchant_id: ID,
    amount: u64,
}

public(package) fun emit_farm_redeemed(
    merchant_id: ID,
    amount: u64,
) {
    event::emit(FarmRedeemed { merchant_id, amount });
}
```

- [ ] **Step 3: Build and test**

Run: `cd move/baleenpay && sui move build && sui move test`
Expected: Build succeeds, all tests pass

- [ ] **Step 4: Commit**

```bash
git add move/baleenpay/sources/events.move
git commit -m "feat(move): add FarmDeposited and FarmRedeemed events"
```

---

### Task 3: Move — StablecoinVault + keeper_deposit_to_farm + take_stablecoin

**Files:**
- Modify: `move/baleenpay/sources/router.move`

- [ ] **Step 1: Add StablecoinVault struct**

Add after the `YieldVault` struct:

```move
/// Holds minted Stablecoin receipts. Merchants take from here to redeem via StableLayer.
public struct StablecoinVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}
```

- [ ] **Step 2: Add create_stablecoin_vault**

Add after `create_yield_vault`:

```move
public fun create_stablecoin_vault<T>(_admin: &AdminCap, ctx: &mut TxContext) {
    transfer::share_object(StablecoinVault<T> {
        id: object::new(ctx),
        balance: balance::zero(),
    });
}
```

- [ ] **Step 3: Add keeper_deposit_to_farm**

Add after `create_stablecoin_vault`. This replaces the broken flow where keeper_withdraw doesn't update merchant accounting:

```move
/// Keeper deposits Stablecoin receipt into StablecoinVault and updates merchant accounting.
/// Called after mint in the same PTB. Moves idle_principal → farming_principal.
public fun keeper_deposit_to_farm<T>(
    _admin: &AdminCap,
    account: &mut MerchantAccount,
    stablecoin_vault: &mut StablecoinVault<T>,
    stablecoin_coin: Coin<T>,
    amount: u64,
) {
    assert!(amount > 0, EZeroAmount);
    stablecoin_vault.balance.join(stablecoin_coin.into_balance());
    merchant::move_to_farming(account, amount);
    events::emit_farm_deposited(
        object::id(account),
        amount,
        object::id(stablecoin_vault),
    );
}
```

- [ ] **Step 4: Add take_stablecoin for merchant redeem**

Add after `keeper_deposit_to_farm`:

```move
/// Merchant takes Stablecoin from StablecoinVault for burning via StableLayer.
/// Returns Coin<T> for PTB composition with request_burn → farm::pay → fulfill_burn.
public fun take_stablecoin<T>(
    cap: &merchant::MerchantCap,
    account: &mut MerchantAccount,
    stablecoin_vault: &mut StablecoinVault<T>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(amount > 0, EZeroAmount);
    assert!(merchant::get_merchant_id(cap) == object::id(account), ENotMerchantOwner);
    assert!(!merchant::get_paused(account), EPaused);
    merchant::return_from_farming(account, amount);
    events::emit_farm_redeemed(object::id(account), amount);
    stablecoin_vault.balance.split(amount).into_coin(ctx)
}
```

- [ ] **Step 5: Add missing error constants**

Add these error constants at the top of router.move (if not already present):

```move
#[error]
const ENotMerchantOwner: u64 = 26;
#[error]
const EPaused: u64 = 27;
```

- [ ] **Step 6: Add getter for StablecoinVault**

Add to the getters section:

```move
public fun stablecoin_vault_balance<T>(sv: &StablecoinVault<T>): u64 { sv.balance.value() }
```

- [ ] **Step 7: Add test helpers**

Add to the `#[test_only]` section:

```move
#[test_only]
public fun deposit_to_stablecoin_vault_for_testing<T>(sv: &mut StablecoinVault<T>, coin: Coin<T>) {
    sv.balance.join(coin.into_balance());
}
```

- [ ] **Step 8: Build and test**

Run: `cd move/baleenpay && sui move build && sui move test`
Expected: Build succeeds, all existing tests pass

- [ ] **Step 9: Commit**

```bash
git add move/baleenpay/sources/router.move
git commit -m "feat(move): add StablecoinVault, keeper_deposit_to_farm, take_stablecoin"
```

---

### Task 4: Move — farming and redeem tests

**Files:**
- Create: `move/baleenpay/tests/farming_tests.move`

- [ ] **Step 1: Write test file with setup helpers**

```move
#[test_only]
module baleenpay::farming_tests {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::router::{Self, Vault, StablecoinVault};

    public struct USDC has drop {}
    public struct STABLECOIN has drop {}

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

    #[test]
    fun test_move_to_farming() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        assert!(merchant::get_idle_principal(&account) == 1000);
        assert!(merchant::get_farming_principal(&account) == 0);

        merchant::move_to_farming_for_testing(&mut account, 600);
        assert!(merchant::get_idle_principal(&account) == 400);
        assert!(merchant::get_farming_principal(&account) == 600);

        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EInsufficientPrincipal
    fun test_move_to_farming_exceeds_idle() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 100);
        merchant::move_to_farming_for_testing(&mut account, 200); // abort

        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    fun test_return_from_farming() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        merchant::move_to_farming_for_testing(&mut account, 800);
        assert!(merchant::get_farming_principal(&account) == 800);

        merchant::return_from_farming_for_testing(&mut account, 300);
        assert!(merchant::get_farming_principal(&account) == 500);
        assert!(merchant::get_idle_principal(&account) == 200); // unchanged by return_from_farming

        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EInsufficientPrincipal
    fun test_return_from_farming_exceeds() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 500);
        merchant::move_to_farming_for_testing(&mut account, 500);
        merchant::return_from_farming_for_testing(&mut account, 600); // abort

        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    fun test_create_stablecoin_vault() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        assert!(router::stablecoin_vault_balance(&sv) == 0);
        test_scenario::return_shared(sv);
        scenario.end();
    }

    #[test]
    fun test_keeper_deposit_to_farm() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Simulate merchant received payment
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);

        // Admin creates stablecoin vault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Keeper deposits stablecoin (simulating post-mint)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm<STABLECOIN>(
            &admin_cap, &mut account, &mut sv, stablecoin, 1000,
        );
        assert!(merchant::get_idle_principal(&account) == 0);
        assert!(merchant::get_farming_principal(&account) == 1000);
        assert!(router::stablecoin_vault_balance(&sv) == 1000);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_take_stablecoin() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Setup: payment + farming
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm<STABLECOIN>(
            &admin_cap, &mut account, &mut sv, stablecoin, 1000,
        );
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Merchant takes stablecoin for redeem
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin<STABLECOIN>(
            &cap, &mut account, &mut sv, 600, scenario.ctx(),
        );
        assert!(coin.value() == 600);
        assert!(merchant::get_farming_principal(&account) == 400);
        assert!(router::stablecoin_vault_balance(&sv) == 400);
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EPaused
    fun test_take_stablecoin_paused() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm<STABLECOIN>(
            &admin_cap, &mut account, &mut sv, stablecoin, 1000,
        );
        // Pause merchant
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Merchant tries take — paused
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin<STABLECOIN>(
            &cap, &mut account, &mut sv, 500, scenario.ctx(),
        ); // abort
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure] // ENotMerchantOwner (wrong cap)
    fun test_take_stablecoin_wrong_cap() {
        let admin = @0xAD;
        let merchant_a = @0xBB;
        let merchant_b = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_a);
        register_merchant(&mut scenario, merchant_b);

        // Setup merchant_a with farming
        scenario.next_tx(merchant_a);
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(
            test_scenario::most_recent_id_shared<MerchantAccount>(),
        );
        merchant::add_payment_for_testing(&mut account_a, 1000);
        let account_a_id = object::id(&account_a);
        test_scenario::return_shared(account_a);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm<STABLECOIN>(
            &admin_cap, &mut account_a, &mut sv, stablecoin, 1000,
        );
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(admin_cap);

        // merchant_b tries to take from merchant_a's stablecoin
        scenario.next_tx(merchant_b);
        let cap_b = scenario.take_from_sender<MerchantCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin<STABLECOIN>(
            &cap_b, &mut account_a, &mut sv, 500, scenario.ctx(),
        ); // abort: wrong cap
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(cap_b);
        scenario.end();
    }
}
```

- [ ] **Step 2: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: All tests pass (existing + new farming tests)

- [ ] **Step 3: Commit**

```bash
git add move/baleenpay/tests/farming_tests.move
git commit -m "test(move): add farming accounting and take_stablecoin tests"
```

---

### Task 5: Move — merchant_withdraw tests

**Files:**
- Create: `move/baleenpay/tests/merchant_withdraw_tests.move`

- [ ] **Step 1: Write merchant_withdraw test file**

```move
#[test_only]
module baleenpay::merchant_withdraw_tests {
    use sui::test_scenario;
    use sui::coin::{Self, Coin};
    use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::router::{Self, Vault};

    public struct USDC has drop {}

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

    #[test]
    fun test_merchant_withdraw_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Create vault and fund it
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Simulate payment: add to vault + merchant idle
        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        merchant::add_payment_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);
        test_scenario::return_shared(vault);

        // Merchant withdraws 400
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        router::merchant_withdraw<USDC>(
            &cap, &mut account, &mut vault, 400, scenario.ctx(),
        );
        assert!(merchant::get_idle_principal(&account) == 600);
        assert!(router::vault_balance(&vault) == 600);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Verify merchant received USDC
        scenario.next_tx(merchant_addr);
        let usdc: Coin<USDC> = scenario.take_from_sender();
        assert!(usdc.value() == 400);
        scenario.return_to_sender(usdc);

        scenario.end();
    }

    #[test]
    #[expected_failure] // EInsufficientPrincipal
    fun test_merchant_withdraw_exceeds_idle() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let usdc = coin::mint_for_testing<USDC>(100, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        merchant::add_payment_for_testing(&mut account, 100);
        test_scenario::return_shared(account);
        test_scenario::return_shared(vault);

        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        router::merchant_withdraw<USDC>(
            &cap, &mut account, &mut vault, 200, scenario.ctx(),
        ); // abort
        test_scenario::return_shared(vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EPaused
    fun test_merchant_withdraw_paused() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        merchant::add_payment_for_testing(&mut account, 500);
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        router::merchant_withdraw<USDC>(
            &cap, &mut account, &mut vault, 300, scenario.ctx(),
        ); // abort: paused
        test_scenario::return_shared(vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
```

- [ ] **Step 2: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add move/baleenpay/tests/merchant_withdraw_tests.move
git commit -m "test(move): add merchant_withdraw tests (success, exceeds, paused)"
```

---

### Task 6: SDK — StableLayerClient.buildRedeemTx

**Files:**
- Modify: `packages/sdk/src/stablelayer/client.ts`
- Modify: `packages/sdk/test/stablelayer.test.ts`

- [ ] **Step 1: Add BuildRedeemOptions interface**

Add after `BuildClaimOptions` in `client.ts`:

```typescript
export interface BuildRedeemOptions {
  tx: Transaction
  stablecoinCoin: TransactionArgument
}
```

- [ ] **Step 2: Add buildRedeemTx method**

Add to `StableLayerClient` class after `buildClaimTx`:

```typescript
/**
 * Build redeem PTB commands: request_burn → farm::pay → fulfill_burn.
 * Returns the redeemed Coin<USDC>.
 *
 * request_burn<Stablecoin, USDC>(registry, stablecoinCoin) → Request
 * farm::pay<Stablecoin, USDC>(farmRegistry, clock, &mut request) → void
 * fulfill_burn<Stablecoin, USDC>(registry, request) → Coin<USDC>
 */
buildRedeemTx({ tx, stablecoinCoin }: BuildRedeemOptions): TransactionArgument {
  // Step 1: request_burn — burn Stablecoin, get Request hot-potato
  const request = tx.moveCall({
    target: `${this.packageId}::stable_layer::request_burn`,
    typeArguments: [this.stablecoinType, this.usdcType],
    arguments: [
      tx.object(this.registryId),
      stablecoinCoin,
    ],
  })

  // Step 2: farm::pay — Farm settles the debt via &mut Request
  tx.moveCall({
    target: `${this.farmPackageId}::farm::pay`,
    typeArguments: [this.stablecoinType, this.usdcType],
    arguments: [
      tx.object(this.farmRegistryId),
      tx.object('0x6'), // Clock
      request,
    ],
  })

  // Step 3: fulfill_burn — consume Request, get Coin<USDC> back
  const usdcCoin = tx.moveCall({
    target: `${this.packageId}::stable_layer::fulfill_burn`,
    typeArguments: [this.stablecoinType, this.usdcType],
    arguments: [
      tx.object(this.registryId),
      request,
    ],
  })

  return usdcCoin
}
```

- [ ] **Step 3: Write test for buildRedeemTx**

Add to `packages/sdk/test/stablelayer.test.ts`:

```typescript
describe('buildRedeemTx', () => {
  it('creates request_burn + farm::pay + fulfill_burn commands', () => {
    const client = new StableLayerClient(config)
    const tx = new Transaction()
    const mockStablecoin = tx.splitCoins(tx.gas, [100n])

    const usdcCoin = client.buildRedeemTx({ tx, stablecoinCoin: mockStablecoin })
    // splitCoins + request_burn + farm::pay + fulfill_burn = 4 commands
    expect(tx.getData().commands.length).toBe(4)
    expect(usdcCoin).toBeDefined()
  })
})
```

- [ ] **Step 4: Run SDK tests**

Run: `cd packages/sdk && pnpm test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add packages/sdk/src/stablelayer/client.ts packages/sdk/test/stablelayer.test.ts
git commit -m "feat(sdk): add StableLayerClient.buildRedeemTx (request_burn → farm::pay → fulfill_burn)"
```

---

### Task 7: SDK — types + buildMerchantWithdraw + buildMerchantRedeem

**Files:**
- Modify: `packages/sdk/src/types.ts`
- Modify: `packages/sdk/src/transactions/merchant.ts`
- Create: `packages/sdk/src/transactions/redeem.ts`
- Modify: `packages/sdk/src/transactions/index.ts`

- [ ] **Step 1: Add types**

Add to `BaleenPayConfig` in `types.ts`:

```typescript
stablecoinVaultId?: ObjectId
```

Add new interfaces at end of file (before closing):

```typescript
export interface MerchantBalance {
  idle: bigint
  farming: bigint
  yield: bigint
  total: bigint
}

export interface RedeemParams {
  merchantCapId: ObjectId
  amount: bigint
  coinType: string
  recipientAddress: string  // merchant wallet address to receive USDC
}

export interface WithdrawParams {
  merchantCapId: ObjectId
  amount: bigint
  coinType: string
}
```

- [ ] **Step 2: Add buildMerchantWithdraw to merchant.ts**

Add to `packages/sdk/src/transactions/merchant.ts`:

```typescript
import { resolveCoin, coinTypeArg } from '../coins/registry.js'
import type { BaleenPayConfig, WithdrawParams } from '../types.js'

export function buildMerchantWithdraw(
  config: BaleenPayConfig,
  params: WithdrawParams,
): Transaction {
  if (params.amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!config.vaultId) throw new Error('vaultId is required in config for merchant_withdraw')

  const resolved = resolveCoin(config.network, params.coinType)
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::merchant_withdraw`,
    typeArguments: [coinTypeArg(resolved.type)],
    arguments: [
      tx.object(params.merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.vaultId),
      tx.pure.u64(params.amount),
    ],
  })
  return tx
}
```

Note: keep existing imports (`Transaction`, `BaleenPayConfig`, `RegisterParams`) and add new ones alongside.

- [ ] **Step 3: Create redeem.ts**

Create `packages/sdk/src/transactions/redeem.ts`:

```typescript
import { Transaction } from '@mysten/sui/transactions'
import type { BaleenPayConfig, RedeemParams } from '../types.js'
import { StableLayerClient } from '../stablelayer/client.js'
import { STABLELAYER_CONFIG } from '../stablelayer/constants.js'
import { coinTypeArg } from '../coins/registry.js'

/**
 * Composite PTB: take_stablecoin → request_burn → farm::pay → fulfill_burn → transfer USDC.
 *
 * Single SDK call for merchant to redeem farming principal back to USDC.
 * Web2 devs call this; SDK handles all PTB complexity.
 */
export function buildMerchantRedeem(
  config: BaleenPayConfig,
  params: RedeemParams,
): Transaction {
  if (params.amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!config.stablecoinVaultId) {
    throw new Error('stablecoinVaultId is required in config for redeem')
  }

  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  // Step 1: Take Stablecoin from BaleenPay's StablecoinVault
  const stablecoinCoin = tx.moveCall({
    target: `${config.packageId}::router::take_stablecoin`,
    typeArguments: [slConfig.stablecoinType],
    arguments: [
      tx.object(params.merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.stablecoinVaultId),
      tx.pure.u64(params.amount),
    ],
  })

  // Steps 2-4: StableLayer burn flow (request_burn → farm::pay → fulfill_burn)
  const usdcCoin = stableClient.buildRedeemTx({ tx, stablecoinCoin })

  // Step 5: Transfer USDC to merchant wallet
  tx.transferObjects([usdcCoin], tx.pure.address(params.recipientAddress))

  return tx
}
```

- [ ] **Step 4: Update index.ts exports**

Add to `packages/sdk/src/transactions/index.ts`:

```typescript
export { buildMerchantWithdraw } from './merchant.js'
export { buildMerchantRedeem } from './redeem.js'
```

Verify existing exports are preserved (don't remove anything).

- [ ] **Step 5: Build SDK**

Run: `cd packages/sdk && pnpm build`
Expected: Build succeeds, no type errors

- [ ] **Step 6: Commit**

```bash
git add packages/sdk/src/types.ts packages/sdk/src/transactions/merchant.ts packages/sdk/src/transactions/redeem.ts packages/sdk/src/transactions/index.ts
git commit -m "feat(sdk): add buildMerchantWithdraw and buildMerchantRedeem transaction builders"
```

---

### Task 8: SDK — fix buildKeeperDeposit to use StablecoinVault

**Files:**
- Modify: `packages/sdk/src/transactions/keeper.ts`
- Modify: `packages/sdk/src/types.ts`

- [ ] **Step 1: Add stablecoinVaultId to KeeperParams**

In `types.ts`, add to `KeeperParams`:

```typescript
export interface KeeperParams {
  adminCapId: ObjectId
  vaultId: ObjectId
  yieldVaultId: ObjectId
  stablecoinVaultId?: ObjectId
}
```

- [ ] **Step 2: Update buildKeeperDeposit**

Replace the `buildKeeperDeposit` function in `keeper.ts`:

```typescript
/**
 * Composite: keeper_withdraw → stable_layer::mint → farm::receive → keeper_deposit_to_farm.
 *
 * Single PTB that atomically:
 * 1. Withdraws USDC from vault
 * 2. Mints Stablecoin via StableLayer (hot-potato Loan consumed by farm::receive)
 * 3. Deposits Stablecoin receipt into StablecoinVault
 * 4. Updates merchant accounting (idle_principal → farming_principal)
 */
export function buildKeeperDeposit(
  config: BaleenPayConfig,
  keeper: KeeperParams,
  amount: bigint,
  coinType: string,
  merchantId?: string,
): Transaction {
  if (amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!keeper.stablecoinVaultId) {
    throw new Error('stablecoinVaultId is required in keeper params for deposit')
  }

  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  // Step 1: Withdraw USDC from Vault
  const usdcCoin = tx.moveCall({
    target: `${config.packageId}::router::keeper_withdraw`,
    typeArguments: [coinTypeArg(coinType)],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(keeper.vaultId),
      tx.pure.u64(amount),
      tx.object('0x6'), // Clock
    ],
  })

  // Step 2: Mint Stablecoin + farm::receive (consumes Loan hot-potato)
  const stablecoin = stableClient.buildMintTx({ tx, usdcCoin })

  // Step 3: Deposit Stablecoin into StablecoinVault + update merchant accounting
  tx.moveCall({
    target: `${config.packageId}::router::keeper_deposit_to_farm`,
    typeArguments: [slConfig.stablecoinType],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(merchantId ?? config.merchantId),
      tx.object(keeper.stablecoinVaultId),
      stablecoin,
      tx.pure.u64(amount),
    ],
  })

  return tx
}
```

- [ ] **Step 3: Build SDK**

Run: `cd packages/sdk && pnpm build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add packages/sdk/src/transactions/keeper.ts packages/sdk/src/types.ts
git commit -m "fix(sdk): buildKeeperDeposit now stores Stablecoin in StablecoinVault + updates merchant accounting"
```

---

### Task 9: SDK — redeem and merchant-withdraw tests

**Files:**
- Create: `packages/sdk/test/redeem.test.ts`
- Create: `packages/sdk/test/merchant-withdraw.test.ts`

- [ ] **Step 1: Write redeem test**

Create `packages/sdk/test/redeem.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { Transaction } from '@mysten/sui/transactions'
import { buildMerchantRedeem } from '../src/transactions/redeem.js'
import type { BaleenPayConfig } from '../src/types.js'

const testConfig: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0x5eea0defa80c75a3f20588e01dba2f57a1e97ad154a487ab0c1979c34c8855e8',
  merchantId: '0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b',
  stablecoinVaultId: '0x1111111111111111111111111111111111111111111111111111111111111111',
}

describe('buildMerchantRedeem', () => {
  it('creates take_stablecoin + request_burn + farm::pay + fulfill_burn + transferObjects', () => {
    const tx = buildMerchantRedeem(testConfig, {
      merchantCapId: '0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f',
      amount: 1000000n,
      coinType: 'USDC',
      recipientAddress: '0xBB00000000000000000000000000000000000000000000000000000000000000',
    })
    const commands = tx.getData().commands
    // take_stablecoin + request_burn + farm::pay + fulfill_burn + transferObjects = 5
    expect(commands.length).toBe(5)
  })

  it('throws on zero amount', () => {
    expect(() =>
      buildMerchantRedeem(testConfig, {
        merchantCapId: '0xabc',
        amount: 0n,
        coinType: 'USDC',
        recipientAddress: '0xBB',
      }),
    ).toThrow('Amount must be greater than zero')
  })

  it('throws without stablecoinVaultId', () => {
    const noVaultConfig = { ...testConfig, stablecoinVaultId: undefined }
    expect(() =>
      buildMerchantRedeem(noVaultConfig, {
        merchantCapId: '0xabc',
        amount: 100n,
        coinType: 'USDC',
        recipientAddress: '0xBB',
      }),
    ).toThrow('stablecoinVaultId is required')
  })
})
```

- [ ] **Step 2: Write merchant-withdraw test**

Create `packages/sdk/test/merchant-withdraw.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { buildMerchantWithdraw } from '../src/transactions/merchant.js'
import type { BaleenPayConfig } from '../src/types.js'

const testConfig: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0x5eea0defa80c75a3f20588e01dba2f57a1e97ad154a487ab0c1979c34c8855e8',
  merchantId: '0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b',
  vaultId: '0x6c7f42f261ba273c360d88c7518b8d70968ff915d25e62466c60923543203dad',
}

describe('buildMerchantWithdraw', () => {
  it('creates merchant_withdraw moveCall', () => {
    const tx = buildMerchantWithdraw(testConfig, {
      merchantCapId: '0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f',
      amount: 500000n,
      coinType: 'USDC',
    })
    const commands = tx.getData().commands
    expect(commands.length).toBe(1)
  })

  it('throws on zero amount', () => {
    expect(() =>
      buildMerchantWithdraw(testConfig, {
        merchantCapId: '0xabc',
        amount: 0n,
        coinType: 'USDC',
      }),
    ).toThrow('Amount must be greater than zero')
  })

  it('throws without vaultId', () => {
    const noVaultConfig = { ...testConfig, vaultId: undefined }
    expect(() =>
      buildMerchantWithdraw(noVaultConfig, {
        merchantCapId: '0xabc',
        amount: 100n,
        coinType: 'USDC',
      }),
    ).toThrow('vaultId is required')
  })
})
```

- [ ] **Step 3: Run all SDK tests**

Run: `cd packages/sdk && pnpm test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add packages/sdk/test/redeem.test.ts packages/sdk/test/merchant-withdraw.test.ts
git commit -m "test(sdk): add redeem and merchant-withdraw transaction builder tests"
```

---

### Task 10: Final verification + type-check

**Files:** None (verification only)

- [ ] **Step 1: Move build + full test suite**

Run: `cd move/baleenpay && sui move build && sui move test`
Expected: Build succeeds (0 errors), all tests pass

- [ ] **Step 2: SDK build + type-check**

Run: `cd packages/sdk && pnpm build && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: SDK full test suite**

Run: `cd packages/sdk && pnpm test`
Expected: All tests pass

- [ ] **Step 4: Commit any remaining changes**

If there are any fixups from verification, commit them:

```bash
git add -A
git commit -m "chore: final verification fixups for merchant redeem feature"
```
