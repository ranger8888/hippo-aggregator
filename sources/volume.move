module hippo_aggregator::volume {

    use std::signer;
    use std::vector;
    use aptos_std::type_info::{TypeInfo};


    const E_NOT_ADMIN: u64 = 1;
    const E_NOT_POSTER: u64 = 2;
    const E_REPEAT_POST: u64 = 3;

    const VOLUME_HISTORY_LENGTH: u64 = 30;
    const PERIOD_LENGTH_24H: u64 = 24 * 60 * 60;
    const PERIOD_LENGTH_7D: u64 = 7 * 24 * 60 * 60;
    struct TotalVolume has drop, store, copy{
        start_time: u64,
        end_time: u64,
        amount: u64
    }

    struct TradingPair has drop, store, copy{
        x_type_info: TypeInfo,
        y_type_info: TypeInfo,
        amount:u64
    }

    struct PoolProvider has drop, store, copy{
        dex_type: u8,
        amount: u8
    }
    struct Volume has key, copy{
        poster: address,
        // sequence number of data end
        data_end_sequence_number: u64,
        // time of data end
        data_end_time: u64,
        volume_decimals: u64,
        total_volume_history_24h:vector<TotalVolume>,
        total_volume_history_7d:vector<TotalVolume>,
        top_trading_pairs_24h:vector<TradingPair>,
        top_trading_pairs_7d:vector<TradingPair>,
        top_pool_provider_24h:vector<PoolProvider>,
        top_pool_provider_7d:vector<PoolProvider>,
    }


    #[cmd]
    public entry fun initialize(admin: &signer, poster: address){
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @hippo_aggregator, E_NOT_ADMIN);
        move_to(admin, Volume{
            poster,
            data_end_sequence_number: 0,
            data_end_time: 0,
            volume_decimals: 4,
            total_volume_history_24h:vector::empty(),
            total_volume_history_7d:vector::empty(),
            top_trading_pairs_24h:vector::empty(),
            top_trading_pairs_7d:vector::empty(),
            top_pool_provider_24h:vector::empty(),
            top_pool_provider_7d:vector::empty()
        })
    }

    #[cmd]
    public entry fun set_poster(admin: &signer, new_poster: address) acquires Volume {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @hippo_aggregator, E_NOT_ADMIN);
        let volume = borrow_global_mut<Volume>(admin_addr);
        volume.poster = new_poster
    }
    
    // the amount can not include next period value
    public entry fun post(
        poster: &signer,
        amount: u64,
        round_start_time_24h: u64,
        round_start_time_7d: u64,
        new_data_end_time: u64,
        new_data_end_seauence_number: u64,
        trading_pairs_24h: &vector<TradingPair>,
        trading_pairs_7d: &vector<TradingPair>,
        pool_provider_24h: &vector<PoolProvider>,
        pool_provider_7d: &vector<PoolProvider>
    ) acquires Volume {
        let volume = borrow_global_mut<Volume>(@hippo_aggregator);
        assert!(signer::address_of(poster) == volume.poster, E_NOT_POSTER);
        assert!(new_data_end_time != volume.data_end_time, E_REPEAT_POST);
        assert!(new_data_end_seauence_number != volume.data_end_sequence_number, E_REPEAT_POST);

        add_volume(&mut volume.total_volume_history_24h, round_start_time_24h, new_data_end_time, PERIOD_LENGTH_24H, amount);
        add_volume(&mut volume.total_volume_history_7d, round_start_time_7d, new_data_end_time, PERIOD_LENGTH_7D, amount);

        volume.data_end_sequence_number = new_data_end_seauence_number;
        volume.data_end_time = new_data_end_time;

        volume.top_trading_pairs_24h = *trading_pairs_24h;
        volume.top_trading_pairs_7d = *trading_pairs_7d;
        volume.top_pool_provider_24h = *pool_provider_24h;
        volume.top_pool_provider_7d = *pool_provider_7d;
    }

    fun add_volume(total_volume_array: &mut vector<TotalVolume>, round_start_time: u64, data_end_time: u64, peroid_length: u64, amount: u64){
        let array_length = vector::length(total_volume_array);
        if (array_length == 0){
            vector::push_back(total_volume_array,TotalVolume{
                start_time: round_start_time,
                end_time: data_end_time,
                amount
            });
            return
        };
        let total_volume = vector::borrow_mut(total_volume_array, array_length-1);
        if (total_volume.start_time == round_start_time || total_volume.start_time+peroid_length <= data_end_time){
            total_volume.amount = total_volume.amount + amount
        } else {
            vector::push_back(total_volume_array,TotalVolume{
                start_time: round_start_time,
                end_time: data_end_time,
                amount
            })
        };
        if (array_length > VOLUME_HISTORY_LENGTH){
            vector::remove(total_volume_array,0);
        };
    }

    public entry fun get_volume():Volume acquires Volume{
        *borrow_global<Volume>(@hippo_aggregator)
    }

    #[query]
    public entry fun fetch_volume(fetcher: &signer) acquires Volume{
        move_to(fetcher,get_volume())
    }


    #[only_test]
    use aptos_std::type_info::{type_of};
    #[only_test]
    use aptos_framework::coin::Coin;
    #[only_test]
    public fun newTradingPair<X, Y>(amount: u64) : TradingPair{
        TradingPair{
            x_type_info:type_of<Coin<X>>(),
            y_type_info:type_of<Coin<Y>>(),
            amount,
        }
    }
}
