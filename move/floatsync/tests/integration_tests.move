#[test_only]
module floatsync::integration_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant;
    use floatsync::payment;
    use floatsync::router;
    use floatsync::test_usdc::TEST_USDC;

    // ── Helpers ──

    fun full_setup(
        scenario: &mut test_scenario::Scenario,
        admin: address,
        merchant_addr: address,
    ) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"IntegShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ══════════════════════════════════════════════
    // Integration Test 1: Full lifecycle
    //   register → pay_once → credit_yield → claim_yield
    // ══════════════════════════════════════════════

    #[test]
    fun test_full_lifecycle_pay_yield_claim() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // ─ Step 1: Payer makes 200 USDC payment ─
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(200_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());

        assert!(merchant::get_total_received(&account) == 200_000_000);
        assert!(merchant::get_idle_principal(&account) == 200_000_000);
        assert!(merchant::get_accrued_yield(&account) == 0);

        // ─ Step 2: Simulate yield accrual (10 USDC) ─
        merchant::credit_yield_for_testing(&mut account, 10_000_000);
        assert!(merchant::get_idle_principal(&account) == 190_000_000);
        assert!(merchant::get_accrued_yield(&account) == 10_000_000);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Step 3: Merchant claims yield ─
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        let claimed = merchant::claim_yield(&cap, &mut account);
        assert!(claimed == 10_000_000);
        assert!(merchant::get_accrued_yield(&account) == 0);
        assert!(merchant::get_idle_principal(&account) == 190_000_000);
        // total_received unchanged by yield ops
        assert!(merchant::get_total_received(&account) == 200_000_000);

        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 2: Subscribe → process all periods → cancel (zero refund)
    // ══════════════════════════════════════════════

    #[test]
    fun test_subscribe_process_all_then_cancel() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let bot = @0xDD;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Subscribe: 3 periods × 10 USDC
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(30_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        payment::subscribe(
            &mut account, coin,
            10_000_000, 86400_000, 3,
            &clock, scenario.ctx(),
        );
        // First period processed: total=10, subs=1, escrow=20
        assert!(merchant::get_total_received(&account) == 10_000_000);
        assert!(merchant::get_active_subscriptions(&account) == 1);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Process period 2 ─
        scenario.next_tx(bot);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000 + 86400_000);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 20_000_000);
        assert!(payment::get_sub_balance(&sub) == 10_000_000);

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Process period 3 (last) ─
        scenario.next_tx(bot);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000 + 86400_000 * 2);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 30_000_000);
        assert!(payment::get_sub_balance(&sub) == 0); // fully drained

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Payer cancels with zero balance → no refund coin ─
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();

        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        assert!(merchant::get_active_subscriptions(&account) == 0);
        assert!(merchant::get_idle_principal(&account) == 30_000_000);

        test_scenario::return_shared(account);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 3: Subscribe → fund → process → cancel (partial refund)
    // ══════════════════════════════════════════════

    #[test]
    fun test_subscribe_fund_process_cancel_lifecycle() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Subscribe: 2 periods × 10 USDC = 20 total
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        payment::subscribe(
            &mut account, coin,
            10_000_000, 86400_000, 2,
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Fund: add 30 more USDC ─
        scenario.next_tx(payer);
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let extra = coin::mint_for_testing<TEST_USDC>(30_000_000, scenario.ctx());
        payment::fund_subscription(&mut sub, extra, scenario.ctx());
        // Balance: 10 (1 remaining) + 30 = 40
        assert!(payment::get_sub_balance(&sub) == 40_000_000);
        test_scenario::return_shared(sub);

        // ─ Process period 2 ─
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000 + 86400_000);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(payment::get_sub_balance(&sub) == 30_000_000);
        assert!(merchant::get_total_received(&account) == 20_000_000);

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ─ Cancel → refund 30 USDC ─
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();

        payment::cancel_subscription(&mut account, sub, scenario.ctx());
        assert!(merchant::get_active_subscriptions(&account) == 0);
        test_scenario::return_shared(account);

        // Verify refund
        scenario.next_tx(payer);
        let refund = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
        assert!(refund.value() == 30_000_000);
        scenario.return_to_sender(refund);

        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 4: Pause blocks subscription process, unpause resumes
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = payment::EPaused)]
    fun test_pause_blocks_process_subscription() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Subscribe
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        payment::subscribe(
            &mut account, coin,
            10_000_000, 86400_000, 2,
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Admin pauses
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Process while paused → should abort
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000 + 86400_000);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 5: Unpause then process succeeds
    // ══════════════════════════════════════════════

    #[test]
    fun test_unpause_then_process_succeeds() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Subscribe
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        payment::subscribe(
            &mut account, coin,
            10_000_000, 86400_000, 2,
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Admin pauses then unpauses
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        merchant::unpause_merchant(&admin_cap, &mut account);
        assert!(!merchant::get_paused(&account));
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Process succeeds after unpause
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000 + 86400_000);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 20_000_000);

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 6: Multiple payers to same merchant
    // ══════════════════════════════════════════════

    #[test]
    fun test_multiple_payers_same_merchant() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer1 = @0xC1;
        let payer2 = @0xC2;
        let payer3 = @0xC3;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Payer1: pay_once 100
        scenario.next_tx(payer1);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c1, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer2: subscribe 2×50
        scenario.next_tx(payer2);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c2 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        payment::subscribe(
            &mut account, c2, 50_000_000, 86400_000, 2,
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer3: pay_once 25
        scenario.next_tx(payer3);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c3 = coin::mint_for_testing<TEST_USDC>(25_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c3, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Verify accumulated totals: 100 + 50 (first period) + 25 = 175
        scenario.next_tx(admin);
        let account = scenario.take_shared<merchant::MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 175_000_000);
        assert!(merchant::get_idle_principal(&account) == 175_000_000);
        assert!(merchant::get_active_subscriptions(&account) == 1);
        test_scenario::return_shared(account);

        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 7: Multiple subscriptions same merchant
    // ══════════════════════════════════════════════

    #[test]
    fun test_multiple_subscriptions_same_merchant() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer1 = @0xC1;
        let payer2 = @0xC2;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Payer1 subscribes: 2×10
        scenario.next_tx(payer1);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c1 = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(
            &mut account, c1, 10_000_000, 86400_000, 2,
            &clock, scenario.ctx(),
        );
        assert!(merchant::get_active_subscriptions(&account) == 1);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer2 subscribes: 3×5
        scenario.next_tx(payer2);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c2 = coin::mint_for_testing<TEST_USDC>(15_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(
            &mut account, c2, 5_000_000, 3600_000, 3,
            &clock, scenario.ctx(),
        );
        assert!(merchant::get_active_subscriptions(&account) == 2);
        // total: 10 (payer1 first) + 5 (payer2 first) = 15
        assert!(merchant::get_total_received(&account) == 15_000_000);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer1 cancels their sub → subs count drops to 1
        scenario.next_tx(payer1);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let sub1 = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        // Need to find payer1's sub
        if (payment::get_sub_payer(&sub1) == payer1) {
            payment::cancel_subscription(&mut account, sub1, scenario.ctx());
            assert!(merchant::get_active_subscriptions(&account) == 1);
            test_scenario::return_shared(account);
        } else {
            test_scenario::return_shared(sub1);
            let sub2 = scenario.take_shared<payment::Subscription<TEST_USDC>>();
            payment::cancel_subscription(&mut account, sub2, scenario.ctx());
            assert!(merchant::get_active_subscriptions(&account) == 1);
            test_scenario::return_shared(account);
        };

        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 8: Pay + yield + claim + pay again (ledger consistency)
    // ══════════════════════════════════════════════

    #[test]
    fun test_yield_claim_then_more_payments() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Pay 100
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c1, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Yield 10, claim it
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::credit_yield_for_testing(&mut account, 10_000_000);
        let claimed = merchant::claim_yield(&cap, &mut account);
        assert!(claimed == 10_000_000);
        // State: total=100, idle=90, yield=0
        assert!(merchant::get_idle_principal(&account) == 90_000_000);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Pay another 50
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c2 = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c2, &clock, scenario.ctx());

        // State: total=150, idle=140, yield=0
        assert!(merchant::get_total_received(&account) == 150_000_000);
        assert!(merchant::get_idle_principal(&account) == 140_000_000);
        assert!(merchant::get_accrued_yield(&account) == 0);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Integration Test 9: Router fallback mode + yield flow coexist
    // ══════════════════════════════════════════════

    #[test]
    fun test_router_fallback_with_yield_flow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        full_setup(&mut scenario, admin, merchant_addr);

        // Verify router is fallback
        scenario.next_tx(admin);
        let config = scenario.take_shared<router::RouterConfig>();
        assert!(router::is_fallback(&config));
        test_scenario::return_shared(config);

        // Pay 500
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(500_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Simulate yield of 25 and claim
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::credit_yield_for_testing(&mut account, 25_000_000);
        let claimed = merchant::claim_yield(&cap, &mut account);
        assert!(claimed == 25_000_000);

        // In fallback mode yield still works at ledger level (actual yield source is future)
        assert!(merchant::get_idle_principal(&account) == 475_000_000);

        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
