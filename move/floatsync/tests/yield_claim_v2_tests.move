#[test_only]
module floatsync::yield_claim_v2_tests {
    use sui::test_scenario;
    use sui::coin::{Self, Coin};
    use floatsync::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
    use floatsync::router::{Self, YieldVault};

    // Test coin type
    public struct USDB has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
        scenario.next_tx(merchant_addr);
        let mut registry = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(
            &mut registry,
            b"TestMerchant".to_string(),
            scenario.ctx(),
        );
        test_scenario::return_shared(registry);
    }

    #[test]
    fun test_credit_external_yield_does_not_deduct_principal() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Simulate: idle_principal = 1000, accrued_yield = 0
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        assert!(merchant::get_idle_principal(&account) == 1000);
        assert!(merchant::get_accrued_yield(&account) == 0);

        // credit_external_yield: should NOT deduct idle_principal
        merchant::credit_external_yield_for_testing(&mut account, 500);
        assert!(merchant::get_idle_principal(&account) == 1000); // unchanged!
        assert!(merchant::get_accrued_yield(&account) == 500);

        test_scenario::return_shared(account);
        scenario.end();
    }

    #[test]
    fun test_claim_yield_from_vault() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Admin creates YieldVault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Seed YieldVault with USDB (simulating keeper deposit)
        scenario.next_tx(admin);
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let usdb_coin = coin::mint_for_testing<USDB>(500, scenario.ctx());
        router::keeper_deposit_yield<USDB>(
            &admin_cap,
            &mut yield_vault,
            &mut account,
            usdb_coin,
        );
        assert!(merchant::get_accrued_yield(&account) == 500);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(yield_vault);

        // Merchant claims yield from YieldVault (via router::claim_yield_v2)
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(
            &cap,
            &mut account,
            &mut yield_vault,
            scenario.ctx(),
        );
        assert!(merchant::get_accrued_yield(&account) == 0);
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);

        // Verify merchant received the USDB
        scenario.next_tx(merchant_addr);
        let usdb: Coin<USDB> = scenario.take_from_sender();
        assert!(usdb.value() == 500);
        scenario.return_to_sender(usdb);

        scenario.end();
    }

    #[test]
    #[expected_failure]
    fun test_claim_yield_insufficient_vault_balance() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Create YieldVault (empty)
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Manually set accrued_yield > vault balance
        scenario.next_tx(admin);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::credit_external_yield_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);

        // Merchant tries to claim — vault only has 0
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(
            &cap,
            &mut account,
            &mut yield_vault,
            scenario.ctx(),
        ); // should abort: balance.split insufficient
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EPaused
    fun test_claim_yield_v2_paused() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        // Create YieldVault + seed
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let usdb_coin = coin::mint_for_testing<USDB>(500, scenario.ctx());
        router::keeper_deposit_yield<USDB>(&admin_cap, &mut yield_vault, &mut account, usdb_coin);
        // Pause merchant
        merchant::pause_merchant(&admin_cap, &mut account);
        test_scenario::return_shared(account);
        test_scenario::return_shared(yield_vault);
        scenario.return_to_sender(admin_cap);

        // Try claim — should fail (paused)
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 12)] // EZeroYield
    fun test_claim_yield_v2_zero() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register_merchant(&mut scenario, merchant_addr);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
        router::claim_yield_v2<USDB>(&cap, &mut account, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(yield_vault);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
