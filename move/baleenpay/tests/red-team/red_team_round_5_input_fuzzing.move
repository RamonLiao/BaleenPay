#[test_only]
module baleenpay::red_team_round_5_input_fuzzing;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant::{Self, MerchantAccount, MerchantRegistry};
use baleenpay::payment;
use baleenpay::test_usdc::TEST_USDC;

fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

// ── Attack 5a: Empty order_id ──
#[test]
#[expected_failure]
fun red_team_round_5a_empty_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // Empty order_id should be rejected by validate_order_id
    payment::pay_once_v2(&mut account, coin, b"".to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 5b: Order_id with control characters (0x00, 0x1F) ──
#[test]
#[expected_failure]
fun red_team_round_5b_control_char_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // Null byte in order_id
    let bad_id = vector[0x00, 0x41, 0x42]; // \0AB
    payment::pay_once_v2(&mut account, coin, bad_id.to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 5c: Max-length order_id (64 bytes, right at limit) ──
#[test]
fun red_team_round_5c_max_length_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // Exactly 64 bytes of printable ASCII
    let max_id = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    assert!(max_id.length() == 64);
    payment::pay_once_v2(&mut account, coin, max_id.to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 5d: Over-max order_id (65 bytes) ──
#[test]
#[expected_failure]
fun red_team_round_5d_overlength_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // 65 bytes -- exceeds MAX_ORDER_ID_BYTES
    let over_id = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    assert!(over_id.length() == 65);
    payment::pay_once_v2(&mut account, coin, over_id.to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 5e: Zero coin payment ──
#[test]
#[expected_failure] // EZeroAmount
fun red_team_round_5e_zero_coin_payment() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 5f: Space character in order_id (0x20 is below 0x21 threshold) ──
#[test]
#[expected_failure]
fun red_team_round_5f_space_in_order_id() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once_v2(&mut account, coin, b"ORDER 001".to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();
    scenario.end();
}
