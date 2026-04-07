#[test_only]
module baleenpay::red_team_round_7_type_confusion {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry};
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;
    use baleenpay::brand_usd::BRAND_USD;

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Attack 7a: Subscribe with coin type A, fund with coin type B ──
    // Subscription<T> is parameterized. fund_subscription<T> must match.
    // Move type system enforces this at compile time -- cannot pass wrong type.
    // But we verify: subscribe with TEST_USDC, then pay_once with BRAND_USD to same merchant.
    // The ledger (total_received) mixes coin types -- no per-type accounting!
    #[test]
    fun red_team_round_7a_mixed_coin_type_ledger() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Pay with TEST_USDC
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin1 = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin1, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Pay with BRAND_USD (different coin type)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin2 = coin::mint_for_testing<BRAND_USD>(2_000_000, scenario.ctx());
        let clock2 = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin2, &clock2, scenario.ctx());

        // FINDING: total_received = 3M but it mixes two different coin types!
        // Ledger doesn't track per-coin-type totals.
        assert!(merchant::get_total_received(&account) == 3_000_000);

        test_scenario::return_shared(account);
        clock2.destroy_for_testing();
        scenario.end();
    }

    // ── Attack 7b: Process subscription of type A on same merchant that has type B subscription ──
    // Each Subscription<T> is a separate shared object. process_subscription checks merchant_id.
    // Move type system prevents type confusion at the balance level.
    #[test]
    fun red_team_round_7b_multi_type_subscriptions_independent() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe with TEST_USDC
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin1 = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin1, 1_000_000, 1000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Subscribe with BRAND_USD
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin2 = coin::mint_for_testing<BRAND_USD>(2_000_000, scenario.ctx());
        let clock2 = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin2, 1_000_000, 1000, 2, &clock2, scenario.ctx());
        test_scenario::return_shared(account);

        // Verify: 2 active subscriptions, total from both first payments = 2M
        scenario.next_tx(payer);
        let account = scenario.take_shared<MerchantAccount>();
        assert!(merchant::get_active_subscriptions(&account) == 2);
        assert!(merchant::get_total_received(&account) == 2_000_000); // 1M + 1M first payments
        test_scenario::return_shared(account);

        clock2.destroy_for_testing();
        scenario.end();
    }
}
