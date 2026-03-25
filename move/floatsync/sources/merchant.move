#[allow(unused_const)]
module floatsync::merchant {
    use sui::table::{Self, Table};
    use std::string::String;
    use floatsync::events;

    // ── Error codes (spec §3.8) ──
    const ENotMerchantOwner: u64 = 0;     // MerchantCap.merchant_id != account.id
    const EPaused: u64 = 2;               // MerchantAccount.paused == true
    const EAlreadyRegistered: u64 = 6;    // Merchant address already in registry
    const EZeroYield: u64 = 12;           // accrued_yield == 0, nothing to claim

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

    /// Owned capability proving merchant ownership. Required for claim_yield.
    public struct MerchantCap has key, store {
        id: UID,
        merchant_id: ID,
    }

    /// Shared merchant ledger. Payers write via pay_once; privileged ops need cap.
    /// NOTE: phantom T + active_subscriptions deferred to Task 5 (subscriptions).
    public struct MerchantAccount has key {
        id: UID,
        owner: address,
        brand_name: String,
        total_received: u64,
        idle_principal: u64,
        accrued_yield: u64,
        active_subscriptions: u64,
        paused: bool,
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
            paused: false,
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

    /// Emergency pause. Requires AdminCap.
    public fun pause_merchant(
        _admin: &AdminCap,
        account: &mut MerchantAccount,
    ) {
        account.paused = true;
        events::emit_merchant_paused(object::id(account));
    }

    /// Unpause. Requires AdminCap.
    public fun unpause_merchant(
        _admin: &AdminCap,
        account: &mut MerchantAccount,
    ) {
        account.paused = false;
        events::emit_merchant_unpaused(object::id(account));
    }

    // ── Package-internal mutators (used by payment module) ──

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
        account.active_subscriptions = account.active_subscriptions - 1;
    }

    // ── Getters (for tests and payment module) ──

    public fun get_total_received(account: &MerchantAccount): u64 { account.total_received }
    public fun get_brand_name(account: &MerchantAccount): String { account.brand_name }
    public fun get_paused(account: &MerchantAccount): bool { account.paused }
    public fun get_idle_principal(account: &MerchantAccount): u64 { account.idle_principal }
    public fun get_accrued_yield(account: &MerchantAccount): u64 { account.accrued_yield }
    public fun get_owner(account: &MerchantAccount): address { account.owner }
    public fun get_active_subscriptions(account: &MerchantAccount): u64 { account.active_subscriptions }
    public fun get_merchant_id(cap: &MerchantCap): ID { cap.merchant_id }
}
