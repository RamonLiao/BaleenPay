#[test_only]
/// Red Team Round 16: Integer abuse on typed yield functions.
/// Attack vectors: overflow via repeated credit, MAX_U64 credit, zero-amount edge cases.
module baleenpay::red_team_round_16_typed_yield_integer {
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

    fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Target".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    /// 16a: Credit MAX_U64 yield, then credit 1 more — should overflow.
    /// Attack: accumulate typed yield past u64 max.
    #[test, expected_failure]
    fun red_team_16a_typed_yield_overflow() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        // Credit MAX_U64
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 18_446_744_073_709_551_615);
        // Credit 1 more — should abort on overflow
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 1);
        test_scenario::return_shared(account);
        scenario.end();
    }

    /// 16b: Claim zero typed yield — should abort with EZeroYield.
    #[test, expected_failure]
    fun red_team_16b_claim_zero_typed_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Create yield vault but don't credit any typed yield
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Merchant tries to claim zero yield
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

    /// 16c: admin_set_yield to MAX_U64, then claim — vault has less.
    /// Attack: inflate accrued yield beyond vault balance to drain.
    #[test, expected_failure]
    fun red_team_16c_inflated_yield_vs_vault() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Create yield vault with only 100 coins
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut yv = scenario.take_shared<YieldVault<USDB>>();
        let coin = coin::mint_for_testing<USDB>(100, scenario.ctx());
        router::deposit_to_yield_vault_for_testing(&mut yv, coin);
        test_scenario::return_shared(yv);

        // Admin sets yield to 1000 (10x vault balance)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 1000);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Merchant claims — vault only has 100, should abort on balance.split(1000)
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
