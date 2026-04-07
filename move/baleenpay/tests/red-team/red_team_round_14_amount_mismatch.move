/// Red Team Round 14: Integer Abuse — amount mismatch FIX VERIFICATION
/// The original attack exploited a separate `amount` param in keeper_deposit_to_farm.
/// Fix: amount is now derived from coin.value() (single source of truth).
/// These tests verify the fix holds — accounting always matches coin value.
#[test_only]
module baleenpay::red_team_round_14_amount_mismatch;
use sui::test_scenario;
use sui::coin;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantRegistry};
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

/// VERIFY FIX: farming_principal always equals coin.value() deposited
#[test]
fun test_fix_farming_matches_coin_value() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 2000);
    test_scenario::return_shared(account);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Deposit coin worth 500
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stablecoin = coin::mint_for_testing<STABLECOIN>(500, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, stablecoin);

    // farming_principal MUST equal coin.value() = 500 (not any other number)
    let farming = merchant::farming_principal(&account);
    let vault_bal = router::stablecoin_vault_balance(&sv);
    assert!(farming == 500, 100);
    assert!(vault_bal == 500, 101);
    assert!(farming == vault_bal, 102); // accounting matches vault

    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

/// VERIFY FIX: zero-value coin is rejected
#[test]
#[expected_failure] // EZeroAmount
fun test_fix_zero_coin_rejected() {
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

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stablecoin = coin::mint_for_testing<STABLECOIN>(0, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, stablecoin);

    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
