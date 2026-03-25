module floatsync::events {
    use sui::object::ID;
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
}
