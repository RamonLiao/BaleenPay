/// Red Team Round 19: Accounting Invariant — conservation law violation
/// Attack vectors:
/// 1. Verify idle + farming always equals total_received minus withdrawals
/// 2. return_from_farming doesn't restore idle (by design) — verify no phantom funds
/// 3. Repeated move_to_farming / return cycles don't create or destroy value
#[test_only]
module baleenpay::red_team_round_19_accounting_invariant;
use sui::test_scenario;
use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry};

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
}

fun register(scenario: &mut test_scenario::Scenario, addr: address) {
    scenario.next_tx(addr);
    let mut reg = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut reg, b"Test".to_string(), scenario.ctx());
    test_scenario::return_shared(reg);
}

/// ATTACK: Rapidly cycle move_to_farming → return_from_farming
/// Verify farming_principal doesn't leak (return doesn't restore idle)
#[test]
fun test_attack_cycle_farming_no_value_creation() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 10000);

    // Initial state
    let initial_idle = merchant::idle_principal(&account);
    assert!(initial_idle == 10000);
    assert!(merchant::farming_principal(&account) == 0);

    // Cycle 10 times: move 1000 to farming, then return 500
    let mut i = 0;
    while (i < 10) {
        merchant::move_to_farming_for_testing(&mut account, 1000);
        merchant::return_from_farming_for_testing(&mut account, 500);
        i = i + 1;
    };

    // After 10 cycles:
    // idle: 10000 - (10 * 1000) = 0
    // farming: 10 * (1000 - 500) = 5000
    // NOTE: return_from_farming does NOT add back to idle!
    let final_idle = merchant::idle_principal(&account);
    let final_farming = merchant::farming_principal(&account);

    assert!(final_idle == 0, 100);
    assert!(final_farming == 5000, 101);

    // Total accounted = idle + farming = 5000 < 10000 (initial)
    // The "missing" 5000 is the returned farming that doesn't go back to idle.
    // This is by design — the USDC comes back via StableLayer burn, not accounting.
    // But it means 5000 is "phantom" — no ledger entry tracks it.
    // This is a DESIGN CONCERN, not necessarily a bug.

    test_scenario::return_shared(account);
    scenario.end();
}

/// Verify: move_to_farming is strictly subtractive from idle
#[test]
#[expected_failure] // Can't move more than remaining idle
fun test_attack_exhaust_idle_then_move_more() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 100);
    merchant::move_to_farming_for_testing(&mut account, 100);
    // idle = 0 now
    merchant::move_to_farming_for_testing(&mut account, 1); // should fail

    test_scenario::return_shared(account);
    scenario.end();
}

/// Verify: return_from_farming is strictly subtractive from farming
#[test]
#[expected_failure]
fun test_attack_return_more_than_farming() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 100);
    merchant::move_to_farming_for_testing(&mut account, 50);
    merchant::return_from_farming_for_testing(&mut account, 51); // should fail

    test_scenario::return_shared(account);
    scenario.end();
}
