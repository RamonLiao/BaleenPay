#[test_only]
module floatsync::router_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant;
    use floatsync::payment;
    use floatsync::router;
    use floatsync::test_usdc::TEST_USDC;

    // ── Helpers ──

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Router Config Tests ──

    #[test]
    fun test_router_init_fallback_mode() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        scenario.next_tx(admin);
        router::init_for_testing(scenario.ctx());

        scenario.next_tx(admin);
        let config = scenario.take_shared<router::RouterConfig>();
        assert!(router::get_mode(&config) == 0);
        assert!(router::is_fallback(&config));
        test_scenario::return_shared(config);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = router::ESameMode)]
    fun test_set_mode_same_mode_fails() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut config = scenario.take_shared<router::RouterConfig>();

        // Try to set same mode (0 → 0) → should abort
        router::set_mode(&admin_cap, &mut config, 0);

        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = router::EInvalidMode)]
    fun test_set_mode_invalid_mode_fails() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut config = scenario.take_shared<router::RouterConfig>();

        // Mode 5 is invalid
        router::set_mode(&admin_cap, &mut config, 5);

        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    // ── claim_yield Tests ──

    #[test]
    fun test_claim_yield_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Payer makes a payment to create idle_principal
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());
        assert!(merchant::get_idle_principal(&account) == 100_000_000);

        // Simulate yield accrual: 5 USDC yield from 100 idle_principal
        merchant::credit_yield_for_testing(&mut account, 5_000_000);
        assert!(merchant::get_accrued_yield(&account) == 5_000_000);
        assert!(merchant::get_idle_principal(&account) == 95_000_000);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Merchant claims yield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        let claimed = merchant::claim_yield(&cap, &mut account);
        assert!(claimed == 5_000_000);
        assert!(merchant::get_accrued_yield(&account) == 0);

        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = merchant::EZeroYield)]
    fun test_claim_yield_zero_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // No yield accrued → should abort
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        merchant::claim_yield(&cap, &mut account);

        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = merchant::ENotMerchantOwner)]
    fun test_claim_yield_wrong_cap_fails() {
        let admin = @0xAD;
        let merchant_a = @0xBB;
        let merchant_b = @0xCC;
        let payer = @0xDD;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_a);

        // Register a second merchant
        scenario.next_tx(merchant_b);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"OtherShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Pay merchant_a to create idle_principal, then simulate yield.
        // Take both accounts, identify by owner, operate on the correct one.
        scenario.next_tx(payer);
        let mut acct_1 = scenario.take_shared<merchant::MerchantAccount>();
        let mut acct_2 = scenario.take_shared<merchant::MerchantAccount>();

        // Identify which is merchant_a's account
        let (account_a_is_1) = merchant::get_owner(&acct_1) == merchant_a;

        if (account_a_is_1) {
            let coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
            let clock = clock::create_for_testing(scenario.ctx());
            payment::pay_once(&mut acct_1, coin, &clock, scenario.ctx());
            merchant::credit_yield_for_testing(&mut acct_1, 2_000_000);
            clock::destroy_for_testing(clock);
        } else {
            let coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
            let clock = clock::create_for_testing(scenario.ctx());
            payment::pay_once(&mut acct_2, coin, &clock, scenario.ctx());
            merchant::credit_yield_for_testing(&mut acct_2, 2_000_000);
            clock::destroy_for_testing(clock);
        };

        test_scenario::return_shared(acct_1);
        test_scenario::return_shared(acct_2);

        // merchant_b tries to claim merchant_a's yield → wrong cap → abort
        scenario.next_tx(merchant_b);
        let cap_b = scenario.take_from_sender<merchant::MerchantCap>();

        // Take both again, find merchant_a's account
        let mut acct_1 = scenario.take_shared<merchant::MerchantAccount>();
        let mut acct_2 = scenario.take_shared<merchant::MerchantAccount>();

        if (merchant::get_owner(&acct_1) == merchant_a) {
            // cap_b belongs to merchant_b, account belongs to merchant_a → mismatch
            merchant::claim_yield(&cap_b, &mut acct_1);
            test_scenario::return_shared(acct_1);
            test_scenario::return_shared(acct_2);
        } else {
            merchant::claim_yield(&cap_b, &mut acct_2);
            test_scenario::return_shared(acct_1);
            test_scenario::return_shared(acct_2);
        };

        scenario.return_to_sender(cap_b);
        scenario.end();
    }

    // ── Fallback mode payment flow (unchanged behavior) ──

    #[test]
    fun test_fallback_mode_payment_direct() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Verify router is in fallback mode
        scenario.next_tx(admin);
        let config = scenario.take_shared<router::RouterConfig>();
        assert!(router::is_fallback(&config));
        test_scenario::return_shared(config);

        // Payment goes directly to merchant (same as before — fallback = no routing)
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());

        assert!(merchant::get_total_received(&account) == 100_000_000);
        assert!(merchant::get_idle_principal(&account) == 100_000_000);
        assert!(merchant::get_accrued_yield(&account) == 0); // no yield in fallback

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
}
