#[test_only]
module floatsync::monkey_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant;
    use floatsync::payment;
    use floatsync::router::{Self, YieldVault};
    use floatsync::test_usdc::TEST_USDC;

    // ── Helpers ──

    fun setup(
        scenario: &mut test_scenario::Scenario,
        admin: address,
        merchant_addr: address,
    ) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
        // Create YieldVault for claim_yield_v2 tests
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        router::create_yield_vault<TEST_USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"MonkeyShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ══════════════════════════════════════════════
    // Monkey 1: u64 overflow in subscribe (amount_per_period * prepaid_periods)
    //   MAX_U64 / 2 + 1 * 2 = overflow
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_subscribe_overflow_amount_times_periods() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        // This will overflow: (MAX_U64/2 + 1) * 2 > MAX_U64
        let huge_coin = coin::mint_for_testing<TEST_USDC>(
            18_446_744_073_709_551_615, // MAX_U64
            scenario.ctx(),
        );
        let clock = clock::create_for_testing(scenario.ctx());

        // amount_per_period = MAX_U64/2 + 1, prepaid = 2 → overflow in multiplication
        payment::subscribe(
            &mut account, huge_coin,
            9_223_372_036_854_775_808, // 2^63
            86400_000,
            2,
            &clock, scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 2: Massive single payment (MAX_U64)
    // ══════════════════════════════════════════════

    #[test]
    fun test_pay_once_max_u64_amount() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let max_coin = coin::mint_for_testing<TEST_USDC>(
            18_446_744_073_709_551_615, // MAX_U64
            scenario.ctx(),
        );
        let clock = clock::create_for_testing(scenario.ctx());

        payment::pay_once(&mut account, max_coin, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 18_446_744_073_709_551_615);
        assert!(merchant::get_idle_principal(&account) == 18_446_744_073_709_551_615);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 3: Two MAX_U64/2 payments → overflow on total_received
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_pay_once_double_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // First payment: MAX_U64 / 2 + 1
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c1 = coin::mint_for_testing<TEST_USDC>(
            9_223_372_036_854_775_808, // 2^63
            scenario.ctx(),
        );
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c1, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Second payment: same amount → total_received overflows
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let c2 = coin::mint_for_testing<TEST_USDC>(
            9_223_372_036_854_775_808,
            scenario.ctx(),
        );
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, c2, &clock, scenario.ctx());

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 4: credit_yield more than idle_principal → underflow
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_credit_yield_exceeds_idle_principal_underflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Pay 100
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());

        // Try to credit 200 yield when idle is only 100 → underflow
        merchant::credit_yield_for_testing(&mut account, 200_000_000);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 5: Minimum period (1ms) rapid subscription processing
    // ══════════════════════════════════════════════

    #[test]
    fun test_subscribe_min_period_rapid_process() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        // 5 periods × 1 unit, period = 1ms
        let coin = coin::mint_for_testing<TEST_USDC>(5, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);

        payment::subscribe(
            &mut account, coin,
            1, // 1 unit per period
            1, // 1ms period
            5, // 5 periods
            &clock, scenario.ctx(),
        );
        // First period processed: total=1, escrow=4
        assert!(merchant::get_total_received(&account) == 1);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Rapid-fire process remaining 4 periods
        let mut i = 1u64;
        while (i <= 4) {
            scenario.next_tx(payer);
            let mut account = scenario.take_shared<merchant::MerchantAccount>();
            let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
            let mut clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut clock, i); // each ms

            payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

            test_scenario::return_shared(sub);
            test_scenario::return_shared(account);
            clock::destroy_for_testing(clock);
            i = i + 1;
        };

        // Verify all 5 periods processed
        scenario.next_tx(payer);
        let account = scenario.take_shared<merchant::MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 5);
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        assert!(payment::get_sub_balance(&sub) == 0);
        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);

        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 6: Subscribe with 1 prepaid_period → immediately drained escrow
    //   Then process → insufficient balance
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EInsufficientBalance
    fun test_subscribe_single_period_then_process_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);

        payment::subscribe(
            &mut account, coin,
            100, 1000, 1, // 1 period
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Try to process next period → escrow is 0 → abort
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 7: Fund with zero amount → fails
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EZeroAmount
    fun test_fund_subscription_zero_amount_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(10, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::subscribe(
            &mut account, coin,
            5, 1000, 2,
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Fund with 0 → should abort
        scenario.next_tx(payer);
        let account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let zero = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
        payment::fund_subscription(&account, &mut sub, zero, scenario.ctx());

        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 8: Subscribe with zero amount_per_period → fails
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EZeroAmount
    fun test_subscribe_zero_amount_per_period_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::subscribe(
            &mut account, coin,
            0, // zero amount per period
            1000, 3,
            &clock, scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 9: Subscribe with zero period_ms → fails
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EZeroPeriod
    fun test_subscribe_zero_period_ms_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::subscribe(
            &mut account, coin,
            10, 0, 3, // zero period
            &clock, scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 10: Subscribe with zero prepaid_periods → fails
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EZeroPrepaidPeriods
    fun test_subscribe_zero_prepaid_periods_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::subscribe(
            &mut account, coin,
            10, 1000, 0, // zero prepaid periods
            &clock, scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 11: Pay 1 unit (minimum non-zero amount)
    // ══════════════════════════════════════════════

    #[test]
    fun test_pay_once_minimum_amount() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let tiny = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::pay_once(&mut account, tiny, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 1);

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 12: Double claim_yield → second fails (zero yield)
    // ══════════════════════════════════════════════

    #[test]
    #[expected_failure] // EZeroYield
    fun test_double_claim_yield_fails() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Credit external yield + fund YieldVault
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin, &clock, scenario.ctx());
        merchant::credit_external_yield_for_testing(&mut account, 50);
        test_scenario::return_shared(account);

        let yield_coin = coin::mint_for_testing<TEST_USDC>(50, scenario.ctx());
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
        test_scenario::return_shared(yield_vault);
        clock::destroy_for_testing(clock);

        // First claim succeeds
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        assert!(merchant::get_accrued_yield(&account) == 0);

        // Second claim → zero yield → abort
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());

        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 13: Many rapid payments (stress test ledger accumulation)
    // ══════════════════════════════════════════════

    #[test]
    fun test_stress_many_payments() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        let mut i = 0u64;
        let payment_amount = 1_000_000u64; // 1 USDC each
        let num_payments = 20u64;

        while (i < num_payments) {
            scenario.next_tx(payer);
            let mut account = scenario.take_shared<merchant::MerchantAccount>();
            let coin = coin::mint_for_testing<TEST_USDC>(payment_amount, scenario.ctx());
            let clock = clock::create_for_testing(scenario.ctx());
            payment::pay_once(&mut account, coin, &clock, scenario.ctx());
            test_scenario::return_shared(account);
            clock::destroy_for_testing(clock);
            i = i + 1;
        };

        // Verify final state
        scenario.next_tx(admin);
        let account = scenario.take_shared<merchant::MerchantAccount>();
        assert!(merchant::get_total_received(&account) == payment_amount * num_payments);
        assert!(merchant::get_idle_principal(&account) == payment_amount * num_payments);
        test_scenario::return_shared(account);

        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 14: Process subscription exactly at boundary then 1ms before
    // ══════════════════════════════════════════════

    #[test]
    fun test_process_at_exact_boundary() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(20, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 100);

        payment::subscribe(
            &mut account, coin,
            10, 50, 2, // period = 50ms
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Process exactly at next_due = 150
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 150); // exact boundary

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(merchant::get_total_received(&account) == 20);
        assert!(payment::get_sub_balance(&sub) == 0);
        // next_due advanced to 200
        assert!(payment::get_sub_next_due(&sub) == 200);

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════
    // Monkey 15: Process well after due (late processing)
    // ══════════════════════════════════════════════

    #[test]
    fun test_process_subscription_late() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);
        scenario.next_tx(payer);

        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(30, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);

        payment::subscribe(
            &mut account, coin,
            10, 100, 3, // period = 100ms
            &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Process at t=999999 (way past due at t=100)
        // Only processes ONE period per call, next_due advances by period_ms
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 999_999);

        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        // next_due = 100 + 100 = 200 (not jumped to 999999)
        assert!(payment::get_sub_next_due(&sub) == 200);

        // Can immediately process again because 999999 >= 200
        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        assert!(payment::get_sub_next_due(&sub) == 300);
        assert!(payment::get_sub_balance(&sub) == 0);
        assert!(merchant::get_total_received(&account) == 30);

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }
}
