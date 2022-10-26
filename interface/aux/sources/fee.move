module aux::fee {

    struct Fee has key {
        maker_rebate_bps: u8,
        taker_fee_bps: u8
    }

    public fun fee_exists(account: address) : bool{
        exists<Fee>(account)
    }
}
