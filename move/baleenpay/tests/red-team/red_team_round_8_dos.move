#[test_only]
module baleenpay::red_team_round_8_dos;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry, AdminCap};
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

// ── Attack 8a: Storage bloat via dynamic fields ──
// Attacker spams pay_once_v2 with unique order_ids to add dynamic fields to merchant.
// Each dynamic field costs storage. Merchant can remove them but needs to know each (payer, order_id).
#[test]
fun red_team_round_8a_storage_bloat_dynamic_fields() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let attacker = @0xEE;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Spam 20 unique order_ids
    let mut i = 0u64;
    while (i < 20) {
        scenario.next_tx(attacker);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(1, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        let mut order_bytes = b"SPAM-";
        let d1 = ((i / 10) % 10) as u8;
        let d2 = (i % 10) as u8;
        order_bytes.push_back(0x30 + d1);
        order_bytes.push_back(0x30 + d2);

        payment::pay_once_v2(
            &mut account, coin, order_bytes.to_string(), &clock, scenario.ctx(),
        );
        test_scenario::return_shared(account);
        clock.destroy_for_testing();
        i = i + 1;
    };

    // Verify all 20 records exist
    scenario.next_tx(attacker);
    let account = scenario.take_shared<MerchantAccount>();
    assert!(merchant::total_received(&account) == 20);
    assert!(payment::has_order_record(&account, attacker, b"SPAM-00".to_string()));
    assert!(payment::has_order_record(&account, attacker, b"SPAM-19".to_string()));
    test_scenario::return_shared(account);

    // Merchant CAN clean up, but must know each key
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    payment::remove_order_record(&cap, &mut account, attacker, b"SPAM-00".to_string());
    assert!(!payment::has_order_record(&account, attacker, b"SPAM-00".to_string()));
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    scenario.end();
    // FINDING: Attacker pays gas + dust per record. Merchant's shared object grows.
    // No limit on number of dynamic fields per merchant.
    // Merchant must enumerate attacker's order_ids off-chain to clean up.
}

// ── Attack 8b: Subscription count manipulation -- create many then cancel ──
// Each subscribe increments, each cancel decrements. Count should stay consistent.
#[test]
fun red_team_round_8b_subscription_count_consistency() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Create 3 subscriptions
    let mut i = 0u64;
    while (i < 3) {
        scenario.next_tx(payer);
        let mut account = scenario.take_shared<MerchantAccount>();
        let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 2, &clock, scenario.ctx());
        test_scenario::return_shared(account);
        clock.destroy_for_testing();
        i = i + 1;
    };

    scenario.next_tx(payer);
    let account = scenario.take_shared<MerchantAccount>();
    assert!(merchant::active_subscriptions(&account) == 3);
    test_scenario::return_shared(account);

    // Cancel 1 subscription
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    payment::cancel_subscription(&mut account, sub, scenario.ctx());
    assert!(merchant::active_subscriptions(&account) == 2);
    test_scenario::return_shared(account);

    scenario.end();
}

// ── Attack 8c: Decrement subscriptions below zero ──
#[test]
#[expected_failure] // ENoActiveSubscriptions
fun red_team_round_8c_decrement_below_zero() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Create 1 subscription
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::subscribe(&mut account, coin, 1_000_000, 86400_000, 2, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();

    // Cancel it
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    payment::cancel_subscription(&mut account, sub, scenario.ctx());
    assert!(merchant::active_subscriptions(&account) == 0);
    // Manually try to decrement again (package-internal, but test_only can access)
    merchant::decrement_subscriptions(&mut account); // Should abort
    test_scenario::return_shared(account);
    scenario.end();
}
