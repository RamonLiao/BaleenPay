#[test_only]
module baleenpay::stablelayer_monkey_tests {
    use sui::test_scenario;
    use sui::coin;
    use sui::clock;
    use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry, AdminCap, MerchantCap};
    use baleenpay::router::{Self, Vault, YieldVault, RouterConfig};
    use baleenpay::payment;

    public struct USDC has drop {}
    public struct USDB has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register_merchant(scenario: &mut test_scenario::Scenario, addr: address) {
        scenario.next_tx(addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Monkey".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
    }

    // ── Withdraw edge cases ──

    #[test]
    #[expected_failure] // EZeroAmount
    fun test_keeper_withdraw_zero() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let c = router::keeper_withdraw<USDC>(&admin_cap, &mut vault, 0, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
        coin::burn_for_testing(c);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure]
    fun test_keeper_withdraw_u64_max() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let c = router::keeper_withdraw<USDC>(
            &admin_cap, &mut vault, 18_446_744_073_709_551_615, &clock, scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        coin::burn_for_testing(c);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    // ── Concurrent drain ──

    #[test]
    fun test_sequential_drain_vault() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Deposit 1000
        scenario.next_tx(admin);
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
        router::deposit_to_vault_for_testing(&mut vault, usdc);
        test_scenario::return_shared(vault);

        // Withdraw 600
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = router::keeper_withdraw<USDC>(&admin_cap, &mut vault, 600, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
        coin::burn_for_testing(c1);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);

        // Withdraw remaining 400
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let c2 = router::keeper_withdraw<USDC>(&admin_cap, &mut vault, 400, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
        assert!(router::vault_balance(&vault) == 0);
        coin::burn_for_testing(c2);
        test_scenario::return_shared(vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    // ── Mode flip ──

    #[test]
    fun test_mode_flip_fallback_to_stablelayer_and_back() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);

        // Start in fallback
        scenario.next_tx(admin);
        let config = scenario.take_shared<RouterConfig>();
        assert!(router::is_fallback(&config));
        test_scenario::return_shared(config);

        // Switch to stablelayer
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut config = scenario.take_shared<RouterConfig>();
        router::set_mode(&admin_cap, &mut config, 1);
        assert!(router::is_stablelayer(&config));
        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);

        // Switch back to fallback
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut config = scenario.take_shared<RouterConfig>();
        router::set_mode(&admin_cap, &mut config, 0);
        assert!(router::is_fallback(&config));
        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    // ── Deposit yield with zero coin ──

    #[test]
    #[expected_failure] // EZeroAmount
    fun test_keeper_deposit_yield_zero() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let zero_coin = coin::mint_for_testing<USDB>(0, scenario.ctx());
        router::keeper_deposit_yield<USDB>(
            &admin_cap, &mut yield_vault, &mut account, zero_coin,
        );
        test_scenario::return_shared(account);
        test_scenario::return_shared(yield_vault);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    // ── Full lifecycle: pay → vault → withdraw → deposit yield → claim ──

    #[test]
    fun test_full_lifecycle() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let payer = @0xCC;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Enable stablelayer + create vaults
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut config = scenario.take_shared<RouterConfig>();
        router::set_mode(&admin_cap, &mut config, 1);
        router::create_vault<USDC>(&admin_cap, scenario.ctx());
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        test_scenario::return_shared(config);
        scenario.return_to_sender(admin_cap);

        // Payer pays 1000 USDC
        scenario.next_tx(payer);
        let config = scenario.take_shared<RouterConfig>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
        payment::pay_once_routed<USDC>(
            &config, &mut account, &mut vault, usdc,
            b"lifecycle-001".to_string(), &clock, scenario.ctx(),
        );
        assert!(router::vault_balance(&vault) == 1000);
        assert!(merchant::get_idle_principal(&account) == 1000);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(account);
        test_scenario::return_shared(config);

        // Keeper withdraws 1000 USDC from vault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut vault = scenario.take_shared<Vault<USDC>>();
        let clock = clock::create_for_testing(scenario.ctx());
        let withdrawn = router::keeper_withdraw<USDC>(&admin_cap, &mut vault, 1000, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
        assert!(router::vault_balance(&vault) == 0);
        coin::burn_for_testing(withdrawn);
        test_scenario::return_shared(vault);

        // Keeper deposits 50 USDB yield
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let usdb = coin::mint_for_testing<USDB>(50, scenario.ctx());
        router::keeper_deposit_yield<USDB>(
            &admin_cap, &mut yield_vault, &mut account, usdb,
        );
        assert!(merchant::get_accrued_yield(&account) == 50);
        assert!(router::yield_vault_balance(&yield_vault) == 50);
        test_scenario::return_shared(account);
        test_scenario::return_shared(yield_vault);
        scenario.return_to_sender(admin_cap);

        // Merchant claims yield
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        assert!(merchant::get_accrued_yield(&account) == 0);
        assert!(router::yield_vault_balance(&yield_vault) == 0);
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Verify merchant received USDB
        scenario.next_tx(merchant_addr);
        let usdb_received: sui::coin::Coin<USDB> = scenario.take_from_sender();
        assert!(usdb_received.value() == 50);
        scenario.return_to_sender(usdb_received);

        scenario.end();
    }
}
