#[test_only]
module baleenpay::farming_tests;
use sui::test_scenario;
use sui::coin;
use std::option;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::router::{Self, StablecoinVault};

public struct STABLECOIN has drop {}

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
}

fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestMerchant".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

#[test]
fun test_move_to_farming() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    assert!(merchant::get_idle_principal(&account) == 1000);
    assert!(merchant::get_farming_principal(&account) == 0);

    merchant::move_to_farming_for_testing(&mut account, 600);
    assert!(merchant::get_idle_principal(&account) == 400);
    assert!(merchant::get_farming_principal(&account) == 600);

    test_scenario::return_shared(account);
    scenario.end();
}

#[test]
#[expected_failure] // EInsufficientPrincipal
fun test_move_to_farming_exceeds_idle() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 100);
    merchant::move_to_farming_for_testing(&mut account, 200); // abort

    test_scenario::return_shared(account);
    scenario.end();
}

#[test]
fun test_return_from_farming() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    merchant::move_to_farming_for_testing(&mut account, 800);
    assert!(merchant::get_farming_principal(&account) == 800);

    merchant::return_from_farming_for_testing(&mut account, 300);
    assert!(merchant::get_farming_principal(&account) == 500);
    assert!(merchant::get_idle_principal(&account) == 200); // unchanged by return_from_farming

    test_scenario::return_shared(account);
    scenario.end();
}

#[test]
#[expected_failure] // EInsufficientPrincipal
fun test_return_from_farming_exceeds() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 500);
    merchant::move_to_farming_for_testing(&mut account, 500);
    merchant::return_from_farming_for_testing(&mut account, 600); // abort

    test_scenario::return_shared(account);
    scenario.end();
}

#[test]
fun test_create_stablecoin_vault() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    assert!(router::stablecoin_vault_balance(&sv) == 0);
    test_scenario::return_shared(sv);
    scenario.end();
}

#[test]
fun test_keeper_deposit_to_farm() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

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
    let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm<STABLECOIN>(
        &admin_cap, &mut account, &mut sv, stablecoin,
    );
    assert!(merchant::get_idle_principal(&account) == 0);
    assert!(merchant::get_farming_principal(&account) == 1000);
    assert!(router::stablecoin_vault_balance(&sv) == 1000);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

#[test]
fun test_take_stablecoin() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

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
    let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm<STABLECOIN>(
        &admin_cap, &mut account, &mut sv, stablecoin,
    );
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant takes stablecoin for redeem
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin<STABLECOIN>(
        &cap, &mut account, &mut sv, 600, scenario.ctx(),
    );
    assert!(coin.value() == 600);
    assert!(merchant::get_farming_principal(&account) == 400);
    assert!(router::stablecoin_vault_balance(&sv) == 400);
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test]
#[expected_failure] // EPaused
fun test_take_stablecoin_paused() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

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
    let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm<STABLECOIN>(
        &admin_cap, &mut account, &mut sv, stablecoin,
    );
    // Pause merchant
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant tries take — paused
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin<STABLECOIN>(
        &cap, &mut account, &mut sv, 500, scenario.ctx(),
    ); // abort
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test]
#[expected_failure] // ENotMerchantOwner (wrong cap)
fun test_take_stablecoin_wrong_cap() {
    let admin = @0xAD;
    let merchant_a = @0xBB;
    let merchant_b = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_a);

    // Record merchant_a's account ID before registering merchant_b
    scenario.next_tx(merchant_a);
    let account_a = scenario.take_shared<MerchantAccount>();
    let account_a_id = object::id(&account_a);
    test_scenario::return_shared(account_a);

    register_merchant(&mut scenario, merchant_b);

    // Setup merchant_a with farming
    scenario.next_tx(merchant_a);
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    merchant::add_payment_for_testing(&mut account_a, 1000);
    test_scenario::return_shared(account_a);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let stablecoin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm<STABLECOIN>(
        &admin_cap, &mut account_a, &mut sv, stablecoin,
    );
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account_a);
    scenario.return_to_sender(admin_cap);

    // merchant_b tries to take from merchant_a's stablecoin
    scenario.next_tx(merchant_b);
    let cap_b = scenario.take_from_sender<MerchantCap>();
    let mut account_a = scenario.take_shared_by_id<MerchantAccount>(account_a_id);
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin<STABLECOIN>(
        &cap_b, &mut account_a, &mut sv, 500, scenario.ctx(),
    ); // abort: wrong cap
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account_a);
    scenario.return_to_sender(cap_b);
    scenario.end();
}
