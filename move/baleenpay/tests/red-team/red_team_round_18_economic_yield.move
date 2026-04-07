#[test_only]
/// Red Team Round 18: Economic attacks on typed yield.
/// Attack vectors: double-claim, claim-then-credit-then-claim, vault drain via multi-merchant.
module baleenpay::red_team_round_18_economic_yield {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
    use baleenpay::router::{Self, YieldVault};

    public struct USDB has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    /// 18a: Claim yield, then immediately try to claim again — second should fail.
    #[test, expected_failure]
    fun red_team_18a_double_claim() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Merchant".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Setup: credit 100 USDB yield + vault with 100
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
        test_scenario::return_shared(account);

        scenario.next_tx(admin);
        let mut yv = scenario.take_shared<YieldVault<USDB>>();
        let coin = coin::mint_for_testing<USDB>(100, scenario.ctx());
        router::deposit_to_yield_vault_for_testing(&mut yv, coin);
        test_scenario::return_shared(yv);

        // First claim — should succeed
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yv = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yv, scenario.ctx());

        // Second claim in SAME tx — should abort (df removed, EZeroYield)
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yv, scenario.ctx());

        test_scenario::return_shared(yv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    /// 18b: admin_set_yield to 0, then claim — should fail with EZeroYield.
    /// Attack: admin zeros yield, merchant still tries to claim.
    #[test, expected_failure]
    fun red_team_18b_claim_after_admin_zero() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Merchant".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Credit 100, then admin zeros it
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
        merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 0);
        test_scenario::return_shared(account);

        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Merchant tries to claim — df removed, EZeroYield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yv = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yv, scenario.ctx());
        test_scenario::return_shared(yv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
