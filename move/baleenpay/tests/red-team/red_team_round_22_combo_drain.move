/// Red Team Round 22: Combo Economic + Accounting — multi-merchant vault drain
/// Attack vectors:
/// 1. Two merchants share same StablecoinVault; merchant A redeems more than their share
/// 2. Merchant A's farming_principal > their actual vault contribution (cross-merchant drain)
#[test_only]
module baleenpay::red_team_round_22_combo_drain {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
    use baleenpay::router::{Self, StablecoinVault};

    public struct STABLECOIN has drop {}

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

    /// ATTACK: Two merchants, shared StablecoinVault.
    /// Merchant A has farming=800, Merchant B has farming=200. Vault total=1000.
    /// Merchant A redeems 800, then Merchant B tries 200 — should work (vault still has 200).
    /// But what if Merchant A tries to redeem 900 (more than their farming)?
    #[test]
    fun test_multi_merchant_fair_redeem() {
        let admin = @0xAD;
        let merchant_a = @0xAA;
        let merchant_b = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register(&mut scenario, merchant_a);

        // Record A's ID
        scenario.next_tx(merchant_a);
        let account_a = scenario.take_shared<MerchantAccount>();
        let account_a_id = object::id(&account_a);
        test_scenario::return_shared(account_a);

        register(&mut scenario, merchant_b);

        // Record B's ID
        scenario.next_tx(merchant_b);
        let account_b = scenario.take_shared<MerchantAccount>();
        let account_b_id = object::id(&account_b);
        test_scenario::return_shared(account_b);

        // Fund both merchants
        scenario.next_tx(admin);
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        merchant::add_payment_for_testing(&mut account_a, 800);
        test_scenario::return_shared(account_a);

        scenario.next_tx(admin);
        let mut account_b = scenario.take_shared_by_id<MerchantAccount>(account_b_id);
        merchant::add_payment_for_testing(&mut account_b, 200);
        test_scenario::return_shared(account_b);

        // Create shared StablecoinVault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Keeper deposits for A: 800
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = coin::mint_for_testing<STABLECOIN>(800, scenario.ctx());
        router::keeper_deposit_to_farm(&admin_cap, &mut account_a, &mut sv, coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(admin_cap);

        // Keeper deposits for B: 200
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account_b = scenario.take_shared_by_id<MerchantAccount>(account_b_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = coin::mint_for_testing<STABLECOIN>(200, scenario.ctx());
        router::keeper_deposit_to_farm(&admin_cap, &mut account_b, &mut sv, coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_b);
        scenario.return_to_sender(admin_cap);

        // Vault total = 1000. A farming=800, B farming=200.

        // Merchant A redeems 800 — should succeed
        scenario.next_tx(merchant_a);
        let cap_a = scenario.take_from_sender<MerchantCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin(&cap_a, &mut account_a, &mut sv, 800, scenario.ctx());
        assert!(coin.value() == 800);
        assert!(router::stablecoin_vault_balance(&sv) == 200);
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(cap_a);

        // Merchant B redeems 200 — should succeed (vault has exactly 200 left)
        scenario.next_tx(merchant_b);
        let cap_b = scenario.take_from_sender<MerchantCap>();
        let mut account_b = scenario.take_shared_by_id<MerchantAccount>(account_b_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin(&cap_b, &mut account_b, &mut sv, 200, scenario.ctx());
        assert!(coin.value() == 200);
        assert!(router::stablecoin_vault_balance(&sv) == 0);
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_b);
        scenario.return_to_sender(cap_b);

        scenario.end();
    }

    /// ATTACK: Merchant A tries to redeem more than their farming_principal
    /// farming_A = 800, vault = 1000. Can A take 900?
    #[test]
    #[expected_failure] // EInsufficientPrincipal (farming < 900)
    fun test_attack_redeem_more_than_own_farming() {
        let admin = @0xAD;
        let merchant_a = @0xAA;
        let merchant_b = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register(&mut scenario, merchant_a);

        scenario.next_tx(merchant_a);
        let account_a = scenario.take_shared<MerchantAccount>();
        let account_a_id = object::id(&account_a);
        test_scenario::return_shared(account_a);

        register(&mut scenario, merchant_b);

        scenario.next_tx(admin);
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        merchant::add_payment_for_testing(&mut account_a, 800);
        test_scenario::return_shared(account_a);

        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
        scenario.return_to_sender(admin_cap);

        // Deposit 800 for A, 200 for B = 1000 total in vault
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = coin::mint_for_testing<STABLECOIN>(800, scenario.ctx());
        router::keeper_deposit_to_farm(&admin_cap, &mut account_a, &mut sv, coin);
        // Also add 200 directly to vault (simulating B's deposit without B's account)
        let extra = coin::mint_for_testing<STABLECOIN>(200, scenario.ctx());
        router::deposit_to_stablecoin_vault_for_testing(&mut sv, extra);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(admin_cap);

        // ATTACK: A tries to take 900 (more than their farming=800, less than vault=1000)
        scenario.next_tx(merchant_a);
        let cap_a = scenario.take_from_sender<MerchantCap>();
        let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = router::take_stablecoin(&cap_a, &mut account_a, &mut sv, 900, scenario.ctx());
        // farming_principal check (800 < 900) → abort before vault balance check
        coin::burn_for_testing(coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account_a);
        scenario.return_to_sender(cap_a);
        scenario.end();
    }
}
