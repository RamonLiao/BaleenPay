# Per-Coin-Type Yield Tracking Design Spec

**Date**: 2026-04-07
**Status**: Approved
**Scope**: merchant.move, router.move, SDK client.ts

## Problem

`accrued_yield: u64` on `MerchantAccount` is a single counter that doesn't distinguish coin types. `claim_yield_v2<T>` withdraws from a specific `YieldVault<T>`, so when yield is credited from multiple coin types (e.g., USDB from farm + Stablecoin from other sources), `accrued_yield` and vault balance diverge. This causes `balance.split(amount)` abort when the vault balance < accrued_yield.

## Solution

Replace the single `accrued_yield: u64` struct field with per-type dynamic fields keyed by `AccruedYieldKey<phantom T>`. Same pattern as existing `FarmingPrincipalKey`.

## Move Changes

### merchant.move

#### New error constant
```move
#[error]
const EAlreadyMigrated: u64 = 28; // admin_migrate_yield already called for this type
```

#### New struct
```move
public struct AccruedYieldKey<phantom T> has copy, drop, store {}
```

#### New functions

```move
/// Credit yield per coin type — writes to dynamic field.
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

/// Reset yield for specific coin type — removes dynamic field, returns amount.
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

/// Getter for typed accrued yield.
public fun get_accrued_yield_typed<T>(account: &MerchantAccount): u64 {
    let key = AccruedYieldKey<T> {};
    if (dynamic_field::exists_(&account.id, key)) {
        *dynamic_field::borrow<AccruedYieldKey<T>, u64>(&account.id, key)
    } else {
        0
    }
}
```

#### Existing functions — changes

- `credit_external_yield()`: **Keep** (can't remove `public(package)` in compatible upgrade). Change body to forward to `credit_external_yield_typed` — but this function has no type parameter, so it **cannot** forward. Instead: make it a no-op that writes to struct field only (deprecated path). All production callers (router.move) will be updated to call `credit_external_yield_typed<T>` directly.

- `reset_accrued_yield()`: **Keep** (same reason). Change body to return 0 and skip assert — or keep existing logic for backward compat. Since `claim_yield_v2` will be updated to call `reset_accrued_yield_typed<T>`, the old function becomes unused in production. Keep as-is for safety.

- `get_accrued_yield()`: **Keep**. Returns struct field (will be 0 after migration). Add comment marking as deprecated.

- `accrued_yield` struct field: **Keep** (can't remove). Set to 0 after migration. Not written to by any production path post-upgrade.

#### Migration function

```move
/// One-time migration: move accrued_yield struct field value into AccruedYieldKey<T> df.
/// Admin calls once per merchant per yield type after upgrade.
/// Guard: asserts df does NOT already exist to prevent accidental double-call
/// (which would double-count the legacy amount via credit_external_yield_typed's += logic).
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
```

#### Admin correction function

```move
/// Admin sets accrued yield for a specific type. For fixing historical accounting errors.
/// Emits event for audit trail.
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
    // Also zero out legacy struct field as safety measure
    account.accrued_yield = 0;
    events::emit_yield_corrected(object::id(account), new_amount);
}
```

### router.move

#### Changed functions

- `keeper_deposit_yield<T>`: Change `merchant::credit_external_yield(account, amount)` → `merchant::credit_external_yield_typed<T>(account, amount)`

- `claim_yield_v2<T>`: Change `merchant::reset_accrued_yield(cap, account)` → `merchant::reset_accrued_yield_typed<T>(cap, account)`

#### No signature changes — SDK transaction builders unaffected.

### events.move

Add new event:

```move
public(package) fun emit_yield_corrected(merchant_id: ID, new_amount: u64) {
    event::emit(YieldCorrected { merchant_id, new_amount });
}
```

### Test helpers

```move
#[test_only]
public fun credit_external_yield_typed_for_testing<T>(account: &mut MerchantAccount, amount: u64) {
    credit_external_yield_typed<T>(account, amount);
}
```

## SDK Changes

### client.ts

`getMerchantInfo()` currently reads `fields.accrued_yield` (struct field). After migration this is always 0.

**Change**: Add `getAccruedYieldTyped(merchantId, coinType)` that calls the on-chain getter via `devInspectTransactionBlock`:

```typescript
async getAccruedYieldTyped(merchantId: string, coinType: string): Promise<bigint> {
    const tx = new Transaction()
    tx.moveCall({
        target: `${this.config.packageId}::merchant::get_accrued_yield_typed`,
        typeArguments: [coinType],
        arguments: [tx.object(merchantId)],
    })
    const result = await this.grpcClient.devInspectTransactionBlock({
        sender: '0x0',
        transactionBlock: tx,
    })
    // Parse return value (u64)
    const returnValue = result.results?.[0]?.returnValues?.[0]
    if (!returnValue) return 0n
    const bytes = new Uint8Array(returnValue[0])
    return new DataView(bytes.buffer).getBigUint64(0, true)
}
```

`getMerchantInfo()` response type: `accruedYield` field becomes deprecated (always 0). Add `accruedYieldByType` or let callers use `getAccruedYieldTyped()` directly.

### Transaction builders — NO CHANGES

`buildKeeperHarvest`, `buildKeeperDepositYield`, `buildClaimYield` all use the same Move function targets with same signatures. Internal Move logic change is transparent to SDK.

## Deployment / Migration Plan

1. **Upgrade** package to v3
2. **Immediately** call `admin_migrate_yield<USDB>(admin, merchant)` — moves 81 → df, clears struct field
3. **Then** call `admin_set_yield<USDB>(admin, merchant, 80)` — correct to match YieldVault<USDB> balance (80)
4. **Verify**: `get_accrued_yield_typed<USDB>(merchant)` == 80, `get_accrued_yield(merchant)` == 0, `YieldVault<USDB>.balance` == 80
5. **Resume** normal operations

Steps 1-3 can be a single PTB for atomicity. Step 2+3 can be collapsed: just `admin_set_yield<USDB>(admin, merchant, 80)` directly (it also zeros struct field).

**Note**: `admin_migrate_yield` uses `df::add` directly (not `credit_external_yield_typed`) and has an `EAlreadyMigrated` guard to prevent double-call, which would otherwise double-count the legacy amount.

## Security

- `admin_migrate_yield` / `admin_set_yield`: AdminCap gated ✅
- `emit_yield_corrected` event for audit trail ✅
- `phantom T` prevents cross-type access ✅
- `df::remove` on claim prevents double-claim ✅
- Old `credit_external_yield()` becomes dead code in production — safe ✅

## What Does NOT Change

- `YieldVault<T>` struct — unchanged
- `StablecoinVault<T>` / `Vault<T>` — unchanged
- `FarmingPrincipalKey` / farming accounting — unchanged
- SDK public API for transactions — unchanged
- All existing shared objects — unchanged

## New On-Chain Object

- `YieldVault<USDB>`: `0xe90a8e473936b8d920afb5c5a793181a0fc8d7a62a9021f4d270205e69b23775` (already created)
