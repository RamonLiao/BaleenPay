#[test_only]
module baleenpay::monkey_v2_tests;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use std::string;
use baleenpay::merchant;
use baleenpay::payment;
use baleenpay::test_usdc::TEST_USDC;

fun setup_merchant(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

// Max length order_id (64 bytes, all printable ASCII)
#[test]
fun test_max_length_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());
    let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
    // 64 chars of 'A' (0x41)
    let long_id = string::utf8(b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
    payment::pay_once_v2(&mut account, coin, long_id, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// 65 bytes — should fail
#[test]
#[expected_failure] // EInvalidOrderId (#[error] constant)
fun test_order_id_65_bytes_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());
    let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
    let too_long = string::utf8(b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"); // 65
    payment::pay_once_v2(&mut account, coin, too_long, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// Boundary ASCII chars (0x21 = '!' and 0x7E = '~')
#[test]
fun test_boundary_ascii_chars() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());
    let coin = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
    payment::pay_once_v2(&mut account, coin, string::utf8(b"!~"), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// subscribe_v2 with MAX_PREPAID_PERIODS (1000) — should succeed
#[test]
fun test_subscribe_v2_max_periods() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());
    // 1 USDC * 1000 periods = 1000 USDC
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000_000, scenario.ctx());
    payment::subscribe_v2(
        &mut account, coin, 1_000_000, 86_400_000, 1000,
        string::utf8(b"sub_max"), &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// subscribe_v2 with 1001 periods — should fail (exceeds MAX_PREPAID_PERIODS)
#[test]
#[expected_failure] // EExceedsMaxPrepaidPeriods (#[error] constant)
fun test_subscribe_v2_over_max_periods_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());
    let coin = coin::mint_for_testing<TEST_USDC>(2_000_000_000, scenario.ctx());
    payment::subscribe_v2(
        &mut account, coin, 1_000_000, 86_400_000, 1001,
        string::utf8(b"sub_over"), &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// Cross-coin blocking: pay_once_v2 then subscribe_v2 with same order_id — should fail
#[test]
#[expected_failure] // EOrderAlreadyPaid (#[error] constant)
fun test_cross_operation_same_order_id_blocked() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let clock = clock::create_for_testing(scenario.ctx());

    // pay_once_v2 first
    let coin1 = coin::mint_for_testing<TEST_USDC>(100, scenario.ctx());
    payment::pay_once_v2(&mut account, coin1, string::utf8(b"shared_id"), &clock, scenario.ctx());

    // subscribe_v2 with same order_id — should abort
    let coin2 = coin::mint_for_testing<TEST_USDC>(300, scenario.ctx());
    payment::subscribe_v2(&mut account, coin2, 100, 86_400_000, 3, string::utf8(b"shared_id"), &clock, scenario.ctx());

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}
