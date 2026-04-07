#[test_only]
module baleenpay::merchant_withdraw_tests;
use sui::test_scenario;
use sui::coin::{Self, Coin};
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::router::{Self, Vault};

public struct USDC has drop {}

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
fun test_merchant_withdraw_success() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Create vault and fund it
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Simulate payment: add to vault + merchant idle
    scenario.next_tx(admin);
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let usdc = coin::mint_for_testing<USDC>(1000, scenario.ctx());
    router::deposit_to_vault_for_testing(&mut vault, usdc);
    merchant::add_payment_for_testing(&mut account, 1000);
    test_scenario::return_shared(account);
    test_scenario::return_shared(vault);

    // Merchant withdraws 400
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    router::merchant_withdraw<USDC>(
        &cap, &mut account, &mut vault, 400, scenario.ctx(),
    );
    assert!(merchant::idle_principal(&account) == 600);
    assert!(router::vault_balance(&vault) == 600);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Verify merchant received USDC
    scenario.next_tx(merchant_addr);
    let usdc: Coin<USDC> = scenario.take_from_sender();
    assert!(usdc.value() == 400);
    scenario.return_to_sender(usdc);

    scenario.end();
}

#[test]
#[expected_failure] // EInsufficientPrincipal
fun test_merchant_withdraw_exceeds_idle() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let usdc = coin::mint_for_testing<USDC>(100, scenario.ctx());
    router::deposit_to_vault_for_testing(&mut vault, usdc);
    merchant::add_payment_for_testing(&mut account, 100);
    test_scenario::return_shared(account);
    test_scenario::return_shared(vault);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    router::merchant_withdraw<USDC>(
        &cap, &mut account, &mut vault, 200, scenario.ctx(),
    ); // abort
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test]
#[expected_failure] // EPaused
fun test_merchant_withdraw_paused() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(admin);
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    router::deposit_to_vault_for_testing(&mut vault, usdc);
    merchant::add_payment_for_testing(&mut account, 500);
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    test_scenario::return_shared(vault);
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    router::merchant_withdraw<USDC>(
        &cap, &mut account, &mut vault, 300, scenario.ctx(),
    ); // abort: paused
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
