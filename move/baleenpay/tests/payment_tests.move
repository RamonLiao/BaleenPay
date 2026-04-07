#[test_only]
module baleenpay::payment_tests;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant;
use baleenpay::payment;
use baleenpay::test_usdc::TEST_USDC;

// ── Helpers ──

fun setup_merchant(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"TestShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

// ── Tests ──

#[test]
fun test_pay_once_success() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    // payer sends 100 USDC (6 decimals)
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let payment_coin = coin::mint_for_testing<TEST_USDC>(100_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::pay_once(&mut account, payment_coin, &clock, scenario.ctx());

    // verify ledger updated
    assert!(merchant::get_total_received(&account) == 100_000_000);
    assert!(merchant::get_idle_principal(&account) == 100_000_000);

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // verify merchant received the coin
    scenario.next_tx(merchant_addr);
    let received = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
    assert!(received.value() == 100_000_000);
    scenario.return_to_sender(received);

    scenario.end();
}

#[test]
fun test_pay_once_multiple_payments_accumulate() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer1 = @0xCC;
    let payer2 = @0xDD;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);

    // payer1 pays 50
    scenario.next_tx(payer1);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin1 = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin1, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // payer2 pays 75
    scenario.next_tx(payer2);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin2 = coin::mint_for_testing<TEST_USDC>(75_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin2, &clock, scenario.ctx());

    // verify accumulated totals
    assert!(merchant::get_total_received(&account) == 125_000_000);
    assert!(merchant::get_idle_principal(&account) == 125_000_000);

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure] // EPaused
fun test_pay_once_paused_merchant_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);

    // admin pauses merchant
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // payer tries to pay → should abort
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let payment_coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::pay_once(&mut account, payment_coin, &clock, scenario.ctx());

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure] // EZeroAmount
fun test_pay_once_zero_amount_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let zero_coin = coin::mint_for_testing<TEST_USDC>(0, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::pay_once(&mut account, zero_coin, &clock, scenario.ctx());

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// ── Subscription Tests ──

#[test]
fun test_subscribe_success() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    // 3 periods × 10 USDC = 30 USDC total, coin has 50 (excess refunded)
    let coin = coin::mint_for_testing<TEST_USDC>(50_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000); // start at t=1000ms

    payment::subscribe(
        &mut account, coin,
        10_000_000, // amount_per_period
        86400_000,  // period_ms (1 day)
        3,          // prepaid_periods
        &clock,
        scenario.ctx(),
    );

    // First period processed immediately → ledger has 10 USDC
    assert!(merchant::get_total_received(&account) == 10_000_000);
    assert!(merchant::get_idle_principal(&account) == 10_000_000);
    assert!(merchant::get_active_subscriptions(&account) == 1);

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Verify: payer gets refund of excess (50 - 30 = 20)
    scenario.next_tx(payer);
    let refund = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
    assert!(refund.value() == 20_000_000);
    scenario.return_to_sender(refund);

    // Verify: merchant received first period payment
    scenario.next_tx(merchant_addr);
    let received = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
    assert!(received.value() == 10_000_000);
    scenario.return_to_sender(received);

    // Verify subscription object state
    scenario.next_tx(payer);
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    assert!(payment::get_sub_balance(&sub) == 20_000_000); // 2 remaining periods
    assert!(payment::get_sub_next_due(&sub) == 1000 + 86400_000);
    assert!(payment::get_sub_payer(&sub) == payer);
    assert!(payment::get_sub_amount_per_period(&sub) == 10_000_000);
    test_scenario::return_shared(sub);

    scenario.end();
}

#[test]
fun test_subscribe_exact_amount_no_refund() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    // Exact amount: 2 periods × 5 = 10
    let coin = coin::mint_for_testing<TEST_USDC>(10_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        5_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );

    assert!(merchant::get_total_received(&account) == 5_000_000);
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // No refund coin should exist for payer
    scenario.next_tx(payer);
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    assert!(payment::get_sub_balance(&sub) == 5_000_000); // 1 remaining
    test_scenario::return_shared(sub);

    scenario.end();
}

#[test]
fun test_process_subscription_when_due() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let bot = @0xDD; // permissionless caller
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(30_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000);

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 3,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Advance clock past next_due and process as bot
    scenario.next_tx(bot);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000 + 86400_000); // exactly at due time

    payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

    // Ledger: 10 (subscribe) + 10 (process) = 20
    assert!(merchant::get_total_received(&account) == 20_000_000);
    assert!(payment::get_sub_balance(&sub) == 10_000_000); // 1 period left
    assert!(payment::get_sub_next_due(&sub) == 1000 + 86400_000 * 2);

    test_scenario::return_shared(sub);
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure] // ENotDue
fun test_process_subscription_not_due_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000);

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Try to process before due → should abort
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000 + 86400_000 - 1); // 1ms before due

    payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

    test_scenario::return_shared(sub);
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
fun test_cancel_subscription_refund() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(30_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 3,
        &clock, scenario.ctx(),
    );
    assert!(merchant::get_active_subscriptions(&account) == 1);
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Payer cancels → refund 20 USDC (2 remaining periods)
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();

    payment::cancel_subscription(&mut account, sub, scenario.ctx());

    assert!(merchant::get_active_subscriptions(&account) == 0);
    test_scenario::return_shared(account);

    // Verify refund coin
    scenario.next_tx(payer);
    let refund = scenario.take_from_sender<coin::Coin<TEST_USDC>>();
    assert!(refund.value() == 20_000_000);
    scenario.return_to_sender(refund);

    scenario.end();
}

#[test]
#[expected_failure] // ENotPayer
fun test_cancel_subscription_not_payer_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let attacker = @0xEE;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Attacker tries to cancel → should abort
    scenario.next_tx(attacker);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();

    payment::cancel_subscription(&mut account, sub, scenario.ctx());

    test_scenario::return_shared(account);
    scenario.end();
}

#[test]
fun test_fund_subscription() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Payer adds 30 more USDC
    scenario.next_tx(payer);
    let account = scenario.take_shared<merchant::MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let extra = coin::mint_for_testing<TEST_USDC>(30_000_000, scenario.ctx());

    payment::fund_subscription(&account, &mut sub, extra, scenario.ctx());
    test_scenario::return_shared(account);

    // Balance: 10 (1 remaining from subscribe) + 30 = 40
    assert!(payment::get_sub_balance(&sub) == 40_000_000);
    test_scenario::return_shared(sub);

    scenario.end();
}

#[test]
#[expected_failure] // ENotPayer
fun test_fund_subscription_not_payer_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let stranger = @0xEE;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Stranger tries to fund → should abort
    scenario.next_tx(stranger);
    let account = scenario.take_shared<merchant::MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let extra = coin::mint_for_testing<TEST_USDC>(10_000_000, scenario.ctx());

    payment::fund_subscription(&account, &mut sub, extra, scenario.ctx());

    test_scenario::return_shared(account);
    test_scenario::return_shared(sub);
    scenario.end();
}

#[test]
#[expected_failure] // EInsufficientPrepaid
fun test_subscribe_insufficient_prepaid_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    // Need 30 but only have 20
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 3,
        &clock, scenario.ctx(),
    );

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure] // EInsufficientBalance
fun test_process_subscription_insufficient_balance_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);
    scenario.next_tx(payer);

    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    // Only 1 prepaid period → after subscribe processes first, balance = 0
    let coin = coin::mint_for_testing<TEST_USDC>(10_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000);

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 1,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);

    // Try to process with empty balance → should abort
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000 + 86400_000);

    payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());

    test_scenario::return_shared(sub);
    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// ── Merchant Mismatch Tests ──

#[test]
#[expected_failure] // EMerchantMismatch
fun test_process_subscription_wrong_merchant_fails() {
    let admin = @0xAD;
    let merchant_a = @0xBB;
    let merchant_b = @0xDD;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    // Init + register merchant A
    setup_merchant(&mut scenario, admin, merchant_a);

    // Capture merchant A's ID
    scenario.next_tx(payer);
    let account_a_obj = scenario.take_shared<merchant::MerchantAccount>();
    let id_a = object::id(&account_a_obj);
    test_scenario::return_shared(account_a_obj);

    // Register merchant B
    scenario.next_tx(merchant_b);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    // Capture merchant B's ID
    scenario.next_tx(payer);
    let account_a_tmp = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_a);
    let account_b_obj = scenario.take_shared<merchant::MerchantAccount>();
    let id_b = object::id(&account_b_obj);
    test_scenario::return_shared(account_a_tmp);
    test_scenario::return_shared(account_b_obj);

    // Payer subscribes to merchant A
    scenario.next_tx(payer);
    let mut account_a = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_a);
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000);

    payment::subscribe(
        &mut account_a, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account_a);
    clock::destroy_for_testing(clock);

    // Process subscription against merchant B → should abort EMerchantMismatch
    scenario.next_tx(payer);
    let mut account_b = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_b);
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock::set_for_testing(&mut clock, 1000 + 86400_000);

    payment::process_subscription(&mut account_b, &mut sub, &clock, scenario.ctx());

    test_scenario::return_shared(sub);
    test_scenario::return_shared(account_b);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure] // EMerchantMismatch
fun test_cancel_subscription_wrong_merchant_fails() {
    let admin = @0xAD;
    let merchant_a = @0xBB;
    let merchant_b = @0xDD;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    // Init + register merchant A
    setup_merchant(&mut scenario, admin, merchant_a);

    // Capture merchant A's ID
    scenario.next_tx(payer);
    let account_a_obj = scenario.take_shared<merchant::MerchantAccount>();
    let id_a = object::id(&account_a_obj);
    test_scenario::return_shared(account_a_obj);

    // Register merchant B
    scenario.next_tx(merchant_b);
    let mut registry = scenario.take_shared<merchant::MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"ShopB".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);

    // Capture merchant B's ID
    scenario.next_tx(payer);
    let account_a_tmp = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_a);
    let account_b_obj = scenario.take_shared<merchant::MerchantAccount>();
    let id_b = object::id(&account_b_obj);
    test_scenario::return_shared(account_a_tmp);
    test_scenario::return_shared(account_b_obj);

    // Payer subscribes to merchant A
    scenario.next_tx(payer);
    let mut account_a = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_a);
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account_a, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );
    test_scenario::return_shared(account_a);
    clock::destroy_for_testing(clock);

    // Payer cancels but passes merchant B → should abort EMerchantMismatch
    scenario.next_tx(payer);
    let mut account_b = test_scenario::take_shared_by_id<merchant::MerchantAccount>(&scenario, id_b);
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();

    payment::cancel_subscription(&mut account_b, sub, scenario.ctx());

    test_scenario::return_shared(account_b);
    scenario.end();
}

#[test]
#[expected_failure] // EPaused
fun test_subscribe_paused_merchant_fails() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);

    setup_merchant(&mut scenario, admin, merchant_addr);

    // Admin pauses merchant
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Payer tries to subscribe → should abort
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<merchant::MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(20_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    payment::subscribe(
        &mut account, coin,
        10_000_000, 86400_000, 2,
        &clock, scenario.ctx(),
    );

    test_scenario::return_shared(account);
    clock::destroy_for_testing(clock);
    scenario.end();
}
