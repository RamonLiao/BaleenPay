#[test_only]
module baleenpay::router_tests;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant;
use baleenpay::payment;
use baleenpay::router::{Self, YieldVault};
use baleenpay::test_usdc::TEST_USDC;

// ── Helpers ──

fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
    // Create YieldVault for claim_yield_v2 tests
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    router::create_yield_vault<TEST_USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

// ── Router Config Tests ──

#[test]
fun test_router_init_fallback_mode() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    scenario.next_tx(admin);
    router::init_for_testing(scenario.ctx());

    scenario.next_tx(admin);
    let config = scenario.take_shared<router::RouterConfig>();
    assert!(router::mode(&config) == 0);
    assert!(router::is_fallback(&config));
    test_scenario::return_shared(config);

    scenario.end();
}

#[test]
#[expected_failure] // ESameMode
fun test_set_mode_same_mode_fails() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut config = scenario.take_shared<router::RouterConfig>();

    // Try to set same mode (0 → 0) → should abort
    router::set_mode(&admin_cap, &mut config, 0);

    test_scenario::return_shared(config);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure] // EInvalidMode
fun test_set_mode_invalid_mode_fails() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut config = scenario.take_shared<router::RouterConfig>();

    // Mode 5 is invalid
    router::set_mode(&admin_cap, &mut config, 5);

    test_scenario::return_shared(config);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

// ── claim_yield Tests ──

#[test]
fun test_claim_yield_success() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup(&mut scenario, admin, merchant_addr);

    // Payer makes a payment to create idle_principal
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin, &clock, scenario.ctx());
    assert!(merchant::idle_principal(&account) == 100_000_000);

    // Simulate external yield: credit account + fund YieldVault
    merchant::credit_external_yield_typed_for_testing<TEST_USDC>(&mut account, 5_000_000);
    assert!(merchant::accrued_yield_typed<TEST_USDC>(&account) == 5_000_000);

    test_scenario::return_shared(account);

    // Fund YieldVault with matching coins
    let yield_coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
    router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
    test_scenario::return_shared(yield_vault);
    clock::destroy_for_testing(clock);

    // Merchant claims yield via v2
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<merchant::MerchantCap>();
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();

    router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
    assert!(merchant::accrued_yield_typed<TEST_USDC>(&account) == 0);

    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test]
#[expected_failure] // EZeroYield
fun test_claim_yield_zero_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);

    setup(&mut scenario, admin, merchant_addr);

    // No yield accrued → should abort
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<merchant::MerchantCap>();
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();

    router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());

    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

#[test]
#[expected_failure] // ENotMerchantOwner
fun test_claim_yield_wrong_cap_fails() {
    let admin = @0xAD;
    let merchant_a = @0xBB;
    let merchant_b = @0xCC;
    let payer = @0xDD;
    let mut scenario = test_scenario::begin(admin);

    setup(&mut scenario, admin, merchant_a);

    // Register a second merchant
    scenario.next_tx(merchant_b);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"OtherShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    // Pay merchant_a to create idle_principal, then simulate yield.
    // Take both accounts, identify by owner, operate on the correct one.
    scenario.next_tx(payer);
    let mut acct_1 = scenario.take_shared<merchant::MerchantAccount>();
    let mut acct_2 = scenario.take_shared<merchant::MerchantAccount>();

    // Identify which is merchant_a's account
    let (account_a_is_1) = merchant::owner(&acct_1) == merchant_a;

    // Fund the YieldVault with coins for claim
    let yield_coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
    router::deposit_to_yield_vault_for_testing(&mut yield_vault, yield_coin);
    test_scenario::return_shared(yield_vault);

    if (account_a_is_1) {
        let coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut acct_1, coin, &clock, scenario.ctx());
        merchant::credit_external_yield_typed_for_testing<TEST_USDC>(&mut acct_1, 2_000_000);
        clock::destroy_for_testing(clock);
    } else {
        let coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::pay_once(&mut acct_2, coin, &clock, scenario.ctx());
        merchant::credit_external_yield_typed_for_testing<TEST_USDC>(&mut acct_2, 2_000_000);
        clock::destroy_for_testing(clock);
    };

    test_scenario::return_shared(acct_1);
    test_scenario::return_shared(acct_2);

    // merchant_b tries to claim merchant_a's yield → wrong cap → abort
    scenario.next_tx(merchant_b);
    let cap_b = scenario.take_from_sender<merchant::MerchantCap>();

    // Take both again, find merchant_a's account
    let mut acct_1 = scenario.take_shared<merchant::MerchantAccount>();
    let mut acct_2 = scenario.take_shared<merchant::MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();

    if (merchant::owner(&acct_1) == merchant_a) {
        // cap_b belongs to merchant_b, account belongs to merchant_a → mismatch
        router::claim_yield_v2<TEST_USDC>(&cap_b, &mut acct_1, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(acct_1);
        test_scenario::return_shared(acct_2);
    } else {
        router::claim_yield_v2<TEST_USDC>(&cap_b, &mut acct_2, &mut yield_vault, scenario.ctx());
        test_scenario::return_shared(acct_1);
        test_scenario::return_shared(acct_2);
    };
    test_scenario::return_shared(yield_vault);

    scenario.return_to_sender(cap_b);
    scenario.end();
}

// ── Fallback mode payment flow (unchanged behavior) ──

#[test]
fun test_fallback_mode_payment_direct() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup(&mut scenario, admin, merchant_addr);

    // Verify router is in fallback mode
    scenario.next_tx(admin);
    let config = scenario.take_shared<router::RouterConfig>();
    assert!(router::is_fallback(&config));
    test_scenario::return_shared(config);

    // Payment goes directly to merchant (same as before — fallback = no routing)
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin, &clock, scenario.ctx());

    assert!(merchant::total_received(&account) == 100_000_000);
    assert!(merchant::idle_principal(&account) == 100_000_000);
    assert!(merchant::accrued_yield(&account) == 0); // no yield in fallback

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}
