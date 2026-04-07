#[test_only]
module baleenpay::test_usdc {
    use sui::coin;

    public struct TEST_USDC has drop {}

    fun init(witness: TEST_USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 6, b"USDC", b"Test USDC", b"", option::none(), ctx,
        );
        transfer::public_transfer(treasury_cap, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
