/// Red Team Round 21: Combo Integer + Object — overflow farming_principal via repeated deposits
/// Attack vectors:
/// 1. Accumulate farming_principal close to MAX_U64, then one more deposit → overflow
/// 2. move_to_farming overflow: farming + amount > MAX_U64
#[test_only]
module baleenpay::red_team_round_21_overflow_farming {
    use sui::test_scenario;
    use sui::coin;
    use baleenpay::merchant::{Self, AdminCap, MerchantAccount, MerchantRegistry};
    use baleenpay::router::{Self, StablecoinVault};

    public struct STABLECOIN has drop {}
    const MAX_U64: u64 = 18_446_744_073_709_551_615;
    const HALF_MAX: u64 = 9_223_372_036_854_775_807;

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

    /// ATTACK: Overflow farming_principal by depositing twice near MAX_U64
    /// farming_principal = HALF_MAX + HALF_MAX + 2 = MAX_U64 + 1 → overflow
    #[test]
    #[expected_failure] // arithmetic overflow in move_to_farming (farming + amount wraps)
    fun test_attack_overflow_farming_principal() {
        let admin = @0xAD;
        let merchant_addr = @0xBB;
        let mut scenario = test_scenario::begin(admin);
        setup(&mut scenario, admin);
        register(&mut scenario, merchant_addr);

        // Give merchant MAX_U64 idle (requires overflow-safe add_payment)
        // add_payment has overflow check, so we do it in two parts
        scenario.next_tx(merchant_addr);
        let mut account = scenario.take_shared<MerchantAccount>();
        merchant::add_payment_for_testing(&mut account, HALF_MAX);
        merchant::add_payment_for_testing(&mut account, HALF_MAX);
        // idle = 2 * HALF_MAX = MAX_U64 - 1

        // Move HALF_MAX + 1 to farming
        merchant::move_to_farming_for_testing(&mut account, HALF_MAX + 1);
        // farming = HALF_MAX + 1, idle = HALF_MAX - 1

        // Move remaining HALF_MAX - 1 to farming → farming = MAX_U64
        merchant::move_to_farming_for_testing(&mut account, HALF_MAX - 1);
        // farming = HALF_MAX + 1 + HALF_MAX - 1 = 2 * HALF_MAX = MAX_U64 - 1

        // Now idle = 0. Give more idle and try to overflow farming
        merchant::add_payment_for_testing(&mut account, 2);
        // idle = 2
        merchant::move_to_farming_for_testing(&mut account, 2);
        // farming = MAX_U64 - 1 + 2 = MAX_U64 + 1 → overflow!

        test_scenario::return_shared(account);
        scenario.end();
    }
}
