#[test_only]
/// Red Team Round 17: Type confusion on phantom T.
/// Attack vectors: credit yield as type A, claim as type B; migrate to wrong type.
module baleenpay::red_team_round_17_type_confusion {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
    use baleenpay::router::{Self, YieldVault};

    public struct USDB has drop {}
    public struct FAKE_USDB has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Target".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    /// 17a: Credit yield as USDB, try to claim as FAKE_USDB — should fail.
    /// Attack: phantom type mismatch to drain wrong vault.
    #[test, expected_failure]
    fun red_team_17a_claim_wrong_type() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Credit USDB yield
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 500);
        test_scenario::return_shared(account);

        // Create YieldVault<FAKE_USDB> with coins
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<FAKE_USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut yv = scenario.take_shared<YieldVault<FAKE_USDB>>();
        let coin = coin::mint_for_testing<FAKE_USDB>(500, scenario.ctx());
        router::deposit_to_yield_vault_for_testing(&mut yv, coin);
        test_scenario::return_shared(yv);

        // Try claim FAKE_USDB — no AccruedYieldKey<FAKE_USDB> exists → EZeroYield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yv = scenario.take_shared<YieldVault<FAKE_USDB>>();
        router::claim_yield_v2<FAKE_USDB>(&cap, &mut account, &mut yv, scenario.ctx());
        test_scenario::return_shared(yv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    /// 17b: Migrate legacy yield to type A, then try to migrate again to type B.
    /// Attack: double-migrate to duplicate yield across types.
    /// Note: second migrate should succeed (different type) but struct field is already 0.
    #[test]
    fun red_team_17b_migrate_to_two_types() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Legacy yield = 100
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_for_testing(&mut account, 100);
        test_scenario::return_shared(account);

        // Migrate to USDB — moves 100 to df, struct → 0
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);
        assert!(merchant::get_accrued_yield(&account) == 0);

        // Migrate to FAKE_USDB — struct field is 0, so no df added
        merchant::admin_migrate_yield<FAKE_USDB>(&admin_cap, &mut account);
        // FAKE_USDB should be 0 — NOT duplicated from USDB
        assert!(merchant::get_accrued_yield_typed<FAKE_USDB>(&account) == 0);
        // USDB untouched
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);

        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }
}
