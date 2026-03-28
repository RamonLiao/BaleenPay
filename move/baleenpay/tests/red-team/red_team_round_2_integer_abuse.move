#[test_only]
module baleenpay::red_team_round_2_integer_abuse {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry};
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

    // ── Attack 2a: subscribe() overflow via amount_per_period * prepaid_periods ──
    // subscribe (v1) now has explicit overflow guard (backported from v2).
    #[test]
    #[expected_failure]
    fun red_team_round_2a_subscribe_v1_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        // amount_per_period = (MAX_U64 / 2) + 1 = 9223372036854775808
        // prepaid_periods = 2
        // product = 18446744073709551616 which overflows u64
        let amount_per_period: u64 = 9_223_372_036_854_775_808;
        let prepaid_periods: u64 = 2;
        // We only need a small coin since overflow wraps to small value
        // Overflow: 9223372036854775808 * 2 = 0 (wraps to 0 in u64)
        // total_required = 0, so even a small coin passes >= check
        let coin = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        // This will either: abort with VM arithmetic overflow, or succeed with wrapped value
        // If it succeeds, the payer locks only tiny amount but gets subscription for huge per-period
        payment::subscribe(
            &mut account,
            coin,
            amount_per_period,
            86400_000,
            prepaid_periods,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ── Attack 2b: subscribe_v2 has overflow guard -- verify it blocks ──
    #[test]
    #[expected_failure]
    fun red_team_round_2b_subscribe_v2_overflow_defended() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let amount_per_period: u64 = 9_223_372_036_854_775_808;
        let prepaid_periods: u64 = 2;
        let coin = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        payment::subscribe_v2(
            &mut account,
            coin,
            amount_per_period,
            86400_000,
            prepaid_periods,
            b"ORDER-OVF".to_string(),
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ── Attack 2c: Ledger total_received overflow via repeated payments ──
    // add_payment does unchecked total_received + amount. VM catches it.
    // FINDING: No explicit overflow guard in add_payment, relies on VM.
    #[test]
    #[expected_failure(arithmetic_error, location = baleenpay::merchant)]
    fun red_team_round_2c_ledger_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // First payment: near MAX
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin1 = coin::mint_for_testing<TEST_USDC>(18_446_744_073_709_551_615, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, coin1, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);

        // Second payment: +1 should overflow total_received
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin2 = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let clock2 = clock::create_for_testing(scenario.ctx());
        // This should abort with arithmetic overflow in add_payment
        payment::pay_once(&mut account, coin2, &clock2, scenario.ctx());
        test_scenario::return_shared(account);
        clock2.destroy_for_testing();
        scenario.end();
    }

    // ── Attack 2d: next_due overflow in process_subscription ──
    // next_due + period_ms now has explicit overflow guard (EOverflow).
    #[test]
    #[expected_failure]
    fun red_team_round_2d_next_due_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Create subscription with very large period_ms
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        // period_ms near MAX_U64/2, prepaid=2 periods
        let period_ms: u64 = 9_223_372_036_854_775_807; // MAX_U64/2
        let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        // Set clock to a large timestamp
        clock.set_for_testing(9_000_000_000_000_000_000);
        payment::subscribe(
            &mut account,
            coin,
            1_000_000,
            period_ms,
            2,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(account);

        // Now try to process: next_due = 9000000000000000000 + 9223372036854775807 => overflow
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        // Advance clock past next_due
        clock.set_for_testing(18_446_744_073_709_551_000);
        payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        test_scenario::return_shared(sub);
        clock.destroy_for_testing();
        scenario.end();
    }
}
