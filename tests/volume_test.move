#[test_only]
module hippo_aggregator::volume_test {

    use hippo_aggregator::volume;
    use std::signer;
    use std::vector;
    use hippo_aggregator::volume::{TradingPair, PoolProvider};
    use coin_list::devnet_coins::{DevnetUSDC, DevnetBTC};

    fun initialize(admin: &signer, poster: &signer){
        volume::initialize(admin, signer::address_of(poster))
    }
    #[test(
        admin = @hippo_aggregator,
        poster = @poster
    )]
    fun test_initialize(admin: &signer, poster: &signer){
        initialize(admin, poster)
    }

    #[test(
        admin = @hippo_aggregator,
        poster = @poster,
        new_poster = @0x3
    )]
    fun test_set_poster(admin: &signer, poster: &signer, new_poster: &signer){
        initialize(admin, poster);
        volume::set_poster(admin, signer::address_of(new_poster))
    }
    fun post(poster: &signer){
        let top_trading_pair = vector::empty<TradingPair>();
        vector::push_back(&mut top_trading_pair, volume::newTradingPair<DevnetUSDC, DevnetBTC>(10));
        volume::post(
            poster,
            100,
            20000,
            10000,
            20000 + 60*60*1,
            100,
            &top_trading_pair,
            &top_trading_pair,
            &vector::empty<PoolProvider>(),
            &vector::empty<PoolProvider>()
        );
        volume::post(
            poster,
            120,
            20000,
            10000,
            20000 + 60*60*2,
            120,
            &top_trading_pair,
            &top_trading_pair,
            &vector::empty<PoolProvider>(),
            &vector::empty<PoolProvider>()
        );
        volume::post(
            poster,
            150,
            21000,
            10000,
            21000 + 60*60,
            140,
            &top_trading_pair,
            &top_trading_pair,
            &vector::empty<PoolProvider>(),
            &vector::empty<PoolProvider>()
        )
    }

    #[test(
        admin = @hippo_aggregator,
        poster = @poster
    )]
    fun test_post(admin: &signer, poster: &signer){
        initialize(admin, poster);
        post(poster)
    }
    #[test(
        admin = @hippo_aggregator,
        poster = @poster,
        poster_2 = @poster_2
    )]
    #[expected_failure(abort_code = 2)]
    fun test_post_fail(admin: &signer, poster: &signer, poster_2: &signer){
        initialize(admin, poster);
        post(poster_2)
    }


}
