#[test_only]
/// Red Team Round 15: Access control bypass on typed yield admin functions.
/// Attack vectors: call admin_migrate_yield / admin_set_yield without AdminCap.
module baleenpay::red_team_round_15_typed_yield_access;
use sui::test_scenario;
use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry, AdminCap};
use baleenpay::router;

public struct USDB has drop {}

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
}

fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"Victim".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

/// 15a: Attacker tries admin_migrate_yield without AdminCap.
/// Expected: compilation error or abort — AdminCap is required by type system.
/// This test verifies the type-level protection is not bypassed.
#[test, expected_failure]
fun red_team_15a_migrate_without_admin_cap() {
    let admin = @0xAD;
    let attacker = @0xEE;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Seed legacy yield
    scenario.next_tx(admin);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_for_testing(&mut account, 100);
    test_scenario::return_shared(account);

    // Attacker tries to migrate — has no AdminCap
    scenario.next_tx(attacker);
    let admin_cap = scenario.take_from_sender<AdminCap>(); // should fail: attacker has no AdminCap
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

/// 15b: Attacker tries admin_set_yield to inflate their yield balance.
#[test, expected_failure]
fun red_team_15b_set_yield_without_admin_cap() {
    let admin = @0xAD;
    let attacker = @0xEE;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Attacker tries to set yield to MAX — no AdminCap
    scenario.next_tx(attacker);
    let admin_cap = scenario.take_from_sender<AdminCap>(); // fail
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 18_446_744_073_709_551_615);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
