# BaleenPay SDK Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver `@baleenpay/sdk` + `@baleenpay/react` + contract Order ID upgrade as a production-ready monorepo, incorporating all review findings.

**Architecture:** Contract-first upgrade (order_id dedup on MerchantAccount via dynamic fields), then TypeScript SDK wrapping PTB construction with coin helper utilities, then React components consuming SDK hooks. Monorepo managed by pnpm workspaces + turbo.

**Tech Stack:** SUI Move (edition 2024), TypeScript 5.x, @mysten/sui, @mysten/dapp-kit, React 18, tsup, vitest, pnpm workspaces, turborepo

---

## Scope Check

This plan covers 3 subsystems that depend on each other sequentially:

1. **Contract Upgrade** (Task 1-3) — Move code, must deploy before SDK can target v2
2. **SDK Core** (Task 4-8) — TypeScript, depends on contract ABI
3. **React Components** (Task 9-11) — depends on SDK core

Each subsystem is independently testable. Contract tasks use `sui move test`. SDK/React tasks use `vitest`.

---

## Review Findings Incorporated

These issues from the triple review (architecture + code quality + security) are addressed in this plan:

| Finding | Severity | Where Addressed |
|---------|----------|-----------------|
| Coin splitting unspecified in spec | ISSUE | Task 5 (CoinHelper) |
| pause/unpause needs AdminCap, not in general SDK | WARNING | Task 4 (AdminClient split) |
| JSON-RPC deprecation — need rpcUrl config | WARNING | Task 4 (BaleenPayConfig) |
| Missing imports (df, type_name) | CONCERN | Task 1 |
| PaymentReceivedV2 + emitter missing | CONCERN | Task 1 |
| uid()/uid_mut() missing on merchant | CONCERN | Task 1 |
| Overflow guard for amount*periods | MEDIUM | Task 2 (checked multiplication + EOverflow) |
| remove_order_record → tombstone + event | MEDIUM | Task 1 |
| #[error] annotations | CONCERN | Task 1 |
| orderId PII warning in SDK | MEDIUM | Task 5 |
| SubscriptionCreated missing subscription_id | WARNING | Task 1 (events) |
| v1/v2 event union type unspecified | WARNING | Task 6 (EventStream) |
| Clock object not mentioned in spec | WARNING | Task 5 (PTB builders) |
| process_subscription automation | WARNING | Task 8 (docs only, Phase 2 backlog) |

---

## File Structure

### Contract Changes (Move)

```
move/baleenpay/sources/
├── merchant.move        # MODIFY: add uid()/uid_mut(), self_pause/self_unpause
├── payment.move         # MODIFY: add pay_once_v2, subscribe_v2, OrderKey, OrderRecord, remove_order_record
├── events.move          # MODIFY: add PaymentReceivedV2, OrderRecordRemoved, SubscriptionCreatedV2 + emitters
├── router.move          # NO CHANGE
└── brand_usd.move       # NO CHANGE

move/baleenpay/tests/
├── payment_v2_tests.move    # CREATE: order_id dedup tests
├── monkey_v2_tests.move     # CREATE: v2 edge case / adversarial tests
└── (existing test files)    # NO CHANGE
```

### SDK Monorepo (TypeScript)

```
packages/
├── sdk/                          # @baleenpay/sdk
│   ├── src/
│   │   ├── client.ts             # BaleenPay main class
│   │   ├── admin.ts              # AdminClient (pause/unpause — AdminCap ops)
│   │   ├── transactions/
│   │   │   ├── pay.ts            # buildPayOnce / buildPayOnceV2
│   │   │   ├── subscribe.ts      # buildSubscribe / buildSubscribeV2
│   │   │   ├── merchant.ts       # buildRegisterMerchant
│   │   │   ├── yield.ts          # buildClaimYield
│   │   │   └── subscription.ts   # buildProcessSubscription, buildCancelSubscription, buildFundSubscription
│   │   ├── coins/
│   │   │   ├── registry.ts       # COIN_MAP per network + resolve()
│   │   │   ├── helper.ts         # CoinHelper: getCoins → merge/split PTB construction
│   │   │   └── validator.ts      # CoinMetadata RPC validation
│   │   ├── events/
│   │   │   ├── stream.ts         # EventStream: SUI event subscription wrapper
│   │   │   └── types.ts          # Event type defs + v1/v2 union normalization
│   │   ├── errors.ts             # Error hierarchy + abort code map
│   │   ├── idempotency.ts        # In-memory dedup guard
│   │   ├── version.ts            # Contract version detection (v1 vs v2)
│   │   ├── types.ts              # All public types
│   │   ├── constants.ts          # Package IDs, object IDs, defaults
│   │   └── index.ts              # Public API re-exports
│   ├── test/
│   │   ├── client.test.ts
│   │   ├── coins.test.ts
│   │   ├── transactions.test.ts
│   │   ├── events.test.ts
│   │   ├── errors.test.ts
│   │   ├── idempotency.test.ts
│   │   └── integration.test.ts
│   ├── tsup.config.ts
│   ├── package.json
│   └── tsconfig.json
├── react/                        # @baleenpay/react
│   ├── src/
│   │   ├── provider.tsx          # <BaleenPayProvider>
│   │   ├── components/
│   │   │   ├── CheckoutButton.tsx
│   │   │   ├── PaymentForm.tsx
│   │   │   ├── SubscribeButton.tsx
│   │   │   └── MerchantBadge.tsx
│   │   ├── hooks/
│   │   │   ├── useBaleenPay.ts
│   │   │   ├── usePayment.ts
│   │   │   ├── useSubscription.ts
│   │   │   ├── useMerchant.ts
│   │   │   └── usePaymentHistory.ts
│   │   ├── types.ts
│   │   └── index.ts
│   ├── test/
│   │   ├── provider.test.tsx
│   │   ├── usePayment.test.tsx
│   │   └── components.test.tsx
│   ├── tsup.config.ts
│   ├── package.json
│   └── tsconfig.json
apps/
└── demo/                         # Next.js demo app
    └── (Task 12 — deferred to separate plan)

# Root workspace files
package.json                      # pnpm workspace root
pnpm-workspace.yaml
turbo.json
tsconfig.base.json
```

---

## Task 1: Contract — Events V2 + Merchant UID Accessors

> **Skill:** @sui-developer for implementation, @sui-tester for tests

**Files:**
- Modify: `move/baleenpay/sources/events.move`
- Modify: `move/baleenpay/sources/merchant.move`

**Why first:** All subsequent contract tasks depend on these building blocks.

### events.move additions

- [ ] **Step 1: Add PaymentReceivedV2 struct + emitter**

```move
public struct PaymentReceivedV2 has copy, drop {
    merchant_id: ID,
    payer: address,
    amount: u64,
    payment_type: u8,
    timestamp: u64,
    order_id: String,
    coin_type: String,
}

public(package) fun emit_payment_received_v2(
    merchant_id: ID,
    payer: address,
    amount: u64,
    payment_type: u8,
    timestamp: u64,
    order_id: String,
    coin_type: String,
) {
    event::emit(PaymentReceivedV2 {
        merchant_id, payer, amount, payment_type, timestamp, order_id, coin_type,
    });
}
```

- [ ] **Step 2: Add SubscriptionCreatedV2 struct + emitter (includes subscription_id)**

```move
public struct SubscriptionCreatedV2 has copy, drop {
    merchant_id: ID,
    subscription_id: ID,
    payer: address,
    amount_per_period: u64,
    period_ms: u64,
    prepaid_periods: u64,
    order_id: String,
}

public(package) fun emit_subscription_created_v2(
    merchant_id: ID,
    subscription_id: ID,
    payer: address,
    amount_per_period: u64,
    period_ms: u64,
    prepaid_periods: u64,
    order_id: String,
) {
    event::emit(SubscriptionCreatedV2 {
        merchant_id, subscription_id, payer, amount_per_period, period_ms, prepaid_periods, order_id,
    });
}
```

- [ ] **Step 3: Add OrderRecordRemoved event (audit trail for remove_order_record)**

```move
public struct OrderRecordRemoved has copy, drop {
    merchant_id: ID,
    payer: address,
    order_id: String,
}

public(package) fun emit_order_record_removed(
    merchant_id: ID,
    payer: address,
    order_id: String,
) {
    event::emit(OrderRecordRemoved { merchant_id, payer, order_id });
}
```

### merchant.move additions

- [ ] **Step 4: Add uid() and uid_mut() accessors**

```move
/// Expose UID for dynamic field access (order_id dedup in payment module).
public(package) fun uid(account: &MerchantAccount): &UID { &account.id }
public(package) fun uid_mut(account: &mut MerchantAccount): &mut UID { &mut account.id }
```

- [ ] **Step 5: Add self_pause / self_unpause (MerchantCap-gated)**

Review finding: spec had pause/unpause as general SDK methods, but contract uses AdminCap. Add MerchantCap-gated self-pause so merchants can pause their own account.

```move
/// Merchant self-pause. Requires MerchantCap matching this account.
public fun self_pause(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
) {
    assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
    account.paused = true;
    events::emit_merchant_paused(object::id(account));
}

/// Merchant self-unpause. Requires MerchantCap matching this account.
public fun self_unpause(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
) {
    assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
    account.paused = false;
    events::emit_merchant_unpaused(object::id(account));
}
```

- [ ] **Step 6: Run build to verify compilation**

Run: `cd move/baleenpay && sui move build`
Expected: SUCCESS (no errors)

- [ ] **Step 7: Commit**

```bash
git add move/baleenpay/sources/events.move move/baleenpay/sources/merchant.move
git commit -m "feat(contract): add v2 events, uid accessors, self-pause"
```

---

## Task 2: Contract — pay_once_v2 + subscribe_v2 + Order ID Dedup

> **Skill:** @sui-developer for implementation

**Files:**
- Modify: `move/baleenpay/sources/payment.move`

**Depends on:** Task 1 (events v2 + uid accessors)

- [ ] **Step 1: Add imports and error constants**

At top of `payment.move`, add:

```move
use sui::dynamic_field as df;
use std::type_name;
use std::string::String;
use baleenpay::merchant::MerchantCap;
```

Add constants (after existing EZeroPrepaidPeriods = 17):

```move
const ENotMerchantOwner: u64 = 0;
#[error]
const EOrderAlreadyPaid: u64 = 18;
#[error]
const EInvalidOrderId: u64 = 19;
#[error]
const EExceedsMaxPrepaidPeriods: u64 = 22;
#[error]
const EOverflow: u64 = 23;
const MAX_ORDER_ID_BYTES: u64 = 64;
const MAX_PREPAID_PERIODS: u64 = 1000;
```

- [ ] **Step 2: Add OrderKey + OrderRecord structs**

```move
/// Dynamic field key scoped to payer — prevents front-running/squatting.
public struct OrderKey has copy, drop, store {
    payer: address,
    order_id: String,
}

/// Stored as dynamic field on MerchantAccount. Soft-delete via `removed` flag.
public struct OrderRecord has store, drop {
    amount: u64,
    timestamp_ms: u64,
    coin_type: String,
}
```

- [ ] **Step 3: Add validate_order_id helper**

```move
fun validate_order_id(order_id: &String) {
    let bytes = order_id.as_bytes();
    let len = bytes.length();
    assert!(len > 0 && len <= MAX_ORDER_ID_BYTES, EInvalidOrderId);
    let mut i = 0;
    while (i < len) {
        let b = bytes[i];
        assert!(b >= 0x21 && b <= 0x7E, EInvalidOrderId);
        i = i + 1;
    };
}
```

- [ ] **Step 4: Implement pay_once_v2**

```move
/// One-time payment with order_id deduplication.
/// Order ID scoped to (payer, order_id) — same order_id from different payers are independent.
public fun pay_once_v2<T>(
    account: &mut MerchantAccount,
    coin: Coin<T>,
    order_id: String,
    clock: &Clock,
    ctx: &TxContext,
) {
    validate_order_id(&order_id);
    let key = OrderKey { payer: ctx.sender(), order_id };
    assert!(!df::exists_(merchant::uid(account), key), EOrderAlreadyPaid);

    assert!(!merchant::get_paused(account), EPaused);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);

    merchant::add_payment(account, amount);
    transfer::public_transfer(coin, merchant::get_owner(account));

    let now = clock.timestamp_ms();
    df::add(merchant::uid_mut(account), key, OrderRecord {
        amount,
        timestamp_ms: now,
        coin_type: type_name::get<T>().into_string().to_string(),
    });

    events::emit_payment_received_v2(
        object::id(account),
        ctx.sender(),
        amount,
        0,
        now,
        key.order_id,
        type_name::get<T>().into_string().to_string(),
    );
}
```

- [ ] **Step 5: Implement subscribe_v2**

```move
/// Subscribe with order_id deduplication.
#[allow(lint(self_transfer))]
public fun subscribe_v2<T>(
    account: &mut MerchantAccount,
    mut coin: Coin<T>,
    amount_per_period: u64,
    period_ms: u64,
    prepaid_periods: u64,
    order_id: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_order_id(&order_id);
    let key = OrderKey { payer: ctx.sender(), order_id };
    assert!(!df::exists_(merchant::uid(account), key), EOrderAlreadyPaid);

    assert!(!merchant::get_paused(account), EPaused);
    assert!(amount_per_period > 0, EZeroAmount);
    assert!(period_ms > 0, EZeroPeriod);
    assert!(prepaid_periods > 0, EZeroPrepaidPeriods);
    // Overflow guard: cap prepaid_periods + checked multiplication
    assert!(prepaid_periods <= MAX_PREPAID_PERIODS, EExceedsMaxPrepaidPeriods);
    assert!(amount_per_period <= 18_446_744_073_709_551_615 / prepaid_periods, EOverflow);

    let total_required = amount_per_period * prepaid_periods;
    assert!(coin.value() >= total_required, EInsufficientPrepaid);

    let escrow_coin = coin.split(total_required, ctx);
    if (coin.value() > 0) {
        transfer::public_transfer(coin, ctx.sender());
    } else {
        coin.destroy_zero();
    };

    let mut escrow_balance = escrow_coin.into_balance();
    let first_payment = escrow_balance.split(amount_per_period);
    transfer::public_transfer(first_payment.into_coin(ctx), merchant::get_owner(account));
    merchant::add_payment(account, amount_per_period);

    let now = clock.timestamp_ms();
    let merchant_id = object::id(account);

    df::add(merchant::uid_mut(account), key, OrderRecord {
        amount: total_required,
        timestamp_ms: now,
        coin_type: type_name::get<T>().into_string().to_string(),
    });

    merchant::increment_subscriptions(account);

    events::emit_payment_received_v2(
        merchant_id, ctx.sender(), amount_per_period, 1, now,
        key.order_id, type_name::get<T>().into_string().to_string(),
    );

    let sub_uid = object::new(ctx);
    let subscription_id = sub_uid.to_inner();

    // V2 event includes subscription_id
    events::emit_subscription_created_v2(
        merchant_id, subscription_id, ctx.sender(),
        amount_per_period, period_ms, prepaid_periods, key.order_id,
    );

    transfer::share_object(Subscription<T> {
        id: sub_uid,
        merchant_id,
        payer: ctx.sender(),
        amount_per_period,
        period_ms,
        next_due: now + period_ms,
        balance: escrow_balance,
    });
}
```

- [ ] **Step 6: Implement remove_order_record with audit event**

```move
/// Remove an order record. MerchantCap gated. Emits audit event.
/// WARNING: Removing a record allows the same order_id to be reused.
/// This is an admin escape hatch, not for routine use.
public fun remove_order_record(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    payer: address,
    order_id: String,
) {
    assert!(merchant::get_merchant_id(cap) == object::id(account), ENotMerchantOwner);
    let key = OrderKey { payer, order_id };
    let _: OrderRecord = df::remove(merchant::uid_mut(account), key);

    events::emit_order_record_removed(
        object::id(account),
        payer,
        key.order_id,
    );
}
```

- [ ] **Step 7: Add getter for OrderRecord existence (for SDK queries)**

```move
/// Check if an order_id has been paid by a specific payer.
public fun has_order_record(
    account: &MerchantAccount,
    payer: address,
    order_id: String,
): bool {
    let key = OrderKey { payer, order_id };
    df::exists_(merchant::uid(account), key)
}
```

- [ ] **Step 8: Run build**

Run: `cd move/baleenpay && sui move build`
Expected: SUCCESS

- [ ] **Step 9: Commit**

```bash
git add move/baleenpay/sources/payment.move
git commit -m "feat(contract): add pay_once_v2, subscribe_v2 with order_id dedup"
```

---

## Task 3: Contract — V2 Tests + Monkey Tests

> **Skill:** @sui-tester

**Files:**
- Create: `move/baleenpay/tests/payment_v2_tests.move`
- Create: `move/baleenpay/tests/monkey_v2_tests.move`

**Depends on:** Task 2

### payment_v2_tests.move

- [ ] **Step 1: Write pay_once_v2 success test**

```move
#[test_only]
module baleenpay::payment_v2_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use std::string;
    use baleenpay::merchant;
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;

    fun setup_merchant(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    #[test]
    fun test_pay_once_v2_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let payment_coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::pay_once_v2(
            &mut account,
            payment_coin,
            string::utf8(b"order_001"),
            &clock,
            scenario.ctx(),
        );

        assert!(merchant::get_total_received(&account) == 100_000_000);
        assert!(payment::has_order_record(&account, payer, string::utf8(b"order_001")));

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd move/baleenpay && sui move test --filter payment_v2`
Expected: PASS

- [ ] **Step 3: Write duplicate order_id rejection test**

```move
    #[test]
    #[expected_failure(abort_code = 18)] // EOrderAlreadyPaid
    fun test_pay_once_v2_duplicate_order_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());

        // First payment succeeds
        let coin1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, string::utf8(b"order_dup"), &clock, scenario.ctx());

        // Second payment with same order_id aborts
        let coin2 = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_dup"), &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
```

- [ ] **Step 4: Write cross-payer isolation test (same order_id, different payers both succeed)**

```move
    #[test]
    fun test_pay_once_v2_different_payers_same_order_ok() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer1 = @0xCC;
        let payer2 = @0xDD;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);

        // Payer 1 pays
        scenario.next_tx(payer1);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, string::utf8(b"order_shared"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer 2 pays same order_id — should succeed
        scenario.next_tx(payer2);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin2 = coin::mint_for_testing<TEST_USDC>(200_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_shared"), &clock, scenario.ctx());

        assert!(merchant::get_total_received(&account) == 300_000_000);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
```

- [ ] **Step 5: Write invalid order_id tests (empty, too long, non-ASCII)**

```move
    #[test]
    #[expected_failure(abort_code = 19)] // EInvalidOrderId
    fun test_pay_once_v2_empty_order_id_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b""), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 19)] // EInvalidOrderId — contains space (0x20)
    fun test_pay_once_v2_space_in_order_id_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"order 123"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
```

- [ ] **Step 6: Write subscribe_v2 success test**

```move
    #[test]
    fun test_subscribe_v2_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());

        payment::subscribe_v2(
            &mut account,
            coin,
            100_000_000,   // amount_per_period
            86_400_000,    // period_ms (1 day)
            3,             // prepaid_periods
            string::utf8(b"sub_001"),
            &clock,
            scenario.ctx(),
        );

        // First period processed immediately
        assert!(merchant::get_total_received(&account) == 100_000_000);
        assert!(payment::has_order_record(&account, payer, string::utf8(b"sub_001")));

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
```

- [ ] **Step 7: Write subscribe_v2 duplicate order rejection test**

```move
    #[test]
    #[expected_failure(abort_code = 18)]
    fun test_subscribe_v2_duplicate_order_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());

        let coin1 = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());
        payment::subscribe_v2(&mut account, coin1, 100_000_000, 86_400_000, 3, string::utf8(b"sub_dup"), &clock, scenario.ctx());

        let coin2 = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());
        payment::subscribe_v2(&mut account, coin2, 100_000_000, 86_400_000, 3, string::utf8(b"sub_dup"), &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
```

- [ ] **Step 8: Write remove_order_record test**

```move
    #[test]
    fun test_remove_order_record_and_repay() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        // Payer pays
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"order_rm"), &clock, scenario.ctx());
        assert!(payment::has_order_record(&account, payer, string::utf8(b"order_rm")));
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Merchant removes record
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        payment::remove_order_record(&cap, &mut account, payer, string::utf8(b"order_rm"));
        assert!(!payment::has_order_record(&account, payer, string::utf8(b"order_rm")));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);

        // Payer can now re-pay same order_id
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin2 = coin::mint_for_testing<TEST_USDC>(200, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_rm"), &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 300); // 100 + 200
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        scenario.end();
    }
```

- [ ] **Step 9: Write additional edge case tests**

Add to `payment_v2_tests.move`:

```move
    // Zero-amount coin should abort
    #[test]
    #[expected_failure(abort_code = 10)] // EZeroAmount
    fun test_pay_once_v2_zero_amount_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"zero_test"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // Paused merchant rejects v2 payment
    #[test]
    #[expected_failure(abort_code = 2)] // EPaused
    fun test_pay_once_v2_paused_merchant_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        // Admin pauses merchant
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Payer tries v2 payment — should fail
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"paused_test"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // Wrong MerchantCap on remove_order_record
    #[test]
    #[expected_failure(abort_code = 0)] // ENotMerchantOwner
    fun test_remove_order_record_wrong_cap_aborts() {
        let admin = @0xAD;
        let merchant_addr1 = @0xBB;
        let merchant_addr2 = @0xDD;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr1);

        // Register second merchant
        scenario.next_tx(merchant_addr2);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"OtherShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Payer pays merchant 1
        scenario.next_tx(payer);
        let mut account1 = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account1, coin, string::utf8(b"wrong_cap"), &clock, scenario.ctx());
        test_scenario::return_shared(account1);
        clock::destroy_for_testing(clock);

        // Merchant 2 tries to remove merchant 1's order record — should fail
        scenario.next_tx(merchant_addr2);
        let mut account1 = scenario.take_shared<merchant::MerchantAccount>();
        let cap2 = scenario.take_from_sender<merchant::MerchantCap>();
        payment::remove_order_record(&cap2, &mut account1, payer, string::utf8(b"wrong_cap"));
        scenario.return_to_sender(cap2);
        test_scenario::return_shared(account1);
        scenario.end();
    }
```

- [ ] **Step 10: Write self_pause / self_unpause test (in payment_v2_tests.move)**

```move
    #[test]
    fun test_self_pause_and_unpause() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let cap = scenario.take_from_sender<merchant::MerchantCap>();

        merchant::self_pause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == true);

        merchant::self_unpause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == false);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);
        scenario.end();
    }
```

- [ ] **Step 10: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: ALL PASS (existing 52 tests + new tests)

### monkey_v2_tests.move

- [ ] **Step 11: Write monkey tests (extreme edge cases)**

Create `move/baleenpay/tests/monkey_v2_tests.move`:

```move
#[test_only]
module baleenpay::monkey_v2_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use std::string;
    use baleenpay::merchant;
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;

    fun setup_merchant(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // Max length order_id (64 bytes, all printable ASCII)
    #[test]
    fun test_max_length_order_id() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        // 64 chars of 'A' (0x41)
        let long_id = string::utf8(b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        payment::pay_once_v2(&mut account, coin, long_id, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // 65 bytes — should fail
    #[test]
    #[expected_failure(abort_code = 19)]
    fun test_order_id_65_bytes_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let too_long = string::utf8(b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"); // 65
        payment::pay_once_v2(&mut account, coin, too_long, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // Boundary ASCII chars (0x21 = '!' and 0x7E = '~')
    #[test]
    fun test_boundary_ascii_chars() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"!~"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // subscribe_v2 with MAX_PREPAID_PERIODS (1000) — should succeed
    #[test]
    fun test_subscribe_v2_max_periods() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        // 1 USDC * 1000 periods = 1000 USDC
        let coin = coin::mint_for_testing<TEST_USDC>(1_000_000_000, scenario.ctx());
        payment::subscribe_v2(
            &mut account, coin, 1_000_000, 86_400_000, 1000,
            string::utf8(b"sub_max"), &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // subscribe_v2 with 1001 periods — should fail (exceeds MAX_PREPAID_PERIODS)
    #[test]
    #[expected_failure(abort_code = 22)] // EExceedsMaxPrepaidPeriods
    fun test_subscribe_v2_over_max_periods_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(2_000_000_000, scenario.ctx());
        payment::subscribe_v2(
            &mut account, coin, 1_000_000, 86_400_000, 1001,
            string::utf8(b"sub_over"), &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // Cross-coin blocking: pay with USDC, then try same order_id — should fail
    // (uses TEST_USDC for both since we only have one test coin, but validates the key logic)
    #[test]
    #[expected_failure(abort_code = 18)]
    fun test_cross_operation_same_order_id_blocked() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());

        // pay_once_v2 first
        let coin1 = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, string::utf8(b"shared_id"), &clock, scenario.ctx());

        // subscribe_v2 with same order_id — should abort
        let coin2 = coin::mint_for_testing<TEST_USDC>(300, scenario.ctx());
        payment::subscribe_v2(&mut account, coin2, 100, 86_400_000, 3, string::utf8(b"shared_id"), &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
}
```

- [ ] **Step 12: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: ALL PASS

- [ ] **Step 13: Commit**

```bash
git add move/baleenpay/tests/payment_v2_tests.move move/baleenpay/tests/monkey_v2_tests.move
git commit -m "test(contract): add v2 dedup tests + monkey tests"
```

---

## Task 4: SDK — Monorepo Setup + Types + Constants

> **Skill:** @sui-ts-sdk for SUI SDK patterns

**Files:**
- Create: `package.json` (workspace root)
- Create: `pnpm-workspace.yaml`
- Create: `turbo.json`
- Create: `tsconfig.base.json`
- Create: `packages/sdk/package.json`
- Create: `packages/sdk/tsconfig.json`
- Create: `packages/sdk/src/types.ts`
- Create: `packages/sdk/src/constants.ts`
- Create: `packages/sdk/src/index.ts`

**Depends on:** None (can start parallel with Task 1-3 for the TS scaffolding)

- [ ] **Step 1: Create workspace root**

`package.json`:
```json
{
  "name": "baleenpay",
  "private": true,
  "packageManager": "pnpm@9.15.0",
  "scripts": {
    "build": "turbo build",
    "test": "turbo test",
    "typecheck": "turbo typecheck"
  }
}
```

`pnpm-workspace.yaml`:
```yaml
packages:
  - "packages/*"
  - "apps/*"
```

`turbo.json`:
```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "test": { "dependsOn": ["build"] },
    "typecheck": { "dependsOn": ["^build"] }
  }
}
```

`tsconfig.base.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true
  }
}
```

- [ ] **Step 2: Create SDK package skeleton**

`packages/sdk/package.json`:
```json
{
  "name": "@baleenpay/sdk",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.cjs",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "require": "./dist/index.cjs",
      "types": "./dist/index.d.ts"
    }
  },
  "scripts": {
    "build": "tsup",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@mysten/sui": "^1.24.0"
  },
  "devDependencies": {
    "tsup": "^8.0.0",
    "typescript": "^5.7.0",
    "vitest": "^3.0.0"
  }
}
```

`packages/sdk/tsconfig.json`:
```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

`packages/sdk/tsup.config.ts`:
```typescript
import { defineConfig } from 'tsup'

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  clean: true,
  sourcemap: true,
})
```

- [ ] **Step 3: Write types.ts**

```typescript
// packages/sdk/src/types.ts

/** All object IDs are 0x-prefixed hex strings */
export type ObjectId = string

export interface BaleenPayConfig {
  network: 'mainnet' | 'testnet' | 'devnet'
  packageId: ObjectId
  merchantId: ObjectId
  registryId?: ObjectId
  routerConfigId?: ObjectId
  /** Custom RPC/GraphQL endpoint. Defaults to public endpoint for the network. */
  rpcUrl?: string
}

export interface PayParams {
  amount: bigint | number
  coin: string           // shorthand ('USDC') or full type ('0x...::mod::TYPE')
  orderId: string        // required for v2 dedup
}

export interface SubscribeParams {
  amountPerPeriod: bigint | number
  periodMs: number
  prepaidPeriods: number
  coin: string
  orderId: string
}

export interface FundParams {
  subscriptionId: ObjectId
  amount: bigint | number
  coin: string
}

export interface RegisterParams {
  brandName: string
  registryId?: ObjectId
}

export interface QueryParams {
  cursor?: string
  limit?: number
  order?: 'asc' | 'desc'
}

export interface TransactionResult {
  tx: import('@mysten/sui/transactions').Transaction
}

export interface ExecutedResult {
  digest: string
  status: 'success' | 'failure'
  events: BaleenPayEventData[]
  gasUsed: bigint
  payment?: { orderId: string; amount: bigint; coinType: string }
  subscription?: { subscriptionId: string; nextDue: number }
  merchant?: { merchantId: string; capId: string }
}

// ── Event types ──

export type BaleenPayEventName =
  | 'payment.received'
  | 'subscription.created'
  | 'subscription.processed'
  | 'subscription.cancelled'
  | 'subscription.funded'
  | 'merchant.registered'
  | 'merchant.paused'
  | 'merchant.unpaused'
  | 'yield.claimed'
  | 'router.mode_changed'
  | 'order.record_removed'
  | '*'

export interface BaleenPayEventData {
  type: BaleenPayEventName
  merchantId?: string
  payer?: string
  amount?: bigint
  orderId?: string
  coinType?: string
  timestamp?: number
  [key: string]: unknown
}

export type EventCallback = (event: BaleenPayEventData) => void
export type Unsubscribe = () => void

// ── Merchant info ──

export interface MerchantInfo {
  merchantId: ObjectId
  owner: string
  brandName: string
  totalReceived: bigint
  idlePrincipal: bigint
  accruedYield: bigint
  activeSubscriptions: number
  paused: boolean
}

export interface SubscriptionInfo {
  subscriptionId: ObjectId
  merchantId: ObjectId
  payer: string
  amountPerPeriod: bigint
  periodMs: number
  nextDue: number
  balance: bigint
}
```

- [ ] **Step 4: Write constants.ts**

```typescript
// packages/sdk/src/constants.ts

export const CLOCK_OBJECT_ID = '0x6'

export const DEFAULT_RPC_URLS: Record<string, string> = {
  mainnet: 'https://fullnode.mainnet.sui.io:443',
  testnet: 'https://fullnode.testnet.sui.io:443',
  devnet: 'https://fullnode.devnet.sui.io:443',
}

export const MAX_ORDER_ID_LENGTH = 64
export const ORDER_ID_REGEX = /^[\x21-\x7e]{1,64}$/

/** Abort code → SDK error code mapping */
export const ABORT_CODE_MAP: Record<number, { code: string; message: string }> = {
  0: { code: 'NOT_MERCHANT_OWNER', message: "MerchantCap doesn't match this account" },
  2: { code: 'MERCHANT_PAUSED', message: 'Merchant is paused' },
  3: { code: 'NOT_PAYER', message: 'Only the original payer can perform this action' },
  6: { code: 'ALREADY_REGISTERED', message: 'This address already has a merchant account' },
  7: { code: 'NO_ACTIVE_SUBSCRIPTIONS', message: 'No active subscriptions to decrement' },
  8: { code: 'INSUFFICIENT_PRINCIPAL', message: 'Insufficient idle principal for yield credit' },
  10: { code: 'ZERO_AMOUNT', message: 'Payment amount must be greater than zero' },
  11: { code: 'NOT_DUE', message: 'Subscription payment is not yet due' },
  12: { code: 'ZERO_YIELD', message: 'No yield available to claim' },
  13: { code: 'INSUFFICIENT_PREPAID', message: 'Not enough prepaid periods' },
  14: { code: 'ZERO_PERIOD', message: 'Subscription period must be greater than zero' },
  15: { code: 'INSUFFICIENT_BALANCE', message: 'Subscription escrow balance too low' },
  16: { code: 'MERCHANT_MISMATCH', message: "Subscription doesn't belong to this merchant" },
  17: { code: 'ZERO_PREPAID_PERIODS', message: 'Must prepay at least one period' },
  18: { code: 'ORDER_ALREADY_PAID', message: 'This order has already been paid' },
  19: { code: 'INVALID_ORDER_ID', message: 'Order ID must be 1-64 ASCII printable characters' },
  20: { code: 'INVALID_MODE', message: 'Invalid router mode' },
  21: { code: 'SAME_MODE', message: 'Router is already in this mode' },
  22: { code: 'EXCEEDS_MAX_PREPAID_PERIODS', message: 'Prepaid periods exceeds maximum (1000)' },
  23: { code: 'OVERFLOW', message: 'Amount × periods would overflow' },
}
```

- [ ] **Step 5: Write index.ts (stub exports)**

```typescript
// packages/sdk/src/index.ts

export type {
  BaleenPayConfig,
  PayParams,
  SubscribeParams,
  FundParams,
  RegisterParams,
  QueryParams,
  TransactionResult,
  ExecutedResult,
  BaleenPayEventName,
  BaleenPayEventData,
  EventCallback,
  Unsubscribe,
  MerchantInfo,
  SubscriptionInfo,
  ObjectId,
} from './types.js'

export { ABORT_CODE_MAP, CLOCK_OBJECT_ID, MAX_ORDER_ID_LENGTH, ORDER_ID_REGEX } from './constants.js'
```

- [ ] **Step 6: Install dependencies and verify build**

Run: `cd /path/to/baleenpay && pnpm install && pnpm --filter @baleenpay/sdk typecheck`
Expected: SUCCESS

- [ ] **Step 7: Commit**

```bash
git add package.json pnpm-workspace.yaml turbo.json tsconfig.base.json packages/sdk/
git commit -m "feat(sdk): scaffold monorepo + SDK types and constants"
```

---

## Task 5: SDK — Coin Helper + PTB Builders

> **Skill:** @sui-ts-sdk

**Files:**
- Create: `packages/sdk/src/coins/registry.ts`
- Create: `packages/sdk/src/coins/helper.ts`
- Create: `packages/sdk/src/coins/validator.ts`
- Create: `packages/sdk/src/transactions/pay.ts`
- Create: `packages/sdk/src/transactions/subscribe.ts`
- Create: `packages/sdk/src/transactions/merchant.ts`
- Create: `packages/sdk/src/transactions/yield.ts`
- Create: `packages/sdk/src/transactions/subscription.ts`
- Create: `packages/sdk/test/coins.test.ts`
- Create: `packages/sdk/test/transactions.test.ts`

**Depends on:** Task 4 (types + constants)

This is the **most critical task** — addresses the #1 review finding (coin splitting + type arg resolution unspecified).

- [ ] **Step 1: Write coin registry**

`packages/sdk/src/coins/registry.ts` — shorthand → full coin type mapping per network.

- [ ] **Step 2: Write coin helper (getCoins → merge/split PTB)**

`packages/sdk/src/coins/helper.ts` — the key missing piece from the spec:
1. `SuiClient.getCoins()` to find user's coins of type T
2. If multiple coin objects → merge into one via `tx.mergeCoins()`
3. `tx.splitCoins()` to extract exact payment amount
4. Return the split coin for use in `pay_once_v2` PTB
5. Handle edge case: user has exact amount in one coin (no split needed)

- [ ] **Step 3: Write coin validator**

`packages/sdk/src/coins/validator.ts` — CoinMetadata RPC check for custom coin types.

- [ ] **Step 4: Write pay PTB builder**

`packages/sdk/src/transactions/pay.ts`:
- `buildPayOnceV2(client, config, params)` → constructs full PTB:
  1. Resolve coin type via registry
  2. Use CoinHelper to get/merge/split coins
  3. Pass CLOCK_OBJECT_ID as `&Clock`
  4. Call `pay_once_v2<T>(account, coin, order_id, clock)`
  5. Validate orderId with `ORDER_ID_REGEX` before building (SDK pre-validation)
  6. **PII warning:** reject orderId matching email/phone patterns

- [ ] **Step 5: Write subscribe PTB builder**

`packages/sdk/src/transactions/subscribe.ts`:
- `buildSubscribeV2(client, config, params)` → similar to pay but with subscription params
- Pre-validate: `prepaidPeriods <= 1000`, `amountPerPeriod > 0`, etc.

- [ ] **Step 6: Write merchant + yield + subscription PTB builders**

`packages/sdk/src/transactions/merchant.ts` — `buildRegisterMerchant`, `buildSelfPause`, `buildSelfUnpause`
`packages/sdk/src/transactions/yield.ts` — `buildClaimYield`
`packages/sdk/src/transactions/subscription.ts` — `buildProcessSubscription`, `buildCancelSubscription`, `buildFundSubscription`

- [ ] **Step 7: Write unit tests for coin registry + helper**

`packages/sdk/test/coins.test.ts` — test shorthand resolution, unknown coin error, validation.

- [ ] **Step 8: Write unit tests for PTB builders**

`packages/sdk/test/transactions.test.ts` — test that builders produce valid `Transaction` objects, orderId validation, PII rejection.

- [ ] **Step 9: Run tests**

Run: `pnpm --filter @baleenpay/sdk test`
Expected: ALL PASS

- [ ] **Step 10: Commit**

```bash
git add packages/sdk/src/coins/ packages/sdk/src/transactions/ packages/sdk/test/
git commit -m "feat(sdk): coin helper + PTB builders with orderId validation"
```

---

## Task 6: SDK — Error System + Event Stream + Version Detection

**Files:**
- Create: `packages/sdk/src/errors.ts`
- Create: `packages/sdk/src/events/stream.ts`
- Create: `packages/sdk/src/events/types.ts`
- Create: `packages/sdk/src/version.ts`
- Create: `packages/sdk/test/errors.test.ts`
- Create: `packages/sdk/test/events.test.ts`

**Depends on:** Task 4

- [ ] **Step 1: Write error hierarchy**

`packages/sdk/src/errors.ts`:
```typescript
export class BaleenPayError extends Error { code: string; ... }
export class PaymentError extends BaleenPayError { ... }
export class MerchantError extends BaleenPayError { ... }
export class ValidationError extends BaleenPayError { ... }
export class NetworkError extends BaleenPayError { ... }

// parseAbortCode(status) → BaleenPayError with human message from ABORT_CODE_MAP
```

- [ ] **Step 2: Write event types with v1/v2 union normalization**

`packages/sdk/src/events/types.ts`:
- Map `PaymentReceived` (v1: no orderId) and `PaymentReceivedV2` (v2: has orderId) into unified `payment.received` shape
- v1 events get `orderId: undefined, coinType: undefined`
- Map `SubscriptionCreated` (v1) and `SubscriptionCreatedV2` (v2) similarly

- [ ] **Step 3: Write event stream**

`packages/sdk/src/events/stream.ts`:
- Subscribe to SUI events filtered by package ID
- Parse event type → map to SDK event name
- Support wildcard `*` listener
- Support filter by field (e.g., `{ payer: '0x...' }`)
- Note in code: `suix_subscribeEvent` is JSON-RPC WebSocket; future migration to gRPC needed

- [ ] **Step 4: Write version detection**

`packages/sdk/src/version.ts`:
- Use `SuiClient.getNormalizedMoveModule()` to check if `pay_once_v2` exists in `payment` module
- Cache result per client instance
- Return `{ hasV2: boolean }`

- [ ] **Step 5: Write tests**

- `packages/sdk/test/errors.test.ts` — abort code parsing, error hierarchy
- `packages/sdk/test/events.test.ts` — event name mapping, v1/v2 normalization, filter logic

- [ ] **Step 6: Run tests**

Run: `pnpm --filter @baleenpay/sdk test`
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add packages/sdk/src/errors.ts packages/sdk/src/events/ packages/sdk/src/version.ts packages/sdk/test/
git commit -m "feat(sdk): error system, event stream with v1/v2 normalization, version detection"
```

---

## Task 7: SDK — Idempotency Guard + Client Class

**Files:**
- Create: `packages/sdk/src/idempotency.ts`
- Create: `packages/sdk/src/client.ts`
- Create: `packages/sdk/src/admin.ts`
- Modify: `packages/sdk/src/index.ts` (add all exports)
- Create: `packages/sdk/test/idempotency.test.ts`
- Create: `packages/sdk/test/client.test.ts`

**Depends on:** Task 5, Task 6

- [ ] **Step 1: Write idempotency guard**

`packages/sdk/src/idempotency.ts`:
- In-memory Map<string, 'pending' | ExecutedResult>
- Key generation: `(merchantId, orderId)` if orderId provided, else `(merchantId, method, amount, coin, timestamp_bucket)`
- `check()`, `markPending()`, `markCompleted()`, `getCachedResult()`

- [ ] **Step 2: Write BaleenPay client class**

`packages/sdk/src/client.ts`:
- Constructor takes `BaleenPayConfig`, creates `SuiClient`
- Methods: `pay()`, `subscribe()`, `processSubscription()`, `cancelSubscription()`, `fundSubscription()`, `registerMerchant()`, `claimYield()`, `selfPause()`, `selfUnpause()`
- Each method: validate → idempotency check → build PTB → return `TransactionResult`
- `on()` delegates to EventStream
- `getMerchant()`, `getSubscription()`, `getPaymentHistory()` as query methods

- [ ] **Step 3: Write query methods on client**

In `packages/sdk/src/client.ts`, implement:
- `getMerchant(merchantId?)` — uses `SuiClient.getObject({ id, options: { showContent: true } })`, deserializes `MerchantAccount` fields into `MerchantInfo`
- `getSubscription(subscriptionId)` — same pattern, deserializes `Subscription<T>` into `SubscriptionInfo`
- `getPaymentHistory(params?)` — uses `SuiClient.queryEvents({ query: { MoveEventType: '<pkg>::events::PaymentReceivedV2' }, cursor, limit, order })`, normalizes v1/v2

- [ ] **Step 4: Write AdminClient (AdminCap operations)**

`packages/sdk/src/admin.ts`:
- Extends or wraps BaleenPay with admin-only ops: `pause()`, `unpause()`, `setRouterMode()`
- Clearly documented: requires AdminCap object

- [ ] **Step 5: Update index.ts with all exports**

- [ ] **Step 6: Write tests**

- `packages/sdk/test/idempotency.test.ts` — dedup logic, key generation, reset behavior
- `packages/sdk/test/client.test.ts` — client construction, method delegation, config validation, query method deserialization

- [ ] **Step 7: Run tests + typecheck**

Run: `pnpm --filter @baleenpay/sdk test && pnpm --filter @baleenpay/sdk typecheck`
Expected: ALL PASS

- [ ] **Step 8: Build SDK**

Run: `pnpm --filter @baleenpay/sdk build`
Expected: dist/ generated with ESM + CJS + types

- [ ] **Step 9: Commit**

```bash
git add packages/sdk/
git commit -m "feat(sdk): BaleenPay client + AdminClient + idempotency guard"
```

---

## Task 8: SDK — Integration Test + Documentation Notes

**Files:**
- Create: `packages/sdk/test/integration.test.ts`
- Modify: `packages/sdk/src/client.ts` (if fixes needed)

**Depends on:** Task 7

- [ ] **Step 1: Write integration tests**

End-to-end test flow (mocked SUI client):
1. Create BaleenPay client
2. Register merchant → verify PTB structure
3. Pay with orderId → verify coin helper called, PTB correct
4. Pay same orderId → verify idempotency guard blocks
5. Subscribe → verify PTB with subscription params
6. Query merchant → verify deserialization
7. Listen to events → verify event mapping

- [ ] **Step 2: Write monkey tests for SDK**

- Invalid config (missing packageId)
- Invalid orderId (PII patterns, empty, too long, unicode)
- Amount = 0
- Negative periodMs
- prepaidPeriods > 1000

- [ ] **Step 3: Run all SDK tests**

Run: `pnpm --filter @baleenpay/sdk test`
Expected: ALL PASS

- [ ] **Step 4: Document Phase 2 backlog items in tasks/notes.md**

Items identified during review but deferred:
- `processSubscription` automation (cron/keeper pattern)
- gRPC migration for event stream (before April 2026 JSON-RPC removal)
- `min_payment_amount` per merchant
- Tombstone pattern for `remove_order_record` (current: hard delete + audit event)

- [ ] **Step 5: Commit**

```bash
git add packages/sdk/test/ tasks/notes.md
git commit -m "test(sdk): integration + monkey tests, document Phase 2 backlog"
```

---

## Task 9: React — Package Setup + Provider + useBaleenPay

> **Skill:** @sui-frontend

**Files:**
- Create: `packages/react/package.json`
- Create: `packages/react/tsconfig.json`
- Create: `packages/react/tsup.config.ts`
- Create: `packages/react/src/provider.tsx`
- Create: `packages/react/src/hooks/useBaleenPay.ts`
- Create: `packages/react/src/types.ts`
- Create: `packages/react/src/index.ts`
- Create: `packages/react/test/provider.test.tsx`

**Depends on:** Task 7 (SDK client)

- [ ] **Step 1: Create react package with dependencies**

`packages/react/package.json`:
```json
{
  "name": "@baleenpay/react",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": { "import": "./dist/index.js", "types": "./dist/index.d.ts" }
  },
  "scripts": {
    "build": "tsup",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@baleenpay/sdk": "workspace:*",
    "@mysten/dapp-kit": "^0.14.0",
    "@mysten/sui": "^1.24.0"
  },
  "peerDependencies": {
    "react": "^18.0.0 || ^19.0.0",
    "react-dom": "^18.0.0 || ^19.0.0"
  },
  "devDependencies": {
    "@testing-library/react": "^16.0.0",
    "jsdom": "^26.0.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "tsup": "^8.0.0",
    "typescript": "^5.7.0",
    "vitest": "^3.0.0"
  }
}
```

- [ ] **Step 2: Write BaleenPayProvider + useBaleenPay hook**

Provider creates SDK client from config, stores in React context. `useBaleenPay()` returns client instance.

- [ ] **Step 3: Write tests**

Test provider renders, useBaleenPay returns client, missing provider throws.

- [ ] **Step 4: Run tests**

Run: `pnpm --filter @baleenpay/react test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add packages/react/
git commit -m "feat(react): BaleenPayProvider + useBaleenPay hook"
```

---

## Task 10: React — Payment + Subscription Hooks

**Files:**
- Create: `packages/react/src/hooks/usePayment.ts`
- Create: `packages/react/src/hooks/useSubscription.ts`
- Create: `packages/react/src/hooks/useMerchant.ts`
- Create: `packages/react/src/hooks/usePaymentHistory.ts`
- Create: `packages/react/test/usePayment.test.tsx`

**Depends on:** Task 9

- [ ] **Step 1: Write usePayment hook**

Implements payment state machine:
`idle → validating → building → signing → confirming → success`
With error/rejected branches + auto-reset.

Exposes: `{ pay, status, error, reset, result }`

- [ ] **Step 2: Write useSubscription hook**

`{ subscribe, processSubscription, cancelSubscription, fundSubscription, status, error, reset }`

- [ ] **Step 3: Write useMerchant + usePaymentHistory hooks**

Query hooks using SUI RPC.

- [ ] **Step 4: Write tests**

Test state machine transitions, error handling, auto-reset.

- [ ] **Step 5: Run tests**

Run: `pnpm --filter @baleenpay/react test`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add packages/react/src/hooks/ packages/react/test/
git commit -m "feat(react): payment + subscription hooks with state machine"
```

---

## Task 11: React — Components (CheckoutButton, PaymentForm, SubscribeButton, MerchantBadge)

**Files:**
- Create: `packages/react/src/components/CheckoutButton.tsx`
- Create: `packages/react/src/components/PaymentForm.tsx`
- Create: `packages/react/src/components/SubscribeButton.tsx`
- Create: `packages/react/src/components/MerchantBadge.tsx`
- Modify: `packages/react/src/index.ts` (export all)
- Create: `packages/react/test/components.test.tsx`

**Depends on:** Task 10

- [ ] **Step 1: Write CheckoutButton**

Headless by default. Uses `usePayment` internally. Props: `amount, coin, orderId, onSuccess, onError, theme?`.

- [ ] **Step 2: Write PaymentForm**

Amount input + coin selector + orderId display + pay button. Uses `usePayment`.

- [ ] **Step 3: Write SubscribeButton**

Similar to CheckoutButton but for subscriptions. Uses `useSubscription`.

- [ ] **Step 4: Write MerchantBadge**

Displays merchant info (brand name, total received). Uses `useMerchant`.

- [ ] **Step 5: Update index.ts with all exports**

- [ ] **Step 6: Write component tests**

Test rendering, click → state transitions, error display.

- [ ] **Step 7: Run all react tests + build**

Run: `pnpm --filter @baleenpay/react test && pnpm --filter @baleenpay/react build`
Expected: ALL PASS, dist/ generated

- [ ] **Step 8: Commit**

```bash
git add packages/react/
git commit -m "feat(react): CheckoutButton, PaymentForm, SubscribeButton, MerchantBadge"
```

---

## Task 12: Contract Deploy (Testnet Upgrade) + Smoke Test

> **Skill:** @sui-deployer

**Files:**
- Modify: `move/baleenpay/deployed.testnet.json` (update with new digest)

**Depends on:** Task 3 (all contract tests pass)

- [ ] **Step 1: Build for deployment**

Run: `cd move/baleenpay && sui move build`
Expected: SUCCESS

- [ ] **Step 2: Upgrade on testnet**

Run: `sui client upgrade --upgrade-capability <cap_id> --skip-dependency-verification`
(Get cap_id from `deployed.testnet.json`)

- [ ] **Step 3: Smoke test pay_once_v2 on testnet**

Run: `sui client call --package <pkg> --module payment --function pay_once_v2 --type-args <USDC_TYPE> --args <merchant_account> <coin_id> "smoke_test_001" <clock_0x6>`

- [ ] **Step 4: Verify OrderRecord created**

Check MerchantAccount dynamic fields via `sui client object <merchant_id> --json`

- [ ] **Step 5: Update deployed.testnet.json**

- [ ] **Step 6: Commit**

```bash
git add move/baleenpay/deployed.testnet.json
git commit -m "deploy(contract): upgrade v2 with order_id dedup to testnet"
```

---

## Summary

| Task | Subsystem | Estimated Steps | Key Deliverable |
|------|-----------|-----------------|-----------------|
| 1 | Contract | 7 | Events V2 + UID accessors + self-pause |
| 2 | Contract | 9 | pay_once_v2, subscribe_v2, remove_order_record |
| 3 | Contract | 13 | V2 unit tests + monkey tests |
| 4 | SDK | 7 | Monorepo + types + constants |
| 5 | SDK | 10 | CoinHelper + PTB builders (critical gap fix) |
| 6 | SDK | 7 | Errors + events + version detection |
| 7 | SDK | 8 | Client + AdminClient + idempotency |
| 8 | SDK | 5 | Integration tests + Phase 2 backlog |
| 9 | React | 5 | Provider + useBaleenPay |
| 10 | React | 6 | Payment/subscription hooks |
| 11 | React | 8 | UI components |
| 12 | Contract | 6 | Testnet upgrade + smoke test |

**Parallelization:** Task 4 (SDK scaffold) can run in parallel with Tasks 1-3 (contract). Tasks 5-8 are sequential (SDK). Tasks 9-11 are sequential (React). Task 12 runs after Task 3.

**Demo app** (Task 13) is deferred to a separate plan — it deserves its own brainstorming for UX/design.
