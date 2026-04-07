#[test_only]
module baleenpay::red_team_round_11_vault_drain {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::payment;
    use baleenpay::router::{Self, Vault, YieldVault, RouterConfig};
    use baleenpay::test_usdc::TEST_USDC;

    fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        router::create_vault<TEST_USDC>(&admin_cap, scenario.ctx());
        router::create_yield_vault<TEST_USDC>(&admin_cap, scenario.ctx());
        // Set to stablelayer mode so route_payment works
        let mut config = scenario.take_shared<RouterConfig>();
        router::set_mode(&admin_cap, &mut config, 1);
        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"VaultShop".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Attack 11a: claim_yield_v2 when YieldVault has less balance than accrued_yield ──
    // If keeper credits yield via credit_external_yield but doesn't actually deposit
    // enough coins into YieldVault, claim_yield_v2 will abort on balance::split.
    // This tests the desync vector: ledger says X yield, vault has < X coins.
    #[test]
    #[expected_failure] // balance::split aborts if insufficient
    fun red_team_round_11a_yield_vault_desync_claim() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Credit 5M yield to merchant ledger but only put 1M in YieldVault
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<TEST_USDC>(&mut account, 5_000_000);
        test_scenario::return_shared(account);

        let yield_coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
        test_scenario::return_shared(yield_vault);

        // Merchant tries to claim 5M but vault only has 1M -- should abort
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
        // FINDING: Contract aborts (DEFENDED), but accrued_yield is NOT reset on failure.
        // This means the merchant's yield is stuck until vault is topped up.
        // No fund loss, but availability issue -- merchant cannot claim partial yield.
    }

    // ── Attack 11b: keeper_withdraw total_deposited overflow ──
    // total_deposited += amount on each withdraw. If keeper withdraws enough times,
    // total_deposited could overflow (though practically unlikely).
    #[test]
    #[expected_failure]
    fun red_team_round_11b_keeper_total_deposited_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Fund vault with MAX_U64
        scenario.next_tx(admin);
        let big_coin = coin::mint_for_testing<TEST_USDC>(18_446_744_073_709_551_615, scenario.ctx());
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        router::deposit_to_vault_for_testing(&mut vault, big_coin);
        test_scenario::return_shared(vault);

        // First withdraw: total_deposited = MAX_U64
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = router::keeper_withdraw<TEST_USDC>(
            &admin_cap, &mut vault, 18_446_744_073_709_551_615, &clock, scenario.ctx(),
        );
        transfer::public_transfer(c1, admin);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        clock.destroy_for_testing();

        // Re-fund vault
        scenario.next_tx(admin);
        let coin2 = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        router::deposit_to_vault_for_testing(&mut vault, coin2);
        test_scenario::return_shared(vault);

        // Second withdraw: total_deposited = MAX_U64 + 1 → overflow
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        let clock2 = clock::create_for_testing(scenario.ctx());
        let c2 = router::keeper_withdraw<TEST_USDC>(
            &admin_cap, &mut vault, 1, &clock2, scenario.ctx(),
        );
        transfer::public_transfer(c2, admin);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        clock2.destroy_for_testing();
        scenario.end();
        // FINDING: total_deposited overflows silently in Move 2024 (wrapping or abort depending on mode).
        // This is a SUSPICIOUS finding -- the counter becomes meaningless after overflow.
        // No fund loss but total_deposited tracking becomes incorrect.
    }

    // ── Attack 11c: keeper_withdraw more than what was deposited via payments ──
    // Vault balance can be topped up via deposit_to_vault_for_testing (test only),
    // but in production, only route_payment adds funds. keeper_withdraw has no check
    // that amount <= funds deposited via route_payment. It only checks balance::split.
    // This is BY DESIGN (admin/keeper is trusted), but worth documenting.
    #[test]
    fun red_team_round_11c_keeper_withdraw_exceeds_payment_deposits() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer deposits 1M via routed payment
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        let config = scenario.take_shared<RouterConfig>();
        let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once_routed(
            &config, &mut account, &mut vault, coin,
            b"ORDER-100".to_string(), &clock, scenario.ctx(),
        );
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(account);
        clock.destroy_for_testing();

        // Keeper withdraws exactly 1M (correct)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut vault = scenario.take_shared<Vault<TEST_USDC>>();
        let clock2 = clock::create_for_testing(scenario.ctx());
        let withdrawn = router::keeper_withdraw<TEST_USDC>(
            &admin_cap, &mut vault, 1_000_000, &clock2, scenario.ctx(),
        );
        assert!(withdrawn.value() == 1_000_000);
        // Vault now empty
        assert!(router::vault_balance<TEST_USDC>(&vault) == 0);
        // total_deposited = 1M (tracks keeper withdrawals, not payment deposits)
        assert!(router::vault_total_deposited<TEST_USDC>(&vault) == 1_000_000);
        transfer::public_transfer(withdrawn, admin);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        clock2.destroy_for_testing();

        scenario.end();
        // DEFENDED: keeper can only withdraw up to vault.balance (enforced by balance::split).
        // total_deposited naming is confusing -- it tracks "total withdrawn by keeper", not deposits.
    }

    // ── Attack 11d: Rapid process_subscription -- process multiple periods in one epoch ──
    // If clock advances past multiple due dates, can attacker process N times in one tx?
    #[test]
    fun red_team_round_11d_multi_period_rapid_process() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Payer creates sub: 1M per period, 100ms period, 5 periods prepaid
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
        let mut clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 100, 5, &clock, scenario.ctx());
        // First period auto-paid, 4 remaining in escrow
        assert!(merchant::get_total_received(&account) == 1_000_000);
        test_scenario::return_shared(account);

        // Advance clock by 500ms (past 4 remaining due dates)
        clock.set_for_testing(600);

        // Process 4 times rapidly
        let mut processed = 0u64;
        while (processed < 4) {
            scenario.next_tx(@0xDD); // anyone can process
            let mut account = scenario.take_shared<MerchantAccount>();
            let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
            payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
            processed = processed + 1;
            test_scenario::return_shared(account);
            test_scenario::return_shared(sub);
        };

        // Verify all 5 periods processed
        scenario.next_tx(merchant_addr);
        let account = scenario.take_shared<MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 5_000_000);
        test_scenario::return_shared(account);

        // Sub should be empty now
        scenario.next_tx(payer);
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        assert!(payment::get_sub_balance<TEST_USDC>(&sub) == 0);
        test_scenario::return_shared(sub);

        clock.destroy_for_testing();
        scenario.end();
        // FINDING: If clock skips ahead past multiple periods, all can be processed
        // in rapid succession. Each process only advances next_due by period_ms,
        // so N calls drain N periods. This is BY DESIGN (permissionless crank),
        // but means a bot can drain all prepaid funds in one block if clock jumps.
        // No exploit -- funds go to correct merchant. But UX surprise for payer.
    }

    // ── Attack 11e: credit_external_yield inflates accrued_yield without real funds ──
    // credit_external_yield is public(package), so only router module can call it.
    // keeper_deposit_yield is the entry point: it takes real coins AND credits yield.
    // But if there's a code path that calls credit_external_yield without depositing...
    // In current code: keeper_deposit_yield always pairs coin deposit with credit.
    // DEFENDED by design -- no way to inflate yield without depositing coins via AdminCap.
    #[test]
    fun red_team_round_11e_external_yield_requires_real_coins() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin, merchant_addr);

        // Admin deposits yield with real coins
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        let yield_coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
        router::keeper_deposit_yield<TEST_USDC>(
            &admin_cap, &mut yield_vault, &mut account, yield_coin,
        );
        // Yield credited AND coins deposited
        assert!(merchant::get_accrued_yield_typed<TEST_USDC>(&account) == 2_000_000);
        assert!(router::yield_vault_balance<TEST_USDC>(&yield_vault) == 2_000_000);
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Merchant claims -- should succeed, vault has matching funds
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        assert!(merchant::get_accrued_yield_typed<TEST_USDC>(&account) == 0);
        assert!(router::yield_vault_balance<TEST_USDC>(&yield_vault) == 0);
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
        // DEFENDED: keeper_deposit_yield atomically deposits coins and credits yield.
    }
}
