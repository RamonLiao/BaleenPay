module baleenpay::router;
use sui::coin::Coin;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount};
use baleenpay::events;

// ── Router modes ──
const MODE_FALLBACK: u8 = 0;
const MODE_STABLELAYER: u8 = 1;

// ── Error codes ──
#[error]
const EInvalidMode: u64 = 20;
#[error]
const ESameMode: u64 = 21;
#[error]
const ENotStableLayerMode: u64 = 25;
#[error]
const EZeroAmount: u64 = 10;
#[error]
const EOverflow: u64 = 23;
#[error]
const ENotMerchantOwner: u64 = 26;
#[error]
const EPaused: u64 = 27;

/// Shared config object controlling payment routing strategy.
/// AdminCap is the sole gatekeeper for all privileged operations (including keeper ops).
public struct RouterConfig has key {
    id: UID,
    mode: u8,
}

/// Shared vault holding coins awaiting StableLayer deposit.
public struct Vault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
    total_deposited: u64,
    total_yield_harvested: u64,
}

/// Holds minted Stablecoin receipts. Merchants take from here to redeem via StableLayer.
public struct StablecoinVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}

/// Holds reward coins from StableLayer, claimable by merchants.
public struct YieldVault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}

// ── Init ──

fun init(ctx: &mut TxContext) {
    transfer::share_object(RouterConfig {
        id: object::new(ctx),
        mode: MODE_FALLBACK,
    });
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

// ── Admin: mode + keeper ──

public fun set_mode(
    _admin: &AdminCap,
    config: &mut RouterConfig,
    new_mode: u8,
) {
    assert!(new_mode <= MODE_STABLELAYER, EInvalidMode);
    assert!(new_mode != config.mode, ESameMode);
    let old_mode = config.mode;
    config.mode = new_mode;
    events::emit_router_mode_changed(old_mode, new_mode);
}

// ── Vault lifecycle ──

public fun create_vault<T>(_admin: &AdminCap, ctx: &mut TxContext) {
    transfer::share_object(Vault<T> {
        id: object::new(ctx),
        balance: balance::zero(),
        total_deposited: 0,
        total_yield_harvested: 0,
    });
}

public fun create_yield_vault<T>(_admin: &AdminCap, ctx: &mut TxContext) {
    transfer::share_object(YieldVault<T> {
        id: object::new(ctx),
        balance: balance::zero(),
    });
}

public fun create_stablecoin_vault<T>(_admin: &AdminCap, ctx: &mut TxContext) {
    transfer::share_object(StablecoinVault<T> {
        id: object::new(ctx),
        balance: balance::zero(),
    });
}

/// Keeper deposits Stablecoin receipt into StablecoinVault and updates merchant accounting.
/// Called after mint in the same PTB. Moves idle_principal → farming_principal.
/// Amount is derived from coin.value() (single source of truth — no separate amount param).
public fun keeper_deposit_to_farm<T>(
    _admin: &AdminCap,
    account: &mut MerchantAccount,
    stablecoin_vault: &mut StablecoinVault<T>,
    stablecoin_coin: Coin<T>,
) {
    let amount = stablecoin_coin.value();
    assert!(amount > 0, EZeroAmount);
    stablecoin_vault.balance.join(stablecoin_coin.into_balance());
    merchant::move_to_farming(account, amount);
    events::emit_farm_deposited(
        object::id(account),
        amount,
        object::id(stablecoin_vault),
    );
}

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

// ── Payment routing (package-internal) ──

/// Route payment to vault. Only valid when mode == MODE_STABLELAYER.
/// SDK uses pay_once_v2 directly for MODE_FALLBACK (no vault needed).
public(package) fun route_payment<T>(
    config: &RouterConfig,
    account: &mut MerchantAccount,
    vault: &mut Vault<T>,
    coin: Coin<T>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(config.mode == MODE_STABLELAYER, ENotStableLayerMode);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);

    merchant::add_payment(account, amount);
    vault.balance.join(coin.into_balance());

    events::emit_vault_deposited(
        object::id(vault),
        amount,
        object::id(account),
        ctx.sender(),
        clock.timestamp_ms(),
    );
}

// ── Keeper operations ──

/// Withdraw coins from vault for StableLayer deposit.
/// Returns Coin<T> for same-PTB StableLayer interaction.
public fun keeper_withdraw<T>(
    _admin: &AdminCap,
    vault: &mut Vault<T>,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(amount > 0, EZeroAmount);
    assert!(vault.total_deposited <= 18_446_744_073_709_551_615 - amount, EOverflow);
    vault.total_deposited = vault.total_deposited + amount;
    events::emit_vault_withdrawn(
        object::id(vault),
        amount,
        ctx.sender(),
        clock.timestamp_ms(),
    );
    vault.balance.split(amount).into_coin(ctx)
}

/// Deposit yield coins to YieldVault and credit merchant.
/// Amount is derived from coin.value() (single source of truth).
public fun keeper_deposit_yield<T>(
    _admin: &AdminCap,
    yield_vault: &mut YieldVault<T>,
    account: &mut MerchantAccount,
    coin: Coin<T>,
) {
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    yield_vault.balance.join(coin.into_balance());
    merchant::credit_external_yield_typed<T>(account, amount);
}

/// Merchant withdraws idle principal from Vault.
/// Only withdrawable amount is idle_principal (not yet sent to StableLayer by keeper).
public fun merchant_withdraw<T>(
    cap: &merchant::MerchantCap,
    account: &mut MerchantAccount,
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(amount > 0, EZeroAmount);
    merchant::deduct_idle_principal(cap, account, amount);
    let coin = vault.balance.split(amount).into_coin(ctx);
    transfer::public_transfer(coin, merchant::get_owner(account));
    events::emit_merchant_withdrawn(object::id(account), object::id(vault), amount);
}

/// Claim yield v2 — withdraws actual coins from YieldVault and transfers to merchant.
/// Moved here (instead of merchant.move) to avoid circular dependency.
public fun claim_yield_v2<T>(
    cap: &merchant::MerchantCap,
    account: &mut MerchantAccount,
    yield_vault: &mut YieldVault<T>,
    ctx: &mut TxContext,
) {
    let amount = merchant::reset_accrued_yield_typed<T>(cap, account);
    let coin = yield_vault.balance.split(amount).into_coin(ctx);
    transfer::public_transfer(coin, merchant::get_owner(account));
    events::emit_yield_claimed(object::id(account), amount);
}

// ── Getters ──

public fun get_mode(config: &RouterConfig): u8 { config.mode }
public fun is_fallback(config: &RouterConfig): bool { config.mode == MODE_FALLBACK }
public fun is_stablelayer(config: &RouterConfig): bool { config.mode == MODE_STABLELAYER }

public fun vault_balance<T>(vault: &Vault<T>): u64 { vault.balance.value() }
public fun vault_total_deposited<T>(vault: &Vault<T>): u64 { vault.total_deposited }
public fun vault_total_yield_harvested<T>(vault: &Vault<T>): u64 { vault.total_yield_harvested }

public fun yield_vault_balance<T>(yv: &YieldVault<T>): u64 { yv.balance.value() }
public fun stablecoin_vault_balance<T>(sv: &StablecoinVault<T>): u64 { sv.balance.value() }

// ── Test helpers ──

#[test_only]
public fun deposit_to_vault_for_testing<T>(vault: &mut Vault<T>, coin: Coin<T>) {
    vault.balance.join(coin.into_balance());
}

#[test_only]
public fun deposit_to_yield_vault_for_testing<T>(yv: &mut YieldVault<T>, coin: Coin<T>) {
    yv.balance.join(coin.into_balance());
}

#[test_only]
public fun deposit_to_stablecoin_vault_for_testing<T>(sv: &mut StablecoinVault<T>, coin: Coin<T>) {
    sv.balance.join(coin.into_balance());
}
