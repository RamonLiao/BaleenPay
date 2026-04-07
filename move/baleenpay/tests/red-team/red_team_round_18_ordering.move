/// Red Team Round 18: Ordering Attack — deposit then immediate take in same epoch
/// Attack vectors:
/// 1. keeper_deposit_to_farm then take_stablecoin in back-to-back txs (same epoch)
/// 2. Merchant withdraws idle while keeper is depositing to farm (concurrent)
/// 3. Double take_stablecoin in rapid succession
#[test_only]
module baleenpay::red_team_round_18_ordering;
use sui::test_scenario;
use sui::coin;
use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantCap, MerchantRegistry};
use baleenpay::router::{Self, Vault, StablecoinVault};

public struct USDC has drop {}
public struct STABLECOIN has drop {}

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

/// ATTACK: Deposit to farm then immediately take_stablecoin in next tx
/// Tests whether there's any time-lock or cooldown protection
#[test]
fun test_attack_instant_deposit_and_redeem() {
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

    // Keeper deposits to farm
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = coin::mint_for_testing<STABLECOIN>(1000, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // IMMEDIATELY: Merchant takes it all back (no cooldown)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 1000, scenario.ctx());
    // This succeeds — no cooldown exists. This is a design decision, not a bug,
    // because the merchant owns the funds. But it does mean flash-redeem is possible.
    assert!(coin.value() == 1000);
    assert!(merchant::get_farming_principal(&account) == 0);
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}

/// ATTACK: merchant_withdraw + take_stablecoin drains more than total received
/// idle=500, farming=500 → withdraw 500 idle + take 500 stablecoin = 1000 total
/// This is LEGITIMATE (merchant recovers all their funds). Verify accounting is clean.
#[test]
fun test_attack_withdraw_plus_redeem_full_drain() {
    let admin = @0xAD;
    let merchant_addr = @0xBB;
    let mut scenario = test_scenario::begin(admin);
    setup(&mut scenario, admin);
    register(&mut scenario, merchant_addr);

    // Setup: 1000 received, 500 stays idle, 500 goes to farming
    scenario.next_tx(merchant_addr);
    let mut account = scenario.take_shared<MerchantAccount>();
    merchant::add_payment_for_testing(&mut account, 1000);
    test_scenario::return_shared(account);

    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    router::create_vault<USDC>(&admin_cap, scenario.ctx());
    router::create_stablecoin_vault<STABLECOIN>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Fund USDC vault for idle withdrawal
    scenario.next_tx(admin);
    let mut vault = scenario.take_shared<Vault<USDC>>();
    let usdc = coin::mint_for_testing<USDC>(500, scenario.ctx());
    router::deposit_to_vault_for_testing(&mut vault, usdc);
    test_scenario::return_shared(vault);

    // Keeper deposits 500 to farm
    scenario.next_tx(admin);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = coin::mint_for_testing<STABLECOIN>(500, scenario.ctx());
    router::keeper_deposit_to_farm(&admin_cap, &mut account, &mut sv, coin);
    assert!(merchant::get_idle_principal(&account) == 500);
    assert!(merchant::get_farming_principal(&account) == 500);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(admin_cap);

    // Merchant withdraws all idle (500 USDC)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut vault = scenario.take_shared<Vault<USDC>>();
    router::merchant_withdraw(&cap, &mut account, &mut vault, 500, scenario.ctx());
    assert!(merchant::get_idle_principal(&account) == 0);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);

    // Merchant redeems all farming (500 stablecoin)
    scenario.next_tx(merchant_addr);
    let cap = scenario.take_from_sender<MerchantCap>();
    let mut account = scenario.take_shared<MerchantAccount>();
    let mut sv = scenario.take_shared<StablecoinVault<STABLECOIN>>();
    let coin = router::take_stablecoin(&cap, &mut account, &mut sv, 500, scenario.ctx());
    assert!(coin.value() == 500);
    assert!(merchant::get_farming_principal(&account) == 0);
    assert!(merchant::get_idle_principal(&account) == 0);
    coin::burn_for_testing(coin);
    test_scenario::return_shared(sv);
    test_scenario::return_shared(account);
    scenario.return_to_sender(cap);
    scenario.end();
}
