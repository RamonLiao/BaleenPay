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
    }

    public struct MerchantUnpaused has copy, drop {
        merchant_id: ID,
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

    public fun emit_merchant_registered(merchant_id: ID, brand_name: String, owner: address) {
        event::emit(MerchantRegistered { merchant_id, brand_name, owner });
    }

    public fun emit_merchant_paused(merchant_id: ID) {
        event::emit(MerchantPaused { merchant_id });
    }

    public fun emit_merchant_unpaused(merchant_id: ID) {
        event::emit(MerchantUnpaused { merchant_id });
    }

    public fun emit_payment_received(
        merchant_id: ID,
        payer: address,
        amount: u64,
        payment_type: u8,
        timestamp: u64,
    ) {
        event::emit(PaymentReceived { merchant_id, payer, amount, payment_type, timestamp });
    }

    public fun emit_subscription_created(
        merchant_id: ID,
        payer: address,
        amount_per_period: u64,
        period_ms: u64,
        prepaid_periods: u64,
    ) {
        event::emit(SubscriptionCreated { merchant_id, payer, amount_per_period, period_ms, prepaid_periods });
    }

    public fun emit_subscription_processed(
        merchant_id: ID,
        payer: address,
        amount: u64,
        next_due: u64,
    ) {
        event::emit(SubscriptionProcessed { merchant_id, payer, amount, next_due });
    }

    public fun emit_subscription_cancelled(
        merchant_id: ID,
        payer: address,
        refunded_amount: u64,
    ) {
        event::emit(SubscriptionCancelled { merchant_id, payer, refunded_amount });
    }

    public fun emit_subscription_funded(
        merchant_id: ID,
        payer: address,
        funded_amount: u64,
    ) {
        event::emit(SubscriptionFunded { merchant_id, payer, funded_amount });
    }
}
