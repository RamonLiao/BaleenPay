# FloatSync MVP Design Specification

> **Version:** 1.2
> **Date:** 2026-03-25
> **Status:** Draft
> **Scope:** M1 (checkout + dashboard) + M2 (StableLayer integration)

---

## 1. Executive Summary

FloatSync is a white-label stablecoin payment widget for SaaS platforms on the SUI blockchain. Users pay USDC, which is routed through StableLayer to mint BrandUSD and auto-deposit into yield pools. Merchants earn yield on idle payment float and can claim it anytime.

**Key value proposition:** Turn SaaS payment float into a yield-generating asset, transparently and on-chain.

**MVP delivers:**
- Embeddable checkout widget (one-time + subscription payments)
- Merchant dashboard (stats, payment history, claim yield)
- Move contracts on SUI with StableLayer integration + fallback Treasury
- Testnet-deployable, Hackathon-demo-ready, architecture extensible for production

---

## 2. Architecture Overview

### 2.1 System Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         Frontend (Next.js)                       │
│                                                                  │
│  ┌─────────────────────┐     ┌─────────────────────────────┐    │
│  │  Checkout Widget     │     │  Merchant Dashboard          │    │
│  │  /checkout/[id]      │     │  /dashboard/*                │    │
│  └────────┬────────────┘     └──────────┬──────────────────┘    │
│           │                             │                        │
│  ┌────────┴─────────────────────────────┴──────────────────┐    │
│  │              lib/sui/ (DataSource abstraction)           │    │
│  │  transactions.ts  │  queries.ts  │  hooks/               │    │
│  └────────┬─────────────────────────────────────────────────┘    │
└───────────┼──────────────────────────────────────────────────────┘
            │ PTB (Programmable Transaction Block)
            ▼
┌──────────────────────────────────────────────────────────────────┐
│                    SUI Blockchain (Testnet)                       │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              floatsync package (single package)          │    │
│  │                                                         │    │
│  │  merchant.move ◄── payment.move ──► router.move         │    │
│  │  (register,        (pay_once,       (StableLayer,       │    │
│  │   claim,            subscribe,       fallback)           │    │
│  │   pause)            process,                             │    │
│  │                     cancel)                              │    │
│  └───────────────────────┬─────────────────────────────────┘    │
│                          │                                       │
│                          ▼                                       │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │   StableLayer (external, deployed on testnet)            │    │
│  │   - Yield Aggregator Pool                                │    │
│  │   - BrandUSD Minting                                     │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Package structure | Single package, multi-module | MVP speed; `public(package)` for access control; split to multi-package post-stabilization |
| MerchantAccount | Shared Object | Payers and keepers need write access |
| Privilege control | MerchantCap (Owned) + AdminCap (Owned) | Capability pattern: Shared for access, Owned cap for authorization |
| payment ↔ router | PTB composition, not internal calls | Decoupled modules; payment returns Coin, PTB passes to router |
| Subscription | Escrow-based keeper pattern | Pre-funded escrow allows trustless auto-debit without payer signature |
| Yield sync | Lazy update on claim | No keeper needed for yield sync; devInspectTransaction for dashboard display |
| BrandUSD | StableLayer mint (primary) / self-mint (fallback) | Showcase StableLayer integration; fallback ensures demo resilience |
| Frontend data | On-chain RPC + events (MVP) | DataSource interface abstracts away; swap to backend/indexer later |
| Tech stack | Next.js + shadcn/ui + @mysten/dapp-kit | plan.md preference; production-grade UI with minimal setup |

---

## 3. Move Contract Design

### 3.1 Module Structure

```
move/floatsync/
├── Move.toml
├── sources/
│   ├── brand_usd.move       # OTW + coin creation (BRAND_USD type)
│   ├── merchant.move        # Merchant registration, MerchantCap, ledger, claim yield
│   ├── payment.move         # One-time payment, subscription state machine, escrow
│   ├── router.move          # StableLayer routing, fallback Treasury setup, vault
│   └── events.move          # All event structs
└── tests/
    ├── merchant_tests.move
    ├── payment_tests.move
    ├── subscription_tests.move
    ├── router_fallback_tests.move
    └── integration_tests.move
```

> **Note on error codes:** Move `const` is always module-private (no `public const`). Each module defines its own error codes. See Section 3.8 for the full registry with module ownership.

### 3.2 Object Model

#### AdminCap (Owned → deployer)

```move
public struct AdminCap has key, store {
    id: UID,
}
```

Created in `merchant::init()`. Grants global admin privileges: set RouterConfig, emergency pause.

#### MerchantRegistry (Shared, singleton)

```move
public struct MerchantRegistry has key {
    id: UID,
    merchants: Table<address, ID>,  // owner address → MerchantAccount ID
}
```

Created in `merchant::init()` and shared. Used by merchants to look up their own MerchantAccount ID from their wallet address. Payers do NOT need the registry — they access MerchantAccount directly via the object ID from the checkout URL.

#### MerchantCap (Owned → merchant)

```move
public struct MerchantCap has key, store {
    id: UID,
    merchant_id: ID,  // points to MerchantAccount
}
```

Created during `register_merchant()`, transferred to the registrant. Required for `claim_yield`.

#### MerchantAccount (Shared)

```move
public struct MerchantAccount<phantom T> has key {
    id: UID,
    owner: address,
    brand_name: String,
    total_received: u64,
    idle_principal: u64,
    accrued_yield: u64,
    active_subscriptions: Table<address, Subscription<T>>,
    paused: bool,
}
// Production: MerchantAccount<USDC>  |  Tests: MerchantAccount<TEST_USDC>
```

Created during `register_merchant()` and shared. Any user can call `pay_once` or `process_subscription` on it. Write-privileged operations require `MerchantCap` or `AdminCap`.

#### Subscription (stored in Table)

```move
public struct Subscription<phantom T> has store {
    amount_per_period: u64,
    period_ms: u64,
    next_due: u64,
    status: u8,              // 0=active, 1=paused, 2=cancelled
    payments_made: u64,
    escrowed_balance: Balance<T>,   // generic over payment coin type
    max_periods_prepaid: u64,
}
```

#### RouterConfig (Shared, admin-writable)

```move
public struct RouterConfig has key {
    id: UID,
    mode: u8,                          // 0=StableLayer, 1=Fallback
    stablelayer_pool_id: Option<ID>,
    stablelayer_config_id: Option<ID>,
}
```

Created in `router::init()` and shared. Readable by anyone (frontend reads mode to build correct PTB). Writable only via AdminCap.

#### BRAND_USD Coin Type (via brand_usd.move OTW)

```move
// brand_usd.move
module floatsync::brand_usd {
    public struct BRAND_USD has drop {}

    fun init(witness: BRAND_USD, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 6, b"BUSD", b"BrandUSD",
            b"FloatSync branded stablecoin", option::none(), ctx
        );
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
    }
}
```

OTW `BRAND_USD` is created in `brand_usd::init()`. The resulting `TreasuryCap<BRAND_USD>` is transferred to the deployer, who then wraps it into `FallbackTreasury` via a post-deploy setup PTB (see Section 3.7).

> **Why a separate module?** SUI OTW struct name must be the UPPER_CASE of the module name. To get a coin type named `BRAND_USD`, the module must be named `brand_usd`. Putting it in `router.move` would create a coin type `ROUTER`, which is not meaningful.

#### FallbackTreasury (Shared, package-internal)

```move
public struct FallbackTreasury has key {
    id: UID,
    cap: TreasuryCap<BRAND_USD>,
}
```

Created via `router::setup_treasury()` admin function (post-deploy). Wraps TreasuryCap from brand_usd::init. Mint access restricted to `public(package)` functions in router.move.

#### FallbackVault (Shared)

```move
public struct FallbackVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,   // generic over payment coin type (USDC in production)
}
```

Stores USDC in fallback mode. Created via `router::setup_treasury()` (post-deploy, together with FallbackTreasury).

> **Known limitation:** One subscription per payer per merchant. If a user cancels and re-subscribes, the cancelled entry is removed from the Table before the new one is inserted.

### 3.3 Core Function Interfaces

#### merchant.move

```move
// Register a new merchant. Creates MerchantAccount (shared) + MerchantCap (to sender).
public fun register_merchant(
    registry: &mut MerchantRegistry,
    brand_name: String,
    ctx: &mut TxContext,
)

// Claim accrued yield via fallback vault. Requires MerchantCap.
// Aborts with EZeroYield if accrued_yield == 0 (saves caller gas).
// Withdraws USDC from FallbackVault based on accrued_yield.
// For StableLayer mode, use claim_yield_stablelayer instead.
public fun claim_yield_fallback(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    vault: &mut FallbackVault,
    ctx: &mut TxContext,
): Coin<USDC>
// → PTB must call TransferObjects to send yield_coin to sender

// Claim accrued yield via StableLayer. Requires MerchantCap.
// Lazy yield update: reads current yield from StableLayer pool at claim time.
public fun claim_yield_stablelayer(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    config: &RouterConfig,
    pool: &mut stablelayer::pool::Pool,
    sl_config: &stablelayer::config::GlobalConfig,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<USDC>
// → PTB must call TransferObjects to send yield_coin to sender

// Emergency pause. Requires AdminCap.
public fun pause_merchant(
    admin: &AdminCap,
    account: &mut MerchantAccount,
)

// Unpause. Requires AdminCap.
public fun unpause_merchant(
    admin: &AdminCap,
    account: &mut MerchantAccount,
)
```

#### payment.move

```move
// One-time payment. Updates ledger (total_received + idle_principal), emits event,
// returns the same coin (pass-through) for PTB to route to router.
// Does NOT split/create coins — purely record-keeping + event emission.
// All accounting lives here; router does NOT touch MerchantAccount.
public fun pay_once(
    account: &mut MerchantAccount,
    coin: Coin<USDC>,
    clock: &Clock,
    ctx: &TxContext,  // immutable: no coin creation needed, just reads sender
): Coin<USDC>

// Create subscription + execute first payment. Returns coin for routing.
public fun create_subscription(
    account: &mut MerchantAccount,
    amount_per_period: u64,
    period_ms: u64,
    prepaid_coin: Coin<USDC>,  // covers first payment + escrow for future periods
    num_periods_prepaid: u64,
    clock: &Clock,
    ctx: &mut TxContext,  // mut: splits coin into first payment + escrow
): Coin<USDC>  // first period's payment, to be routed; escrow stored in Subscription

// Fund additional periods for an existing subscription.
public fun fund_subscription(
    account: &mut MerchantAccount,
    coin: Coin<USDC>,
    ctx: &TxContext,
)

// Keeper-callable: process due subscription. Returns coin (from escrow) for routing.
// Takes `payer` address to locate subscription in Table. Any address can call.
public fun process_subscription(
    account: &mut MerchantAccount,
    payer: address,
    clock: &Clock,
    ctx: &mut TxContext,  // mut: needs UID for coin::from_balance
): Coin<USDC>

// Cancel subscription. Uses tx_context::sender(ctx) as Table key to locate subscription.
// Asserts sender matches subscription payer. Removes entry from Table. Refunds escrow.
public fun cancel_subscription(
    account: &mut MerchantAccount,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<USDC>  // refunded escrow balance; PTB sends via TransferObjects to sender
```

#### router.move

```move
// Post-deploy setup: wrap TreasuryCap into FallbackTreasury shared object.
// Called once after deployment. Requires AdminCap.
public fun setup_treasury(
    admin: &AdminCap,
    cap: TreasuryCap<BRAND_USD>,
    ctx: &mut TxContext,
)
// → Creates and shares FallbackTreasury + FallbackVault

// Route funds via StableLayer (mode=0).
// Called by PTB after payment::pay_once or payment::process_subscription.
// Does NOT touch MerchantAccount — all ledger updates happen in payment module.
public fun route_to_stablelayer(
    config: &RouterConfig,
    pool: &mut stablelayer::pool::Pool,
    sl_config: &stablelayer::config::GlobalConfig,
    coin: Coin<USDC>,
    recipient: address,   // BrandUSD recipient (merchant owner)
    clock: &Clock,
    ctx: &mut TxContext,
)

// Route funds via fallback Treasury (mode=1).
// Does NOT touch MerchantAccount — all ledger updates happen in payment module.
public fun route_to_fallback(
    config: &RouterConfig,
    treasury: &mut FallbackTreasury,
    vault: &mut FallbackVault,
    coin: Coin<USDC>,
    recipient: address,   // BrandUSD recipient (merchant owner)
    ctx: &mut TxContext,
)

// Redeem BRAND_USD for USDC (fallback mode only). Requires MerchantCap.
// Burns BRAND_USD, withdraws equivalent USDC from FallbackVault.
public fun redeem_brand_usd(
    cap: &MerchantCap,
    treasury: &mut FallbackTreasury,
    vault: &mut FallbackVault,
    brand_coin: Coin<BRAND_USD>,
    ctx: &mut TxContext,
): Coin<USDC>

// Calculate current yield (view function, used in claim_yield).
public(package) fun calculate_yield(
    config: &RouterConfig,
    account: &MerchantAccount,
): u64

// Admin: set router mode.
public fun set_mode(
    admin: &AdminCap,
    config: &mut RouterConfig,
    mode: u8,
)
```

#### events.move

```move
public struct MerchantRegistered has copy, drop {
    merchant_id: ID,
    brand_name: String,
    owner: address,
}

public struct PaymentReceived has copy, drop {
    merchant_id: ID,
    payer: address,
    amount: u64,
    payment_type: u8,   // PAYMENT_TYPE_ONETIME=0, PAYMENT_TYPE_SUBSCRIPTION=1 (constants in errors.move)
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
```

### 3.4 PTB Composition Patterns

#### One-time Payment

```
PTB:
  1. splitCoins(gas, [amount]) → coin
  2. payment::pay_once(account, coin, clock) → returned_coin
  3. router::route_to_stablelayer(config, pool, sl_config, returned_coin, merchant_owner, clock)
     OR router::route_to_fallback(config, treasury, vault, returned_coin, merchant_owner)
```

> **Note:** `merchant_owner` address is read from MerchantAccount on the frontend before building the PTB. Router does NOT access MerchantAccount — all ledger updates happen in step 2.

#### Create Subscription

```
PTB:
  1. splitCoins(gas, [first_period + escrow_amount]) → coin
  2. payment::create_subscription(account, amount, period_ms, coin, num_periods, clock) → first_coin
  3. router::route_to_stablelayer(config, pool, sl_config, first_coin, merchant_owner, clock)
     OR router::route_to_fallback(config, treasury, vault, first_coin, merchant_owner)
```

#### Keeper Process Subscription

```
PTB:
  1. payment::process_subscription(account, payer_addr, clock) → coin
  2. router::route_to_stablelayer(config, pool, sl_config, coin, merchant_owner, clock)
     OR router::route_to_fallback(config, treasury, vault, coin, merchant_owner)
```

#### Cancel Subscription

```
PTB:
  1. payment::cancel_subscription(account, clock) → refund_coin
  2. TransferObjects([refund_coin], sender)
```

#### Fund Subscription

```
PTB:
  1. splitCoins(gas, [fund_amount]) → coin
  2. payment::fund_subscription(account, coin)
```

#### Claim Yield (Fallback)

```
PTB:
  1. merchant::claim_yield_fallback(cap, account, vault) → yield_coin
  2. TransferObjects([yield_coin], sender)
```

#### Claim Yield (StableLayer)

```
PTB:
  1. merchant::claim_yield_stablelayer(cap, account, config, pool, sl_config, clock) → yield_coin
  2. TransferObjects([yield_coin], sender)
```

#### Redeem BRAND_USD (Fallback only)

```
PTB:
  1. router::redeem_brand_usd(cap, treasury, vault, brand_coin) → usdc_coin
  2. TransferObjects([usdc_coin], sender)
```

#### Post-deploy Setup (one-time)

```
PTB:
  1. router::setup_treasury(admin_cap, treasury_cap)
  // Creates and shares FallbackTreasury + FallbackVault
```

### 3.5 Cross-Module Access Control

| Function | Access | Mechanism |
|----------|--------|-----------|
| `register_merchant` | Anyone | Public |
| `pay_once` | Anyone (when not paused) | Public, checks `!paused`; updates all ledger fields |
| `create_subscription` | Anyone (when not paused) | Public, checks `!paused` |
| `process_subscription` | Anyone (keeper) | Public, checks `next_due <= now` |
| `cancel_subscription` | Subscriber only | Public, checks `ctx.sender == payer` |
| `fund_subscription` | Subscriber only | Public, checks `ctx.sender == payer` |
| `claim_yield_*` | Merchant only | Requires `MerchantCap` |
| `pause/unpause_merchant` | Admin only | Requires `AdminCap` |
| `setup_treasury` | Admin only (one-time) | Requires `AdminCap` |
| `set_mode` | Admin only | Requires `AdminCap` |
| `route_to_stablelayer` | Anyone via PTB | Public; safe — only deposits coin, does NOT touch MerchantAccount |
| `route_to_fallback` | Anyone via PTB | Public; safe — only deposits coin + mints BrandUSD, does NOT touch MerchantAccount |
| `redeem_brand_usd` | Merchant only | Requires `MerchantCap`; burns BRAND_USD, returns USDC |
| `calculate_yield` (internal) | Package only | `public(package)` |

### 3.6 StableLayer Integration

**Status:** StableLayer is deployed on testnet with public package ID and API.

**Integration points (to be verified via `sui-decompile` before implementation):**

```
// TODO: Verify actual StableLayer API before coding
// - Package ID: TBD (query testnet)
// - stablelayer::pool::deposit(pool, config, coin, clock, ctx)
// - stablelayer::mint::mint_brand(pool, amount, ctx) → Coin<BrandUSD>
// - stablelayer::pool::get_position_value(pool, position_id) → u64
```

**Fallback activation criteria:**
- StableLayer API unavailable or incompatible at implementation time
- Critical bug in StableLayer integration during Hackathon
- Admin manually switches `RouterConfig.mode` to 1

### 3.7 Init Flow (Module → Objects Created)

| Module | `init()` Creates | Notes |
|--------|-----------------|-------|
| `brand_usd.move` | `TreasuryCap<BRAND_USD>` (transfer to deployer), `CoinMetadata` (freeze) | OTW module. Deployer receives TreasuryCap, then wraps it via `router::setup_treasury` in a post-deploy PTB. |
| `merchant.move` | `AdminCap` (transfer to deployer), `MerchantRegistry` (share) | AdminCap is the root privilege for the entire system |
| `router.move` | `RouterConfig` (share) | FallbackTreasury + FallbackVault are created later via `setup_treasury()` admin call |
| `payment.move` | (none) | Stateless module, all ledger state lives in MerchantAccount |
| `events.move` | (none) | Pure struct definitions |

**Post-deploy setup PTB (required, one-time):**
```
1. router::setup_treasury(admin_cap, treasury_cap)
   → Creates FallbackTreasury (wraps TreasuryCap) + FallbackVault → both shared
```

### 3.8 Error Codes & Constants Registry

> **Move constraint:** `const` is always module-private. Each module defines its own error codes and domain constants. This section is a human-readable registry to prevent code collisions.

#### merchant.move

```move
const ENotMerchantOwner: u64 = 0;     // MerchantCap.merchant_id != account.id
const EPaused: u64 = 2;               // MerchantAccount.paused == true
const EAlreadyRegistered: u64 = 6;    // Merchant address already in registry
const EZeroYield: u64 = 12;           // accrued_yield == 0, nothing to claim
```

#### payment.move

```move
const EZeroAmount: u64 = 1;           // Coin value is 0
const EPaused: u64 = 2;               // MerchantAccount.paused == true
const ENotYetDue: u64 = 3;            // clock.timestamp_ms < subscription.next_due
const ESubscriptionNotActive: u64 = 4; // subscription.status != ACTIVE
const ENotSubscriber: u64 = 5;        // tx_context::sender != subscription payer
const ESubscriptionExists: u64 = 7;   // Payer already has active subscription for this merchant
const EInsufficientEscrow: u64 = 8;   // Escrow balance < amount_per_period
const EInvalidPeriod: u64 = 10;       // period_ms == 0
const EInsufficientPrepaid: u64 = 11; // prepaid_coin < amount_per_period * num_periods

// Domain constants
const PAYMENT_TYPE_ONETIME: u8 = 0;
const PAYMENT_TYPE_SUBSCRIPTION: u8 = 1;
const SUBSCRIPTION_ACTIVE: u8 = 0;
const SUBSCRIPTION_PAUSED: u8 = 1;
const SUBSCRIPTION_CANCELLED: u8 = 2;
```

#### router.move

```move
const EInvalidMode: u64 = 9;          // RouterConfig.mode not 0 or 1
const EInsufficientVault: u64 = 13;   // FallbackVault balance insufficient for redeem

const ROUTER_MODE_STABLELAYER: u8 = 0;
const ROUTER_MODE_FALLBACK: u8 = 1;
```

> **Note:** Duplicate codes across modules (e.g., `EPaused = 2` in both merchant and payment) are fine — Move error codes are scoped to the module that aborts. The abort origin (module + code) is reported in the transaction error.

### 3.9 Fallback Yield Strategy

In fallback mode (mode=1), USDC is stored in `FallbackVault` but **does not earn real yield** — there is no DeFi integration in fallback mode.

**MVP approach:**
- `accrued_yield` remains 0 in fallback mode. The Dashboard will show "Yield: 0 (fallback mode — no yield source connected)."
- This is acceptable for Hackathon: the fallback exists to ensure the payment flow works even without StableLayer. The yield demo requires StableLayer mode.
- Merchants can still `claim_yield_fallback` but it will return 0.

**Post-MVP option:** In fallback mode, route USDC to a SUI DeFi protocol (e.g., Navi, Scallop) instead of just holding in vault. This would be a new router strategy (mode=2).

> **Known limitation:** `FallbackVault` is a single shared pool with no per-merchant accounting. All merchants' USDC co-mingles in one `Balance<USDC>`. This is safe for MVP because fallback yield is 0 (no withdrawals from yield). If post-MVP fallback mode ever accrues real yield, the vault would need per-merchant position tracking (e.g., `Table<ID, u64>` mapping merchant_id → deposited amount).

### 3.10 Subscription Query Strategy

`active_subscriptions: Table<address, Subscription>` **cannot be iterated on-chain** (Tables are key-value stores with O(1) lookup, no iteration).

**Frontend approaches for listing subscriptions:**
1. **Primary:** Query `SubscriptionCreated` and `SubscriptionCancelled` events, reconstruct active set client-side
2. **Fallback:** Maintain a `VecSet<address>` of active subscriber addresses alongside the Table (adds gas cost but enables on-chain enumeration if needed)

**MVP decision:** Use event-based reconstruction (approach 1). Simpler, no extra gas cost. The DataSource interface already abstracts this:

```typescript
// OnChainDataSource.getActiveSubscriptions() implementation:
// 1. queryEvents for SubscriptionCreated with this merchantId
// 2. queryEvents for SubscriptionCancelled with this merchantId
// 3. Diff the two sets to get active subscribers
// 4. For each active subscriber, getObject on MerchantAccount to read subscription details via devInspect
```

---

## 4. Frontend Design

### 4.1 Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js (App Router) |
| UI | shadcn/ui + Tailwind CSS |
| Wallet | @mysten/dapp-kit (React hooks) |
| SUI SDK | @mysten/sui (`Transaction`, `SuiClient`). Note: JSON-RPC deprecated in v1.68, removal ~April 2026. MVP uses JSON-RPC; plan migration to gRPC (GA) or GraphQL (beta) for production. |
| Charts | Recharts (lightweight, for yield trends) |
| Testing | Vitest + React Testing Library + Playwright |

### 4.2 Directory Structure

```
frontend/
├── package.json
├── next.config.ts
├── tailwind.config.ts
├── src/
│   ├── app/
│   │   ├── layout.tsx                    # Global layout + WalletProvider
│   │   ├── page.tsx                      # Landing / demo entry
│   │   ├── checkout/
│   │   │   └── [merchantId]/
│   │   │       └── page.tsx              # Checkout widget page
│   │   └── dashboard/
│   │       ├── layout.tsx                # Dashboard layout (sidebar)
│   │       ├── page.tsx                  # Overview: stats cards
│   │       ├── payments/page.tsx         # Payment history
│   │       ├── subscriptions/page.tsx    # Subscription management
│   │       └── settings/page.tsx         # Merchant settings
│   ├── components/
│   │   ├── checkout/
│   │   │   ├── CheckoutWidget.tsx        # Embeddable checkout component
│   │   │   ├── PaymentForm.tsx           # Amount + pay button
│   │   │   └── SubscriptionPlan.tsx      # Plan selection
│   │   ├── dashboard/
│   │   │   ├── StatsCards.tsx            # 3 metric cards
│   │   │   ├── YieldChart.tsx            # Yield trend chart
│   │   │   ├── PaymentTable.tsx          # Payment history table
│   │   │   └── ClaimYieldButton.tsx      # Claim button + tx status
│   │   └── shared/
│   │       ├── ConnectWallet.tsx          # Wallet connection
│   │       └── TransactionStatus.tsx      # Tx pending/success/fail
│   ├── lib/
│   │   ├── sui/
│   │   │   ├── client.ts                # SuiClient initialization
│   │   │   ├── constants.ts             # Package ID, object IDs
│   │   │   ├── transactions.ts          # PTB builders
│   │   │   └── queries.ts              # DataSource interface + OnChainDataSource
│   │   └── hooks/
│   │       ├── useMerchantAccount.ts    # Read merchant ledger
│   │       ├── usePaymentHistory.ts     # Event-based payment history
│   │       └── useYieldEstimate.ts      # devInspect yield estimation
│   └── types/
│       └── index.ts
```

### 4.3 Data Fetching Architecture

```typescript
// DataSource abstraction — MVP uses on-chain, swap to backend later
export interface DataSource {
  getMerchantAccount(id: string): Promise<MerchantAccount>;
  getPaymentHistory(merchantId: string, cursor?: string): Promise<PaginatedResult<PaymentEvent>>;
  getYieldEstimate(merchantId: string): Promise<bigint>;
  getActiveSubscriptions(merchantId: string): Promise<Subscription[]>;
  getRouterConfig(): Promise<RouterConfig>;
}

// MVP implementation
export class OnChainDataSource implements DataSource {
  constructor(private client: SuiClient) {}
  // Uses SuiClient.getObject, queryEvents, devInspectTransaction
}

// Future implementation
// export class ApiDataSource implements DataSource {
//   constructor(private baseUrl: string) {}
//   // Uses REST/GraphQL API backed by indexer
// }
```

### 4.4 User Flows

#### Payer: One-time Payment

1. Visit `/checkout/[merchantId]`
2. Connect SUI wallet
3. Select "One-time Payment", enter amount
4. Confirm → sign PTB (pay_once + route)
5. See transaction result (success/failure)

#### Payer: Subscribe

1. Visit `/checkout/[merchantId]`
2. Connect SUI wallet
3. Select subscription plan (amount + period)
4. Choose prepaid periods (min 1)
5. Confirm → sign PTB (create_subscription + route first payment)
6. See subscription confirmation

#### Merchant: Register

1. Visit `/dashboard`, connect wallet
2. No MerchantCap detected → show registration form
3. Enter brand name → sign `register_merchant` tx
4. Redirect to dashboard overview

#### Merchant: Dashboard

1. Visit `/dashboard`, connect wallet
2. MerchantCap detected → load merchant data
3. Overview: StatsCards (total_received, idle_principal, accrued_yield)
4. Payments: paginated history from event query
5. Subscriptions: active subscriber list
6. Claim: ClaimYieldButton → sign `claim_yield` tx

#### Merchant: Checkout Widget Embedding

```html
<!-- Third-party SaaS embeds via iframe -->
<iframe
  src="https://floatsync.app/checkout/0xMERCHANT_ACCOUNT_ID?plan=subscription&amount=10&period=month"
  width="400"
  height="600"
/>

<!-- Future: npm package -->
<!-- <FloatSyncCheckout merchantId="0x..." plan="subscription" amount={10} period="month" /> -->
```

---

## 5. Security Considerations

### 5.1 Smart Contract Threat Model

| Threat | Mitigation |
|--------|-----------|
| Fake MerchantCap (forged capability) | Cap stores `merchant_id: ID`; all privileged functions assert `cap.merchant_id == object::id(account)` |
| Integer overflow on total_received / idle_principal | Move's u64 arithmetic aborts on overflow by default; additional explicit checks for yield calculation |
| Double-process subscription in same block | `next_due` updated immediately after process; second call fails `next_due <= now` check |
| Zero-amount payment | Explicit `assert!(coin::value(&coin) > 0, EZeroAmount)` |
| Cancel other user's subscription | `assert!(tx_context::sender(ctx) == payer_address, ENotSubscriber)` |
| Escrow drain (process more than funded) | `balance::split` aborts if insufficient; `escrowed_balance` checked before debit |
| Unauthorized pause/unpause | Requires `AdminCap` (Owned object, only admin can use in tx) |
| Router mode manipulation | `set_mode` requires `AdminCap` |
| Reentrancy | SUI Move does not support reentrancy; all state updates are atomic within a PTB |
| Direct router call (skip payment) | Router does NOT touch MerchantAccount — attacker only deposits USDC into vault and gets BRAND_USD with no ledger credit. No fund loss, no accounting impact. |
| Shared Object contention (high traffic) | **Known limitation for MVP.** All payments to one merchant compete for the same Shared Object. SUI orders these via consensus. For MVP throughput this is fine. Post-MVP: consider sharding MerchantAccount or event-sourcing pattern. |

### 5.2 Frontend Security

| Threat | Mitigation |
|--------|-----------|
| Malicious iframe embedding | Content-Security-Policy headers; validate `merchantId` parameter |
| Wallet phishing | Only interact with verified contract package ID in constants.ts |
| Event spoofing | Filter events by exact `MoveEventType` with verified package ID |

---

## 6. Testing Strategy

### 6.1 Move Contract Tests

| Layer | Scope | Approach |
|-------|-------|----------|
| Unit (pure) | payment + merchant logic | Test record-keeping, escrow, cap verification. No router dependency. |
| Unit (fallback) | router fallback path | Test FallbackTreasury mint, FallbackVault balance, BRAND_USD transfer |
| Monkey | Edge cases + attack vectors | Forged cap, overflow, double-process, zero amount, cancel+process, escrow drain |
| Integration (testnet) | StableLayer path | TypeScript E2E scripts against devnet/testnet with real StableLayer contracts |

#### Monkey Test Cases

```
- Forged MerchantCap → claim → abort ENotMerchantOwner
- total_received near u64::MAX + payment → abort (overflow)
- process_subscription twice in same PTB → second aborts ENotYetDue
- pay_once with 0 USDC → abort EZeroAmount
- cancel_subscription then process → abort ESubscriptionNotActive
- User A cancels User B subscription → abort ENotSubscriber
- fund_subscription 1 period, process 2x → second aborts (insufficient balance)
- pay_once on paused merchant → abort EPaused
- Non-admin calls pause_merchant → tx fails (no AdminCap)
- redeem_brand_usd more than vault balance → abort EInsufficientVault
- redeem_brand_usd with wrong MerchantCap → abort ENotMerchantOwner
- Direct route_to_fallback call (skip pay_once) → no accounting impact, just USDC→vault + BrandUSD mint
```

### 6.2 Frontend Tests

| Layer | Tool | Coverage |
|-------|------|----------|
| Unit | Vitest | PTB builders, DataSource logic, utility functions |
| Component | React Testing Library | CheckoutWidget flow, Dashboard data rendering, wallet states |
| E2E | Playwright | Connect wallet → pay → dashboard verify (testnet) |

### 6.3 Pre-deploy Checklist

```bash
# 1. Move build
sui move build

# 2. Move tests (with gas tracking)
sui move test --gas-limit 1000000000

# 3. Frontend type check
cd frontend && npx tsc --noEmit

# 4. Frontend unit tests
npm run test

# 5. Deploy to devnet
sui client publish --gas-budget 100000000

# 6. Run E2E integration tests against devnet
npm run test:e2e
```

---

## 7. Deployment Plan

### 7.1 Staged Rollout

| Stage | Network | Purpose |
|-------|---------|---------|
| 1 | Devnet | Contract development + iteration |
| 2 | Testnet | StableLayer integration testing + Hackathon demo |
| 3 | Mainnet | Production (post-MVP, after audit) |

### 7.2 Deployment Artifacts

```
- floatsync package → SUI network
- Frontend → Vercel (Next.js)
- Constants update: package ID, object IDs in frontend/src/lib/sui/constants.ts
```

### 7.3 Post-deployment Verification

```bash
# Verify published package
sui client object <PACKAGE_ID>

# Verify shared objects created
sui client object <MERCHANT_REGISTRY_ID>
sui client object <ROUTER_CONFIG_ID>
sui client object <FALLBACK_TREASURY_ID>
sui client object <FALLBACK_VAULT_ID>

# Test register_merchant tx
sui client call --package <PKG> --module merchant --function register_merchant ...

# Test pay_once + route PTB
# (via TypeScript test script)
```

---

## 8. Future Extensibility

### 8.1 Package Split (Post-MVP)

When contract stabilizes, split into:
- `floatsync_core` (merchant + payment) — low change frequency
- `floatsync_router` (router + treasury) — high change frequency

Replace `public(package)` with Witness pattern for cross-package auth.

### 8.2 Backend Service (Post-MVP)

Add indexer + API backend:
- Swap `OnChainDataSource` → `ApiDataSource` in frontend
- Historical analytics, webhook notifications, subscription reminders
- No frontend UI changes needed (DataSource abstraction)

### 8.3 SDK Distribution

Package CheckoutWidget as npm SDK:
```bash
npm install @floatsync/checkout
```

```tsx
import { FloatSyncCheckout } from '@floatsync/checkout';
<FloatSyncCheckout merchantId="0x..." network="mainnet" />
```

---

## Appendix A: Package Upgrade Policy

**MVP: Upgradeable (compatible).** The package is published with the default `compatible` upgrade policy, allowing:
- Adding new modules
- Adding new functions to existing modules
- Adding new struct types
- NOT changing existing function signatures or struct layouts

This is required for iterating during development and post-Hackathon improvements. For mainnet production, consider restricting to `additive` or `immutable` after stabilization.

```bash
# Default publish (upgradeable)
sui client publish --gas-budget 100000000

# Future: restrict upgrade policy
sui client publish --upgrade-policy additive
```

## Appendix B: Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | StableLayer exact API signatures (deposit, mint, get_position_value) | TODO: verify via sui-decompile |
| 2 | StableLayer testnet package ID and shared object IDs | TODO: query testnet |
| 3 | BrandUSD coin type — does StableLayer return a generic `Coin<T>` or specific type? | TODO: verify |
| 4 | Domain registration (floatsync.app) and GitHub org | TODO: manual |
| 5 | Hackathon submission deadline and requirements | TODO: confirm with user |

## Appendix C: Dependency Versions

| Dependency | Version |
|-----------|---------|
| SUI CLI | >= 1.68.0 |
| Move Edition | 2024 |
| Next.js | 15.x |
| @mysten/sui | latest |
| @mysten/dapp-kit | latest |
| shadcn/ui | latest |
| TypeScript | 5.x |
| Node.js | 20.x LTS |
