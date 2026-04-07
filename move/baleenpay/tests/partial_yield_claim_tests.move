#[test_only]
module baleenpay::partial_yield_claim_tests;
use sui::test_scenario;
use sui::coin::{Self, Coin};
use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
use baleenpay::router::{Self, YieldVault};

public struct USDB has drop {}
public struct STABLE has drop {}

fun setup(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
}

fun register_merchant(scenario: &mut test_scenario::Scenario, merchant_addr: address) {
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(
        &mut registry,
        b"TestMerchant".to_string(),
        scenario.ctx(),
    );
    test_scenario::return_shared(registry);
}

fun create_yield_vault_usdb(scenario: &mut test_scenario::Scenario, admin: address) {
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_yield_vault<USDB>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);
}

fun seed_yield_vault(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    amount: u64,
) {
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let usdb_coin = coin::mint_for_testing<USDB>(amount, scenario.ctx());
    router::keeper_deposit_yield<USDB>(
        &admin_cap,
        &mut yield_vault,
        &mut account,
        usdb_coin,
    );
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(yield_vault);
}

// ── Happy path ──

#[test]
fun partial_claim_basic() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim 40 out of 100
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 60);
    assert!(router::yield_vault_balance<USDB>(&yield_vault) == 60);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Verify merchant received 40
    scenario.next_tx(merchant_addr);
    let usdb: Coin<USDB> = scenario.take_from_sender();
    assert!(usdb.value() == 40);
    scenario.return_to_sender(usdb);

    scenario.end();
}

#[test]
fun partial_claim_all_removes_df() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim exactly 100 (full amount via partial)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 100, scenario.ctx(),
    );
    // df should be removed → getter returns 0
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 0);
    assert!(router::yield_vault_balance<USDB>(&yield_vault) == 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

#[test]
fun v2_wrapper_still_works() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 500);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_v2<USDB>(
        &cap, &mut account, &mut yield_vault, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.next_tx(merchant_addr);
    let usdb: Coin<USDB> = scenario.take_from_sender();
    assert!(usdb.value() == 500);
    scenario.return_to_sender(usdb);

    scenario.end();
}

#[test]
fun multiple_partial_claims() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    // Claim 30
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 30, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 70);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Claim 30 more
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 30, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 40);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Claim remaining 40
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

// ── Abort tests ──

#[test, expected_failure]
fun abort_zero_amount() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 0, scenario.ctx(),
    );
    abort 0 // unreachable
}

#[test, expected_failure]
fun abort_exceeds_accrued() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 101, scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure]
fun abort_no_accrued_yield() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    // No yield seeded

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 50, scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure]
fun abort_vault_balance_insufficient() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);

    // Manually credit accrued yield without actually depositing to vault
    scenario.next_tx(admin);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::credit_external_yield_typed_for_testing<USDB>(&mut account, 1000);
    test_scenario::return_shared(account);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 500, scenario.ctx(),
    );
    abort 0
}

// ── Monkey tests ──

#[test]
fun claim_1_mist() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);
    create_yield_vault_usdb(&mut scenario, admin);
    seed_yield_vault(&mut scenario, admin, 100);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 1, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 99);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}

#[test]
fun multi_type_interleave() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register_merchant(&mut scenario, merchant_addr);

    // Create YieldVault<USDB>
    create_yield_vault_usdb(&mut scenario, admin);

    // Create YieldVault<STABLE>
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_yield_vault<STABLE>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Seed USDB 100
    seed_yield_vault(&mut scenario, admin, 100);

    // Seed STABLE 50
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut yield_vault_stable = scenario.take_shared<YieldVault<STABLE>>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let stable_coin = coin::mint_for_testing<STABLE>(50, scenario.ctx());
    router::keeper_deposit_yield<STABLE>(
        &admin_cap,
        &mut yield_vault_stable,
        &mut account,
        stable_coin,
    );
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(yield_vault_stable);

    // Partial claim USDB 40
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<USDB>>();
    router::claim_yield_partial<USDB>(
        &cap, &mut account, &mut yield_vault, 40, scenario.ctx(),
    );
    assert!(merchant::accrued_yield_typed<USDB>(&account) == 60);
    // STABLE untouched
    assert!(merchant::accrued_yield_typed<STABLE>(&account) == 50);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
}
