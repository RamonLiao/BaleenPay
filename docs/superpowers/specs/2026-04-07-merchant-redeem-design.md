# Merchant Self-Service Redeem Design

**Date:** 2026-04-07
**Status:** Approved
**Scope:** Move contracts + SDK — merchant-driven redemption from StableLayer

## Problem

BaleenPay currently has no path for merchants to retrieve principal that has been deposited into StableLayer for yield farming. The keeper (AdminCap) sends USDC to StableLayer via `mint → farm::receive`, but there is no reverse flow. Merchants can only claim yield (USDB), not redeem their principal back to USDC.

Additionally, `keeper_withdraw` does not deduct `idle_principal` from the merchant, creating an accounting mismatch between on-chain state and actual vault balance.

## Design Principles

1. **Merchant autonomy** — merchants trigger their own redemptions via MerchantCap, no keeper involvement needed
2. **Keeper for compliance only** — AdminCap used solely for regulatory freeze (pause/unpause)
3. **SDK wraps complexity** — Web2 developers call `sdk.merchant.withdraw(amount)`, SDK handles PTB construction and routing
4. **Standard StableLayer integration** — use the protocol's native `request_burn → farm::pay → fulfill_burn` flow

## StableLayer Protocol Analysis

### Mint Flow (existing)
```
PTB:
1. stable_layer::mint<Stablecoin, USDC, FarmEntity>(registry, usdcCoin)
   → (Coin<Stablecoin>, Loan)
2. farm::receive<Stablecoin, USDC>(farmRegistry, loan, clock)
   → consumes Loan hot-potato
Result: Coin<Stablecoin> stays with caller, Farm records USDC debt
```

### Burn Flow (to implement)
```
PTB:
1. stable_layer::request_burn<Stablecoin, USDC>(registry, stablecoinCoin)
   → Request hot-potato
2. farm::pay<Stablecoin, USDC>(farmRegistry, clock, &mut request)
   → Farm clears USDC debt
3. stable_layer::fulfill_burn<Stablecoin, USDC>(registry, request)
   → Coin<USDC>
```

Key insight: `farm::receive` consumes a `Loan` (by value), `farm::pay` takes `&mut Request` (mutable ref). The `Request` is then consumed by `fulfill_burn`. Three-step atomic settlement.

## Architecture

### On-Chain Fund Flow

```
Customer ──pay──→ Vault<USDC>
                    ↓ keeper_deposit_to_farm (automated)
                    ↓ idle_principal → farming_principal
                    ↓ USDC → mint → Stablecoin
                    ↓
              StablecoinVault<Stablecoin>
                    ↓ take_stablecoin (MerchantCap, self-service)
                    ↓ request_burn → farm::pay → fulfill_burn
                    ↓
              Coin<USDC> → Merchant wallet

Keeper regulatory: pause_merchant / unpause_merchant
                   (freezes ALL merchant operations)
```

### Move Contract Changes

#### `merchant.move`

**farming_principal tracking via dynamic field (Option B):**

Use a dynamic field keyed by a marker struct to store `farming_principal` on MerchantAccount. This avoids breaking the existing struct layout and requires no migration.

```move
public struct FarmingPrincipalKey has copy, drop, store {}

// Package-internal mutators
public(package) fun move_to_farming(account: &mut MerchantAccount, amount: u64)
  // assert idle_principal >= amount
  // idle_principal -= amount
  // dynamic_field farming_principal += amount

public(package) fun return_from_farming(account: &mut MerchantAccount, amount: u64)
  // dynamic_field farming_principal -= amount

public fun get_farming_principal(account: &MerchantAccount): u64
  // read dynamic field, default 0
```

#### `router.move`

**New shared object:**
```move
public struct StablecoinVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}
```

**New/modified functions:**

| Function | Auth | Purpose |
|----------|------|---------|
| `create_stablecoin_vault<T>` | AdminCap | Create shared StablecoinVault |
| `keeper_deposit_to_farm<T, S>` | AdminCap | Deposit Stablecoin into StablecoinVault + update merchant accounting (idle→farming) |
| `take_stablecoin<T>` | MerchantCap | Withdraw Stablecoin for burn (deducts farming_principal). Returns `Coin<T>` for PTB composition with StableLayer |
| `merchant_withdraw<T>` | MerchantCap | (existing) Withdraw idle USDC from Vault |
| `claim_yield_v2<T>` | MerchantCap | (existing) Claim USDB yield |

**`keeper_deposit_to_farm` replaces the current broken `keeper_withdraw`:**
- Deducts `idle_principal` from merchant
- Adds to `farming_principal` (dynamic field)
- Stores Stablecoin in StablecoinVault
- Old `keeper_withdraw` is kept for backward compat but should be deprecated

#### `events.move`

New events:
- `FarmDeposited { merchant_id, amount }` — keeper deposits to StableLayer
- `FarmRedeemed { merchant_id, amount }` — merchant redeems from StableLayer
- `MerchantWithdrawn { merchant_id, vault_id, amount }` — (already added) merchant withdraws idle

### SDK Changes

#### `StableLayerClient` — new method

```typescript
buildRedeemTx({ tx, stablecoinCoin }: BuildRedeemOptions): TransactionArgument
  // 1. request_burn<Stablecoin, USDC>(registry, stablecoinCoin) → Request
  // 2. farm::pay<Stablecoin, USDC>(farmRegistry, clock, &mut request)
  // 3. fulfill_burn<Stablecoin, USDC>(registry, request) → Coin<USDC>
```

#### `keeper.ts` — modify `buildKeeperDeposit`

Currently the minted Stablecoin is a dead value (unused). Fix to:
1. Accept `stablecoinVaultId` and `merchantId` params
2. Deposit Stablecoin into StablecoinVault via `keeper_deposit_to_farm`
3. Update merchant's idle→farming accounting

#### New: `merchant.ts` — high-level merchant API

```typescript
class MerchantClient {
  // Smart withdrawal: auto-routes idle vs redeem
  async withdraw(amount: bigint): Promise<TransactionResult>
    // 1. Query merchant balance (idle vs farming)
    // 2. If idle >= amount → merchant_withdraw (single call)
    // 3. If idle < amount → take_stablecoin + StableLayer burn + transfer remainder from idle
    // 4. Build and return unsigned TX for wallet signing

  async claimYield(): Promise<TransactionResult>
    // Wraps claim_yield_v2

  async getBalance(): Promise<MerchantBalance>
    // { idle, farming, yield, total }
    // Reads MerchantAccount fields + dynamic field
}
```

## Migration Strategy (Option B — Dynamic Field)

**Chosen approach:** Dynamic field for `farming_principal`. No struct change, no migration needed.

- First access to `farming_principal` on existing MerchantAccounts returns 0 (default)
- `move_to_farming` lazily initializes the dynamic field on first call
- Existing `idle_principal` semantics unchanged

## Future: Migration Function (Option A — for reference)

When moving to mainnet with a clean deploy, or if a struct-level change is preferred:

```move
public fun migrate_merchant_v2(
    _admin: &AdminCap,
    account: &mut MerchantAccount,
) {
    // Add farming_principal field to struct
    // Set initial value = 0
    // Copy dynamic field value if exists, then remove dynamic field
}
```

This requires:
1. Package upgrade with new struct definition
2. Admin calls `migrate_merchant_v2` for each existing MerchantAccount
3. SDK version bump to handle both v1 and v2 accounts during transition

**Decision:** Use Option A for mainnet production deploy. Use Option B (dynamic field) for testnet iteration.

## Security Considerations

- `take_stablecoin` checks: MerchantCap ownership, not paused, farming_principal >= amount
- Vault balance check is implicit (Balance::split aborts on insufficient)
- Keeper cannot redeem on behalf of merchant (no AdminCap override for take_stablecoin)
- Pause freezes ALL merchant operations (withdraw, redeem, claim)

## Testing Plan

- Unit: `move_to_farming` / `return_from_farming` accounting
- Unit: `take_stablecoin` auth checks (wrong cap, paused, insufficient)
- Integration: full PTB mock (deposit → redeem → verify balances)
- Red team: overflow, double-redeem, race between keeper deposit and merchant redeem

## Object IDs (Testnet — will change after upgrade)

| Object | Current ID |
|--------|-----------|
| StableLayer Package | `0x9c248c80c3a757167780f17e0c00a4d293280be7276f1b81a153f6e47d2567c9` |
| StableRegistry | `0xfa0fd96e0fbc07dc6bdc23cc1ac5b4c0056f4b469b9db0a70b6ea01c14a4c7b5` |
| Farm Package | `0x3a55ec8fabe5f3e982908ed3a7c3065f26e83ab226eb8d3450177dbaac25878b` |
| FarmRegistry | `0xc3e8d2e33e36f6a4b5c199fe2dde3ba6dc29e7af8dd045c86e62d7c21f374d02` |
| StablecoinVault | TBD (create after upgrade) |
