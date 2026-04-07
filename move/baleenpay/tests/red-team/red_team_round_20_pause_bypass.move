/// Red Team Round 20: Access Control + Economic — pause bypass on farming operations
/// Attack vectors:
/// 1. Admin pauses merchant, keeper still deposits to farm (should it work?)
/// 2. Admin pauses, merchant tries take_stablecoin (should fail)
/// 3. Admin pauses, merchant tries merchant_withdraw (should fail)
/// 4. Self-pause doesn't block keeper operations (by design — keeper is admin)
#[test_only]
module baleenpay::red_team_round_20_pause_bypass;
use sui::test_scenario;
use sui::coin;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::router::{Self, Vault, StablecoinVault};

public struct USDC has drop {}
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

/// ATTACK: Keeper deposits to farm WHILE merchant is paused
/// keeper_deposit_to_farm only requires AdminCap, not pause check.
/// This is by design (admin/keeper should be able to manage funds regardless)
/// but verify accounting still works correctly.
#[test]
fun test_attack_keeper_deposit_while_paused() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    test_scenario::return_shared(account);

    // Admin pauses merchant
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    assert!(merchant::is_paused(&account) == true);
    test_scenario::return_shared(account);

    // Create vault
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Keeper deposits to farm WHILE paused — this SHOULD succeed
    // because keeper_deposit_to_farm has no pause check (AdminCap only)
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);

    // Verify accounting: idle→farming even while paused
    assert!(merchant::idle_principal(&account) == 0);
    assert!(merchant::farming_principal(&account) == 1000);

    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

/// ATTACK: Paused merchant tries merchant_withdraw on idle USDC
#[test]
#[expected_failure] // EPaused
fun test_attack_paused_merchant_withdraw() {
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
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
    router::deposit_to_vault_for_testing(&mut vault, usdc);
    test_scenario::return_shared(vault);

    // Admin pauses
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant tries to withdraw while paused
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    router::merchant_withdraw(&cap, &mut account, &mut vault, 500, scenario.ctx());
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
