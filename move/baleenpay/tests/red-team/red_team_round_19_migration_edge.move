#[test_only]
/// Red Team Round 19: Migration edge cases.
/// Attack vectors: migrate with 0 balance, admin_set after migrate, re-migrate after set.
module baleenpay::red_team_round_19_migration_edge;
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
    merchant::register_merchant(&mut registry, b"Target".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

/// 19a: Migrate with 0 legacy yield — should succeed (no df added, struct stays 0).
/// Then admin_set_yield should work (creates df fresh).
#[test]
fun red_team_19a_migrate_zero_then_set() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // No legacy yield — struct field = 0
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();

    // Migrate with 0 — should NOT create df (amount == 0 → skip add)
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 0);

    // admin_set_yield should still work — creates df from scratch
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 50);
    assert!(merchant::get_accrued_yield_typed<USDB>(&account) == 50);

    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

/// 19b: Migrate with 0 yield, then try migrate again — should FAIL (EAlreadyMigrated).
/// df is always added (even with value 0), so guard triggers correctly.
#[test, expected_failure]
fun red_team_19b_double_migrate_zero_yield() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();

    // First migrate — 0 yield, df added with value 0
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);
    // Second migrate — should abort (EAlreadyMigrated)
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);

    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

/// 19c: admin_set_yield to non-zero, then admin_migrate — should fail (df exists).
#[test, expected_failure]
fun red_team_19c_migrate_after_set() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();

    // Set yield to 50 — creates df
    merchant::admin_set_yield<USDB>(&admin_cap, &mut account, 50);

    // Try migrate — should FAIL (df already exists → EAlreadyMigrated)
    merchant::admin_migrate_yield<USDB>(&admin_cap, &mut account);

    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}
