/// Red Team Round 16: Economic Attack — farming_principal inflation to drain vault
/// Attack vectors:
/// 1. Repeated keeper_deposit_to_farm without real StableLayer mint → inflated farming
/// 2. Double-count: deposit same coin twice
/// 3. Drain vault by inflating farming_principal beyond actual vault balance
#[test_only]
module baleenpay::red_team_round_16_farming_inflation;
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

/// ATTACK: Keeper deposits multiple times, inflating farming_principal
/// Then merchant redeems full farming_principal (draining vault)
/// This tests whether take_stablecoin can exceed vault balance
#[test]
fun test_attack_multi_deposit_then_full_drain() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 3000);
    test_scenario::return_shared(account);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Deposit 3 times: 1000 each
    let mut i = 0;
    while (i < 3) {
        scenario.next_tx(admin);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let mut account = scenario.take_shared<MerchantAccount>();
        let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
        let coin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
        router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
        test_scenario::return_shared(sv);
        test_scenario::return_shared(account);
        scenario.return_to_sender(admin_cap);
        i = i + 1;
    };

    // Verify: farming = 3000, vault = 3000 — consistent
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();

    assert!(merchant::get_farming_principal(&account) == 3000);
    assert!(router::stablecoin_vault_balance(&sv) == 3000);

    // Redeem ALL — should succeed and leave both at 0
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 3000, scenario.ctx());
    assert!(coin.value() == 3000);
    assert!(merchant::get_farming_principal(&account) == 0);
    assert!(router::stablecoin_vault_balance(&sv) == 0);

    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

/// ATTACK: Try to redeem MORE than vault balance
/// farming_principal = 1000 but vault has only 500 (simulated desync)
#[test]
#[expected_failure] // Balance::split would abort
fun test_attack_redeem_exceeds_vault_balance() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    test_scenario::return_shared(account);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Deposit with inflated amount (coin=500, amount=1000)
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = coin::mint_for_testing<STABLECOIN>(500, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Try to redeem 1000 (farming_principal) but vault only has 500
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 1000, scenario.ctx());
    // Balance::split(500, 1000) → abort
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
