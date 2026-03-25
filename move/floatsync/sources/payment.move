module floatsync::payment {
    use sui::coin::{Self, Coin};
    use sui::balance::Balance;
    use sui::clock::Clock;
    use floatsync::merchant::{Self, MerchantAccount};
    use floatsync::events;

    // ── Error codes (spec §3.8) ──
    const EPaused: u64 = 2;
    const ENotPayer: u64 = 3;
    const EZeroAmount: u64 = 10;
    const ENotDue: u64 = 11;
    const EInsufficientPrepaid: u64 = 13;
    const EZeroPeriod: u64 = 14;
    const EInsufficientBalance: u64 = 15;

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
        assert!(prepaid_periods > 0, EZeroAmount);

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
        let first_coin = coin::from_balance(first_payment, ctx);
        transfer::public_transfer(first_coin, merchant::get_owner(account));
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

    /// Process a due subscription payment. Permissionless — anyone can call.
    public fun process_subscription<T>(
        account: &mut MerchantAccount,
        subscription: &mut Subscription<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!merchant::get_paused(account), EPaused);
        assert!(clock.timestamp_ms() >= subscription.next_due, ENotDue);
        assert!(
            subscription.balance.value() >= subscription.amount_per_period,
            EInsufficientBalance,
        );

        let payment = subscription.balance.split(subscription.amount_per_period);
        let payment_coin = coin::from_balance(payment, ctx);
        transfer::public_transfer(payment_coin, merchant::get_owner(account));

        merchant::add_payment(account, subscription.amount_per_period);
        subscription.next_due = subscription.next_due + subscription.period_ms;

        events::emit_subscription_processed(
            subscription.merchant_id,
            subscription.payer,
            subscription.amount_per_period,
            subscription.next_due,
        );
    }

    /// Cancel subscription. Only payer can cancel. Refunds remaining balance.
    public fun cancel_subscription<T>(
        account: &mut MerchantAccount,
        subscription: Subscription<T>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == subscription.payer, ENotPayer);

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
            let refund_coin = coin::from_balance(balance, ctx);
            transfer::public_transfer(refund_coin, payer);
        } else {
            balance.destroy_zero();
        };

        merchant::decrement_subscriptions(account);

        events::emit_subscription_cancelled(
            merchant_id,
            payer,
            refunded_amount,
        );

        object::delete(id);
    }

    /// Add more funds to an existing subscription. Only payer can fund.
    public fun fund_subscription<T>(
        subscription: &mut Subscription<T>,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
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

    // ── Getters (for tests) ──

    public fun get_sub_balance<T>(sub: &Subscription<T>): u64 { sub.balance.value() }
    public fun get_sub_next_due<T>(sub: &Subscription<T>): u64 { sub.next_due }
    public fun get_sub_payer<T>(sub: &Subscription<T>): address { sub.payer }
    public fun get_sub_merchant_id<T>(sub: &Subscription<T>): ID { sub.merchant_id }
    public fun get_sub_amount_per_period<T>(sub: &Subscription<T>): u64 { sub.amount_per_period }
}
