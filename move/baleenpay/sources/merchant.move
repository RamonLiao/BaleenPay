#[allow(unused_const)]
module baleenpay::merchant {
    use sui::table::{Self, Table};
    use std::string::String;
    use baleenpay::events;

    // ── Error codes (spec §3.8) ──
    #[error]
    const ENotMerchantOwner: u64 = 0;     // MerchantCap.merchant_id != account.id
    #[error]
    const EPaused: u64 = 2;               // MerchantAccount is paused (any source)
    #[error]
    const EAlreadyRegistered: u64 = 6;    // Merchant address already in registry
    #[error]
    const EZeroYield: u64 = 12;           // accrued_yield == 0, nothing to claim
    #[error]
    const ENoActiveSubscriptions: u64 = 7; // active_subscriptions == 0, cannot decrement
    #[error]
    const EInsufficientPrincipal: u64 = 8; // idle_principal < amount for credit_yield
    #[error]
    const EAdminFrozen: u64 = 24;         // admin-paused, self_unpause blocked

    // ── Structs ──

    /// Root admin privilege. Created at init, transferred to deployer.
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Singleton registry: owner address → MerchantAccount ID.
    public struct MerchantRegistry has key {
        id: UID,
        merchants: Table<address, ID>,
    }

    /// Owned capability proving merchant ownership. Required for claim_yield_v2 (router module).
    public struct MerchantCap has key, store {
        id: UID,
        merchant_id: ID,
    }

    /// Shared merchant ledger. Payers write via pay_once; privileged ops need cap.
    /// Dual-pause model: two independent flags, `get_paused()` returns OR.
    ///   - `paused_by_admin`: regulatory freeze (AdminCap-gated)
    ///   - `paused_by_self`: merchant voluntary pause (MerchantCap-gated)
    /// Admin operations never touch `paused_by_self` and vice versa.
    public struct MerchantAccount has key {
        id: UID,
        owner: address,
        brand_name: String,
        total_received: u64,
        idle_principal: u64,
        accrued_yield: u64,
        active_subscriptions: u64,
        paused_by_admin: bool,
        paused_by_self: bool,
    }

    // ── Init ──

    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            AdminCap { id: object::new(ctx) },
            ctx.sender(),
        );
        transfer::share_object(MerchantRegistry {
            id: object::new(ctx),
            merchants: table::new(ctx),
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ── Public functions ──

    /// Register a new merchant. Creates MerchantAccount (shared) + MerchantCap (to sender).
    #[allow(lint(self_transfer))]
    public fun register_merchant(
        registry: &mut MerchantRegistry,
        brand_name: String,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();
        assert!(!registry.merchants.contains(sender), EAlreadyRegistered);

        let account_uid = object::new(ctx);
        let account_id = account_uid.to_inner();

        let account = MerchantAccount {
            id: account_uid,
            owner: sender,
            brand_name,
            total_received: 0,
            idle_principal: 0,
            accrued_yield: 0,
            active_subscriptions: 0,
            paused_by_admin: false,
            paused_by_self: false,
        };

        registry.merchants.add(sender, account_id);

        events::emit_merchant_registered(account_id, account.brand_name, sender);

        transfer::share_object(account);
        transfer::transfer(
            MerchantCap {
                id: object::new(ctx),
                merchant_id: account_id,
            },
            sender,
        );
    }

    /// Admin freeze. Requires AdminCap. Only touches `paused_by_admin`.
    public fun pause_merchant(
        _admin: &AdminCap,
        account: &mut MerchantAccount,
    ) {
        account.paused_by_admin = true;
        events::emit_merchant_paused(object::id(account), true);
    }

    /// Admin unfreeze. Requires AdminCap. Only clears `paused_by_admin`.
    /// Preserves merchant's self-pause if active.
    public fun unpause_merchant(
        _admin: &AdminCap,
        account: &mut MerchantAccount,
    ) {
        account.paused_by_admin = false;
        events::emit_merchant_unpaused(object::id(account), true);
    }

    /// Merchant self-pause. Requires MerchantCap matching this account.
    public fun self_pause(
        cap: &MerchantCap,
        account: &mut MerchantAccount,
    ) {
        assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
        account.paused_by_self = true;
        events::emit_merchant_paused(object::id(account), false);
    }

    /// Merchant self-unpause. Requires MerchantCap matching this account.
    /// Cannot override admin freeze — only admin can lift admin-paused state.
    public fun self_unpause(
        cap: &MerchantCap,
        account: &mut MerchantAccount,
    ) {
        assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
        assert!(!account.paused_by_admin, EAdminFrozen);
        account.paused_by_self = false;
        events::emit_merchant_unpaused(object::id(account), false);
    }

    // ── Package-internal mutators (used by payment module) ──

    /// Expose UID for dynamic field access (order_id dedup in payment module).
    public(package) fun uid(account: &MerchantAccount): &UID { &account.id }
    public(package) fun uid_mut(account: &mut MerchantAccount): &mut UID { &mut account.id }

    /// Credit a one-time payment to the merchant ledger.
    public(package) fun add_payment(account: &mut MerchantAccount, amount: u64) {
        account.total_received = account.total_received + amount;
        account.idle_principal = account.idle_principal + amount;
    }

    /// Increment active subscription count.
    public(package) fun increment_subscriptions(account: &mut MerchantAccount) {
        account.active_subscriptions = account.active_subscriptions + 1;
    }

    /// Decrement active subscription count.
    public(package) fun decrement_subscriptions(account: &mut MerchantAccount) {
        assert!(account.active_subscriptions > 0, ENoActiveSubscriptions);
        account.active_subscriptions = account.active_subscriptions - 1;
    }

    /// Credit yield to merchant (called by router when yield is accrued).
    /// Moves amount from idle_principal to accrued_yield.
    public(package) fun credit_yield(account: &mut MerchantAccount, amount: u64) {
        assert!(account.idle_principal >= amount, EInsufficientPrincipal);
        account.idle_principal = account.idle_principal - amount;
        account.accrued_yield = account.accrued_yield + amount;
    }

    /// Credit yield from external source (StableLayer keeper).
    /// Only increases accrued_yield — does NOT deduct idle_principal.
    /// This is different from credit_yield which moves from principal to yield.
    public(package) fun credit_external_yield(account: &mut MerchantAccount, amount: u64) {
        account.accrued_yield = account.accrued_yield + amount;
    }

    /// Reset accrued_yield to zero and return the previous value.
    /// Used by router::claim_yield_v2 to avoid circular dependency.
    public(package) fun reset_accrued_yield(
        cap: &MerchantCap,
        account: &mut MerchantAccount,
    ): u64 {
        assert!(!account.paused_by_admin && !account.paused_by_self, EPaused);
        assert!(cap.merchant_id == object::id(account), ENotMerchantOwner);
        let amount = account.accrued_yield;
        assert!(amount > 0, EZeroYield);
        account.accrued_yield = 0;
        amount
    }

    #[test_only]
    /// Simulate yield accrual for testing claim_yield.
    public fun credit_yield_for_testing(account: &mut MerchantAccount, amount: u64) {
        credit_yield(account, amount);
    }

    #[test_only]
    public fun credit_external_yield_for_testing(account: &mut MerchantAccount, amount: u64) {
        credit_external_yield(account, amount);
    }

    #[test_only]
    public fun add_payment_for_testing(account: &mut MerchantAccount, amount: u64) {
        add_payment(account, amount);
    }

    // ── Getters (for tests and payment module) ──

    public fun get_total_received(account: &MerchantAccount): u64 { account.total_received }
    public fun get_brand_name(account: &MerchantAccount): String { account.brand_name }
    /// Returns true if paused by ANY source (admin OR self).
    public fun get_paused(account: &MerchantAccount): bool { account.paused_by_admin || account.paused_by_self }
    public fun get_idle_principal(account: &MerchantAccount): u64 { account.idle_principal }
    public fun get_accrued_yield(account: &MerchantAccount): u64 { account.accrued_yield }
    public fun get_owner(account: &MerchantAccount): address { account.owner }
    public fun get_active_subscriptions(account: &MerchantAccount): u64 { account.active_subscriptions }
    public fun get_admin_paused(account: &MerchantAccount): bool { account.paused_by_admin }
    public fun get_self_paused(account: &MerchantAccount): bool { account.paused_by_self }
    public fun get_merchant_id(cap: &MerchantCap): ID { cap.merchant_id }
}
