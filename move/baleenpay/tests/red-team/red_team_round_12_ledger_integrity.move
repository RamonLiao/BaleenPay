#[test_only]
module baleenpay::red_team_round_12_ledger;
use sui::test_scenario;
use sui::coin;
use sui::clock;
use baleenpay::merchant::{Self, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::payment;
use baleenpay::router::{Self, YieldVault};
use baleenpay::test_usdc::TEST_USDC;

fun setup(scenario: &mut test_scenario::Scenario, admin: address, merchant_addr: address) {
    scenario.next_tx(admin);
    merchant::init_for_testing(scenario.ctx());
    router::init_for_testing(scenario.ctx());
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    router::create_yield_vault<TEST_USDC>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(merchant_addr);
    let mut registry = scenario.take_shared<MerchantRegistry>();
    merchant::register_merchant(&mut registry, b"LedgerShop".to_string(), scenario.ctx());
    test_scenario::return_shared(registry);
}

// ── Attack 12a: total_received overflow via massive payments ──
// add_payment does unchecked addition: total_received + amount.
// Two payments of MAX_U64/2 + 1 each = overflow.
#[test]
#[expected_failure]
fun red_team_round_12a_total_received_overflow() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    let half_max_plus_one = 9_223_372_036_854_775_808; // MAX_U64/2 + 1

    // First big payment
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin1 = coin::mint_for_testing<TEST_USDC>(half_max_plus_one, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin1, &clock, scenario.ctx());
    assert!(merchant::total_received(&account) == half_max_plus_one);
    test_scenario::return_shared(account);
    clock.destroy_for_testing();

    // Second big payment triggers overflow
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin2 = coin::mint_for_testing<TEST_USDC>(half_max_plus_one, scenario.ctx());
    let clock2 = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin2, &clock2, scenario.ctx());
    test_scenario::return_shared(account);
    clock2.destroy_for_testing();
    scenario.end();
    // EXPLOITED/SUSPICIOUS: add_payment has no overflow check on total_received.
    // Move 2024 aborts on overflow by default, so no silent corruption.
    // But this means a merchant receiving > MAX_U64 total will have their
    // account permanently bricked -- no more payments accepted.
    // Practically unlikely with real tokens, but theoretically possible
    // with dust coins or test tokens.
}

// ── Attack 12b: idle_principal desync after credit_yield ──
// credit_yield moves from idle_principal to accrued_yield.
// If idle_principal < amount, it aborts. But what if keeper credits
// more yield than idle_principal via credit_external_yield (which does NOT deduct)?
// Then accrued_yield > idle_principal, and claim_yield_v2 could drain more
// than what was actually in the vault.
#[test]
fun red_team_round_12b_external_yield_inflates_beyond_principal() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Payer pays 1M
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(1_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::pay_once(&mut account, coin, &clock, scenario.ctx());
    assert!(merchant::idle_principal(&account) == 1_000_000);
    test_scenario::return_shared(account);
    clock.destroy_for_testing();

    // Admin credits 10M external yield (10x more than principal!)
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
    let yield_coin = coin::mint_for_testing<TEST_USDC>(10_000_000, scenario.ctx());
    router::keeper_deposit_yield<TEST_USDC>(
        &admin_cap, &mut yield_vault, &mut account, yield_coin,
    );
    // accrued_yield = 10M, idle_principal = 1M (unchanged by external yield)
    assert!(merchant::accrued_yield_typed<TEST_USDC>(&account) == 10_000_000);
    assert!(merchant::idle_principal(&account) == 1_000_000);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant claims 10M yield -- succeeds because vault has 10M
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut yield_vault = scenario.take_shared<YieldVault<TEST_USDC>>();
    router::claim_yield_v2<TEST_USDC>(&cap, &mut account, &mut yield_vault, scenario.ctx());
    // idle_principal still 1M (untouched), accrued_yield = 0
    assert!(merchant::idle_principal(&account) == 1_000_000);
    assert!(merchant::accrued_yield_typed<TEST_USDC>(&account) == 0);
    test_scenario::return_shared(yield_vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
    // FINDING: credit_external_yield allows yield > principal.
    // This is BY DESIGN for StableLayer returns (external yield source).
    // The invariant is: YieldVault.balance >= sum(all merchants' accrued_yield).
    // Currently no on-chain enforcement of this cross-object invariant.
    // If admin mistakenly credits yield without depositing coins, merchant gets stuck (11a).
}

// ── Attack 12c: cancel subscription after all periods processed (zero balance) ──
// Payer processes all periods, then cancels. Should get 0 refund.
// But does decrement_subscriptions still work correctly?
#[test]
fun red_team_round_12c_cancel_after_fully_processed() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // 2 periods, 1M each
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    payment::subscribe(&mut account, coin, 1_000_000, 100, 2, &clock, scenario.ctx());
    assert!(merchant::active_subscriptions(&account) == 1);
    test_scenario::return_shared(account);

    // Process remaining period
    clock.set_for_testing(200);
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    payment::process_subscription(&mut account, &mut sub, &clock, scenario.ctx());
    assert!(payment::sub_balance<TEST_USDC>(&sub) == 0);
    test_scenario::return_shared(account);
    test_scenario::return_shared(sub);

    // Cancel with zero balance
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    payment::cancel_subscription(&mut account, sub, scenario.ctx());
    assert!(merchant::active_subscriptions(&account) == 0);
    test_scenario::return_shared(account);

    clock.destroy_for_testing();
    scenario.end();
    // DEFENDED: Zero-balance cancel works correctly. No refund coin created (destroy_zero path).
    // Subscription object deleted, counter decremented properly.
}

// ── Attack 12d: fund_subscription while merchant is admin-frozen ──
// fund_subscription checks is_paused (admin OR self). Payer should NOT be
// able to deposit into a frozen merchant's escrow.
#[test]
#[expected_failure] // EPaused
fun red_team_round_12d_fund_during_admin_freeze() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let payer = @0xCC;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin, merchant_addr);

    // Create subscription
    scenario.next_tx(payer);
    let mut account = scenario.take_shared<MerchantAccount>();
    let coin = coin::mint_for_testing<TEST_USDC>(2_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    payment::subscribe(&mut account, coin, 1_000_000, 1000, 2, &clock, scenario.ctx());
    test_scenario::return_shared(account);
    clock.destroy_for_testing();

    // Admin freezes merchant
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<merchant::AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::pause_merchant(&admin_cap, &mut account);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Payer tries to fund -- should fail
    scenario.next_tx(payer);
    let account = scenario.take_shared<MerchantAccount>();
    let mut sub = scenario.take_shared<payment::Subscription<TEST_USDC>>();
    let fund_coin = coin::mint_for_testing<TEST_USDC>(5_000_000, scenario.ctx());
    payment::fund_subscription(&account, &mut sub, fund_coin, scenario.ctx());
    test_scenario::return_shared(sub);
    test_scenario::return_shared(account);
    scenario.end();
    // DEFENDED: fund_subscription correctly checks is_paused which includes admin freeze.
}
