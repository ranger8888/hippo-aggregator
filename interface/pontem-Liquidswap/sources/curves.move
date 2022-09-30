/// Marker structures to use in LiquidityPool third generic.
module Liquidswap::curves {

    const ERR_INVALID_CURVE: u64 = 10001;

    /// For pairs like BTC, Aptos, ETH.
    struct Uncorrelated {}

    /// For stablecoins like USDC, USDT.
    struct Stable {}
}
