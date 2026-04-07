#[test_only]
module baleenpay::routed_payment_tests;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry, AdminCap};
use baleenpay::router::{Self, Vault, RouterConfig};
use baleenpay::payment;

public struct USDC has drop {}

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
}

fun register_merchant(scenario: &mut test_scenario::Scenario, addr: address) {
    scenario.next_tx(addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestMerchant".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

fun enable_stablelayer(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut config = scenario.take_shared<RouterConfig>();
    router::set_mode(&admin_cap, &mut config, 1); // MODE_STABLELAYER
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    test_scenario::return_shared(config);
    scenario.return_to_sender(admin_cap);
}

#[test]
fun test_pay_once_routed_mode_stablelayer() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    enable_stablelayer(&mut scenario, admin);

    // Payer pays via routed path
    scenario.next_tx(payer);
    let config = scenario.take_shared<RouterConfig>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let clock = clock::create_for_testing(scenario.ctx());
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    payment::pay_once_routed<USDC>(
        &config,
        &mut account,
        &mut vault,
        usdc,
        b"order-001".to_string(),
        &clock,
        scenario.ctx(),
    );
    // Funds go to vault, not merchant wallet
    assert!(router::vault_balance(&vault) == 500);
    assert!(merchant::idle_principal(&account) == 500);
    assert!(merchant::total_received(&account) == 500);
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    test_scenario::return_shared(config);
    scenario.end();
}

#[test]
#[expected_failure] // ENotStableLayerMode
fun test_pay_once_routed_rejects_fallback_mode() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Create vault but stay in fallback mode
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(payer);
    let config = scenario.take_shared<RouterConfig>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let clock = clock::create_for_testing(scenario.ctx());
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    payment::pay_once_routed<USDC>(
        &config, &mut account, &mut vault, usdc,
        b"order-002".to_string(), &clock, scenario.ctx(),
    ); // should abort: mode != stablelayer
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    test_scenario::return_shared(config);
    scenario.end();
}

#[test]
#[expected_failure] // EPaused
fun test_pay_once_routed_paused() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    enable_stablelayer(&mut scenario, admin);

    // Pause merchant
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(payer);
    let config = scenario.take_shared<RouterConfig>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let clock = clock::create_for_testing(scenario.ctx());
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    payment::pay_once_routed<USDC>(
        &config, &mut account, &mut vault, usdc,
        b"order-003".to_string(), &clock, scenario.ctx(),
    );
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    test_scenario::return_shared(config);
    scenario.end();
}

#[test]
#[expected_failure]
fun test_pay_once_routed_duplicate_order() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    enable_stablelayer(&mut scenario, admin);

    // First payment
    scenario.next_tx(payer);
    let config = scenario.take_shared<RouterConfig>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let clock = clock::create_for_testing(scenario.ctx());
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    payment::pay_once_routed<USDC>(
        &config, &mut account, &mut vault, usdc,
        b"dup-order".to_string(), &clock, scenario.ctx(),
    );
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    test_scenario::return_shared(config);

    // Duplicate
    scenario.next_tx(payer);
    let config = scenario.take_shared<RouterConfig>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let clock = clock::create_for_testing(scenario.ctx());
    let usdc2 = coin::mint_for_testing<USDC>(500, scenario.ctx());
    payment::pay_once_routed<USDC>(
        &config, &mut account, &mut vault, usdc2,
        b"dup-order".to_string(), &clock, scenario.ctx(),
    ); // should abort: duplicate order_id
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    test_scenario::return_shared(config);
    scenario.end();
}
