/// Red Team Round 17: Input Fuzzing — boundary values on all new functions
/// Attack vectors:
/// 1. take_stablecoin with amount=0
/// 2. take_stablecoin with amount=MAX_U64
/// 3. move_to_farming with amount=MAX_U64
/// 4. return_from_farming with amount=MAX_U64
#[test_only]
module baleenpay::red_team_round_17_farming_fuzzing;
use sui::test_scenario;
use sui::coin;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::router::{Self, StablecoinVault};

public struct STABLECOIN has drop {}
const MAX_U64: u64 = 18_446_744_073_709_551_615;

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

/// ATTACK: take_stablecoin with amount=0
#[test]
#[expected_failure] // EZeroAmount
fun test_fuzz_take_stablecoin_zero() {
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
    let coin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 0, scenario.ctx());
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

/// ATTACK: take_stablecoin with MAX_U64 (far exceeds farming balance)
#[test]
#[expected_failure] // EInsufficientPrincipal (farming < MAX_U64)
fun test_fuzz_take_stablecoin_max_u64() {
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
    let coin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, MAX_U64, scenario.ctx());
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

/// ATTACK: move_to_farming with MAX_U64
#[test]
#[expected_failure] // EInsufficientPrincipal (idle < MAX_U64)
fun test_fuzz_move_to_farming_max_u64() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    merchant::move_to_farming_for_testing(&mut account, MAX_U64);

    test_scenario::return_shared(account);
    scenario.end();
}

/// ATTACK: return_from_farming with MAX_U64
#[test]
#[expected_failure] // EInsufficientPrincipal (farming < MAX_U64)
fun test_fuzz_return_from_farming_max_u64() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    merchant::move_to_farming_for_testing(&mut account, 1000);
    merchant::return_from_farming_for_testing(&mut account, MAX_U64);

    test_scenario::return_shared(account);
    scenario.end();
}
