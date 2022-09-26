module hippo_aggregator::volume {

    use std::signer;
    use std::vector;
    use std::string::String;
    use std::string;


    const E_NOT_ADMIN: u64 = 1;
    const E_NOT_POSTER: u64 = 2;
    const E_REPEAT_POST: u64 = 3;
    const E_VERCTOR_LENGT_NOT_EQUAL: u64 = 4;

    const VOLUME_HISTORY_LENGTH: u64 = 30;
    const PERIOD_LENGTH_24H: u64 = 24 * 60 * 60;
    const PERIOD_LENGTH_7D: u64 = 7 * 24 * 60 * 60;
    struct TotalVolume has drop, store, copy{
        start_time: u64,
        end_time: u64,
        amount: u64
    }

    struct TradingPair has drop, store, copy{
        coin_x: String,
        coin_y: String,
        amount: u64
    }

    struct PoolProvider has drop, store, copy{
        dex_type: u8,
        amount: u64
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

    public entry fun post(
        poster: &signer,
        amount: u64,
        round_start_time_24h: u64,
        round_start_time_7d: u64,
        new_data_end_time: u64,
        new_data_end_seauence_number: u64,
        trading_pairs_24h_coin_x: vector<vector<u8>>,
        trading_pairs_24h_coin_y: vector<vector<u8>>,
        trading_pairs_24h_amount: vector<u64>,
        trading_pairs_7d_coin_x: vector<vector<u8>>,
        trading_pairs_7d_coin_y: vector<vector<u8>>,
        trading_pairs_7d_amount: vector<u64>,
        pool_provider_24h_dex_type: vector<u8>,
        pool_provider_24h_amount: vector<u64>,
        pool_provider_7d_dex_type: vector<u8>,
        pool_provider_7d_amount: vector<u64>
    ) acquires Volume {
        let volume = borrow_global_mut<Volume>(@hippo_aggregator);
        assert!(signer::address_of(poster) == volume.poster, E_NOT_POSTER);
        assert!(new_data_end_time != volume.data_end_time, E_REPEAT_POST);
        assert!(volume.data_end_sequence_number == 0 || new_data_end_seauence_number != volume.data_end_sequence_number, E_REPEAT_POST);
        assert!(vector::length(&trading_pairs_24h_coin_x) == vector::length(&trading_pairs_24h_coin_y), E_VERCTOR_LENGT_NOT_EQUAL);
        assert!(vector::length(&trading_pairs_24h_coin_x) == vector::length(&trading_pairs_24h_amount), E_VERCTOR_LENGT_NOT_EQUAL);
        assert!(vector::length(&trading_pairs_7d_coin_x) == vector::length(&trading_pairs_7d_coin_y), E_VERCTOR_LENGT_NOT_EQUAL);
        assert!(vector::length(&trading_pairs_7d_coin_x) == vector::length(&trading_pairs_7d_amount), E_VERCTOR_LENGT_NOT_EQUAL);
        assert!(vector::length(&pool_provider_24h_dex_type) == vector::length(&pool_provider_24h_amount), E_VERCTOR_LENGT_NOT_EQUAL);
        assert!(vector::length(&pool_provider_7d_dex_type) == vector::length(&pool_provider_7d_amount), E_VERCTOR_LENGT_NOT_EQUAL);

        volume.data_end_time = new_data_end_time;
        volume.data_end_sequence_number = new_data_end_seauence_number;

        add_volume(&mut volume.total_volume_history_24h, round_start_time_24h, new_data_end_time, amount);
        add_volume(&mut volume.total_volume_history_7d, round_start_time_7d, new_data_end_time, amount);

        volume.top_trading_pairs_24h = parse_trading_pairs_vector(&trading_pairs_24h_coin_x, &trading_pairs_24h_coin_y, &trading_pairs_24h_amount);
        volume.top_trading_pairs_7d = parse_trading_pairs_vector(&trading_pairs_7d_coin_x, &trading_pairs_7d_coin_y, &trading_pairs_7d_amount);
        volume.top_pool_provider_24h = parse_pool_provider_vector(&pool_provider_24h_dex_type, &pool_provider_24h_amount);
        volume.top_pool_provider_7d = parse_pool_provider_vector(&pool_provider_7d_dex_type, &pool_provider_7d_amount);
    }
    #[cmd]
    public entry fun clean(poster: &signer) acquires Volume{
        let volume = borrow_global_mut<Volume>(@hippo_aggregator);
        assert!(signer::address_of(poster) == volume.poster, E_NOT_POSTER);
        volume.data_end_sequence_number = 0;
        volume.data_end_time = 0;
        volume.total_volume_history_24h = vector::empty();
        volume.total_volume_history_7d = vector::empty();
        volume.top_trading_pairs_24h = vector::empty();
        volume.top_trading_pairs_7d = vector::empty();
        volume.top_pool_provider_24h = vector::empty();
        volume.top_pool_provider_7d = vector::empty();
    }

    fun parse_trading_pairs_vector(
        coin_x_vector: &vector<vector<u8>>,
        coin_y_vector: &vector<vector<u8>>,
        amount_vector: &vector<u64>,
    ):vector<TradingPair>{
        let trading_pairs = vector::empty<TradingPair>();
        let i = 0;
        while (i < vector::length(coin_x_vector)){
            vector::push_back(&mut trading_pairs, TradingPair{
                coin_x: string::utf8(*vector::borrow(coin_x_vector, i)),
                coin_y: string::utf8(*vector::borrow(coin_y_vector, i)),
                amount:  *vector::borrow(amount_vector, i)
            });
            i = i+1;
        };
        trading_pairs
    }
    fun parse_pool_provider_vector(
        dex_type_vector: &vector<u8>,
        amount_vector: &vector<u64>,
    ):vector<PoolProvider>{
        let pool_provider = vector::empty<PoolProvider>();
        let i = 0;
        while (i < vector::length(dex_type_vector)){
            vector::push_back(&mut pool_provider, PoolProvider{
                dex_type: *vector::borrow(dex_type_vector, i),
                amount: *vector::borrow(amount_vector, i)
            });
            i = i+1;
        };
        pool_provider
    }
    fun add_volume(total_volume_array: &mut vector<TotalVolume>, round_start_time: u64, data_end_time: u64, amount: u64){
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
        if (total_volume.start_time == round_start_time){
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

}
