#[test_only]
module baleenpay::red_team_round_3_object_manipulation;
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

// ── Attack 3a: Process subscription with wrong merchant account ──
// Subscription for merchant A, but process_subscription called with merchant B's account
#[test]
#[expected_failure] // EMerchantMismatch
fun red_team_round_3a_subscription_wrong_merchant() {
    let admin = @0xAD;
    let merchant_a = @0xA1;
    let merchant_b = @0xB2;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());

    // Register two merchants
    scenario.next_tx(merchant_a);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopA".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    scenario.next_tx(merchant_b);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    // Payer subscribes to merchant A
    scenario.next_tx(payer);
    // We need to pick the right account. In test_scenario, take_shared picks by type.
    // We'll subscribe to whichever comes first (both are MerchantAccount).
    let mut account_a = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    payment::subscribe(&mut account_a, coin, 1_000_000, 1000, 5, &clock, scenario.ctx());
    let merchant_a_id = object::id(&account_a);
    test_scenario::return_shared(account_a);

    // Try to process subscription against merchant B's account
    scenario.next_tx(payer);
    // Take the OTHER merchant account (not the one subscription belongs to)
    let mut account_b = scenario.take_shared<MerchantAccount>();
    // If it's the same one, skip this test variant
    if (object::id(&account_b) == merchant_a_id) {
        test_scenario::return_shared(account_b);
        let mut account_b2 = scenario.take_shared<MerchantAccount>();
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        clock.set_for_testing(2000);
        // ATTACK: wrong account
        payment::process_subscription(&mut account_b2, &mut sub, &clock, scenario.ctx());
        test_scenario::return_shared(account_b2);
        test_scenario::return_shared(sub);
    } else {
        let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        clock.set_for_testing(2000);
        payment::process_subscription(&mut account_b, &mut sub, &clock, scenario.ctx());
        test_scenario::return_shared(account_b);
        test_scenario::return_shared(sub);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// ── Attack 3b: Cancel subscription with wrong merchant account ──
#[test]
#[expected_failure] // EMerchantMismatch
fun red_team_round_3b_cancel_wrong_merchant() {
    let admin = @0xAD;
    let merchant_a = @0xA1;
    let merchant_b = @0xB2;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());

    scenario.next_tx(merchant_a);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopA".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    scenario.next_tx(merchant_b);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    // Payer subscribes to merchant A
    scenario.next_tx(payer);
    let mut account_a = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::subscribe(&mut account_a, coin, 1_000_000, 1000, 5, &clock, scenario.ctx());
    let merchant_a_id = object::id(&account_a);
    test_scenario::return_shared(account_a);
    clock.destroy_for_testing();

    // Payer tries to cancel with wrong merchant account
    scenario.next_tx(payer);
    let mut account_b = scenario.take_shared<MerchantAccount>();
    if (object::id(&account_b) == merchant_a_id) {
        test_scenario::return_shared(account_b);
        let mut account_b2 = scenario.take_shared<MerchantAccount>();
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        payment::cancel_subscription(&mut account_b2, sub, scenario.ctx());
        test_scenario::return_shared(account_b2);
    } else {
        let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
        payment::cancel_subscription(&mut account_b, sub, scenario.ctx());
        test_scenario::return_shared(account_b);
    };

    scenario.end();
}

// ── Attack 3c: Dynamic field squatting -- can attacker front-run order_id? ──
// OrderKey is scoped to (payer, order_id), so different payers can use same order_id
// Verify: attacker pays with same order_id as legit payer -- should NOT block legit payer
#[test]
fun red_team_round_3c_order_id_no_cross_payer_collision() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let attacker = @0xEE;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Attacker pays with order_id "ORDER-001"
    scenario.next_tx(attacker);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin1 = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once_v2(&mut account, coin1, b"ORDER-001".to_string(), &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();

    // Legit payer should STILL be able to use same order_id
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin2 = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
    let clock2 = clock::create_for_testing(scenario.ctx());
    payment::pay_once_v2(&mut account, coin2, b"ORDER-001".to_string(), &clock2, scenario.ctx());

    // Both should have records
    assert!(payment::has_order_record(&account, attacker, b"ORDER-001".to_string()));
    assert!(payment::has_order_record(&account, payer, b"ORDER-001".to_string()));

    test_scenario::return_shared(account);
    clock2.destroy_for_testing();
    scenario.end();
}
