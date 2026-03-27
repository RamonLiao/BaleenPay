#[test_only]
module floatsync::red_team_round_10_combo {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant::{Self, MerchantAccount, MerchantRegistry, AdminCap};
    use floatsync::payment;
    use floatsync::test_usdc::TEST_USDC;

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── 10a: Admin freeze blocks cancel — regulatory hold ──
    #[test]
    #[expected_failure]
    fun red_team_round_10a_cancel_blocked_by_admin_freeze() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Admin freezes
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Payer tries to cancel — blocked by admin freeze (EAdminFrozen)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        test_scenario::return_shared(account);

        scenario.end();
    }

    // ── 10a2: Self-pause still allows cancel — payer can always exit merchant-initiated pause ──
    #[test]
    fun red_team_round_10a2_cancel_allowed_during_self_pause() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Merchant self-pauses
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::self_pause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == false);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Payer cancels — allowed (self-pause, not admin freeze)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        test_scenario::return_shared(account);

        // Payer gets refund
        scenario.next_tx(payer);
        let refund = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
        assert!(refund.value() == 2_000_000);
        scenario.return_to_sender(refund);

        scenario.end();
    }

    // ── Attack 10b: Process subscription with insufficient balance ──
    #[test]
    #[expected_failure] // EInsufficientBalance
    fun red_team_round_10b_process_empty_subscription() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Subscribe with exactly 1 period (auto-pays, balance = 0)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 1000, 1, &clock, scenario.ctx());
        test_scenario::return_shared(account);

        // Try to process when balance is 0
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        clock.set_for_testing(2000);
        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);
        clock.destroy_for_testing();
        scenario.end();
    }

    // ── Attack 10c: Double registration attempt ──
    #[test]
    #[expected_failure] // EAlreadyRegistered
    fun red_team_round_10c_double_register() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Try to register again with same address
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopDupe".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.end();
    }

    // ── Attack 10d: subscribe_v2 with MAX_PREPAID_PERIODS+1 ──
    #[test]
    #[expected_failure]
    fun red_team_round_10d_exceed_max_prepaid() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(18_446_744_073_709_551_615, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        // 1001 periods > MAX_PREPAID_PERIODS (1000)
        payment::subscribe_v2(
            &mut account, coin, 1, 1000, 1001,
            b"ORDER-MAX".to_string(), &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock.destroy_for_testing();
        scenario.end();
    }
}
