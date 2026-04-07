# Partial Yield Claim — Design Spec

**Date:** 2026-04-07
**Branch:** TBD (will be created during implementation)
**Scope:** Move contracts + SDK (no frontend UI in this iteration)

## Problem

`claim_yield_v2<T>` is all-or-nothing: merchants must claim their entire accrued yield in a single transaction. This prevents:

1. Keeping partial yield in vault to compound (re-invest)
2. Staged withdrawals for tax/cash-flow management
3. Future system-level minimum withdrawal or reserve requirements

## Decision Summary

| Decision | Choice |
|----------|--------|
| Claim granularity | Merchant specifies exact amount |
| Remaining yield storage | Stays in `AccruedYieldKey<T>` dynamic field |
| API strategy | New `claim_yield_partial<T>` + v2 becomes wrapper |
| amount = 0 | Abort (`EZeroAmount`) |
| amount > accrued | Abort (`EExceedsAccrued`) |
| Event | New `YieldClaimedPartial { merchant_id, claimed, remaining }` |
| Approach | Move + SDK (Approach B); frontend deferred |

## Move Contract Changes

### merchant.move

#### New error constant

```move
#[error]
const EExceedsAccrued: u64 = <next_available>;
```

#### New function: `debit_accrued_yield_typed<T>`

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

#### Test helper

```move
#[test_only]
public fun debit_accrued_yield_typed_for_testing<T>(
    cap: &MerchantCap, account: &mut MerchantAccount, amount: u64,
): u64 {
    debit_accrued_yield_typed<T>(cap, account, amount)
}
```

### router.move

#### New error constant

```move
#[error]
const EInsufficientVaultBalance: u64 = <next_available>;
```

#### New function: `claim_yield_partial<T>`

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

#### Modified: `claim_yield_v2<T>` (becomes wrapper)

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

**Note:** `claim_yield_v2` signature is unchanged — fully backward compatible.

**Event change:** v2 now emits `YieldClaimedPartial` (with `remaining = 0`) instead of `YieldClaimed`. The old `YieldClaimed` struct is preserved (cannot remove in compatible upgrade) but no longer emitted by v2.

### events.move

#### New event struct + emit function

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

## SDK Changes

### `packages/sdk/src/transactions/yield.ts`

New function `buildClaimYieldPartial`:

```ts
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

### `packages/sdk/src/client.ts`

New method on `BaleenPayClient`:

```ts
/** Build a claim_yield_partial transaction. Amount in MIST. */
claimYieldPartial(merchantCapId: string, coinType: string, amount: bigint): TransactionResult {
  return { tx: buildClaimYieldPartial(this.config, merchantCapId, coinType, amount) }
}
```

### Re-exports

`transactions/index.ts` and `src/index.ts` re-export `buildClaimYieldPartial`.

## Testing Strategy

### Move tests (new file: `tests/partial_yield_claim_tests.move`)

1. **Happy path** — credit 100, claim 40, verify remaining = 60
2. **Claim all via partial** — credit 100, claim 100, verify df removed
3. **v2 wrapper** — credit 100, call v2, verify remaining = 0 + df removed
4. **Multiple partial claims** — credit 100, claim 30, claim 30, claim 40
5. **amount = 0** — expect abort `EZeroAmount`
6. **amount > accrued** — expect abort `EExceedsAccrued`
7. **No accrued (df missing)** — expect abort `EZeroYield`
8. **Paused account** — expect abort `EPaused`
9. **Wrong MerchantCap** — expect abort `ENotMerchantOwner`

### Monkey tests (extreme cases)

10. **Claim 1 MIST** — minimum unit
11. **Claim MAX_U64 - 1 when accrued = MAX_U64** — near-overflow boundary
12. **Rapid sequential claims** — credit 1000, claim 1 × 1000 times (loop in test)
13. **Multi-type interleave** — credit USDB 100 + Stablecoin 50, partial claim USDB 40, verify Stablecoin untouched
14. **Vault balance < accrued** — expect abort `EInsufficientVaultBalance`

### SDK tests

15. **`buildClaimYieldPartial` generates correct PTB** — verify moveCall target, typeArgs, args
16. **amount = 0n throws** — client-side validation
17. **`claimYieldPartial` delegates correctly** — verify config wiring

## Known Deviations & Future Work

- **Parameter order:** New functions use cap-first (matching existing v2 API), deviating from Move Book's objects-first guideline. Changing would break API consistency.
- **Composability:** `claim_yield_partial` does `transfer::public_transfer` internally (not PTB-composable). Matches v2 pattern. Future: add a composable variant that returns `Coin<T>`.
- **Frontend UI:** Not in scope. Dashboard partial claim UI is a separate task.
- **Rate limiting / minimum withdrawal:** Architecture supports it (add assert in `claim_yield_partial`), but not implemented per decision to avoid merchant friction.

## Security Review Summary

| Check | Result |
|-------|--------|
| Access control (MerchantCap) | ✅ Preserved |
| Pause check | ✅ Preserved |
| Integer safety (underflow) | ✅ `assert!(amount <= *current)` |
| Zero-amount guard | ✅ `assert!(amount > 0)` |
| Vault balance desync | ✅ `assert!(vault.balance >= amount)` with clear error |
| Type confusion (`<FakeCoin>`) | ✅ DF doesn't exist → `EZeroYield` |
| Zombie DF cleanup | ✅ Remove df when remaining = 0 |
| Repeated drain | ✅ Math-correct deduction per tx |
