#[test_only]
module floatsync::red_team_round_4_economic {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry};
    use floatsync::payment;
    use floatsync::router::{Self, YieldVault};
    use floatsync::test_usdc::TEST_USDC;

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
        // Create YieldVault for claim_yield_v2 tests
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        router::create_yield_vault<TEST_USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Attack 4a: Merchant removes order record then payer "double-pays" same order ──
    // remove_order_record clears the dedup guard. Malicious merchant could:
    // 1. Accept payment with order_id
    // 2. Remove order record
    // 3. Trick payer into paying again with same order_id
    // This is BY DESIGN (WARNING in code), but the risk is real.
    #[test]
    fun red_team_round_4a_remove_then_double_pay() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer pays with order_id
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin1 = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once_v2(&mut account, coin1, b"ORDER-001".to_string(), &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 1_000_000);
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Merchant removes order record
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        payment::remove_order_record(&cap, &mut account, payer, b"ORDER-001".to_string());
        assert!(!payment::has_order_record(&account, payer, b"ORDER-001".to_string()));
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // EXPLOIT: Same order_id can now be paid again!
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin2 = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock2 = clock::create_for_testing(scenario.ctx());
        payment::pay_once_v2(&mut account, coin2, b"ORDER-001".to_string(), &clock2, scenario.ctx());
        // Double payment succeeded -- merchant received 2M total
        assert!(merchant::get_total_received(&account) == 2_000_000);
        test_scenario::return_shared(account);
        clock2.destroy_for_testing();
        scenario.end();
    }

    // ── Attack 4b: Grief merchant by paying dust (1 unit) to bloat ledger ──
    // pay_once only checks amount > 0, so 1 unit is valid.
    // Each payment adds to total_received/idle_principal -- no real harm, just dust.
    // But with pay_once_v2, each order_id creates a dynamic field -- storage cost.
    #[test]
    fun red_team_round_4b_dust_payment_storage_cost() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let attacker = @0xEE;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Attacker sends many dust payments with unique order_ids
        let mut i = 0u64;
        while (i < 10) {
            scenario.next_tx(attacker);
            let mut account = scenario.take_shared<MerchantAccount>();
            let coin = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
            let clock = clock::create_for_testing(scenario.ctx());

            // Each creates a dynamic field on merchant account
            let mut order_bytes = b"DUST-";
            order_bytes.push_back(0x30 + ((i % 10) as u8));
            payment::pay_once_v2(
                &mut account, coin, order_bytes.to_string(), &clock, scenario.ctx(),
            );
            test_scenario::return_shared(account);
            clock.destroy_for_testing();
            i = i + 1;
        };

        // Verify: 10 dust payments, 10 dynamic fields created
        scenario.next_tx(attacker);
        let account = scenario.take_shared<MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 10); // 10 * 1 unit
        test_scenario::return_shared(account);
        scenario.end();
        // FINDING: Each pay_once_v2 adds a dynamic field. Attacker pays gas + 1 unit per field.
        // Merchant cannot remove these without MerchantCap for each (payer, order_id) pair.
        // Storage bloat is attacker-funded, but merchant's object grows.
    }

    // ── Attack 4c: claim_yield twice (double drain) ──
    #[test]
    #[expected_failure] // EZeroYield
    fun red_team_round_4c_double_claim_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer pays, then simulate external yield + fund YieldVault
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(10_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());
        merchant::credit_external_yield_for_testing(&mut account, 5_000_000);
        test_scenario::return_shared(account);

        let yield_coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
        test_scenario::return_shared(yield_vault);
        clock.destroy_for_testing();

        // First claim succeeds
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        assert!(merchant::get_accrued_yield(&account) == 0);
        // Second claim in same tx should fail with EZeroYield
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    // ── Attack 4d: Process subscription for someone else's benefit ──
    // process_subscription is permissionless. Anyone can trigger it.
    // Verify: payment still goes to correct merchant, not caller.
    #[test]
    fun red_team_round_4d_permissionless_process_correct_recipient() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let random_caller = @0xDD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer creates subscription
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 1000, 3, &clock, scenario.ctx());
        test_scenario::return_shared(account);

        // Random caller processes subscription (after first auto-payment, 2 periods left)
        scenario.next_tx(random_caller);
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        clock.set_for_testing(2000); // past next_due
        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);

        // Verify: payment went to merchant, NOT to random_caller
        scenario.next_tx(merchant_addr);
        // Merchant should have received coins (from first auto + process)
        let received = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
        assert!(received.value() == 1_000_000); // first auto-payment
        scenario.return_to_sender(received);
        let received2 = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
        assert!(received2.value() == 1_000_000); // second process
        scenario.return_to_sender(received2);

        clock.destroy_for_testing();
        scenario.end();
    }
}
