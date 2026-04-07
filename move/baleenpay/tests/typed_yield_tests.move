#[test_only]
module baleenpay::typed_yield_tests {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
    use baleenpay::router::{Self, YieldVault};

    public struct USDB has drop {}
    public struct REWARD_A has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestMerchant".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    /// Two yield types credited independently — claiming one does not affect the other.
    #[test]
    fun test_multi_type_yield_isolation() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Credit two types of yield
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
        merchant::credit_external_yield_typed_for_testing<REWARD_A>(&mut account, 200);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);
        assert!(merchant::get_accrued_yield_typed<REWARD_A>(&account) == 200);
        test_scenario::return_shared(account);

        // Create YieldVault<USDB> + seed
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let usdb_coin = coin::mint_for_testing<USDB>(100, scenario.ctx());
        router::deposit_to_yield_vault_for_testing(&mut yield_vault, usdb_coin);
        test_scenario::return_shared(yield_vault);

        // Claim USDB yield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yield_vault, scenario.ctx());

        // USDB yield gone, REWARD_A untouched
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);
        assert!(merchant::get_accrued_yield_typed<REWARD_A>(&account) == 200);

        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    fun test_admin_migrate_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Simulate legacy state: accrued_yield = 50 (struct field)
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_for_testing(&mut account, 50);
        assert!(merchant::get_accrued_yield(&account) == 50);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);
        test_scenario::return_shared(account);

        // Admin migrates
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);

        // Struct field = 0, df = 50
        assert!(merchant::get_accrued_yield(&account) == 0);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 50);

        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EAlreadyMigrated
    fun test_admin_migrate_yield_double_call() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_for_testing(&mut account, 50);
        test_scenario::return_shared(account);

        // First migration — OK
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // Second migration — should abort (EAlreadyMigrated)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_admin_set_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Set yield to 100
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 100);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 100);
        assert!(merchant::get_accrued_yield(&account) == 0); // struct field zeroed

        // Set yield to 0 — df removed
        merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 0);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);

        // Set yield again — df re-created
        merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 42);
        assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 42);

        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure] // EZeroYield
    fun test_claim_typed_yield_nonexistent_type() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Credit USDB yield only
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 100);
        test_scenario::return_shared(account);

        // Create YieldVault<REWARD_A> (different type)
        router::create_yield_vault<REWARD_A>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Try claim REWARD_A — should abort (no df for REWARD_A)
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<REWARD_A>>();
        router::claim_yield_v2<REWARD_A>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
