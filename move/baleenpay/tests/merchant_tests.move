#[test_only]
module baleenpay::merchant_tests {
    use baleenpay::merchant;
    use sui::test_scenario;

    #[test]
    fun test_register_merchant() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        // init creates AdminCap + MerchantRegistry
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);

        // register merchant
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"TestBrand".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.next_tx(merchant_addr);

        // verify MerchantCap received
        let cap = scenario.take_from_sender<merchant::MerchantCap>();
        scenario.return_to_sender(cap);

        // verify MerchantAccount exists as shared
        let account = scenario.take_shared<merchant::MerchantAccount>();
        assert!(merchant::get_total_received(&account) == 0);
        assert!(merchant::get_brand_name(&account) == b"TestBrand".to_string());
        assert!(merchant::get_owner(&account) == merchant_addr);
        assert!(merchant::get_paused(&account) == false);
        assert!(merchant::get_idle_principal(&account) == 0);
        assert!(merchant::get_accrued_yield(&account) == 0);
        test_scenario::return_shared(account);

        scenario.end();
    }

    #[test]
    #[expected_failure] // EAlreadyRegistered
    fun test_double_register_fails() {
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(merchant_addr);
        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);

        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"Brand1".to_string(), scenario.ctx());
        scenario.next_tx(merchant_addr);
        // second register should fail
        merchant::register_merchant(&mut registry, b"Brand2".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.end();
    }

    #[test]
    fun test_pause_unpause_merchant() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(merchant_addr);

        // register
        let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
        merchant::register_merchant(&mut registry, b"PauseBrand".to_string(), scenario.ctx());
        test_scenario::return_shared(registry);
        scenario.next_tx(admin);

        // admin pauses
        let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
        let mut account = scenario.take_shared<merchant::MerchantAccount>();
        merchant::pause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == true);

        // admin unpauses
        merchant::unpause_merchant(&admin_cap, &mut account);
        assert!(merchant::get_paused(&account) == false);

        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_admin_cap_transferred_to_deployer() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        merchant::init_for_testing(scenario.ctx());
        scenario.next_tx(admin);

        // admin should have AdminCap
        let cap = scenario.take_from_sender<merchant::AdminCap>();
        scenario.return_to_sender(cap);

        scenario.end();
    }
}
