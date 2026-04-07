/// Red Team Round 13: Access Control on take_stablecoin
/// Attack vectors:
/// 1. Call take_stablecoin with a MerchantCap belonging to a different merchant
/// 2. Call take_stablecoin as non-owner address
/// 3. Call take_stablecoin while admin-paused
/// 4. Call take_stablecoin while self-paused
#[test_only]
module baleenpay::red_team_round_13_farming_access;
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

fun setup_farming(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    merchant_addr: address,
    amount: u64,
) {
    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, amount);
    test_scenario::return_shared(account);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stablecoin = coin::mint_for_testing<STABLECOIN>(amount, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, stablecoin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
}

/// ATTACK: Merchant B tries to redeem from Merchant A's farming balance
#[test]
#[expected_failure]
fun test_attack_wrong_cap_cross_merchant_redeem() {
    let admin = @0xAD;
    let merchant_a = @0xAA;
    let merchant_b = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_a);

    // Record merchant_a ID before second registration
    scenario.next_tx(merchant_a);
    let account_a = scenario.take_shared<MerchantAccount>();
    let account_a_id = object::id(&account_a);
    test_scenario::return_shared(account_a);

    register(&mut scenario, merchant_b);

    // Setup farming for merchant_a
    scenario.next_tx(merchant_a);
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    merchant::add_payment_for_testing(&mut account_a, 5000);
    test_scenario::return_shared(account_a);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stablecoin = coin::mint_for_testing<STABLECOIN>(5000, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account_a, &mut sv, stablecoin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account_a);
    scenario.return_to_sender(admin_cap);

    // ATTACK: merchant_b uses their own cap to steal from merchant_a
    scenario.next_tx(merchant_b);
    let cap_b = scenario.take_from_sender<MerchantCap>();
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stolen = router::take_stablecoin<STABLECOIN>(
        &cap_b, &mut account_a, &mut sv, 5000, scenario.ctx(),
    );
    // If we get here, exploit succeeded
    coin::burn_for_testing(stolen);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account_a);
    scenario.return_to_sender(cap_b);
    scenario.end();
}

/// ATTACK: Admin-paused merchant tries to take stablecoin
#[test]
#[expected_failure]
fun test_attack_admin_paused_take_stablecoin() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);
    setup_farming(&mut scenario, admin, merchant_addr, 1000);

    // Admin pauses
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant tries to take while paused
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 500, scenario.ctx());
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

/// ATTACK: Self-paused merchant tries to take stablecoin
#[test]
#[expected_failure]
fun test_attack_self_paused_take_stablecoin() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);
    setup_farming(&mut scenario, admin, merchant_addr, 1000);

    // Merchant self-pauses
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::self_pause(&cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Merchant tries to take while self-paused
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 500, scenario.ctx());
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
