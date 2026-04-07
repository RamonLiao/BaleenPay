# BaleenPay SDK Design Specification

> **Version:** 1.0
> **Date:** 2026-03-25
> **Status:** Draft
> **Scope:** Phase 1 — `@baleenpay/sdk` + `@baleenpay/react` + Contract Order ID Upgrade

---

## 1. Executive Summary

BaleenPay SDK is a Stripe-inspired developer toolkit for SUI blockchain payments. It provides a progressive integration model targeting both Web3 native and Web2 developers, enabling SaaS platforms to embed stablecoin payments with minimal effort.

**Phase 1 delivers:**
- `@baleenpay/sdk` — TypeScript SDK with PTB builders, event listeners, coin registry, idempotency
- `@baleenpay/react` — React components (CheckoutButton, PaymentForm, SubscribeButton) + hooks
- Contract upgrade — Order ID deduplication on `pay_once_v2` / `subscribe_v2`
- Demo app — Dogfooding the SDK as both checkout and merchant dashboard

**Future phases (deferred):**
- Phase 2: `@baleenpay/server` (webhook relay, server-side idempotency)
- Phase 3: BaleenPay Cloud (REST API, hosted checkout, API key management, usage metering)

---

## 2. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target audience | Mixed Web2 + Web3 | Two integration surfaces, shared core |
| Revenue model | Contract free + yield spread + Hosted API paid (Phase 3) | Zero barrier entry, Web3 culture fit |
| SDK scope | All operations (pay, subscribe, register, claim, pause) | Full coverage from day 1 |
| Upgrade strategy | Contract additive-first + SDK version routing | SUI `compatible` upgrade policy enforces this naturally |
| Event/Webhook | On-chain event stream (Phase 1) + Hosted webhook (Phase 2) | Web3 uses events, Web2 uses webhooks |
| Coin support | Whitelist shorthand + custom coin type + SDK validation | CoinMetadata RPC check for DX |
| Idempotency | Contract-layer Order ID + SDK-layer idempotency key | Order ID for precise dedup, SDK for UX convenience |
| Release format | SDK → React components → Hosted Checkout (phased) | Pyramid structure, each layer builds on previous |
| Security keys | pk_ (public config) / sk_ (server-side, Phase 3) / whsec_ (webhook, Phase 2) | pk_ is just a config bundle, not a secret |
| PII policy | Never on-chain | SDK rejects PII fields by design |
| Yield strategy | Off-chain (Hosted API layer) | Protect business logic from on-chain visibility |
| Styling | Headless by default, optional theme | SaaS platforms have their own design systems |

---

## 3. Architecture Overview

```
                        SaaS Platform Developer
                     ┌──────────┴──────────┐
                     │                     │
              Web3 native               Web2 Developer
                     │                     │
              ┌──────┘                     └──────┐
              ▼                                   ▼
    @baleenpay/sdk (core)              @baleenpay/react
    ┌─────────────────────┐           ┌──────────────────┐
    │ BaleenPay client    │◄──────────│ <BaleenPayProvider>│
    │   .pay()            │           │ <CheckoutButton>  │
    │   .subscribe()      │           │ <PaymentForm>     │
    │   .claimYield()     │           │ <SubscribeButton> │
    │   .register()       │           │ <MerchantBadge>   │
    │   .pause/unpause()  │           └──────────────────┘
    │                     │
    │ EventStream         │
    │   .on('payment', cb)│
    │                     │
    │ CoinRegistry        │
    │   .resolve('USDC')  │
    │                     │
    │ IdempotencyGuard    │
    └────────┬────────────┘
             │ PTB construction
             ▼
    ┌─────────────────────────────────────┐
    │        SUI Blockchain               │
    │                                     │
    │  baleenpay package (upgraded)       │
    │  ┌─────────┐ ┌──────────┐          │
    │  │merchant │ │ payment  │          │
    │  │ +uid()  │ │ +v2 fns  │          │
    │  │ +remove │ │ +order_id│          │
    │  └─────────┘ └──────────┘          │
    │  ┌─────────┐ ┌──────────┐          │
    │  │ router  │ │ events   │          │
    │  └─────────┘ └──────────┘          │
    └─────────────────────────────────────┘
```

---

## 4. SDK Core (`@baleenpay/sdk`)

### 4.1 Module Structure

```
@baleenpay/sdk/
├── src/
│   ├── client.ts          # BaleenPay main class — single entry point
│   ├── transactions/      # PTB builders (one per contract function)
│   │   ├── pay.ts
│   │   ├── subscribe.ts
│   │   ├── merchant.ts
│   │   └── yield.ts
│   ├── events/            # On-chain event listening
│   │   ├── stream.ts      # SUI event subscription wrapper
│   │   └── types.ts       # Event type definitions
│   ├── coins/             # Coin registry + validation
│   │   ├── registry.ts    # Whitelist + shorthand mapping
│   │   └── validator.ts   # CoinMetadata RPC validation
│   ├── idempotency.ts     # Client-side dedup guard
│   ├── errors.ts          # Error code mapping (abort code → human message)
│   ├── types.ts           # All public types
│   └── index.ts           # Public API exports
├── package.json
└── tsconfig.json
```

### 4.2 Client API

```typescript
class BaleenPay {
  constructor(config: BaleenPayConfig)

  // ── Payments ──
  pay(params: PayParams): Promise<TransactionResult>
  subscribe(params: SubscribeParams): Promise<TransactionResult>
  processSubscription(subscriptionId: string): Promise<TransactionResult>
  cancelSubscription(subscriptionId: string): Promise<TransactionResult>
  fundSubscription(params: FundParams): Promise<TransactionResult>

  // ── Merchant Management ──
  registerMerchant(params: RegisterParams): Promise<TransactionResult>
  claimYield(): Promise<TransactionResult>
  pause(): Promise<TransactionResult>
  unpause(): Promise<TransactionResult>

  // ── Queries ──
  getMerchant(merchantId?: string): Promise<MerchantInfo>
  getSubscription(subscriptionId: string): Promise<SubscriptionInfo>
  getPaymentHistory(params?: QueryParams): Promise<PaymentEvent[]>

  // ── Events ──
  on(event: BaleenPayEvent, callback: EventCallback): Unsubscribe
}
```

### 4.3 Initialization

```typescript
import { BaleenPay } from '@baleenpay/sdk'

const fs = new BaleenPay({
  network: 'testnet',           // 'mainnet' | 'testnet' | 'devnet'
  packageId: '0x7d12...5097',   // baleenpay package
  merchantId: '0x42f2...62ca',  // MerchantAccount object ID
})

// One-line payment
const tx = await fs.pay({
  amount: 10_000_000,
  coin: 'USDC',
  orderId: 'order_123',
})
```

### 4.4 TransactionResult

SDK returns a composable result — does not execute transactions directly:

```typescript
interface TransactionResult {
  tx: Transaction                          // Unsigned PTB (from @mysten/sui)
  execute(signer: WalletAdapter | Keypair): Promise<ExecutedResult>
  // WalletAdapter = @mysten/dapp-kit wallet context (browser)
  // Keypair = @mysten/sui/keypairs (Node.js scripts, bots)
}

interface ExecutedResult {
  digest: string
  status: 'success' | 'failure'
  events: BaleenPayEvent[]
  gasUsed: bigint
  payment?: { orderId: string, amount: bigint, coinType: string }
  subscription?: { subscriptionId: string, nextDue: number }
  merchant?: { merchantId: string, capId: string }
}
```

Returning `Transaction` (not executing) allows Web3 users to compose BaleenPay PTBs with other operations in a single atomic transaction.

### 4.5 Coin Registry

```typescript
interface CoinRegistry {
  // Resolve shorthand to full coin type
  resolve(coin: string): Promise<string>
  // e.g. 'USDC' → '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC'

  // Validate a coin type exists on-chain
  validate(coinType: string): Promise<CoinMetadata>
  // Throws ValidationError if CoinMetadata not found
}

// Built-in shorthand mappings (per network)
const COIN_MAP = {
  testnet: {
    'SUI': '0x2::sui::SUI',
    'USDC': '0x...::usdc::USDC',   // official testnet USDC
    'BRAND_USD': '0x7d12...::brand_usd::BRAND_USD',
  },
  mainnet: {
    'SUI': '0x2::sui::SUI',
    'USDC': '0x...::usdc::USDC',   // official mainnet USDC
  },
}
```

Custom coin types bypass the shorthand map and go directly to `validate()`.

### 4.6 Idempotency Guard

Client-side dedup layer — prevents accidental double-submission from the UI:

```typescript
interface IdempotencyGuard {
  // Check if this key has already been submitted (in-memory, per-session)
  check(key: string): IdempotencyResult  // 'new' | 'pending' | 'completed'

  // Mark a key as pending (before wallet signing)
  markPending(key: string): void

  // Mark a key as completed (after tx confirmed) with cached result
  markCompleted(key: string, result: ExecutedResult): void

  // Get cached result for a completed key
  getCachedResult(key: string): ExecutedResult | null
}
```

- **Scope:** in-memory, per `BaleenPay` instance (resets on page refresh)
- **Key generation:** SDK auto-generates from `(merchantId, orderId)` if orderId provided, otherwise from `(merchantId, method, amount, coinType, timestamp_bucket)`
- **Relationship to contract Order ID:** This is a UX convenience layer. Contract-layer Order ID is the source of truth. If a user refreshes and re-submits, the in-memory guard resets but the contract still blocks the duplicate.

### 4.7 Core Types

```typescript
// All object IDs are hex strings (0x-prefixed)
type ObjectId = string

interface BaleenPayConfig {
  network: 'mainnet' | 'testnet' | 'devnet'
  packageId: ObjectId
  merchantId: ObjectId
  registryId?: ObjectId     // MerchantRegistry (auto-discovered if omitted)
  routerConfigId?: ObjectId // RouterConfig (auto-discovered if omitted)
}

interface PayParams {
  amount: bigint | number
  coin: string           // shorthand ('USDC') or full type ('0x...::mod::TYPE')
  orderId: string        // required — SDK enforces this for v2
}

interface SubscribeParams {
  amountPerPeriod: bigint | number
  periodMs: number
  prepaidPeriods: number
  coin: string
  orderId: string
}

interface FundParams {
  subscriptionId: ObjectId
  amount: bigint | number
  coin: string
}

interface RegisterParams {
  brandName: string
  registryId?: ObjectId
}

interface QueryParams {
  cursor?: string    // event cursor for pagination
  limit?: number     // max events per page (default 50)
  order?: 'asc' | 'desc'
}
```

### 4.8 Version Detection

SDK auto-detects contract version at initialization:

```typescript
// Uses getNormalizedMoveModule to check for pay_once_v2
// Falls back to pay_once if v2 not available
// Transparent to the developer
```

---

## 5. React Components (`@baleenpay/react`)

### 5.1 Module Structure

```
@baleenpay/react/
├── src/
│   ├── provider.tsx            # <BaleenPayProvider>
│   ├── components/
│   │   ├── CheckoutButton.tsx
│   │   ├── PaymentForm.tsx
│   │   ├── SubscribeButton.tsx
│   │   └── MerchantBadge.tsx
│   ├── hooks/
│   │   ├── useBaleenPay.ts     # Get SDK client instance
│   │   ├── usePayment.ts       # Payment state management
│   │   ├── useSubscription.ts  # Subscription operations + state
│   │   ├── useMerchant.ts      # Merchant info queries
│   │   └── usePaymentHistory.ts
│   ├── types.ts
│   └── index.ts
├── package.json
└── tsconfig.json
```

### 5.2 Provider

```tsx
import { BaleenPayProvider, CheckoutButton } from '@baleenpay/react'

<WalletProvider>
  <BaleenPayProvider config={{
    network: 'testnet',
    packageId: '0x7d12...5097',
    merchantId: '0x42f2...62ca',
  }}>
    <CheckoutButton
      amount={10_000_000}
      coin="USDC"
      orderId="order_123"
      onSuccess={(result) => router.push('/thank-you')}
    />
  </BaleenPayProvider>
</WalletProvider>
```

### 5.3 Payment State Machine

```
idle → validating → building → signing → confirming → success → idle
                                  ↓           ↓                   ↑
                               rejected     failed                │
                            (user rejected) (on-chain abort)      │
                                  │           ↓                   │
                                  │     error (translated)        │
                                  └───────────┴───── (auto-reset) ┘
```

All terminal states (`success`, `rejected`, `error`) auto-reset to `idle` after a configurable delay (default: 3s), or immediately via `reset()`. Hooks expose `status` + `error` + `reset()`. Components use hooks internally. Developers can use hooks directly for custom UI.

### 5.4 Styling Strategy

- **Default: headless** — no styles, platform controls appearance
- **Optional: `theme="default"`** — BaleenPay branded styles
- **Optional: custom theme object** — `{ primary, radius, fontFamily }`

---

## 6. Contract Upgrade — Order ID Deduplication

### 6.1 Scope

Additive upgrade only. No changes to existing published functions.

| Change | Method | Impact |
|--------|--------|--------|
| `pay_once_v2<T>` with order_id | New function | Original `pay_once` untouched |
| `subscribe_v2<T>` with order_id | New function | Original `subscribe` untouched |
| Order ID registry | Dynamic fields on MerchantAccount | No struct changes |
| `remove_order_record` | New function (MerchantCap gated) | Cleanup capability |
| `uid()` / `uid_mut()` | New `public(package)` accessors on merchant | For cross-module dynamic field access |

### 6.2 Order ID Key Design

```move
/// Scoped to payer address — prevents squatting and cross-payer collision.
public struct OrderKey has copy, drop, store {
    payer: address,
    order_id: String,
}

/// Stored as dynamic field on MerchantAccount.
public struct OrderRecord has store, drop {
    amount: u64,
    timestamp_ms: u64,
    coin_type: String,
}
```

**Design decisions (from security review):**
- Key includes `payer` — eliminates front-running/squatting attacks (Critical finding)
- Cross-coin-type: same order_id blocks all coin types (intentional, PaymentIntent semantics)
- order_id validation: ASCII printable (0x21-0x7E), 1-64 bytes
- Old `pay_once` preserved, documented as "no dedup guarantee"
- `min_payment_amount` deferred to Phase 2

### 6.3 New Error Codes

| Code | Name | Scenario |
|------|------|----------|
| 18 | `EOrderAlreadyPaid` | Same (payer, order_id) already exists |
| 19 | `EInvalidOrderId` | Empty, too long, or non-ASCII-printable characters |

### 6.4 Implementation Skeleton

```move
const EOrderAlreadyPaid: u64 = 18;
const EInvalidOrderId: u64 = 19;
const MAX_ORDER_ID_BYTES: u64 = 64;

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

    df::add(merchant::uid_mut(account), key, OrderRecord {
        amount,
        timestamp_ms: clock.timestamp_ms(),
        coin_type: type_name::get<T>().into_string().to_string(),
    });

    // Emit event — v2 emitter includes order_id and coin_type
    events::emit_payment_received_v2(
        object::id(account),
        ctx.sender(),
        amount,
        0, // payment_type: 0 = one-time
        clock.timestamp_ms(),
        order_id,
        type_name::get<T>().into_string().to_string(),
    );
}

/// Subscribe with order_id deduplication.
/// Same as subscribe but adds order_id check before creating subscription.
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

    // All existing subscribe logic (pause check, amount checks, escrow, etc.)
    assert!(!merchant::get_paused(account), EPaused);
    assert!(amount_per_period > 0, EZeroAmount);
    assert!(period_ms > 0, EZeroPeriod);
    assert!(prepaid_periods > 0, EZeroPrepaidPeriods);

    let total_required = amount_per_period * prepaid_periods;
    assert!(coin.value() >= total_required, EInsufficientPrepaid);

    // Split exact amount, refund remainder
    let escrow_coin = coin.split(total_required, ctx);
    if (coin.value() > 0) {
        transfer::public_transfer(coin, ctx.sender());
    } else {
        coin.destroy_zero();
    };

    let mut escrow_balance = escrow_coin.into_balance();

    // Process first period immediately
    let first_payment = escrow_balance.split(amount_per_period);
    transfer::public_transfer(first_payment.into_coin(ctx), merchant::get_owner(account));
    merchant::add_payment(account, amount_per_period);

    let now = clock.timestamp_ms();
    let merchant_id = object::id(account);

    // Record order_id
    df::add(merchant::uid_mut(account), key, OrderRecord {
        amount: total_required,
        timestamp_ms: now,
        coin_type: type_name::get<T>().into_string().to_string(),
    });

    // Events + subscription object creation (same as original subscribe)
    merchant::increment_subscriptions(account);
    events::emit_payment_received_v2(
        merchant_id, ctx.sender(), amount_per_period, 1, now,
        order_id, type_name::get<T>().into_string().to_string(),
    );
    events::emit_subscription_created(
        merchant_id, ctx.sender(), amount_per_period, period_ms, prepaid_periods,
    );

    transfer::share_object(Subscription<T> {
        id: object::new(ctx),
        merchant_id,
        payer: ctx.sender(),
        amount_per_period,
        period_ms,
        next_due: now + period_ms,
        balance: escrow_balance,
    });
}

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

/// Remove an order record. MerchantCap gated for cleanup.
public fun remove_order_record(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    payer: address,
    order_id: String,
) {
    assert!(merchant::get_merchant_id(cap) == object::id(account), ENotMerchantOwner);
    let key = OrderKey { payer, order_id };
    let _: OrderRecord = df::remove(merchant::uid_mut(account), key);
}
```

### 6.5 Merchant Module Changes

```move
// New public(package) accessors for dynamic field access
public(package) fun uid(account: &MerchantAccount): &UID { &account.id }
public(package) fun uid_mut(account: &mut MerchantAccount): &mut UID { &mut account.id }
```

---

## 7. Event System

### 7.1 Event Name Mapping (Stripe-style)

| Contract Event Struct | SDK Event Name | Key Payload Fields |
|----------------------|----------------|-------------------|
| `PaymentReceived` | `payment.received` | merchantId, payer, amount, paymentType, timestamp |
| `PaymentReceivedV2` | `payment.received` | merchantId, payer, amount, paymentType, timestamp, orderId, coinType |
| `SubscriptionCreated` | `subscription.created` | merchantId, payer, amountPerPeriod, periodMs, subscriptionId |
| `SubscriptionProcessed` | `subscription.processed` | merchantId, payer, amount, nextDue |
| `SubscriptionCancelled` | `subscription.cancelled` | merchantId, payer, refundedAmount |
| `SubscriptionFunded` | `subscription.funded` | merchantId, payer, fundedAmount |
| `MerchantRegistered` | `merchant.registered` | merchantId, brandName, owner |
| `MerchantPaused` | `merchant.paused` | merchantId |
| `MerchantUnpaused` | `merchant.unpaused` | merchantId |
| `YieldClaimed` | `yield.claimed` | merchantId, amount |
| `RouterModeChanged` | `router.mode_changed` | oldMode, newMode |

### 7.2 Listener API

```typescript
// Listen to specific events
const unsub = fs.on('payment.received', (event) => { ... })

// Listen to all events
fs.on('*', (event) => { ... })

// Filter by payer
fs.on('payment.received', callback, { filter: { payer: '0x...' } })

// Unsubscribe
unsub()
```

---

## 8. Error System

### 8.1 Error Hierarchy

```typescript
BaleenPayError (base)
├── PaymentError      // Payment operation failures
├── MerchantError     // Merchant management failures
├── ValidationError   // SDK pre-validation (before tx)
└── NetworkError      // RPC / connectivity issues
```

### 8.2 Three-Layer Error Interception

| Layer | When | Example |
|-------|------|---------|
| SDK validation | Before building PTB | "Invalid order ID: must be 1-64 ASCII printable characters" |
| Wallet | Signing phase | "Transaction rejected by wallet" |
| On-chain abort | After execution | "Order 'ORD-001' has already been paid (ORDER_ALREADY_PAID)" |

### 8.3 Error Code Map

| Move Code | SDK Code | Human Message |
|-----------|----------|---------------|
| 0 | `NOT_MERCHANT_OWNER` | MerchantCap doesn't match this account |
| 1, 4, 5, 9 | — | Reserved (unused in current contract) |
| 2 | `MERCHANT_PAUSED` | Merchant is paused |
| 3 | `NOT_PAYER` | Only the original payer can perform this action |
| 6 | `ALREADY_REGISTERED` | This address already has a merchant account |
| 7 | `NO_ACTIVE_SUBSCRIPTIONS` | No active subscriptions to decrement |
| 8 | `INSUFFICIENT_PRINCIPAL` | Insufficient idle principal for yield credit |
| 10 | `ZERO_AMOUNT` | Payment amount must be greater than zero |
| 11 | `NOT_DUE` | Subscription payment is not yet due |
| 12 | `ZERO_YIELD` | No yield available to claim |
| 13 | `INSUFFICIENT_PREPAID` | Not enough prepaid periods |
| 14 | `ZERO_PERIOD` | Subscription period must be greater than zero |
| 15 | `INSUFFICIENT_BALANCE` | Subscription escrow balance too low |
| 16 | `MERCHANT_MISMATCH` | Subscription doesn't belong to this merchant |
| 17 | `ZERO_PREPAID_PERIODS` | Must prepay at least one period |
| 18 | `ORDER_ALREADY_PAID` | This order has already been paid |
| 19 | `INVALID_ORDER_ID` | Order ID must be 1-64 ASCII printable characters |
| 20 | `INVALID_MODE` | Invalid router mode |
| 21 | `SAME_MODE` | Router is already in this mode |

---

## 9. Package Structure

### 9.1 Monorepo Layout

```
baleenpay/
├── move/baleenpay/          # Move contracts (existing + order_id upgrade)
├── packages/
│   ├── sdk/                 # @baleenpay/sdk
│   └── react/               # @baleenpay/react
├── apps/
│   └── demo/                # Demo app (checkout + merchant dashboard)
├── package.json             # workspace root
├── pnpm-workspace.yaml
└── turbo.json
```

### 9.2 Dependency Pyramid

```
@baleenpay/react
    ├── @baleenpay/sdk          (core)
    ├── @mysten/dapp-kit  (wallet + React hooks)
    └── react                   (peer dependency)

@baleenpay/sdk
    ├── @mysten/sui             (SUI TypeScript SDK)
    └── zero UI dependencies    (works in Node.js, any framework)
```

### 9.3 Build & Publish

| Package | Format | Target |
|---------|--------|--------|
| `@baleenpay/sdk` | ESM + CJS + types (tsup) | Browser + Node.js |
| `@baleenpay/react` | ESM + types (tsup) | Browser only |
| Demo app | Next.js | Not published |

---

## 10. Security Model

### 10.1 Key Layers (Phase 1)

| Key Type | Scope | Contains | Risk if Leaked |
|----------|-------|----------|---------------|
| `pk_` (config) | Frontend | packageId, network, merchantId | None — all public info |

Phase 2/3 additions: `sk_` (server API access), `whsec_` (webhook signing).

### 10.2 On-Chain Privacy

- All contract state is publicly visible (by design)
- PII must never be stored on-chain — SDK rejects PII fields
- Yield routing strategy kept off-chain (Phase 3 Hosted API)
- Wallet private keys never touched by SDK — signing delegated to wallet adapter

### 10.3 Contract Security (from review)

- Order ID scoped to payer address — prevents front-running/squatting
- ASCII-only validation — prevents Unicode normalization attacks
- `remove_order_record` gated by MerchantCap — cleanup capability
- `min_payment_amount` deferred to Phase 2

---

## 11. Relationship to Existing Plans

Original Task 9-16 (frontend development) is subsumed by this SDK design:

| Original Plan | New Position |
|---------------|-------------|
| Checkout widget | `@baleenpay/react` CheckoutButton + PaymentForm |
| Merchant dashboard | Demo app using SDK merchant hooks |
| lib/sui/ abstraction | `@baleenpay/sdk` (more general, reusable) |

The SDK is the "productized" version of the original frontend plan.

---

## 12. Future Expansion (Phase 2-3 Backlog)

Recorded for future reference (from Full Platform approach B):

### Phase 2: `@baleenpay/server`
- Webhook verification (whsec_)
- Event → Webhook relay (lightweight indexer)
- Server-side idempotency

### Phase 3: BaleenPay Cloud
- REST API Gateway (/v1/payments, /v1/merchants...)
- API Key Management (pk_/sk_/whsec_)
- Hosted Checkout Page (pay.baleenpay.io)
- Dashboard API
- Usage Metering + Billing
- Protocol fee module (contract-layer fee)
- `min_payment_amount` per merchant
