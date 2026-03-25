module floatsync::brand_usd {
    use sui::coin;

    public struct BRAND_USD has drop {}

    fun init(witness: BRAND_USD, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            6,
            b"BUSD",
            b"BrandUSD",
            b"FloatSync branded stablecoin backed by USDC",
            option::none(),
            ctx,
        );
        transfer::public_transfer(treasury_cap, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
