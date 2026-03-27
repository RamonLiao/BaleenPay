module floatsync::router {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use floatsync::merchant::{Self, AdminCap, MerchantAccount};
    use floatsync::events;

    // ── Router modes ──
    const MODE_FALLBACK: u8 = 0;
    const MODE_STABLELAYER: u8 = 1;

    // ── Error codes ──
    const EInvalidMode: u64 = 20;
    const ESameMode: u64 = 21;
    const ENotStableLayerMode: u64 = 25;
    const EZeroAmount: u64 = 10;

    /// Shared config object controlling payment routing strategy.
    public struct RouterConfig has key {
        id: UID,
        mode: u8,
        keeper: address,
    }

    /// Shared vault holding coins awaiting StableLayer deposit.
    public struct Vault<phantom T> has key {
        id: UID,
        balance: Balance<T>,
        total_deposited: u64,
        total_yield_harvested: u64,
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
            keeper: @0x0,
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

    public fun set_keeper(
        _admin: &AdminCap,
        config: &mut RouterConfig,
        keeper: address,
    ) {
        config.keeper = keeper;
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
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(amount > 0, EZeroAmount);
        vault.total_deposited = vault.total_deposited + amount;
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
        merchant::credit_external_yield(account, amount);
    }

    /// Claim yield v2 — withdraws actual coins from YieldVault and transfers to merchant.
    /// Moved here (instead of merchant.move) to avoid circular dependency.
    public fun claim_yield_v2<T>(
        cap: &merchant::MerchantCap,
        account: &mut MerchantAccount,
        yield_vault: &mut YieldVault<T>,
        ctx: &mut TxContext,
    ) {
        let amount = merchant::reset_accrued_yield(cap, account);
        let coin = yield_vault.balance.split(amount).into_coin(ctx);
        transfer::public_transfer(coin, merchant::get_owner(account));
        events::emit_yield_claimed(object::id(account), amount);
    }

    // ── Getters ──

    public fun get_mode(config: &RouterConfig): u8 { config.mode }
    public fun get_keeper(config: &RouterConfig): address { config.keeper }
    public fun is_fallback(config: &RouterConfig): bool { config.mode == MODE_FALLBACK }
    public fun is_stablelayer(config: &RouterConfig): bool { config.mode == MODE_STABLELAYER }

    public fun vault_balance<T>(vault: &Vault<T>): u64 { vault.balance.value() }
    public fun vault_total_deposited<T>(vault: &Vault<T>): u64 { vault.total_deposited }
    public fun vault_total_yield_harvested<T>(vault: &Vault<T>): u64 { vault.total_yield_harvested }

    public fun yield_vault_balance<T>(yv: &YieldVault<T>): u64 { yv.balance.value() }

    // ── Test helpers ──

    #[test_only]
    public fun deposit_to_vault_for_testing<T>(vault: &mut Vault<T>, coin: Coin<T>) {
        vault.balance.join(coin.into_balance());
    }
}
