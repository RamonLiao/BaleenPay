# BaleenPay MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a white-label stablecoin payment widget on SUI with StableLayer yield integration, deployable to testnet for Hackathon demo.

**Architecture:** Single Move package (`baleenpay`) with 5 modules (brand_usd, merchant, payment, router, events). Next.js frontend with Checkout Widget + Merchant Dashboard. PTB composition pattern decouples payment recording from fund routing.

**Tech Stack:** SUI Move (2024 Edition), Next.js 15, shadcn/ui, @mysten/dapp-kit, @mysten/sui, TypeScript 5, Vitest, Playwright

**Spec:** `docs/superpowers/specs/2026-03-25-baleenpay-mvp-design.md` (v1.2)

---

## File Structure

### Move Contract (`move/baleenpay/`)

| File | Responsibility |
|------|---------------|
| `Move.toml` | Package config, dependencies (Sui framework, StableLayer) |
| `sources/brand_usd.move` | OTW, `BRAND_USD` coin type creation, CoinMetadata |
| `sources/events.move` | All event structs (12 events) |
| `sources/merchant.move` | AdminCap, MerchantRegistry, MerchantCap, MerchantAccount, register/claim/pause |
| `sources/payment.move` | pay_once, create/process/cancel/fund_subscription, escrow logic |
| `sources/router.move` | RouterConfig, FallbackTreasury, FallbackVault, setup_treasury, route_to_fallback, redeem_brand_usd, set_mode |
| `tests/merchant_tests.move` | Merchant registration, cap validation, pause/unpause |
| `tests/payment_tests.move` | One-time payment recording, zero-amount rejection |
| `tests/subscription_tests.move` | Full subscription lifecycle: create, process, fund, cancel, escrow edge cases |
| `tests/router_fallback_tests.move` | Fallback mint, vault deposit, redeem, setup_treasury |
| `tests/integration_tests.move` | End-to-end: register → pay → route → claim |

### Frontend (`frontend/`)

| File | Responsibility |
|------|---------------|
| `src/lib/sui/constants.ts` | Package ID, shared object IDs, network config |
| `src/lib/sui/client.ts` | SuiClient singleton initialization |
| `src/lib/sui/queries.ts` | DataSource interface + OnChainDataSource |
| `src/lib/sui/transactions.ts` | All PTB builder functions |
| `src/types/index.ts` | Shared TypeScript types |
| `src/lib/hooks/useMerchantAccount.ts` | React hook: read merchant ledger |
| `src/lib/hooks/usePaymentHistory.ts` | React hook: event-based payment history |
| `src/lib/hooks/useYieldEstimate.ts` | React hook: devInspect yield estimation |
| `src/app/layout.tsx` | Root layout, WalletProvider, QueryClientProvider |
| `src/app/page.tsx` | Landing page / demo entry |
| `src/components/shared/ConnectWallet.tsx` | Wallet connect button |
| `src/components/shared/TransactionStatus.tsx` | Tx pending/success/fail UI |
| `src/components/checkout/PaymentForm.tsx` | Amount input + pay button |
| `src/components/checkout/SubscriptionPlan.tsx` | Plan selection UI |
| `src/components/checkout/CheckoutWidget.tsx` | Composites PaymentForm + SubscriptionPlan |
| `src/app/checkout/[merchantId]/page.tsx` | Checkout page (widget host) |
| `src/components/dashboard/StatsCards.tsx` | 3 metric cards |
| `src/components/dashboard/PaymentTable.tsx` | Payment history table |
| `src/components/dashboard/ClaimYieldButton.tsx` | Claim yield + tx status |
| `src/components/dashboard/YieldChart.tsx` | Yield trend chart |
| `src/app/dashboard/layout.tsx` | Dashboard layout (sidebar + header) |
| `src/app/dashboard/page.tsx` | Dashboard overview |
| `src/app/dashboard/payments/page.tsx` | Payment history page |
| `src/app/dashboard/subscriptions/page.tsx` | Subscription management page |
| `src/app/dashboard/settings/page.tsx` | Merchant settings page |

---

## Task Dependency Graph

```
Task 1 (Move project init)
  └→ Task 2 (events.move + brand_usd.move + test_usdc.move)
       └→ Task 3 (merchant.move: register, pause — NO claim_yield yet)
            └→ Task 4 (payment.move: pay_once + tests)
                 └→ Task 5 (payment.move: subscriptions + tests)
                      └→ Task 6 (router.move: fallback + claim_yield added to merchant)
                           └→ Task 7 (integration tests + monkey tests)
                                └→ Task 8 (devnet deploy + setup PTB)

Task 9 (frontend project init) ← can start parallel with Task 3
  └→ Task 10 (SUI lib: constants, client, types) ← uses placeholder IDs until Task 8
       └→ Task 11 (SUI lib: queries + transactions)
            └→ Task 12 (React hooks)
                 └→ Task 13 (Checkout Widget)
                      └→ Task 14 (Merchant Dashboard)
                           └→ Task 15 (Frontend unit + component tests)
                                └→ Task 16 (E2E integration + polish)
```

**Parallelization:** Tasks 9-12 (frontend foundation) can run in parallel with Tasks 3-7 (Move contracts). Frontend uses **placeholder values** in `constants.ts` until Task 8 (devnet deploy) provides real object IDs.

---

## USDC Type Mocking Strategy for Move Tests

Move unit tests cannot use real USDC (it's an external coin type on mainnet/testnet). Strategy:

**Define a test-only USDC module** in `tests/`:

```move
// tests/test_usdc.move
#[test_only]
module baleenpay::test_usdc {
    use sui::coin;

    public struct TEST_USDC has drop {}

    fun init(witness: TEST_USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 6, b"USDC", b"Test USDC", b"", option::none(), ctx,
        );
        transfer::public_transfer(treasury_cap, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
```

**Make payment and router functions generic** over the coin type `T`:

```move
// payment.move — generic over coin type
public fun pay_once<T>(
    account: &mut MerchantAccount,
    coin: Coin<T>,
    clock: &Clock,
    ctx: &TxContext,
): Coin<T>
```

This way tests use `pay_once<TEST_USDC>(...)` and production uses `pay_once<USDC>(...)`. The generic approach is standard in SUI DeFi contracts (e.g., DeepBook, Cetus). No runtime cost difference.

> **Note:** `Coin<USDC>` in the spec refers to the production type. All function signatures in the implementation should be `<T>` generic. The spec's `Coin<USDC>` notation is shorthand for the expected production usage.

**Structs that must be generic over `<phantom T>` (payment coin type):**

| Struct | Generic? | Reason |
|--------|----------|--------|
| `MerchantAccount<phantom T>` | Yes | Contains `Table<address, Subscription<T>>` |
| `Subscription<phantom T>` | Yes | `escrowed_balance: Balance<T>` |
| `FallbackVault<phantom T>` | Yes | `balance: Balance<T>` |
| `MerchantCap` | No | Only stores `merchant_id: ID`, no coin type |
| `MerchantRegistry` | No | Only stores `Table<address, ID>` |
| `AdminCap` | No | Pure capability |
| `RouterConfig` | No | Only stores mode/IDs |
| `FallbackTreasury` | No | Holds `TreasuryCap<BRAND_USD>` (project coin, not payment coin) |

The generic `<T>` cascades: `Subscription<T>` → `MerchantAccount<T>` → all functions that take `&mut MerchantAccount<T>`. This is the standard SUI DeFi pattern (see DeepBook, Cetus). Production instantiates with `<USDC>`, tests with `<TEST_USDC>`.

---

## Task 1: Move Project Initialization

**Files:**
- Create: `move/baleenpay/Move.toml`
- Create: `move/baleenpay/sources/` (empty dir)
- Create: `move/baleenpay/tests/` (empty dir)

- [ ] **Step 1: Create Move project structure**

```bash
mkdir -p move/baleenpay/sources move/baleenpay/tests
```

- [ ] **Step 2: Write Move.toml**

```toml
[package]
name = "baleenpay"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }

[addresses]
baleenpay = "0x0"
```

> **Note:** StableLayer dependency will be added in Task 6 when implementing router. For now, only Sui framework is needed.

- [ ] **Step 3: Verify build**

Run: `cd move/baleenpay && sui move build`
Expected: Build successful (empty package)

- [ ] **Step 4: Update .gitignore**

Add to project root `.gitignore`:
```
# Move build artifacts
move/baleenpay/build/
```

- [ ] **Step 5: Commit**

```bash
git add move/baleenpay/ .gitignore
git commit -m "chore: init Move project structure for baleenpay"
```

---

## Task 2: Events Module + BRAND_USD Coin Type

**Files:**
- Create: `move/baleenpay/sources/events.move`
- Create: `move/baleenpay/sources/brand_usd.move`

- [ ] **Step 1: Write events.move**

All 12 event structs from spec Section 3.4. Events module has no `init`, no error codes — pure data definitions.

```move
module baleenpay::events {
    use sui::object::ID;
    use std::string::String;

    public struct MerchantRegistered has copy, drop {
        merchant_id: ID,
        brand_name: String,
        owner: address,
    }

    public struct PaymentReceived has copy, drop {
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
    }

    public struct SubscriptionCreated has copy, drop {
        merchant_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
    }

    public struct SubscriptionProcessed has copy, drop {
        merchant_id: ID,
        payer: address,
        amount: u64,
        next_due: u64,
    }

    public struct SubscriptionCancelled has copy, drop {
        merchant_id: ID,
        payer: address,
        refunded_amount: u64,
    }

    public struct SubscriptionFunded has copy, drop {
        merchant_id: ID,
        payer: address,
        funded_amount: u64,
    }

    public struct YieldClaimed has copy, drop {
        merchant_id: ID,
        amount: u64,
    }

    public struct MerchantPaused has copy, drop {
        merchant_id: ID,
    }

    public struct MerchantUnpaused has copy, drop {
        merchant_id: ID,
    }

    public struct RouterModeChanged has copy, drop {
        old_mode: u8,
        new_mode: u8,
    }

    public struct BrandUsdRedeemed has copy, drop {
        merchant_id: ID,
        amount: u64,
    }

    public struct TreasurySetupCompleted has copy, drop {
        treasury_id: ID,
        vault_id: ID,
    }
}
```

- [ ] **Step 2: Write test_usdc.move (test-only mock USDC)**

```move
// tests/test_usdc.move
#[test_only]
module baleenpay::test_usdc {
    use sui::coin;

    public struct TEST_USDC has drop {}

    fun init(witness: TEST_USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 6, b"USDC", b"Test USDC", b"", option::none(), ctx,
        );
        transfer::public_transfer(treasury_cap, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
```

- [ ] **Step 3: Write brand_usd.move**

OTW module. Creates `BRAND_USD` coin type. TreasuryCap goes to deployer.

```move
module baleenpay::brand_usd {
    use sui::coin;
    use sui::url;

    public struct BRAND_USD has drop {}

    fun init(witness: BRAND_USD, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            6,                          // decimals (match USDC)
            b"BUSD",                    // symbol
            b"BrandUSD",               // name
            b"BaleenPay branded stablecoin backed by USDC",
            option::none(),             // icon_url
            ctx,
        );
        transfer::public_transfer(treasury_cap, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
```

- [ ] **Step 4: Verify build**

Run: `cd move/baleenpay && sui move build`
Expected: Build successful

- [ ] **Step 5: Commit**

```bash
git add move/baleenpay/sources/events.move move/baleenpay/sources/brand_usd.move move/baleenpay/tests/test_usdc.move
git commit -m "feat(move): add events module, BRAND_USD coin type, test USDC mock"
```

---

## Task 3: Merchant Module + Tests

**Files:**
- Create: `move/baleenpay/sources/merchant.move`
- Create: `move/baleenpay/tests/merchant_tests.move`

- [ ] **Step 1: Write merchant_tests.move — test register_merchant**

```move
#[test_only]
module baleenpay::merchant_tests {
    use baleenpay::merchant;
    use sui::test_scenario;

    #[test]
    fun test_register_merchant() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        // init creates AdminCap + MerchantRegistry
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);

        // register merchant
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestBrand".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.next_tx(merchant_addr);

        // verify MerchantCap received
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        scenario.return_to_sender(cap);

        // verify MerchantAccount exists as shared
        let account = scenario.take_shared<merchant::MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 0);
        assert!(merchant::get_brand_name(&account) == b"TestBrand".to_string());
        test_scenario::return_shared(account);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = merchant::EAlreadyRegistered)]
    fun test_double_register_fails() {
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(merchant_addr);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);

        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Brand1".to_string(), scenario.ctx());
        scenario.next_tx(merchant_addr);
        // second register should fail
        merchant::register_merchant(&mut registry, b"Brand2".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.end();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move/baleenpay && sui move test --filter merchant_tests`
Expected: FAIL — `merchant` module not found

- [ ] **Step 3: Write merchant.move**

Implement: AdminCap, MerchantRegistry, MerchantCap, MerchantAccount structs. Functions: `init`, `init_for_testing`, `register_merchant`, `pause_merchant`, `unpause_merchant`. Getter functions for test access.

Refer to spec Section 3.2 (Object Model) and Section 3.3 (merchant.move interfaces) for exact struct fields and function signatures.

Key implementation details:
- `init` creates AdminCap (transfer to sender) + MerchantRegistry (share)
- `register_merchant` checks `!table::contains`, creates MerchantAccount (share), creates MerchantCap (transfer to sender), inserts into registry, emits `MerchantRegistered`
- `pause_merchant` / `unpause_merchant` require AdminCap, toggle `paused` flag, emit events

> **`claim_yield_fallback` and `claim_yield_stablelayer` are NOT implemented here.** They depend on `FallbackVault` (from router.move, Task 6). These functions will be added to merchant.move in **Task 6, Step 5** after router types are available. This avoids a compile dependency on a module that doesn't exist yet.

- [ ] **Step 4: Run tests**

Run: `cd move/baleenpay && sui move test --filter merchant_tests`
Expected: All tests PASS

- [ ] **Step 5: Add pause/unpause tests**

Test: pause requires AdminCap, paused merchant blocks operations (tested in payment task), unpause re-enables.

- [ ] **Step 6: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add move/baleenpay/sources/merchant.move move/baleenpay/tests/merchant_tests.move
git commit -m "feat(move): merchant module — register, pause/unpause (claim_yield deferred to Task 6)"
```

---

## Task 4: Payment Module — pay_once + Tests

**Files:**
- Create: `move/baleenpay/sources/payment.move`
- Create: `move/baleenpay/tests/payment_tests.move`

- [ ] **Step 1: Write payment_tests.move — test pay_once**

```move
#[test_only]
module baleenpay::payment_tests {
    use baleenpay::merchant;
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;

    // Uses TEST_USDC (defined in tests/test_usdc.move) as stand-in for real USDC.
    // All payment/router functions are generic over coin type <T>.
    // Production uses Coin<USDC>, tests use Coin<TEST_USDC>.

    #[test]
    fun test_pay_once_records_payment() {
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(merchant_addr);

        // setup: register merchant
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestBrand".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.next_tx(payer);

        // pay_once with TEST_USDC (generic <T>)
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clk = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(1000, scenario.ctx());
        let returned_coin = payment::pay_once<TEST_USDC>(&mut account, coin, &clk, scenario.ctx());

        // verify ledger updated
        assert!(merchant::get_total_received(&account) == 1000);
        assert!(merchant::get_idle_principal(&account) == 1000);
        // verify coin returned intact
        assert!(coin::value(&returned_coin) == 1000);

        coin::burn_for_testing(returned_coin);
        clock::destroy_for_testing(clk);
        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = payment::EZeroAmount)]
    fun test_pay_once_zero_amount_fails() {
        // ... setup, then pay with 0-value Coin<TEST_USDC>
    }

    #[test]
    #[expected_failure(abort_code = payment::EPaused)]
    fun test_pay_once_paused_merchant_fails() {
        // ... setup, pause merchant, then try to pay
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move/baleenpay && sui move test --filter payment_tests`
Expected: FAIL — `payment` module not found

- [ ] **Step 3: Write payment.move — pay_once function**

Implement `pay_once` per spec Section 3.3:
- Assert `!account.paused` (EPaused)
- Assert `coin::value(&coin) > 0` (EZeroAmount)
- Update `account.total_received += amount`
- Update `account.idle_principal += amount`
- Emit `PaymentReceived` event
- Return coin (pass-through)

Error codes and domain constants defined at module level (per spec Section 3.8).

- [ ] **Step 4: Run tests**

Run: `cd move/baleenpay && sui move test --filter payment_tests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add move/baleenpay/sources/payment.move move/baleenpay/tests/payment_tests.move
git commit -m "feat(move): payment module — pay_once with ledger update"
```

---

## Task 5: Payment Module — Subscription Lifecycle + Tests

**Files:**
- Modify: `move/baleenpay/sources/payment.move`
- Create: `move/baleenpay/tests/subscription_tests.move`

- [ ] **Step 1: Write subscription_tests.move — create_subscription**

Test: create subscription with 3 prepaid periods. Verify:
- First period coin returned for routing
- Escrow holds 2 periods worth
- Subscription entry exists in Table
- `SubscriptionCreated` event emitted
- Account `total_received` and `idle_principal` updated for first payment

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move/baleenpay && sui move test --filter subscription_tests`
Expected: FAIL

- [ ] **Step 3: Implement create_subscription**

Per spec Section 3.3:
- Assert `!paused`, `period_ms > 0`, `amount_per_period > 0`
- Assert `coin value >= amount_per_period * num_periods_prepaid`
- Split coin: first period + escrow (remaining)
- Create Subscription struct with escrowed_balance, next_due = now + period_ms
- Insert into `active_subscriptions` Table (assert no existing entry: ESubscriptionExists)
- Update `total_received` and `idle_principal` for first period
- Emit events
- Return first period coin

- [ ] **Step 4: Run tests**

Expected: create_subscription tests PASS

- [ ] **Step 5: Add process_subscription tests**

Test: advance clock past next_due, call process_subscription. Verify:
- Coin returned from escrow (correct amount)
- `next_due` advanced
- `payments_made` incremented
- Account `total_received` and `idle_principal` updated
- Second immediate call fails (ENotYetDue)

- [ ] **Step 6: Implement process_subscription**

Per spec Section 3.3:
- Lookup subscription by payer address
- Assert `status == ACTIVE`, `clock.timestamp_ms >= next_due`
- Split `amount_per_period` from `escrowed_balance` (aborts if insufficient)
- Update `next_due`, `payments_made`
- Update account `total_received` and `idle_principal`
- Emit `SubscriptionProcessed`
- Return coin

- [ ] **Step 7: Run tests**

Expected: process_subscription tests PASS

- [ ] **Step 8: Add cancel_subscription + fund_subscription tests**

Tests for cancel:
- Sender == payer check
- Escrow refunded as Coin
- Table entry removed
- Subsequent process_subscription fails

Tests for fund:
- Only payer can fund
- Escrow balance increased

- [ ] **Step 9: Implement cancel_subscription + fund_subscription**

cancel: lookup by `ctx.sender()`, assert ACTIVE, remove from Table, return escrowed_balance as Coin, emit `SubscriptionCancelled`

fund: lookup by `ctx.sender()`, assert exists, join coin balance into escrow, emit `SubscriptionFunded`

- [ ] **Step 10: Run all subscription tests**

Run: `cd move/baleenpay && sui move test --filter subscription_tests`
Expected: All PASS

- [ ] **Step 11: Commit**

```bash
git add move/baleenpay/sources/payment.move move/baleenpay/tests/subscription_tests.move
git commit -m "feat(move): subscription lifecycle — create, process, cancel, fund with escrow"
```

---

## Task 6: Router Module — Fallback Path + Tests

**Files:**
- Create: `move/baleenpay/sources/router.move`
- Create: `move/baleenpay/tests/router_fallback_tests.move`

- [ ] **Step 1: Write router_fallback_tests.move**

Test setup_treasury:
- Requires AdminCap
- Creates FallbackTreasury (shared) + FallbackVault (shared)
- Emits TreasurySetupCompleted

Test route_to_fallback:
- Deposits USDC into vault
- Mints BRAND_USD to recipient
- Vault balance increases
- Correct BRAND_USD amount

Test redeem_brand_usd:
- Burns BRAND_USD
- Returns equivalent USDC from vault
- Vault balance decreases
- Requires MerchantCap

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move/baleenpay && sui move test --filter router_fallback`
Expected: FAIL

- [ ] **Step 3: Implement router.move**

Structs: RouterConfig, FallbackTreasury, FallbackVault

Functions per spec Section 3.3:
- `init`: create RouterConfig (mode=1 fallback default for MVP), share it
- `setup_treasury(admin, treasury_cap, ctx)`: wrap TreasuryCap into FallbackTreasury, create FallbackVault, share both, emit event
- `route_to_fallback(config, treasury, vault, coin, recipient, ctx)`: assert mode==FALLBACK, deposit USDC to vault, mint BRAND_USD, transfer to recipient
- `redeem_brand_usd(cap, treasury, vault, brand_coin, ctx)`: verify cap, burn BRAND_USD, withdraw USDC from vault, return Coin<USDC>
- `set_mode(admin, config, mode)`: assert valid mode, emit RouterModeChanged
- `calculate_yield(config, account)`: return 0 for fallback mode (stub)
- `route_to_stablelayer`: stub (abort with TODO until StableLayer API verified)

- [ ] **Step 4: Run tests**

Run: `cd move/baleenpay && sui move test --filter router_fallback`
Expected: All PASS

- [ ] **Step 5: Add claim_yield_fallback to merchant.move (deferred from Task 3)**

Now that `FallbackVault` type exists in router.move, implement `claim_yield_fallback` in merchant.move:
- Takes `&MerchantCap`, `&mut MerchantAccount`, `&mut FallbackVault`, `&mut TxContext`
- Assert `cap.merchant_id == object::id(account)` (ENotMerchantOwner)
- Assert `account.accrued_yield > 0` (EZeroYield)
- Withdraw `accrued_yield` amount from vault's USDC balance
- Reset `account.accrued_yield = 0`
- Emit `YieldClaimed`
- Return `Coin<USDC>` (caller's PTB does TransferObjects)

Also stub `claim_yield_stablelayer` (abort with TODO).

- [ ] **Step 6: Add claim_yield tests to merchant_tests.move**

```move
#[test]
fun test_claim_yield_fallback_success() {
    // setup: register merchant, manually set accrued_yield > 0 via test helper
    // call claim_yield_fallback
    // verify: Coin returned with correct amount, accrued_yield reset to 0
}

#[test]
#[expected_failure(abort_code = merchant::EZeroYield)]
fun test_claim_yield_zero_fails() {
    // setup: register merchant (accrued_yield = 0)
    // call claim_yield_fallback → should abort
}

#[test]
#[expected_failure(abort_code = merchant::ENotMerchantOwner)]
fun test_claim_yield_wrong_cap_fails() {
    // setup: register two merchants
    // try to claim merchant B's yield with merchant A's cap → should abort
}
```

- [ ] **Step 7: Run all tests**

Run: `cd move/baleenpay && sui move test`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add move/baleenpay/sources/router.move move/baleenpay/sources/merchant.move move/baleenpay/tests/router_fallback_tests.move move/baleenpay/tests/merchant_tests.move
git commit -m "feat(move): router fallback + claim_yield_fallback in merchant"
```

---

## Task 7: Integration Tests + Monkey Tests

**Files:**
- Create: `move/baleenpay/tests/integration_tests.move`

- [ ] **Step 1: Write integration test — full payment flow**

Test end-to-end with fallback mode:
1. Deploy (init all modules)
2. setup_treasury (admin wraps TreasuryCap)
3. register_merchant
4. pay_once → route_to_fallback (simulating PTB composition)
5. Verify: account.total_received updated, vault has USDC, merchant got BRAND_USD
6. redeem_brand_usd → verify USDC returned

- [ ] **Step 2: Write integration test — subscription flow**

1. register_merchant
2. create_subscription (3 periods prepaid) → route first payment
3. Advance clock → process_subscription → route
4. Advance clock → process_subscription → route
5. Verify: total_received == 3 * amount, escrow depleted
6. cancel_subscription → verify refund == 0 (all periods consumed)

- [ ] **Step 3: Write monkey tests**

Per spec Section 6.1 — ALL 12 monkey test cases:
- Forged MerchantCap → claim → abort ENotMerchantOwner
- total_received near u64::MAX + payment → abort (overflow)
- process_subscription twice same block → second aborts ENotYetDue
- pay_once with 0 USDC → abort EZeroAmount
- cancel then process → abort ESubscriptionNotActive
- User A cancels User B subscription → abort ENotSubscriber
- fund 1 period, process 2x → abort on second (insufficient escrow)
- pay_once paused merchant → abort EPaused
- Non-admin calls pause_merchant → tx fails (no AdminCap)
- redeem_brand_usd more than vault balance → abort EInsufficientVault
- redeem_brand_usd with wrong MerchantCap → abort ENotMerchantOwner
- Direct route_to_fallback call (skip pay_once) → no accounting impact (verify MerchantAccount unchanged)
- redeem more than vault → abort
- redeem with wrong cap → abort

- [ ] **Step 4: Run all Move tests**

Run: `cd move/baleenpay && sui move test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add move/baleenpay/tests/integration_tests.move
git commit -m "test(move): integration tests + monkey tests for all attack vectors"
```

---

## Task 8: Devnet Deployment + Post-deploy Setup

**Files:**
- Create: `scripts/deploy.sh`
- Create: `scripts/setup.ts` (post-deploy setup PTB)

- [ ] **Step 1: Build final package**

Run: `cd move/baleenpay && sui move build`
Expected: Build successful, no warnings

- [ ] **Step 2: Write deploy script**

```bash
#!/bin/bash
# scripts/deploy.sh
set -e

echo "Building..."
cd move/baleenpay && sui move build

echo "Publishing to devnet..."
sui client publish --gas-budget 200000000 --json > /tmp/publish-result.json

echo "Package ID:"
cat /tmp/publish-result.json | jq -r '.objectChanges[] | select(.type == "published") | .packageId'

echo "Created objects:"
cat /tmp/publish-result.json | jq '.objectChanges[] | select(.type == "created") | {objectType: .objectType, objectId: .objectId}'
```

- [ ] **Step 3: Deploy to devnet**

Run: `bash scripts/deploy.sh`
Expected: Package published. Note the Package ID and created object IDs (AdminCap, MerchantRegistry, RouterConfig, TreasuryCap).

- [ ] **Step 4: Write post-deploy setup script**

TypeScript script using @mysten/sui to execute the setup PTB:

```typescript
// scripts/setup.ts
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

const PACKAGE_ID = process.env.PACKAGE_ID!;
const ADMIN_CAP_ID = process.env.ADMIN_CAP_ID!;
const TREASURY_CAP_ID = process.env.TREASURY_CAP_ID!;

const client = new SuiClient({ url: getFullnodeUrl('devnet') });
const keypair = Ed25519Keypair.deriveKeypair(process.env.MNEMONIC!);

async function setup() {
  const tx = new Transaction();

  tx.moveCall({
    target: `${PACKAGE_ID}::router::setup_treasury`,
    arguments: [
      tx.object(ADMIN_CAP_ID),
      tx.object(TREASURY_CAP_ID),
    ],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    options: { showObjectChanges: true },
  });

  console.log('Setup TX:', result.digest);

  const created = result.objectChanges?.filter(c => c.type === 'created');
  console.log('Created objects:', JSON.stringify(created, null, 2));
  // Find FallbackTreasury and FallbackVault IDs from created objects
}

setup().catch(console.error);
```

- [ ] **Step 5: Run setup script**

Run: `npx tsx scripts/setup.ts`
Expected: FallbackTreasury and FallbackVault shared objects created.

- [ ] **Step 6: Update constants.ts with deployed object IDs**

Record all object IDs in `frontend/src/lib/sui/constants.ts`.

- [ ] **Step 7: Commit**

```bash
git add scripts/ frontend/src/lib/sui/constants.ts
git commit -m "chore: devnet deploy scripts + object ID constants"
```

---

## Task 9: Frontend Project Initialization

**Files:**
- Create: `frontend/` (Next.js project)

- [ ] **Step 1: Create Next.js project**

```bash
cd /path/to/BaleenPay
npx create-next-app@latest frontend --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
```

- [ ] **Step 2: Install dependencies**

```bash
cd frontend
npm install @mysten/sui @mysten/dapp-kit @tanstack/react-query recharts
npx shadcn@latest init
npx shadcn@latest add button card input table badge tabs separator
```

- [ ] **Step 3: Verify dev server**

Run: `cd frontend && npm run dev`
Expected: Next.js dev server starts on localhost:3000

- [ ] **Step 4: Commit**

```bash
git add frontend/
git commit -m "chore: init Next.js frontend with shadcn/ui + SUI SDK"
```

---

## Task 10: SUI Lib — Constants, Client, Types

**Files:**
- Create: `frontend/src/lib/sui/constants.ts`
- Create: `frontend/src/lib/sui/client.ts`
- Create: `frontend/src/types/index.ts`

- [ ] **Step 1: Write constants.ts**

```typescript
export const NETWORK = 'devnet'; // switch to 'testnet' for hackathon
export const PACKAGE_ID = '0x...'; // from deploy
export const MERCHANT_REGISTRY_ID = '0x...';
export const ROUTER_CONFIG_ID = '0x...';
export const FALLBACK_TREASURY_ID = '0x...';
export const FALLBACK_VAULT_ID = '0x...';
export const CLOCK_ID = '0x6';
```

- [ ] **Step 2: Write client.ts**

```typescript
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { NETWORK } from './constants';

export const suiClient = new SuiClient({ url: getFullnodeUrl(NETWORK) });
```

- [ ] **Step 3: Write types/index.ts**

TypeScript types mirroring Move structs: MerchantAccount, Subscription, PaymentEvent, RouterConfig, etc.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/lib/sui/ frontend/src/types/
git commit -m "feat(frontend): SUI lib foundation — constants, client, types"
```

---

## Task 11: SUI Lib — Queries + Transactions

**Files:**
- Create: `frontend/src/lib/sui/queries.ts`
- Create: `frontend/src/lib/sui/transactions.ts`

- [ ] **Step 1: Write queries.ts — DataSource interface + OnChainDataSource**

Implement DataSource interface with 5 methods. OnChainDataSource uses:
- `suiClient.getObject()` for MerchantAccount
- `suiClient.queryEvents()` for payment history + subscription reconstruction
- `suiClient.devInspectTransactionBlock()` for yield estimate

- [ ] **Step 2: Write transactions.ts — all PTB builders**

Functions matching spec Section 3.4 PTB patterns:
- `buildPayOnceTx(merchantAccountId, amount, routerMode, ...objectIds)`
- `buildCreateSubscriptionTx(...)`
- `buildProcessSubscriptionTx(...)`
- `buildCancelSubscriptionTx(...)`
- `buildFundSubscriptionTx(...)`
- `buildClaimYieldTx(merchantCapId, merchantAccountId, routerMode, ...)`
- `buildRedeemBrandUsdTx(...)`
- `buildRegisterMerchantTx(registryId, brandName)`

Each function returns a `Transaction` object ready for wallet signing.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/sui/queries.ts frontend/src/lib/sui/transactions.ts
git commit -m "feat(frontend): DataSource queries + PTB transaction builders"
```

---

## Task 12: React Hooks

**Files:**
- Create: `frontend/src/lib/hooks/useMerchantAccount.ts`
- Create: `frontend/src/lib/hooks/usePaymentHistory.ts`
- Create: `frontend/src/lib/hooks/useYieldEstimate.ts`

- [ ] **Step 1: Write useMerchantAccount hook**

Uses `@tanstack/react-query` + OnChainDataSource. Polls MerchantAccount state. Returns `{ data, isLoading, error, refetch }`.

- [ ] **Step 2: Write usePaymentHistory hook**

Event-based pagination. Returns `{ payments, hasMore, loadMore, isLoading }`.

- [ ] **Step 3: Write useYieldEstimate hook**

Uses devInspectTransaction to simulate claim and estimate yield. Returns `{ estimate, isLoading }`.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/lib/hooks/
git commit -m "feat(frontend): React hooks — merchant account, payment history, yield estimate"
```

---

## Task 13: Checkout Widget

**Files:**
- Modify: `frontend/src/app/layout.tsx` (add WalletProvider)
- Create: `frontend/src/components/shared/ConnectWallet.tsx`
- Create: `frontend/src/components/shared/TransactionStatus.tsx`
- Create: `frontend/src/components/checkout/PaymentForm.tsx`
- Create: `frontend/src/components/checkout/SubscriptionPlan.tsx`
- Create: `frontend/src/components/checkout/CheckoutWidget.tsx`
- Create: `frontend/src/app/checkout/[merchantId]/page.tsx`

- [ ] **Step 1: Setup WalletProvider in layout.tsx**

Wrap app with `@mysten/dapp-kit` providers: `SuiClientProvider`, `WalletProvider`, `QueryClientProvider`.

- [ ] **Step 2: Build ConnectWallet component**

Uses `useConnectWallet`, `useCurrentAccount` from dapp-kit. Shows connect button or connected address.

- [ ] **Step 3: Build TransactionStatus component**

Shows pending spinner, success with tx digest link, or error message.

- [ ] **Step 4: Build PaymentForm**

Input for amount, "Pay Now" button. Uses `useSignAndExecuteTransaction` from dapp-kit + `buildPayOnceTx`.

- [ ] **Step 5: Build SubscriptionPlan**

Plan selector (amount + period), prepaid periods input. Uses `buildCreateSubscriptionTx`.

- [ ] **Step 6: Build CheckoutWidget — composite**

Tabs: "One-time" | "Subscribe". Loads merchant info via `useMerchantAccount`. Renders PaymentForm or SubscriptionPlan.

- [ ] **Step 7: Build checkout page**

`/checkout/[merchantId]` — reads merchantId from params, renders CheckoutWidget.

- [ ] **Step 8: Test manually in browser**

Run: `npm run dev`, navigate to `/checkout/<test-merchant-id>`, connect wallet, attempt payment on devnet.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/
git commit -m "feat(frontend): checkout widget — one-time payment + subscription"
```

---

## Task 14: Merchant Dashboard

**Files:**
- Create: `frontend/src/components/dashboard/StatsCards.tsx`
- Create: `frontend/src/components/dashboard/PaymentTable.tsx`
- Create: `frontend/src/components/dashboard/ClaimYieldButton.tsx`
- Create: `frontend/src/components/dashboard/YieldChart.tsx`
- Create: `frontend/src/app/dashboard/layout.tsx`
- Create: `frontend/src/app/dashboard/page.tsx`
- Create: `frontend/src/app/dashboard/payments/page.tsx`
- Create: `frontend/src/app/dashboard/subscriptions/page.tsx`
- Create: `frontend/src/app/dashboard/settings/page.tsx`

- [ ] **Step 1: Build StatsCards**

3 cards: Total Received, Idle Principal, Accrued Yield. Data from `useMerchantAccount`. Format USDC amounts (6 decimals).

- [ ] **Step 2: Build PaymentTable**

Paginated table using `usePaymentHistory`. Columns: payer, amount, type, timestamp. shadcn/ui Table component.

- [ ] **Step 3: Build ClaimYieldButton**

Button that builds + signs `claim_yield` PTB. Shows yield amount, disabled when yield=0. TransactionStatus for feedback.

- [ ] **Step 4: Build YieldChart**

Recharts line chart showing yield over time. Data from payment events (cumulative).

- [ ] **Step 5: Build dashboard layout**

Sidebar navigation: Overview, Payments, Subscriptions, Settings. Header with ConnectWallet. Checks for MerchantCap — if none, shows registration form.

- [ ] **Step 6: Build dashboard pages**

- Overview (`/dashboard`): StatsCards + YieldChart + recent PaymentTable
- Payments (`/dashboard/payments`): full PaymentTable with pagination
- Subscriptions (`/dashboard/subscriptions`): active subscriber list from events
- Settings (`/dashboard/settings`): brand name display (read-only for MVP)

- [ ] **Step 7: Build merchant registration flow**

If no MerchantCap detected on wallet: show registration form (brand name input) → call `buildRegisterMerchantTx` → on success, redirect to dashboard.

- [ ] **Step 8: Test manually**

Run dev server, register as merchant, make a payment from another wallet, verify dashboard updates.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/
git commit -m "feat(frontend): merchant dashboard — stats, payments, subscriptions, claim yield"
```

---

## Task 15: Frontend Unit + Component Tests

**Files:**
- Create: `frontend/src/lib/sui/__tests__/transactions.test.ts`
- Create: `frontend/src/lib/sui/__tests__/queries.test.ts`
- Create: `frontend/src/components/checkout/__tests__/CheckoutWidget.test.tsx`

- [ ] **Step 1: Setup Vitest**

```bash
cd frontend && npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
```

Add vitest config to `vitest.config.ts`.

- [ ] **Step 2: Write transactions.ts unit tests**

Test each PTB builder:
- `buildPayOnceTx` produces correct moveCall target and arguments
- `buildCreateSubscriptionTx` splits coins correctly
- `buildClaimYieldTx` varies by routerMode (fallback vs stablelayer)
- `buildRegisterMerchantTx` includes correct registryId

Mock `Transaction` class to verify moveCall arguments without network.

- [ ] **Step 3: Write queries.ts unit tests**

Test `OnChainDataSource` methods with mocked `SuiClient`:
- `getMerchantAccount` parses object response correctly
- `getPaymentHistory` queries correct event type
- `getActiveSubscriptions` reconstructs from create/cancel events

- [ ] **Step 4: Write CheckoutWidget component test**

Using React Testing Library:
- Renders payment form when "One-time" tab selected
- Renders subscription plan when "Subscribe" tab selected
- Shows connect wallet prompt when no wallet connected
- Disables pay button when amount is 0

- [ ] **Step 5: Run all frontend tests**

Run: `cd frontend && npx vitest run`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add frontend/src/**/__tests__/ frontend/vitest.config.ts
git commit -m "test(frontend): unit tests for PTB builders, queries, CheckoutWidget"
```

---

## Task 16: End-to-End Integration + Polish

**Files:**
- Create: `frontend/src/app/page.tsx` (landing page)
- Modify: various files for polish

- [ ] **Step 1: Build landing page**

Simple landing with:
- "I'm a Merchant" → `/dashboard`
- "I'm a Payer" → input merchant ID → `/checkout/[id]`
- Brief product description

- [ ] **Step 2: Frontend type check**

Run: `cd frontend && npx tsc --noEmit`
Expected: No type errors

- [ ] **Step 3: Full E2E test (manual)**

On devnet:
1. Register merchant (wallet A)
2. Copy MerchantAccount ID
3. Pay one-time (wallet B) via `/checkout/[id]`
4. Create subscription (wallet B)
5. Check dashboard (wallet A) — verify stats, payment history
6. Claim yield (wallet A) — verify tx succeeds (0 yield in fallback is OK)

- [ ] **Step 4: Commit**

```bash
git add frontend/
git commit -m "feat(frontend): landing page + E2E integration verified"
```

- [ ] **Step 5: Final build verification**

```bash
# Move
cd move/baleenpay && sui move build && sui move test

# Frontend
cd frontend && npx tsc --noEmit && npm run build
```

Expected: All pass, build successful.

- [ ] **Step 6: Final commit**

```bash
git commit -m "chore: final build verification — all tests pass"
```

---

## Post-Plan: StableLayer Integration (Task 8.5 — when API verified)

> This task is deferred until StableLayer API is verified via `sui-decompile`. It slots between Task 8 and Task 9 in priority, but can be done any time after Task 6.

- [ ] Verify StableLayer API: `sui-decompile` skill on testnet package
- [ ] Add StableLayer dependency to Move.toml
- [ ] Implement `route_to_stablelayer` in router.move
- [ ] Implement `claim_yield_stablelayer` in merchant.move
- [ ] Integration test on testnet with real StableLayer
- [ ] Switch `RouterConfig.mode` to 0 (StableLayer)
- [ ] Update frontend constants if needed
