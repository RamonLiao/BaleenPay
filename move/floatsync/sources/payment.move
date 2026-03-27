module floatsync::payment {
    use sui::coin::Coin;
    use sui::balance::Balance;
    use sui::clock::Clock;
    use floatsync::merchant::{Self, MerchantAccount};
    use floatsync::events;
    use sui::dynamic_field as df;
    use std::type_name;
    use std::string::String;
    use floatsync::merchant::MerchantCap;
    use floatsync::router::{Self, Vault, RouterConfig};

    // ── Error codes (spec §3.8) ──
    #[error]
    const EPaused: u64 = 2;
    #[error]
    const ENotPayer: u64 = 3;
    #[error]
    const EZeroAmount: u64 = 10;
    #[error]
    const ENotDue: u64 = 11;
    #[error]
    const EInsufficientPrepaid: u64 = 13;
    #[error]
    const EZeroPeriod: u64 = 14;
    #[error]
    const EInsufficientBalance: u64 = 15;
    #[error]
    const EMerchantMismatch: u64 = 16;
    #[error]
    const EZeroPrepaidPeriods: u64 = 17;
    #[error]
    const ENotMerchantOwner: u64 = 0;
    #[error]
    const EOrderAlreadyPaid: u64 = 18;
    #[error]
    const EInvalidOrderId: u64 = 19;
    #[error]
    const EExceedsMaxPrepaidPeriods: u64 = 22;
    #[error]
    const EOverflow: u64 = 23;
    #[error]
    const EAdminFrozen: u64 = 24;
    const MAX_ORDER_ID_BYTES: u64 = 64;
    const MAX_PREPAID_PERIODS: u64 = 1000;

    // ── Subscription struct ──

    /// Shared escrow object for recurring payments.
    /// Balance holds prepaid funds; anyone can trigger process when due.
    public struct Subscription<phantom T> has key {
        id: UID,
        merchant_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        next_due: u64,
        balance: Balance<T>,
    }

    // ── Helpers ──

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

    // ── Order ID dedup structs ──

    /// Dynamic field key scoped to payer — prevents front-running/squatting.
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

    // ── One-time payment ──

    /// One-time payment: transfers coin to merchant owner, updates ledger.
    /// T is generic — works with any coin type (USDC, BRAND_USD, etc.).
    public fun pay_once<T>(
        account: &mut MerchantAccount,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(!merchant::get_paused(account), EPaused);
        let amount = coin.value();
        assert!(amount > 0, EZeroAmount);

        // Update merchant ledger (total_received + idle_principal)
        merchant::add_payment(account, amount);

        // Transfer coin to merchant owner
        transfer::public_transfer(coin, merchant::get_owner(account));

        // Emit event (payment_type 0 = one-time)
        events::emit_payment_received(
            object::id(account),
            ctx.sender(),
            amount,
            0,
            clock.timestamp_ms(),
        );
    }

    /// One-time payment with order_id deduplication.
    /// Order ID scoped to (payer, order_id) — same order_id from different payers are independent.
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

        let now = clock.timestamp_ms();
        let coin_type = type_name::get<T>().into_string().to_string();
        df::add(merchant::uid_mut(account), key, OrderRecord {
            amount,
            timestamp_ms: now,
            coin_type,
        });

        events::emit_payment_received_v2(
            object::id(account),
            ctx.sender(),
            amount,
            0,
            now,
            key.order_id,
            coin_type,
        );
    }

    /// Router-aware one-time payment. Routes coin to Vault when mode=stablelayer.
    /// SDK calls this only when router mode=1. For mode=0, SDK uses pay_once_v2 directly.
    public fun pay_once_routed<T>(
        config: &RouterConfig,
        account: &mut MerchantAccount,
        vault: &mut Vault<T>,
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

        let now = clock.timestamp_ms();
        let coin_type = type_name::get<T>().into_string().to_string();

        // Record order for dedup
        df::add(merchant::uid_mut(account), key, OrderRecord {
            amount,
            timestamp_ms: now,
            coin_type,
        });

        // Route to vault (asserts mode==stablelayer inside)
        router::route_payment(config, account, vault, coin, clock, ctx);

        events::emit_payment_received_v2(
            object::id(account),
            ctx.sender(),
            amount,
            0, // payment_type: one-time
            now,
            key.order_id,
            coin_type,
        );
    }

    // ── Subscription functions ──

    /// Create a recurring subscription. Locks `amount_per_period * prepaid_periods`
    /// into escrow and processes the first period immediately.
    #[allow(lint(self_transfer))]
    public fun subscribe<T>(
        account: &mut MerchantAccount,
        mut coin: Coin<T>,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!merchant::get_paused(account), EPaused);
        assert!(amount_per_period > 0, EZeroAmount);
        assert!(period_ms > 0, EZeroPeriod);
        assert!(prepaid_periods > 0, EZeroPrepaidPeriods);

        // Overflow guard (backported from subscribe_v2)
        assert!(prepaid_periods <= MAX_PREPAID_PERIODS, EExceedsMaxPrepaidPeriods);
        assert!(amount_per_period <= 18_446_744_073_709_551_615 / prepaid_periods, EOverflow);

        let total_required = amount_per_period * prepaid_periods;
        assert!(coin.value() >= total_required, EInsufficientPrepaid);

        // Split exact amount needed; refund remainder
        let escrow_coin = coin.split(total_required, ctx);
        if (coin.value() > 0) {
            transfer::public_transfer(coin, ctx.sender());
        } else {
            coin.destroy_zero();
        };

        // Build escrow balance
        let mut escrow_balance = escrow_coin.into_balance();

        // Process first period immediately
        let first_payment = escrow_balance.split(amount_per_period);
        transfer::public_transfer(first_payment.into_coin(ctx), merchant::get_owner(account));
        merchant::add_payment(account, amount_per_period);

        let now = clock.timestamp_ms();
        let next_due = now + period_ms;
        let merchant_id = object::id(account);

        // Emit first payment event (payment_type 1 = subscription)
        events::emit_payment_received(
            merchant_id,
            ctx.sender(),
            amount_per_period,
            1,
            now,
        );

        // Track subscription count
        merchant::increment_subscriptions(account);

        // Emit subscription created event
        events::emit_subscription_created(
            merchant_id,
            ctx.sender(),
            amount_per_period,
            period_ms,
            prepaid_periods,
        );

        // Share subscription object
        transfer::share_object(Subscription<T> {
            id: object::new(ctx),
            merchant_id,
            payer: ctx.sender(),
            amount_per_period,
            period_ms,
            next_due,
            balance: escrow_balance,
        });
    }

    /// Subscribe with order_id deduplication.
    #[allow(lint(self_transfer))]
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

        assert!(!merchant::get_paused(account), EPaused);
        assert!(amount_per_period > 0, EZeroAmount);
        assert!(period_ms > 0, EZeroPeriod);
        assert!(prepaid_periods > 0, EZeroPrepaidPeriods);
        // Overflow guard: cap prepaid_periods + checked multiplication
        assert!(prepaid_periods <= MAX_PREPAID_PERIODS, EExceedsMaxPrepaidPeriods);
        assert!(amount_per_period <= 18_446_744_073_709_551_615 / prepaid_periods, EOverflow);

        let total_required = amount_per_period * prepaid_periods;
        assert!(coin.value() >= total_required, EInsufficientPrepaid);

        let escrow_coin = coin.split(total_required, ctx);
        if (coin.value() > 0) {
            transfer::public_transfer(coin, ctx.sender());
        } else {
            coin.destroy_zero();
        };

        let mut escrow_balance = escrow_coin.into_balance();
        let first_payment = escrow_balance.split(amount_per_period);
        transfer::public_transfer(first_payment.into_coin(ctx), merchant::get_owner(account));
        merchant::add_payment(account, amount_per_period);

        let now = clock.timestamp_ms();
        let merchant_id = object::id(account);

        let coin_type = type_name::get<T>().into_string().to_string();
        df::add(merchant::uid_mut(account), key, OrderRecord {
            amount: total_required,
            timestamp_ms: now,
            coin_type,
        });

        merchant::increment_subscriptions(account);

        events::emit_payment_received_v2(
            merchant_id, ctx.sender(), amount_per_period, 1, now,
            key.order_id, coin_type,
        );

        let sub_uid = object::new(ctx);
        let subscription_id = sub_uid.to_inner();

        // V2 event includes subscription_id
        events::emit_subscription_created_v2(
            merchant_id, subscription_id, ctx.sender(),
            amount_per_period, period_ms, prepaid_periods, key.order_id,
        );

        transfer::share_object(Subscription<T> {
            id: sub_uid,
            merchant_id,
            payer: ctx.sender(),
            amount_per_period,
            period_ms,
            next_due: now + period_ms,
            balance: escrow_balance,
        });
    }

    /// Process a due subscription payment. Permissionless — anyone can call.
    public fun process_subscription<T>(
        account: &mut MerchantAccount,
        subscription: &mut Subscription<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(subscription.merchant_id == object::id(account), EMerchantMismatch);
        assert!(!merchant::get_paused(account), EPaused);
        assert!(clock.timestamp_ms() >= subscription.next_due, ENotDue);
        assert!(
            subscription.balance.value() >= subscription.amount_per_period,
            EInsufficientBalance,
        );

        let payment = subscription.balance.split(subscription.amount_per_period);
        transfer::public_transfer(payment.into_coin(ctx), merchant::get_owner(account));

        merchant::add_payment(account, subscription.amount_per_period);

        // Guard against next_due overflow (could brick subscription)
        assert!(subscription.next_due <= 18_446_744_073_709_551_615 - subscription.period_ms, EOverflow);
        subscription.next_due = subscription.next_due + subscription.period_ms;

        events::emit_subscription_processed(
            subscription.merchant_id,
            subscription.payer,
            subscription.amount_per_period,
            subscription.next_due,
        );
    }

    /// Cancel subscription. Only payer can cancel. Refunds remaining balance.
    /// Blocked during admin freeze (regulatory hold); allowed during self-pause.
    public fun cancel_subscription<T>(
        account: &mut MerchantAccount,
        subscription: Subscription<T>,
        ctx: &mut TxContext,
    ) {
        assert!(!merchant::get_admin_paused(account), EAdminFrozen);
        assert!(ctx.sender() == subscription.payer, ENotPayer);
        assert!(subscription.merchant_id == object::id(account), EMerchantMismatch);

        let Subscription {
            id,
            merchant_id,
            payer,
            amount_per_period: _,
            period_ms: _,
            next_due: _,
            balance,
        } = subscription;

        let refunded_amount = balance.value();

        // Refund remaining balance to payer
        if (refunded_amount > 0) {
            transfer::public_transfer(balance.into_coin(ctx), payer);
        } else {
            balance.destroy_zero();
        };

        merchant::decrement_subscriptions(account);

        events::emit_subscription_cancelled(
            merchant_id,
            payer,
            refunded_amount,
        );

        id.delete();
    }

    /// Add more funds to an existing subscription. Only payer can fund.
    /// Blocked during any pause — prevents deposits into frozen entity's escrow.
    public fun fund_subscription<T>(
        account: &MerchantAccount,
        subscription: &mut Subscription<T>,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
        assert!(subscription.merchant_id == object::id(account), EMerchantMismatch);
        assert!(!merchant::get_paused(account), EPaused);
        assert!(ctx.sender() == subscription.payer, ENotPayer);
        let funded_amount = coin.value();
        assert!(funded_amount > 0, EZeroAmount);

        subscription.balance.join(coin.into_balance());

        events::emit_subscription_funded(
            subscription.merchant_id,
            subscription.payer,
            funded_amount,
        );
    }

    // ── Order record management ──

    /// Remove an order record. MerchantCap gated. Emits audit event.
    /// WARNING: Removing a record allows the same order_id to be reused.
    /// Blocked during admin freeze — prevents ledger tampering during regulatory hold.
    public fun remove_order_record(
        cap: &MerchantCap,
        account: &mut MerchantAccount,
        payer: address,
        order_id: String,
    ) {
        assert!(!merchant::get_admin_paused(account), EAdminFrozen);
        assert!(merchant::get_merchant_id(cap) == object::id(account), ENotMerchantOwner);
        let key = OrderKey { payer, order_id };
        let _: OrderRecord = df::remove(merchant::uid_mut(account), key);

        events::emit_order_record_removed(
            object::id(account),
            payer,
            key.order_id,
        );
    }

    /// Check if an order_id has been paid by a specific payer.
    public fun has_order_record(
        account: &MerchantAccount,
        payer: address,
        order_id: String,
    ): bool {
        let key = OrderKey { payer, order_id };
        df::exists_(merchant::uid(account), key)
    }

    // ── Getters (for tests) ──

    public fun get_sub_balance<T>(sub: &Subscription<T>): u64 { sub.balance.value() }
    public fun get_sub_next_due<T>(sub: &Subscription<T>): u64 { sub.next_due }
    public fun get_sub_payer<T>(sub: &Subscription<T>): address { sub.payer }
    public fun get_sub_merchant_id<T>(sub: &Subscription<T>): ID { sub.merchant_id }
    public fun get_sub_amount_per_period<T>(sub: &Subscription<T>): u64 { sub.amount_per_period }
}
