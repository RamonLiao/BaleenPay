# BaleenPay StableLayer Integration — Design Spec

**Date**: 2026-03-27
**Status**: Approved
**Scope**: Full-stack — Move contract + SDK + React + Dashboard yield visualization

---

## 1. System Overview

### Purpose

Integrate StableLayer yield protocol into BaleenPay so that SaaS payment float (idle USDC) automatically earns yield via StableLayer's USDC Yield Aggregator. Merchants see accumulated yield on their dashboard and can claim it as USDB.

### Roles

| Role | Identity | Operations |
|------|----------|------------|
| **Payer** | SaaS end-user | Pay USDC via `pay_once_routed` / `subscribe_routed` |
| **Merchant** | SaaS platform | View dashboard, claim yield (USDB) |
| **Admin/Keeper** | BaleenPay operator | Batch deposit vault→StableLayer, harvest yield, distribute to merchants |

### Fund Flow

```
Payer USDC ──pay──→ [BaleenPay Vault<USDC>] ──keeper batch──→ [StableLayer Yield Pool]
                                                                     │
                                                                yield accrues
                                                                     │
[Merchant wallet] ←──claim USDB──── [YieldVault<USDB>] ←──keeper──── [USDB reward]
```

### Key Design Principles

- Contract holds actual funds (Vault) — on-chain verifiable, not ledger-only
- All StableLayer interactions happen in Admin/Keeper PTBs — ownership stays with BaleenPay operator
- Merchant sees only `idle_principal` + `accrued_yield` — no exposure to StableLayer/USDB internals
- MVP: claim as USDB. Phase 2: auto-swap to USDC via DEX

---

## 2. Module Architecture

### File Changes

```
floatsync/sources/
├── merchant.move      ← modify: +credit_external_yield, claim_yield takes YieldVault
├── payment.move       ← modify: +pay_once_routed, +subscribe_routed (router-aware)
├── router.move        ← major: +MODE_STABLELAYER, +Vault, +YieldVault, +keeper ops
├── events.move        ← modify: +VaultDeposited, +VaultWithdrawn, +YieldCredited
├── brand_usd.move     ← no change
└── tests/
    ├── vault_tests.move          ← new
    ├── routed_payment_tests.move ← new
    └── keeper_tests.move         ← new
```

### Module Responsibilities

| Module | Change Scope | Responsibility |
|--------|-------------|----------------|
| **router.move** | Major | Vault management (hold USDC), mode routing, keeper deposit/withdraw |
| **merchant.move** | Minor | +`credit_external_yield` (no principal deduction), `claim_yield` from vault |
| **payment.move** | Medium | +`pay_once_routed` / `subscribe_routed` — mode-aware coin routing |
| **events.move** | Minor | +3 new event types |

### Capability Model

```
AdminCap (existing)
  ├── set_mode()           — switch router mode
  ├── set_keeper()         — set keeper address
  ├── create_vault()       — create Vault<T>
  ├── create_yield_vault() — create YieldVault<T>
  ├── keeper_withdraw()    — vault USDC → StableLayer (via SDK PTB)
  ├── keeper_deposit_yield() — credit yield to merchant
  └── pause/unpause        — existing

MerchantCap (existing)
  ├── claim_yield()        — withdraw USDB from YieldVault
  └── self_pause/unpause   — existing
```

No new capability types. AdminCap doubles as keeper role for MVP.

### Dependencies

```
payment.move → merchant.move, router.move, events.move
router.move  → merchant.move, events.move
merchant.move → events.move
```

No circular dependencies.

---

## 3. Data Structures

### RouterConfig (modified)

```move
public struct RouterConfig has key {
    id: UID,
    mode: u8,          // 0=fallback, 1=stablelayer
    keeper: address,   // authorized keeper address
}
```

### Vault (new)

```move
/// Shared vault holding USDC awaiting StableLayer deposit.
public struct Vault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
    total_deposited: u64,         // lifetime deposited to StableLayer
    total_yield_harvested: u64,   // lifetime USDB harvested
}
```

### YieldVault (new)

```move
/// Holds USDB rewards from StableLayer, claimable by merchants.
public struct YieldVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}
```

### MerchantAccount (unchanged struct)

Existing fields reused:
- `idle_principal` — merchant's principal balance (vault + StableLayer pool combined)
- `accrued_yield` — claimable USDB amount

### New Events

```move
public struct VaultDeposited has copy, drop {
    vault_id: ID,
    amount: u64,
    merchant_id: ID,
    payer: address,
    timestamp: u64,
}

public struct VaultWithdrawn has copy, drop {
    vault_id: ID,
    amount: u64,
    keeper: address,
    timestamp: u64,
}

public struct YieldCredited has copy, drop {
    merchant_id: ID,
    amount: u64,
    source: u8,    // 0=manual, 1=stablelayer
    timestamp: u64,
}
```

---

## 4. Core Functions

### Router Module (new/modified)

```move
// Vault lifecycle
public fun create_vault<T>(_admin: &AdminCap, ctx: &mut TxContext)
public fun create_yield_vault<T>(_admin: &AdminCap, ctx: &mut TxContext)
public fun set_keeper(_admin: &AdminCap, config: &mut RouterConfig, keeper: address)

// Payment routing (called by payment module only — not externally callable)
public(package) fun route_payment<T>(
    config: &RouterConfig,
    account: &mut MerchantAccount,
    vault: &mut Vault<T>,
    coin: Coin<T>,
    clock: &Clock,
    ctx: &TxContext,
)
// assert mode == MODE_STABLELAYER (no fallback branch — SDK uses pay_once_v2 for fallback)
// coin → vault.balance, emit VaultDeposited

// Keeper operations (AdminCap-gated)
public fun keeper_withdraw<T>(
    _admin: &AdminCap,
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T>
// Returns Coin<T> for same-PTB StableLayer deposit

public fun keeper_deposit_yield<T>(
    _admin: &AdminCap,
    yield_vault: &mut YieldVault<T>,
    account: &mut MerchantAccount,
    coin: Coin<T>,
)
// amount derived from coin.value() (single source of truth)
// coin → yield_vault.balance, merchant.accrued_yield += coin.value()
```

### Payment Module (modified)

```move
// New — router-aware payment
public fun pay_once_routed<T>(
    config: &RouterConfig,
    account: &mut MerchantAccount,
    vault: &mut Vault<T>,
    coin: Coin<T>,
    order_id: String,
    clock: &Clock,
    ctx: &TxContext,
)
// validate order_id + dedup, call router::route_payment, emit PaymentReceivedV2

// subscribe_routed<T> — same pattern, escrow unchanged
// process_subscription — modified to call route_payment for period payments
```

Existing `pay_once` / `pay_once_v2` retained for MODE_FALLBACK. SDK selects function based on router mode query:
- mode=0 → `pay_once_v2` (no Vault object needed, no shared object contention)
- mode=1 → `pay_once_routed` (Vault required)

### Merchant Module (modified)

```move
// Modified — takes YieldVault, transfers actual coin
public fun claim_yield<T>(
    cap: &MerchantCap,
    account: &mut MerchantAccount,
    yield_vault: &mut YieldVault<T>,
    ctx: &mut TxContext,
)
// assert !paused, cap match, accrued_yield > 0
// yield_vault.balance.split(amount) → transfer to merchant.owner
// account.accrued_yield = 0

// New — external yield credit (does NOT deduct idle_principal)
public(package) fun credit_external_yield(account: &mut MerchantAccount, amount: u64)
// account.accrued_yield += amount
```

### Function Call Chains

```
pay_once_routed ──→ router::route_payment ──→ vault.balance.join (mode 1 only)
  (SDK only calls pay_once_routed when mode=1; mode=0 uses pay_once_v2 directly)

keeper_withdraw ──→ [SDK PTB: StableLayer.mint → vault_farm.receive]

keeper_deposit_yield ──→ merchant::credit_external_yield
                     ──→ yield_vault.balance.join

claim_yield ──→ yield_vault.balance.split → transfer to merchant
```

---

## 5. Security Considerations

### Attack Vector Analysis

| # | Vector | Risk | Defense |
|---|--------|------|---------|
| 1 | Fake deposit — call `keeper_deposit_yield` to inflate accrued_yield | HIGH | AdminCap gated. YieldVault holds actual USDB; claim can't exceed vault balance |
| 2 | Keeper drains vault — `keeper_withdraw` all USDC without depositing to StableLayer | HIGH | AdminCap = keeper = same trusted party (BaleenPay operator). Future: withdraw cap per epoch, timelock, multi-sig |
| 3 | YieldVault insufficient — multiple merchants claim simultaneously | MEDIUM | `balance.split(amount)` auto-aborts on insufficient. First-come-first-served. Keeper must harvest frequently |
| 4 | Router mode switch race — admin flips mode during user PTB | LOW | SUI object versioning ensures shared object ordering within epoch. Worst case: payment goes to wrong destination but funds are safe |
| 5 | Subscription refund in vault mode | MEDIUM | `cancel_subscription` refunds from subscription.balance (not vault). Only `process_subscription` payments go through route_payment. Independent paths |

### Invariants

```
1. vault.balance >= sum of USDC not yet deposited to StableLayer
2. yield_vault.balance >= sum of all merchants' accrued_yield
3. keeper_withdraw(amount) requires amount <= vault.balance
4. claim_yield(amount) requires amount <= yield_vault.balance
5. credit_external_yield only increases accrued_yield, never decreases idle_principal
```

Note: Invariant 1 is temporarily broken after keeper_withdraw (USDC moves to StableLayer pool). `idle_principal` semantically covers "vault + StableLayer pool" combined. On-chain verification of StableLayer pool balance is not possible — this is an operator trust model tradeoff.

### Phase 2 Risks (noted for future)

- **Multi-vault type safety**: `claim_yield<T>` is generic — if multiple YieldVault types exist (e.g., `YieldVault<USDB>` + `YieldVault<USDC>` after Phase 2 auto-swap), merchant could claim `accrued_yield` from any vault with sufficient balance. Fix: store yield coin type in MerchantAccount or constrain at router level.
- **Keeper batch scalability**: `keeper_deposit_yield` processes one MerchantAccount per call. At scale (100+ merchants), consider a batch version that takes a vector of (merchant_id, amount) pairs.

### Pause Behavior

| Operation | Admin freeze | Self pause | Notes |
|-----------|-------------|------------|-------|
| pay_once_routed | blocked | blocked | Same as existing |
| keeper_withdraw | allowed | N/A | Admin can manage funds during freeze |
| keeper_deposit_yield | allowed | N/A | Yield distribution unaffected by pause |
| claim_yield | blocked | blocked | Same as existing |
| cancel_subscription | blocked (admin) | allowed | Consumer protection preserved |

---

## 6. SDK Integration

### New SDK Structure

```
packages/sdk/src/
├── stablelayer/
│   ├── client.ts          — StableLayerClient wrapper
│   ├── transactions.ts    — PTB builders: mint, claim, deposit-to-pool
│   └── constants.ts       — bUSD coin type, testnet/mainnet addresses
├── transactions/
│   ├── pay.ts             — +buildPayOnceRouted
│   ├── yield.ts           — +buildClaimYieldFromVault
│   ├── keeper.ts          — new: buildKeeperDeposit, buildKeeperHarvest
│   └── ...existing
├── client.ts              — +payRouted(), claimYield() revised, +keeper methods
└── types.ts               — +StableLayerConfig, KeeperParams, YieldInfo
```

### PTB Composition Patterns

**User payment (mode=stablelayer):**
```typescript
// buildPayOnceRouted — single moveCall, contract handles mode internally
const tx = new Transaction()
const coin = prepareCoin(tx, sender, 'USDC', amount)
tx.moveCall({
  target: `${packageId}::payment::pay_once_routed`,
  typeArguments: [USDC_TYPE],
  arguments: [routerConfig, merchantAccount, vault, coin, orderId, clock],
})
```

**Keeper batch deposit:**
```typescript
const tx = new Transaction()
// 1. Withdraw USDC from vault
const usdcCoin = tx.moveCall({
  target: `${packageId}::router::keeper_withdraw`,
  typeArguments: [USDC_TYPE],
  arguments: [adminCap, vault, tx.pure.u64(amount)],
})
// 2. StableLayer mint bUSD (autoTransfer=false → stays in PTB)
stableClient.buildMintTx({ tx, stableCoinType: BUSD_TYPE, usdcCoin, autoTransfer: false })
// 3. bUSD auto-deposited to StableLayer yield pool (mint flow includes receive)
```

**Keeper harvest yield:**
```typescript
const tx = new Transaction()
// 1. StableLayer claim → USDB coin
const usdbCoin = stableClient.buildClaimTx({ tx, stableCoinType: BUSD_TYPE, autoTransfer: false })
// 2. Deposit USDB to YieldVault + credit merchant
tx.moveCall({
  target: `${packageId}::router::keeper_deposit_yield`,
  typeArguments: [USDB_TYPE],
  arguments: [adminCap, yieldVault, merchantAccount, usdbCoin],
})
```

### FloatSync Client Changes

```typescript
class FloatSync {
  // New
  async payRouted(params: PayParams, sender: string): Promise<TransactionResult>
  async getYieldInfo(merchantId?: ObjectId): Promise<YieldInfo>

  // Modified
  async claimYield(merchantCapId: string, coinType?: string): Promise<TransactionResult>

  // Keeper methods (admin only)
  async keeperDeposit(amount: bigint): Promise<TransactionResult>
  async keeperHarvest(merchantId: ObjectId, amount: bigint): Promise<TransactionResult>
}

interface YieldInfo {
  idlePrincipal: bigint
  accruedYield: bigint
  claimableUsdb: bigint       // from StableLayer query
  estimatedApy: number        // calculated from recent yield events
  vaultBalance: bigint        // USDC in vault (not yet deposited)
}
```

### Dependencies

```json
{
  "dependencies": {
    "stable-layer-sdk": "^3.1.0",
    "@bucket-protocol/sdk": "^2.1.0"
  }
}
```

---

## 7. Dashboard Yield Visualization

### Page Structure

```
Dashboard Page
├── Summary Cards (existing + extended)
│   ├── Idle Principal (USDC in system)
│   ├── Accrued Yield (claimable USDB)
│   └── Estimated APY (%)
├── Yield Section (new)
│   ├── Yield Trend Chart (cumulative curve + APY history)
│   ├── Claim History Table (YieldClaimed events)
│   └── Claim Button + tx status
└── existing sections
```

### Data Source Strategy (Hybrid)

| Data | Source | Refresh |
|------|--------|---------|
| idle_principal, accrued_yield | gRPC `getObject` MerchantAccount | Real-time query |
| Claimable USDB | `StableLayerClient.getClaimRewardUsdbAmount()` | 30s poll |
| Yield history anchors | GraphQL `events(type: YieldCredited)` | On page load |
| APY curve | Calculated from yield event deltas | Static calculation |
| Real-time tail | Poll claimable + localStorage time-series | 30s append |
| Claim history | GraphQL `events(type: YieldClaimed)` | On page load |

### React Hooks (new)

```typescript
useYieldInfo(merchantId?: string): {
  idlePrincipal: bigint
  accruedYield: bigint
  claimableUsdb: bigint
  estimatedApy: number
  isLoading: boolean
  refetch: () => void
}

useYieldHistory(merchantId?: string): {
  dataPoints: { timestamp: number; cumulativeYield: number; apy: number }[]
  claimEvents: { timestamp: number; amount: bigint; txDigest: string }[]
  isLoading: boolean
}

useClaimYield(): {
  claim: (merchantCapId: string) => void
  status: 'idle' | 'building' | 'signing' | 'confirming' | 'success' | 'error'
  error: Error | null
  txDigest: string | null
  reset: () => void
}
```

### Trend Chart

- **X axis**: Time (7d / 30d / All toggle)
- **Y axis left**: Cumulative Yield (USDB)
- **Y axis right**: APY %
- **Data construction**: GraphQL events as anchors → linear interpolation → localStorage poll tail
- **APY calculation**: `(yield_delta / principal) * (365d / time_delta) * 100`
- **Chart library**: `recharts`

---

## 8. Testing Strategy

### Move Contract Tests (~31 new)

| Category | Tests | Count |
|----------|-------|-------|
| Vault unit | create, deposit, withdraw, balance | 6 |
| Route payment | mode=0 direct, mode=1 vault, mode switch, paused | 5 |
| Keeper ops | withdraw success, withdraw > balance, deposit_yield, credit | 5 |
| Claim yield v2 | from vault, insufficient, paused, zero | 4 |
| credit_external_yield | normal, idle_principal unchanged | 2 |
| Integration | pay→vault→withdraw→claim full flow, subscription routed | 3 |
| Monkey | withdraw(0), withdraw(u64::MAX), concurrent drain, mode flip, dup vault | 6 |

### SDK Tests (~26 new)

| Category | Tests | Count |
|----------|-------|-------|
| StableLayer wrapper | init, constants, buildMintTx, buildClaimTx | 5 |
| buildPayOnceRouted | mode=0, mode=1, missing vault | 3 |
| buildKeeperDeposit | PTB structure, amount validation | 3 |
| buildKeeperHarvest | PTB structure, merchant credit | 3 |
| buildClaimYieldFromVault | success, zero yield | 2 |
| YieldInfo query | deserialization, StableLayer mock | 3 |
| Integration | full lifecycle | 2 |
| Monkey | amount=0, > vault, invalid coin, init failure, concurrent | 5 |

### React Tests (~25 new)

| Category | Tests | Count |
|----------|-------|-------|
| useYieldInfo | loading, data, refetch, polling, error | 5 |
| useYieldHistory | loading, data points, claims, localStorage, empty | 5 |
| useClaimYield | idle, success, error, paused, reset, reject | 6 |
| Dashboard yield section | cards, chart, claim button, disabled | 5 |
| Monkey | rapid clicks, yield=0, zero data, localStorage corrupt | 4 |

### Totals

```
Move:    ~144 (113 existing + 31 new)
SDK:     ~179 (153 existing + 26 new)
React:   ~95  (70 existing + 25 new)
Total:   ~418
```

---

## 9. Deployment Plan

### Execution Order

```
Phase 1: Move contract (fresh deploy)
  → build + test → deploy testnet → record all object IDs

Phase 2: SDK stablelayer/ module
  → integrate stable-layer-sdk → unit tests → build

Phase 3: SDK client + transaction builders
  → payRouted, keeper methods, claimYield revised → integration tests

Phase 4: React hooks + Dashboard UI
  → useYieldInfo, useYieldHistory, useClaimYield → component tests

Phase 5: Demo App update
  → Dashboard yield section → connect testnet

Phase 6: Testnet smoke test
  → full flow: register → pay → keeper deposit → harvest → claim
```

### Post-Deploy Object IDs to Record

| Object | Source | Usage |
|--------|--------|-------|
| PackageID | `sui client publish` | SDK constants |
| RouterConfig | `init()` | query mode, pay_once_routed |
| AdminCap | `init()` → deployer | Keeper operations |
| MerchantRegistry | `init()` | register_merchant |
| Vault\<USDC\> | `create_vault()` | pay_once_routed, keeper_withdraw |
| YieldVault\<USDB\> | `create_yield_vault()` | keeper_deposit_yield, claim_yield |

### Smoke Test Checklist

```
1. Deploy → record all IDs
2. create_vault<USDC> + create_yield_vault<USDB>
3. set_mode(1) → MODE_STABLELAYER
4. set_keeper(admin_address)
5. register_merchant
6. pay_once_routed<USDC> → verify coin in vault
7. keeper_withdraw → StableLayer.mint(bUSD) → verify deposit
8. StableLayer.claim → keeper_deposit_yield → verify merchant accrued_yield
9. claim_yield → verify USDB transferred to merchant
10. MODE_FALLBACK: pay_once_routed → verify direct transfer
11. Pause: admin freeze blocks pay + claim
```

### StableLayer Testnet Info

- bUSD Coin Type: `0xe25a20601a1ecc2fa5ac9e5d37b52f9ce70a1ebe787856184ffb7dbe31dba4c1::stable_layer::Stablecoin`
- StableLayer Package (testnet): `0x9c248c80c3a757167780f17e0c00a4d293280be7276f1b81a153f6e47d2567c9`
- StableLayer Registry (testnet): `0xfa0fd96e0fbc07dc6bdc23cc1ac5b4c0056f4b469b9db0a70b6ea01c14a4c7b5`
- Mock Farm Package: `0x3a55ec8fabe5f3e982908ed3a7c3065f26e83ab226eb8d3450177dbaac25878b`
- Mock Farm Registry: `0xc3e8d2e33e36f6a4b5c199fe2dde3ba6dc29e7af8dd045c86e62d7c21f374d02`
- Testnet USDC: `0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC`
- Publish TX: `Afz6BGpNVWVc6utybvPwdDkFzk5ZX8Z7fYvk6KvfAxro`
- Register + Mint TX: `5YqVPTxydvook76ZYvqEsYDdkgMQ237VhEKtMQ88RpAV`
- SDK: `stable-layer-sdk@3.1.0` (compatible with `@mysten/sui@^2.8.0`)
- Testnet vault/yield constants are empty — uses mock farm path
- Mock farm may not produce real yield — keeper_harvest testing may require manual USDB injection
