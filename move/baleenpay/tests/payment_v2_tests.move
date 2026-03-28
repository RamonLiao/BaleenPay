#[test_only]
module baleenpay::payment_v2_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use std::string;
    use baleenpay::merchant;
    use baleenpay::payment;
    use baleenpay::test_usdc::TEST_USDC;

    fun setup_merchant(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── pay_once_v2 ──

    #[test]
    fun test_pay_once_v2_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let payment_coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::pay_once_v2(
            &mut account,
            payment_coin,
            string::utf8(b"order_001"),
            &clock,
            scenario.ctx(),
        );

        assert!(merchant::get_total_received(&account) == 100_000_000);
        assert!(payment::has_order_record(&account, payer, string::utf8(b"order_001")));

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EOrderAlreadyPaid (#[error] constant)
    fun test_pay_once_v2_duplicate_order_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());

        let coin1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, string::utf8(b"order_dup"), &clock, scenario.ctx());

        let coin2 = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_dup"), &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_pay_once_v2_different_payers_same_order_ok() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer1 = @0xCC;
        let payer2 = @0xDD;
        let mut scenario = test_scenario::begin(admin);

        setup_merchant(&mut scenario, admin, merchant_addr);

        // Payer 1 pays
        scenario.next_tx(payer1);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin1 = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, string::utf8(b"order_shared"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Payer 2 pays same order_id — should succeed
        scenario.next_tx(payer2);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin2 = coin::mint_for_testing<TEST_USDC>(200_000_000, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_shared"), &clock, scenario.ctx());

        assert!(merchant::get_total_received(&account) == 300_000_000);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EInvalidOrderId (#[error] constant)
    fun test_pay_once_v2_empty_order_id_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b""), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EInvalidOrderId (#[error] constant)
    fun test_pay_once_v2_space_in_order_id_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"order 123"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ── subscribe_v2 ──

    #[test]
    fun test_subscribe_v2_success() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());

        payment::subscribe_v2(
            &mut account,
            coin,
            100_000_000,
            86_400_000,
            3,
            string::utf8(b"sub_001"),
            &clock,
            scenario.ctx(),
        );

        assert!(merchant::get_total_received(&account) == 100_000_000);
        assert!(payment::has_order_record(&account, payer, string::utf8(b"sub_001")));

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EOrderAlreadyPaid (#[error] constant)
    fun test_subscribe_v2_duplicate_order_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());

        let coin1 = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());
        payment::subscribe_v2(&mut account, coin1, 100_000_000, 86_400_000, 3, string::utf8(b"sub_dup"), &clock, scenario.ctx());

        let coin2 = coin::mint_for_testing<TEST_USDC>(300_000_000, scenario.ctx());
        payment::subscribe_v2(&mut account, coin2, 100_000_000, 86_400_000, 3, string::utf8(b"sub_dup"), &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ── remove_order_record ──

    #[test]
    fun test_remove_order_record_and_repay() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        // Payer pays
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"order_rm"), &clock, scenario.ctx());
        assert!(payment::has_order_record(&account, payer, string::utf8(b"order_rm")));
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Merchant removes record
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        payment::remove_order_record(&cap, &mut account, payer, string::utf8(b"order_rm"));
        assert!(!payment::has_order_record(&account, payer, string::utf8(b"order_rm")));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);

        // Payer can now re-pay same order_id
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin2 = coin::mint_for_testing<TEST_USDC>(200, scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, string::utf8(b"order_rm"), &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 300);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        scenario.end();
    }

    // ── Edge cases ──

    #[test]
    #[expected_failure] // EZeroAmount
    fun test_pay_once_v2_zero_amount_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"zero_test"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EPaused
    fun test_pay_once_v2_paused_merchant_aborts() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        // Admin pauses merchant
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Payer tries v2 payment — should fail
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account, coin, string::utf8(b"paused_test"), &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure]
    fun test_remove_order_record_wrong_cap_aborts() {
        let admin = @0xAD;
        let merchant_addr1 = @0xBB;
        let merchant_addr2 = @0xDD;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr1);

        // Payer pays merchant 1
        scenario.next_tx(payer);
        let mut account1 = scenario.take_shared<merchant::MerchantAccount>();
        let clock = clock::create_for_testing(scenario.ctx());
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        payment::pay_once_v2(&mut account1, coin, string::utf8(b"wrong_cap"), &clock, scenario.ctx());
        let account1_id = object::id(&account1);
        test_scenario::return_shared(account1);
        clock::destroy_for_testing(clock);

        // Register second merchant (after payment, so take_shared above is unambiguous)
        scenario.next_tx(merchant_addr2);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"OtherShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Merchant 2 tries to remove merchant 1's order record — should fail
        scenario.next_tx(merchant_addr2);
        let mut account1 = scenario.take_shared_by_id<merchant::MerchantAccount>(account1_id);
        let cap2 = scenario.take_from_sender<merchant::MerchantCap>();
        payment::remove_order_record(&cap2, &mut account1, payer, string::utf8(b"wrong_cap"));
        scenario.return_to_sender(cap2);
        test_scenario::return_shared(account1);
        scenario.end();
    }

    // ── self_pause / self_unpause ──

    #[test]
    fun test_self_pause_and_unpause() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup_merchant(&mut scenario, admin, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let cap = scenario.take_from_sender<merchant::MerchantCap>();

        merchant::self_pause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == true);

        merchant::self_unpause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == false);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);
        scenario.end();
    }
}
