#[test_only]
module floatsync::vault_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use floatsync::merchant::{Self, AdminCap, MerchantRegistry};
    use floatsync::router::{Self, Vault, YieldVault, RouterConfig};

    public struct USDC has drop {}
    public struct USDB has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    #[test]
    fun test_create_vault() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let vault = scenario.take_shared<Vault<USDC>>();
        assert!(router::vault_balance(&vault) == 0);
        assert!(router::vault_total_deposited(&vault) == 0);
        assert!(router::vault_total_yield_harvested(&vault) == 0);
        test_scenario::return_shared(vault);
        scenario.end();
    }

    #[test]
    fun test_create_yield_vault() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let yv = scenario.take_shared<YieldVault<USDB>>();
        assert!(router::yield_vault_balance(&yv) == 0);
        test_scenario::return_shared(yv);
        scenario.end();
    }

    #[test]
    fun test_keeper_withdraw() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        // Create vault and deposit USDC into it
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        assert!(router::vault_balance(&vault) == 1000);
        test_scenario::return_shared(vault);

        // Keeper withdraws
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let withdrawn = router::keeper_withdraw<USDC>(
            &admin_cap, &mut vault, 600, &clock, scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        assert!(withdrawn.value() == 600);
        assert!(router::vault_balance(&vault) == 400);
        assert!(router::vault_total_deposited(&vault) == 600);
        coin::burn_for_testing(withdrawn);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure]
    fun test_keeper_withdraw_exceeds_balance() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let usdc = coin::mint_for_testing<USDC>(100, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        test_scenario::return_shared(vault);

        // Try to withdraw more than balance
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let withdrawn = router::keeper_withdraw<USDC>(
            &admin_cap, &mut vault, 200, &clock, scenario.ctx(),
        ); // should abort
        clock::destroy_for_testing(clock);
        coin::burn_for_testing(withdrawn);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_keeper_deposit_yield() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        // Register merchant
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Test".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);

        // Create yield vault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Deposit yield
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        let usdb = coin::mint_for_testing<USDB>(300, scenario.ctx());
        router::keeper_deposit_yield<USDB>(
            &admin_cap, &mut yield_vault, &mut account, usdb,
        );
        assert!(router::yield_vault_balance(&yield_vault) == 300);
        assert!(merchant::get_accrued_yield(&account) == 300);
        assert!(merchant::get_idle_principal(&account) == 0); // unchanged
        test_scenario::return_shared(account);
        test_scenario::return_shared(yield_vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }
}
