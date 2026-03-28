#[test_only]
module baleenpay::red_team_round_6_ordering {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry, AdminCap};
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

    // ── Attack 6a: Admin pauses merchant AFTER subscription created, blocks process ──
    // Permissionless process_subscription checks paused -- admin can DoS merchant's income
    #[test]
    #[expected_failure] // EPaused
    fun red_team_round_6a_pause_blocks_subscription_process() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer subscribes
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 1000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Admin pauses merchant
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Process should fail due to paused
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock2 = clock::create_for_testing(scenario.ctx());
        clock2.set_for_testing(2000);
        payment::process_subscription(&mut account, &mut sub, &clock2, scenario.ctx());
        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);
        clock2.destroy_for_testing();
        scenario.end();
    }

    // ── Attack 6b: Payer cancels subscription right before process is due ──
    // Race condition: payer cancels and gets refund, but what about pending due payment?
    #[test]
    fun red_team_round_6b_cancel_before_due_refunds_all_remaining() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe: 3 periods of 1M each, first auto-paid
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Immediately cancel -- should refund 2 remaining periods (2M)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        assert!(payment::get_sub_balance<TEST_USDC>(&sub) == 2_000_000);
        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        test_scenario::return_shared(account);

        // Verify payer got refund
        scenario.next_tx(payer);
        let refund = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
        assert!(refund.value() == 2_000_000);
        scenario.return_to_sender(refund);

        scenario.end();
        // FINDING: This is by design, but it means a subscriber can cancel immediately after
        // first payment and avoid all future payments. Merchant only gets 1 period guaranteed.
    }

    // ── Attack 6c: Payment to paused merchant is blocked ──
    #[test]
    #[expected_failure] // EPaused
    fun red_team_round_6c_pay_once_paused() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Admin pauses
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Payer tries to pay
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();
        scenario.end();
    }
}
