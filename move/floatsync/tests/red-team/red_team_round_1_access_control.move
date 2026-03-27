#[test_only]
module floatsync::red_team_round_1_access_control {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry};
    use floatsync::payment;
    use floatsync::test_usdc::TEST_USDC;

    // ── Attack 1a: Use merchant A's cap on merchant B's account ──
    #[test]
    #[expected_failure(abort_code = 0)] // ENotMerchantOwner
    fun red_team_round_1a_cross_merchant_cap_claim_yield() {
        let admin = @0xAD;
        let merchant_a = @0xA1;
        let merchant_b = @0xB2;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        // Init
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());

        // Register merchant A
        scenario.next_tx(merchant_a);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopA".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Register merchant B
        scenario.next_tx(merchant_b);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Payer pays merchant B so there's idle_principal
        scenario.next_tx(payer);
        let mut account_b = scenario.take_shared<MerchantAccount>();
        let payment_coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account_b, payment_coin, &clock, scenario.ctx());
        // Simulate yield
        merchant::credit_yield_for_testing(&mut account_b, 500_000);
        test_scenario::return_shared(account_b);
        clock::destroy_for_testing(clock);

        // ATTACK: merchant A tries to claim yield from merchant B using A's cap
        scenario.next_tx(merchant_a);
        let cap_a = scenario.take_from_sender<MerchantCap>();
        let mut account_b = scenario.take_shared<MerchantAccount>();
        // This should abort with ENotMerchantOwner
        let _amount = merchant::claim_yield(&cap_a, &mut account_b);
        test_scenario::return_shared(account_b);
        scenario.return_to_sender(cap_a);
        scenario.end();
    }

    // ── Attack 1b: Cross-merchant cap for self_pause ──
    #[test]
    #[expected_failure(abort_code = 0)] // ENotMerchantOwner
    fun red_team_round_1b_cross_merchant_cap_self_pause() {
        let admin = @0xAD;
        let merchant_a = @0xA1;
        let merchant_b = @0xB2;
        let mut scenario = test_scenario::begin(admin);

        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());

        scenario.next_tx(merchant_a);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopA".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        scenario.next_tx(merchant_b);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // ATTACK: A tries to pause B's account
        scenario.next_tx(merchant_a);
        let cap_a = scenario.take_from_sender<MerchantCap>();
        let mut account_b = scenario.take_shared<MerchantAccount>();
        merchant::self_pause(&cap_a, &mut account_b); // Should abort
        test_scenario::return_shared(account_b);
        scenario.return_to_sender(cap_a);
        scenario.end();
    }

    // ── Attack 1c: Cross-merchant cap for remove_order_record ──
    #[test]
    #[expected_failure(abort_code = 0)] // ENotMerchantOwner
    fun red_team_round_1c_cross_merchant_remove_order() {
        let admin = @0xAD;
        let merchant_a = @0xA1;
        let merchant_b = @0xB2;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());

        scenario.next_tx(merchant_a);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopA".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        scenario.next_tx(merchant_b);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Payer pays merchant B with order_id
        scenario.next_tx(payer);
        let mut account_b = scenario.take_shared<MerchantAccount>();
        let payment_coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once_v2(&mut account_b, payment_coin, b"ORDER-001".to_string(), &clock, scenario.ctx());
        test_scenario::return_shared(account_b);
        clock::destroy_for_testing(clock);

        // ATTACK: merchant A tries to remove order record from B
        scenario.next_tx(merchant_a);
        let cap_a = scenario.take_from_sender<MerchantCap>();
        let mut account_b = scenario.take_shared<MerchantAccount>();
        payment::remove_order_record(&cap_a, &mut account_b, payer, b"ORDER-001".to_string());
        test_scenario::return_shared(account_b);
        scenario.return_to_sender(cap_a);
        scenario.end();
    }

    // ── Attack 1d: Non-payer cancels subscription ──
    #[test]
    #[expected_failure(abort_code = 3)] // ENotPayer
    fun red_team_round_1d_non_payer_cancel_subscription() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let attacker = @0xEE;
        let mut scenario = test_scenario::begin(admin);

        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Payer creates subscription
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 5, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // ATTACK: attacker (not the payer) tries to cancel
        scenario.next_tx(attacker);
        let mut account = scenario.take_shared<MerchantAccount>();
        let subscription = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        payment::cancel_subscription(&mut account, subscription, scenario.ctx());
        test_scenario::return_shared(account);
        scenario.end();
    }
}
