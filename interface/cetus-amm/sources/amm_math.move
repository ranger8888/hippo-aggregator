module cetus_amm::amm_math {
    use cetus_amm::u256;
    use cetus_amm::u256::U256;
    use std::error;
    const EDIVIDE_BY_ZERO: u64 = 2001;

    public fun safe_mul_div_u128(x: u128, y: u128, z: u128): u128 {
        u256::as_u128(mul_div_u128(x, y, z))
    }

    public fun mul_div_u128(x: u128, y: u128, z: u128): U256 {
        if (z == 0) {
            abort error::aborted(EDIVIDE_BY_ZERO)
        };

        let x_u256 = u256::from_u128(x);
        let y_u256 = u256::from_u128(y);
        let z_u256 = u256::from_u128(z);
        u256::div(u256::mul(x_u256, y_u256), z_u256)
    }


}
