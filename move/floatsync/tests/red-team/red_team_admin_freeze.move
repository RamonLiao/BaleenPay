#[test_only]
/// Red Team: Admin Freeze Feature — Adversarial Tests
/// Targets: claim_yield bypass, state inconsistency, self_unpause race,
///          fund_subscription during freeze, double admin freeze, unpause-without-pause.
module floatsync::red_team_admin_freeze {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant;
    use floatsync::payment;
    use floatsync::router::{Self, YieldVault};
    use floatsync::test_usdc::TEST_USDC;

    // ── Helpers ──

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
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"FreezeTarget".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 1: DEFENDED — claim_yield blocked during admin freeze
    //
    // Attack: Admin freezes merchant (paused=true, paused_by_admin=true).
    //         Merchant calls claim_yield. Contract now checks `!account.paused`
    //         at line 159, so the attack is correctly blocked with EPaused.
    //
    // NOTE: Original hypothesis was that claim_yield only checked MerchantCap.
    //       The contract has been patched — claim_yield now asserts !paused.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    #[expected_failure] // EPaused
    fun red_team_freeze_bypass_claim_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Payer makes a payment to create idle_principal
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let payment_coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut account, payment_coin, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(account);

        // Simulate external yield + fund YieldVault
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::credit_external_yield_for_testing(&mut account, 500_000);
        assert!(merchant::get_accrued_yield(&account) == 500_000);
        let yield_coin = coin::mint_for_testing<TEST_USDC>(500_000, scenario.ctx());
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
        test_scenario::return_shared(yield_vault);

        // Admin freezes the merchant
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == true);
        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);

        // ATTACK: Merchant calls claim_yield while admin-frozen
        // claim_yield checks !account.paused — correctly aborts with EPaused
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        // This aborts with EPaused (code 2) — DEFENDED
        let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
        router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());

        test_scenario::return_shared(yield_vault);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);
        scenario.end();
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 2: DEFENDED — Independent pause flags preserve self-pause after admin unfreeze
    //
    // Scenario: Merchant self-pauses → Admin freezes → Admin unfreezes.
    // Expected: Merchant's self-pause is preserved. get_paused() still true.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    fun red_team_state_consistency_self_pause_preserved_after_admin_unfreeze() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Step 1: Merchant self-pauses
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::self_pause(&cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == false);
        assert!(merchant::get_self_paused(&account) == true);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);

        // Step 2: Admin freezes (regulatory freeze on top of self-pause)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == true);
        assert!(merchant::get_self_paused(&account) == true);

        // Step 3: Admin unfreezes — only clears admin flag
        merchant::unpause_merchant(&admin_cap, &mut account);

        // DEFENDED: self-pause preserved, merchant still paused
        assert!(merchant::get_paused(&account) == true, 0);       // still paused (from self)
        assert!(merchant::get_admin_paused(&account) == false, 0); // admin cleared
        assert!(merchant::get_self_paused(&account) == true, 0);   // self preserved

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);
        scenario.end();
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 3: INFORMATIONAL — Self-unpause blocked during admin freeze
    //
    // Verifies: merchant cannot self_unpause when paused_by_admin == true.
    // This is the DEFENDED case — contract correctly blocks this.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    #[expected_failure]
    fun red_team_self_unpause_blocked_by_admin_freeze() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Admin freezes
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);

        // Merchant tries to self-unpause — should abort with EAdminFrozen
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::self_unpause(&cap, &mut account);

        // Should not reach here
        scenario.return_to_sender(cap);
        test_scenario::return_shared(account);
        scenario.end();
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 4: INFORMATIONAL — fund_subscription blocked during admin freeze
    //
    // Verify: Admin freezes merchant. Payer calls fund_subscription which
    //         checks get_paused(). Since admin freeze sets paused=true,
    //         this should correctly abort with EPaused.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    #[expected_failure] // EPaused
    fun red_team_fund_subscription_blocked_during_admin_freeze() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        // Payer creates a subscription
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let sub_coin = coin::mint_for_testing<TEST_USDC>(3_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(
            &mut account, sub_coin,
            1_000_000, // amount_per_period
            86400_000, // period_ms (1 day)
            3,         // prepaid_periods
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(account);

        // Admin freezes merchant
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == true);
        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);

        // ATTACK: Payer tries to fund subscription while admin-frozen
        // fund_subscription checks get_paused() — should abort
        scenario.next_tx(payer);
        let account = scenario.take_shared<merchant::MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        let fund_coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());

        // This should abort with EPaused — DEFENDED
        payment::fund_subscription(&account, &mut sub, fund_coin, scenario.ctx());

        test_scenario::return_shared(sub);
        test_scenario::return_shared(account);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 5: INFORMATIONAL — Double admin freeze idempotency
    //
    // Attack: Admin calls pause_merchant twice. Verify no state corruption.
    // Expected: Second pause is idempotent, just sets same flags again.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    fun red_team_double_admin_freeze_idempotent() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        // First freeze
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == true);

        // Second freeze — should be idempotent, no abort
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);
        assert!(merchant::get_admin_paused(&account) == true);

        // Verify single unpause clears everything
        merchant::unpause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == false);
        assert!(merchant::get_admin_paused(&account) == false);

        // DEFENDED: No state corruption from double freeze
        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);
        scenario.end();
    }

    // ══════════════════════════════════════════════════════════════════
    // Round 6: INFORMATIONAL — Admin unpause without prior pause
    //
    // Attack: Admin calls unpause_merchant on a merchant that was never paused.
    // Expected: Sets paused=false (already false), paused_by_admin=false (already false).
    //           Should be harmless but emits a misleading "unpaused" event.
    // ══════════════════════════════════════════════════════════════════
    #[test]
    fun red_team_unpause_without_prior_pause() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        setup(&mut scenario, admin, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();

        // Verify initial state: not paused
        assert!(merchant::get_paused(&account) == false);
        assert!(merchant::get_admin_paused(&account) == false);

        // Admin unpauses a non-paused merchant — no abort
        merchant::unpause_merchant(&admin_cap, &mut account);

        // State unchanged
        assert!(merchant::get_paused(&account) == false);
        assert!(merchant::get_admin_paused(&account) == false);

        // DEFENDED: No state corruption.
        // NOTE: Emits MerchantUnpaused event even though merchant was never paused.
        // This is a minor log pollution issue, not a security vulnerability.

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(account);
        scenario.end();
    }
}
