module floatsync::events {
    use sui::event;
    use std::string::String;

    public struct MerchantRegistered has copy, drop {
        merchant_id: ID,
        brand_name: String,
        owner: address,
    }

    public struct PaymentReceived has copy, drop {
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
    }

    public struct SubscriptionCreated has copy, drop {
        merchant_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
    }

    public struct SubscriptionProcessed has copy, drop {
        merchant_id: ID,
        payer: address,
        amount: u64,
        next_due: u64,
    }

    public struct SubscriptionCancelled has copy, drop {
        merchant_id: ID,
        payer: address,
        refunded_amount: u64,
    }

    public struct SubscriptionFunded has copy, drop {
        merchant_id: ID,
        payer: address,
        funded_amount: u64,
    }

    public struct YieldClaimed has copy, drop {
        merchant_id: ID,
        amount: u64,
    }

    public struct MerchantPaused has copy, drop {
        merchant_id: ID,
        by_admin: bool,
    }

    public struct MerchantUnpaused has copy, drop {
        merchant_id: ID,
        by_admin: bool,
    }

    public struct RouterModeChanged has copy, drop {
        old_mode: u8,
        new_mode: u8,
    }

    public struct BrandUsdRedeemed has copy, drop {
        merchant_id: ID,
        amount: u64,
    }

    public struct TreasurySetupCompleted has copy, drop {
        treasury_id: ID,
        vault_id: ID,
    }

    // ── Emit helpers (Move disallows cross-module struct construction) ──

    public(package) fun emit_merchant_registered(merchant_id: ID, brand_name: String, owner: address) {
        event::emit(MerchantRegistered { merchant_id, brand_name, owner });
    }

    public(package) fun emit_merchant_paused(merchant_id: ID, by_admin: bool) {
        event::emit(MerchantPaused { merchant_id, by_admin });
    }

    public(package) fun emit_merchant_unpaused(merchant_id: ID, by_admin: bool) {
        event::emit(MerchantUnpaused { merchant_id, by_admin });
    }

    public(package) fun emit_payment_received(
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
    ) {
        event::emit(PaymentReceived { merchant_id, payer, amount, payment_type, timestamp });
    }

    public(package) fun emit_subscription_created(
        merchant_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
    ) {
        event::emit(SubscriptionCreated { merchant_id, payer, amount_per_period, period_ms, prepaid_periods });
    }

    public(package) fun emit_subscription_processed(
        merchant_id: ID,
        payer: address,
        amount: u64,
        next_due: u64,
    ) {
        event::emit(SubscriptionProcessed { merchant_id, payer, amount, next_due });
    }

    public(package) fun emit_subscription_cancelled(
        merchant_id: ID,
        payer: address,
        refunded_amount: u64,
    ) {
        event::emit(SubscriptionCancelled { merchant_id, payer, refunded_amount });
    }

    public(package) fun emit_subscription_funded(
        merchant_id: ID,
        payer: address,
        funded_amount: u64,
    ) {
        event::emit(SubscriptionFunded { merchant_id, payer, funded_amount });
    }

    public(package) fun emit_yield_claimed(merchant_id: ID, amount: u64) {
        event::emit(YieldClaimed { merchant_id, amount });
    }

    public(package) fun emit_router_mode_changed(old_mode: u8, new_mode: u8) {
        event::emit(RouterModeChanged { old_mode, new_mode });
    }

    // ── V2 events (SDK Phase 1) ──

    public struct PaymentReceivedV2 has copy, drop {
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
        order_id: String,
        coin_type: String,
    }

    public(package) fun emit_payment_received_v2(
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
        order_id: String,
        coin_type: String,
    ) {
        event::emit(PaymentReceivedV2 {
            merchant_id, payer, amount, payment_type, timestamp, order_id, coin_type,
        });
    }

    public struct SubscriptionCreatedV2 has copy, drop {
        merchant_id: ID,
        subscription_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
        order_id: String,
    }

    public(package) fun emit_subscription_created_v2(
        merchant_id: ID,
        subscription_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
        order_id: String,
    ) {
        event::emit(SubscriptionCreatedV2 {
            merchant_id, subscription_id, payer, amount_per_period, period_ms, prepaid_periods, order_id,
        });
    }

    public struct OrderRecordRemoved has copy, drop {
        merchant_id: ID,
        payer: address,
        order_id: String,
    }

    public(package) fun emit_order_record_removed(
        merchant_id: ID,
        payer: address,
        order_id: String,
    ) {
        event::emit(OrderRecordRemoved { merchant_id, payer, order_id });
    }
}
