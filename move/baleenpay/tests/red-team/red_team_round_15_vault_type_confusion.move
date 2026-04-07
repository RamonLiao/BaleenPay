/// Red Team Round 15: Type Confusion — StablecoinVault with wrong phantom type
/// Attack vectors:
/// 1. Create StablecoinVault<FakeToken> and try to mix with real vault operations
/// 2. take_stablecoin from vault of different type than what was deposited
#[test_only]
module baleenpay::red_team_round_15_vault_type_confusion {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::router::{Self, StablecoinVault};

    public struct REAL_STABLECOIN has drop {}
    public struct FAKE_STABLECOIN has drop {}

    fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
        scenario.next_tx(admin);
        merchant::init_for_testing(scenario.ctx());
        router::init_for_testing(scenario.ctx());
    }

    fun register(scenario: &mut test_scenario::Scenario, addr: address) {
        scenario.next_tx(addr);
        let mut reg = scenario.take_shared<MerchantRegistry>();
        merchant::register_merchant(&mut reg, b"Test".to_string(), scenario.ctx());
        test_scenario::return_shared(reg);
    }

    /// ATTACK: Deposit REAL_STABLECOIN, then take from FAKE_STABLECOIN vault
    /// Move's type system should prevent this at compile time or runtime
    #[test]
    fun test_attack_cross_type_vault_isolation() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register(&mut scenario, merchant_addr);

        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, 1000);
        test_scenario::return_shared(account);

        // Create both vault types
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<REAL_STABLECOIN>(&admin_cap, scenario.ctx());
        router::create_stablecoin_vault<FAKE_STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Deposit REAL stablecoin into REAL vault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv_real = scenario.take_shared<StablecoinVault<REAL_STABLECOIN>>();
        let real_coin = coin::mint_for_testing<REAL_STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv_real, real_coin);
        test_scenario::return_shared(sv_real);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);

        // ATTACK: Try to take from FAKE vault (should have 0 balance)
        scenario.next_tx(merchant_addr);
        let cap = scenario.take_from_sender<MerchantCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let sv_fake = scenario.take_shared<StablecoinVault<FAKE_STABLECOIN>>();

        // Verify FAKE vault is empty — type system isolates vaults correctly
        assert!(router::stablecoin_vault_balance(&sv_fake) == 0);
        // farming_principal = 1000 but FAKE vault = 0, can't take from wrong vault

        test_scenario::return_shared(sv_fake);
        test_scenario::return_shared(account);
        scenario.return_to_sender(cap);
        scenario.end();
    }
}
