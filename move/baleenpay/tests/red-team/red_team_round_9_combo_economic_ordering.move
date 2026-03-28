#[test_only]
module baleenpay::red_team_round_9_combo {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Attack 9a: Rapid subscribe + cancel to grief merchant (economic + ordering) ──
    // Subscribe with min prepaid (1 period) to guarantee only first auto-payment,
    // then immediately cancel to get 0 refund but increment/decrement subscription counter.
    // Repeated: merchant's active_subscriptions flickers but no real damage beyond gas.
    #[test]
    fun red_team_round_9a_rapid_subscribe_cancel_grief() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let attacker = @0xEE;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe with 1 period only, auto-pays immediately, balance = 0
        scenario.next_tx(attacker);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 1, &clock, scenario.ctx());
        assert!(merchant::get_active_subscriptions(&account) == 1);
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Immediately cancel
        scenario.next_tx(attacker);
        let mut account = scenario.take_shared<MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        // Balance should be 0 after first period auto-paid
        assert!(payment::get_sub_balance<TEST_USDC>(&sub) == 0);
        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        assert!(merchant::get_active_subscriptions(&account) == 0);
        // Merchant still received the 1M payment
        assert!(merchant::get_total_received(&account) == 1_000_000);
        test_scenario::return_shared(account);

        scenario.end();
        // FINDING: No real exploit, but attacker can create churn in subscription count.
        // Each subscribe+cancel costs attacker gas + amount_per_period (paid to merchant).
        // Merchant profits from each cycle. Not a viable attack vector.
    }

    // ── Attack 9b: remove_order_record + replay attack (economic + access) ──
    // Malicious merchant removes order record, but payer's off-chain system auto-retries.
    // This verifies the ledger tracks the double payment correctly.
    #[test]
    fun red_team_round_9b_remove_and_replay_ledger_tracking() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // First payment
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin1 = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, b"INVOICE-42".to_string(), &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 5_000_000);
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Merchant removes record
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        payment::remove_order_record(&cap, &mut account, payer, b"INVOICE-42".to_string());
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Payer's system re-sends same order_id (auto-retry or user tricked)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin2 = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
        let clock2 = clock::create_for_testing(scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, b"INVOICE-42".to_string(), &clock2, scenario.ctx());
        // Merchant now has 10M total, payer paid twice for same invoice
        assert!(merchant::get_total_received(&account) == 10_000_000);
        test_scenario::return_shared(account);
        clock2.destroy_for_testing();

        scenario.end();
        // CRITICAL FINDING: remove_order_record enables merchant to cause double-charging.
        // The contract has a WARNING comment but no on-chain guard against this pattern.
    }

    // ── Attack 9c: Fund subscription with 0 amount ──
    #[test]
    #[expected_failure] // EZeroAmount
    fun red_team_round_9c_fund_zero() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 2, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        scenario.next_tx(payer);
        let account = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let zero_coin = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
        payment::fund_subscription(&account, &mut sub, zero_coin, scenario.ctx());
        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);
        scenario.end();
    }
}
