module hippo_aggregator::devnet {
    use coin_list::devnet_coins::{DevnetBTC as BTC, DevnetUSDC as USDC, mint_to_wallet};
    use std::signer::address_of;
    use std::string::utf8;
    use aptos_framework::aptos_coin::AptosCoin;

    const BTC_AMOUNT: u64 = 100000000 * 1000;
    const USDC_AMOUNT: u64 = 100000000 * 1000 * 10000;

    struct PontemLP<phantom X, phantom Y> {}

    #[cmd(desc=b"Create BTC-USDC pool on pontem and add liquidity")]
    public entry fun mock_deploy_pontem(admin: signer) {
        use pontem::scripts;
        mint_to_wallet<BTC>(&admin, BTC_AMOUNT);
        mint_to_wallet<USDC>(&admin, USDC_AMOUNT);
        scripts::register_pool_and_add_liquidity<BTC, USDC, PontemLP<BTC, USDC>>(
            &admin,
            2, // uncorrelated,
            BTC_AMOUNT,
            0,
            USDC_AMOUNT,
            0
        )
    }

    #[cmd(desc=b"Create BTC-USDC pool on econia and add liquidity")]
    public entry fun mock_deploy_econia(admin: signer, market_id: u64) {
        use econia::market;
        use econia::user;
        let lot_size: u64 = 1000;
        let tick_size: u64 = 1000;
        market::register_market_pure_coin<BTC, USDC>(&admin, lot_size, tick_size);
        user::register_market_account<BTC, USDC>(&admin, market_id, 0);
        mint_to_wallet<BTC>(&admin, BTC_AMOUNT);
        mint_to_wallet<USDC>(&admin, USDC_AMOUNT);
        user::deposit_from_coinstore<BTC>(&admin, market_id, 0, BTC_AMOUNT);
        user::deposit_from_coinstore<USDC>(&admin, market_id, 0, USDC_AMOUNT);
        market::place_limit_order_user<BTC, USDC>(&admin, address_of(&admin), market_id, true, BTC_AMOUNT / lot_size, 10001 * (lot_size / tick_size), true, false, false);
        market::place_limit_order_user<BTC, USDC>(&admin, address_of(&admin), market_id, false, BTC_AMOUNT / lot_size, 10000 * (lot_size / tick_size), true, false, false);
    }

    #[cmd(desc=b"Create BTC-USDC pool on econia and add liquidity")]
    public entry fun mock_deploy_basiq(admin: &signer) {
        use basiq::dex;
        mint_to_wallet<BTC>(admin, BTC_AMOUNT);
        mint_to_wallet<USDC>(admin, USDC_AMOUNT);
        dex::admin_create_pool<BTC, USDC>(
            admin,
            USDC_AMOUNT / BTC_AMOUNT * 1000000,
            1 * 1000000,
            utf8(b"BTC-USDC LP"),
            utf8(b"BTC-USDC"),
            true,
        );
        dex::add_liquidity_entry<BTC, USDC>(admin, BTC_AMOUNT, USDC_AMOUNT);
    }

    public entry fun registe_coins(hippo_swap: &signer, coin_list: &signer, deploy_coin_list:bool){
        let _hippo_swap = hippo_swap;
        let _coin_list = coin_list;
        let _deploy_coin_list = deploy_coin_list;
    }

    #[cmd(desc=b"Registe coin to coin list")]
    public entry fun registe_coins_to_coin_list(coin_list: &signer) {
        use coin_list::coin_list;
        use ditto::staked_coin as dotti_staked_coin;
        use tortuga::staked_aptos_coin as tortuga_staked_coin;

        coin_list::add_to_registry_by_admin<AptosCoin>(
            coin_list,
            utf8(b"Aptos Coin"),
            utf8(b"APT"),
            utf8(b"aptos"),
            utf8(b"https://assets.coingecko.com/coins/images/26455/small/Aptos_mark_BLK.png?1658118095"),
            utf8(b"https://aptoslabs.com/"),
            false
        );

        coin_list::add_to_registry_by_admin<dotti_staked_coin::StakedAptos>(
            coin_list,
            utf8(b"Ditto Staked Aptos"),
            utf8(b"stAPT"),
            utf8(b""),
            utf8(b""),
            utf8(b"https://www.dittofinance.io/"),
            false
        );

        coin_list::add_to_registry_by_admin<tortuga_staked_coin::StakedAptosCoin>(
            coin_list,
            utf8(b"StakedAptosCoin"),
            utf8(b"tAPT"),
            utf8(b""),
            utf8(b""),
            utf8(b"https://www.dittofinance.io/"),
            false
        );

    }

    #[cmd(desc=b"Registe coin to coin list")]
    public entry fun add_to_list_to_coin_list(hippo_swap: &signer){
        use coin_list::coin_list;
        use ditto::staked_coin as dotti_staked_coin;
        use tortuga::staked_aptos_coin as tortuga_staked_coin;

        coin_list::add_to_list<AptosCoin>(hippo_swap);
        coin_list::add_to_list<dotti_staked_coin::StakedAptos>(hippo_swap);
        coin_list::add_to_list<tortuga_staked_coin::StakedAptosCoin>(hippo_swap);
    }
}
