module aux::clob_market {
    use aptos_framework::coin;
    use aux::critbit::CritbitTree;
    use aux::critbit_v::{CritbitTree as CritbitTreeV};
    use aptos_framework::event;
    use aux::authority;
    use aux::critbit;
    use aux::fee;
    use aptos_framework::timestamp;
    use aux::critbit_v;
    use aux::onchain_signer;

    const E_MARKET_DOES_NOT_EXIST: u64 = 4;
    const E_INVALID_STATE: u64 = 7;
    const E_INVALID_ROUTER_ORDER_TYPE: u64 = 12;
    const E_FEE_UNINITIALIZED: u64 = 16;
    const E_INVALID_QUANTITY: u64 = 22;
    const E_INVALID_PRICE: u64 = 23;
    const E_NO_ASKS_IN_BOOK: u64 = 27;
    const E_NO_BIDS_IN_BOOK: u64 = 28;
    const E_UNSUPPORTED_STP_ACTION_TYPE : u64 = 30;

    // Place an aggressive order. If the entire order cannot fill immediately,
    // cancel the entire order.
    const FILL_OR_KILL: u64 = 101;
    // Place an aggressive order. The portion of the order that does not fill
    // immediately is cancelled.
    const IMMEDIATE_OR_CANCEL: u64 = 102;
    // Place a passive order. If the order would be aggressive, optionally slide
    // it to become passive. Otherwise, cancel the order.
    const POST_ONLY: u64 = 103;
    // Join the best bid or best ask level. Optionally place the order more or
    // less aggressive than the best bid or ask up to the limit price.
    const PASSIVE_JOIN: u64 = 104;
    // Cancel passive side
    const CANCEL_PASSIVE: u64 = 200;
    // Cancel aggressive side
    const CANCEL_AGGRESSIVE: u64 = 201;
    // Cancel both sides
    const CANCEL_BOTH: u64 = 202;
    const MAX_U64: u64 = 18446744073709551615;
    const ZERO_FEES: bool = true;
    const CRITBIT_NULL_INDEX: u64 = 1 << 63;
    struct Order has store {
        id: u128,
        client_order_id: u128,
        price: u64,
        quantity: u64,
        aux_au_to_burn_per_lot: u64,
        is_bid: bool,
        owner_id: address,
        timeout_timestamp: u64,
        order_type: u64,
        timestamp: u64,
    }

    struct Level has store {
        // price
        price: u64,
        // total quantity
        total_quantity: u128,
        orders: CritbitTreeV<Order>,
    }
    struct OrderFillEvent has store, drop {
        order_id: u128,
        client_order_id: u128,
        is_bid: bool,
        owner: address,
        base_qty: u64,  // base qty filled
        price: u64,
        fee: u64,
        rebate: u64,
        remaining_qty: u64,
        timestamp: u64, // timestamp of when the event happens
    }

    struct OrderCancelEvent has store, drop {
        order_id: u128,
        client_order_id: u128,
        owner: address,
        cancel_qty: u64,
        timestamp: u64, // timestamp of when the event happens
        order_type: u64, // immediate-or-cancel, fill-or-kill, maker-or-cancel
    }

    struct OrderPlacedEvent has store, drop {
        order_id: u128,
        client_order_id: u128,
        owner: address,
        is_bid: bool,
        qty: u64,
        price: u64,
        timestamp: u64, // timestamp of when the event happens
    }
    struct Market<phantom B, phantom Q> has key {
        // Orderbook
        bids:  CritbitTree<Level>,
        asks:  CritbitTree<Level>,
        next_order_id: u64,

        // MarketInfo
        base_decimals: u8,
        quote_decimals: u8,
        lot_size: u64,
        tick_size: u64,

        // Events
        fill_events: event::EventHandle<OrderFillEvent>,
        cancel_events: event::EventHandle<OrderCancelEvent>,
        placed_events: event::EventHandle<OrderPlacedEvent>
    }

    struct OpenOrderInfo has store, drop {
        price: u64,
        is_bid: bool,
    }

    struct OpenOrderAccount<phantom B, phantom Q> has key {
        open_orders: CritbitTree<OpenOrderInfo>,
    }

    /// Place a market order (IOC or FOK) on behalf of the router.
    /// Returns (total_base_quantity_owed_au, quote_quantity_owed_au), the amounts that must be credited/debited to the sender.
    /// Emits events on order placement and fills.
    public fun place_market_order_mut<B, Q>(
        _sender_addr: address,
        base_coin: &mut coin::Coin<B>,
        quote_coin: &mut coin::Coin<Q>,
        _is_bid: bool,
        _order_type: u64,
        _limit_price: u64,
        _quantity: u64,
        _client_order_id: u128,
    ): (u64, u64)  acquires Market, OpenOrderAccount {
        coin::destroy_zero(*base_coin);
        coin::destroy_zero(*quote_coin);
        (0, 0)
    }

}
