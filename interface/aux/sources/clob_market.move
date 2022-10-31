module aux::clob_market {
    use aptos_framework::coin;
    use aux::critbit::CritbitTree;
    use aux::critbit_v::CritbitTree as CritbitTreeV;
    use aptos_framework::event;
    use aux::authority;
    use aux::fee;
    use aptos_framework::timestamp;
    use aux::critbit;
    use aux::critbit_v;
    use aux::onchain_signer;
    use aux::vault;
    use aux::aux_coin::AuxCoin;
    use aux::volume_tracker;
    use aux::util;

    // Config
    const CANCEL_EXPIRATION_TIME: u64 = 100000000; // 100 s
    const MAX_U64: u64 = 18446744073709551615;
    const CRITBIT_NULL_INDEX: u64 = 1 << 63;
    const ZERO_FEES: bool = true;

    //////////////////////////////////////////////////////////////////
    // !!! CONSTANTS !!! Keep in sync clob.move, clob_market.move, router.move
    // Order type

    // Place an order in the order book. The portion of the order that matches
    // against passive orders on the opposite side of the book becomes
    // aggressive. The remainder is passive.
    const LIMIT_ORDER: u64 = 100;

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

    // Self-trading prevention (STP) action type
    // This order agrees on the specification that when a self-trading occur, cancel the passive one (the maker order)

    // Cancel passive side
    const CANCEL_PASSIVE: u64 = 200;
    // Cancel aggressive side
    const CANCEL_AGGRESSIVE: u64 = 201;
    // Cancel both sides
    const CANCEL_BOTH: u64 = 202;

    // Order Event Types
    const ORDER_FILL_EVENT: u64 = 1;
    const ORDER_CANCEL_EVENT: u64 = 2;
    const ORDER_PLACED_EVENT: u64 = 3;

    // end !!! CONSTANTS !!! Keep in sync clob.move, clob_market.move, router.move
    //////////////////////////////////////////////////////////////////


    /**********/
    /* ERRORS */
    /**********/
    const E_ONLY_MODULE_PUBLISHER_CAN_CREATE_MARKET: u64 = 1;
    const E_MARKET_ALREADY_EXISTS: u64 = 2;
    const E_MISSING_AUX_USER_ACCOUNT: u64 = 3;
    const E_MARKET_DOES_NOT_EXIST: u64 = 4;
    const E_INSUFFICIENT_BALANCE: u64 = 5;
    const E_INSUFFICIENT_AUX_BALANCE: u64 = 6;
    const E_INVALID_STATE: u64 = 7;
    const E_TEST_FAILURE: u64 = 8;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 9;
    const E_UNABLE_TO_FILL_MARKET_ORDER: u64 = 10;
    const E_UNREACHABLE: u64 = 11;
    const E_INVALID_ROUTER_ORDER_TYPE: u64 = 12;
    const E_USER_FEE_NOT_INITIALIZED: u64 = 13;
    const E_UNSUPPORTED: u64 = 14;
    const E_VOLUME_TRACKER_UNREGISTERED: u64 = 15;
    const E_FEE_UNINITIALIZED: u64 = 16;
    const E_ORDER_NOT_FOUND: u64 = 17;
    const E_UNIMPLEMENTED_ERROR: u64 = 18;
    const E_FAILED_INVARIANT: u64 = 19;
    const E_INVALID_ARGUMENT: u64 = 20;
    const E_INVALID_ORDER_ID: u64 = 21;
    const E_INVALID_QUANTITY: u64 = 22;
    const E_INVALID_PRICE: u64 = 23;
    const E_NOT_ORDER_OWNER: u64 = 24;
    const E_INVALID_QUOTE_QUANTITY: u64 = 25;
    const E_INVALID_TICK_OR_LOT_SIZE: u64 = 26;
    const E_NO_ASKS_IN_BOOK: u64 = 27;
    const E_NO_BIDS_IN_BOOK: u64 = 28;
    const E_SLIDE_TO_ZERO_PRICE: u64 = 29;
    const E_UNSUPPORTED_STP_ACTION_TYPE : u64 = 30;
    const E_CANCEL_WRONG_ORDER: u64 = 31;
    const E_LEVEL_SHOULD_NOT_EMPTY: u64 = 32;
    const E_LEVEL_NOT_EMPTY: u64 = 33;
    const E_ORDER_NOT_IN_OPEN_ORDER_ACCOUNT: u64 = 34;
    const E_NO_OPEN_ORDERS_ACCOUNT: u64 = 35;
    const E_UNAUTHORIZED_FOR_MARKET_UPDATE: u64 = 36;
    const E_UNAUTHORIZED_FOR_MARKET_CREATION: u64 = 37;
    const E_MARKET_NOT_UPDATING: u64 = 38;

    /// Place a market order (IOC or FOK) on behalf of the router.
    /// Returns (total_base_quantity_owed_au, quote_quantity_owed_au), the amounts that must be credited/debited to the sender.
    /// Emits events on order placement and fills.
    public fun place_market_order_mut<B, Q>(
        sender_addr: address,
        base_coin: &mut coin::Coin<B>,
        quote_coin: &mut coin::Coin<Q>,
        is_bid: bool,
        order_type: u64,
        limit_price: u64,
        quantity: u64,
        client_order_id: u128,
    ): (u64, u64)  acquires Market, OpenOrderAccount {

        // Confirm that market exists
        let resource_addr = @aux;
        assert!(market_exists<B, Q>(),E_MARKET_DOES_NOT_EXIST);
        let market = borrow_global_mut<Market<B, Q>>(resource_addr);

        // The router may only place FOK or IOC orders
        assert!(order_type == FILL_OR_KILL || order_type == IMMEDIATE_OR_CANCEL, E_INVALID_ROUTER_ORDER_TYPE);

        // round quantity down (router may submit un-quantized quantities)
        let lot_size = market.lot_size;
        let tick_size = market.lot_size;
        let rounded_quantity = quantity / lot_size * lot_size;
        let rounded_price = limit_price / tick_size * tick_size;

        let (base_au, quote_au) = new_order<B, Q>(
            market,
            sender_addr,
            is_bid,
            rounded_price,
            rounded_quantity,
            0,
            order_type,
            client_order_id,
            0,
            false,
            MAX_U64,
            CANCEL_AGGRESSIVE,
        );

        // Transfer coins
        let vault_addr = @aux;
        let module_signer = &authority::get_signer_self();
        if (base_au != 0 && quote_au != 0) {
            if (is_bid) {
                // taker pays quote, receives base
                let quote = coin::extract<Q>(quote_coin, (quote_au as u64));
                if (!coin::is_account_registered<Q>(@aux)) {
                    coin::register<Q>(module_signer);
                };
                coin::deposit<Q>(vault_addr, quote);
                let base = coin::withdraw<B>(module_signer, (base_au as u64));
                coin::merge<B>(base_coin, base);
            } else {
                // taker receives quote, pays base
                let base = coin::extract<B>(base_coin, (base_au as u64));
                if (!coin::is_account_registered<B>(@aux)) {
                    coin::register<B>(module_signer);
                };
                coin::deposit<B>(vault_addr, base);
                let quote = coin::withdraw<Q>(module_signer, (quote_au as u64));
                coin::merge<Q>(quote_coin, quote);

            }
        } else if (base_au != 0 || quote_au != 0) {
            // abort if sender paid but did not receive and vice versa
            abort(E_INVALID_STATE)
        };
        (base_au, quote_au)
    }

    /// Attempts to place a new order and returns resulting events
    /// ticks_to_slide is only used for post only order and passively join order
    /// direction_aggressive is only used for passively join order
    /// Returns (base_quantity_filled, quote_quantity_filled)
    fun new_order<B, Q>(
        market: &mut Market<B, Q>,
        order_owner: address,
        is_bid: bool,
        limit_price: u64,
        quantity: u64,
        aux_au_to_burn_per_lot: u64,
        order_type: u64,
        client_order_id: u128,
        ticks_to_slide: u64,
        direction_aggressive: bool,
        timeout_timestamp: u64,
        stp_action_type: u64,
    ): (u64, u64) acquires OpenOrderAccount {
        // Confirm the order_owner has fee published
        if (!ZERO_FEES) {
            assert!(fee::fee_exists(order_owner), E_FEE_UNINITIALIZED);
        };
        // Check lot sizes
        let tick_size = market.tick_size;
        let lot_size = market.lot_size;

        if (quantity % lot_size != 0) {
            abort(E_INVALID_QUANTITY)
        } else if (limit_price % tick_size != 0) {
            abort(E_INVALID_PRICE)
        };
        let timestamp = timestamp::now_microseconds();
        let order_id = generate_order_id(market, aux_au_to_burn_per_lot);

        let order = Order{
            id: order_id,
            client_order_id,
            price: limit_price,
            quantity,
            aux_au_to_burn_per_lot,
            is_bid,
            owner_id: order_owner,
            timeout_timestamp,
            order_type,
            timestamp,
        };

        if (order_type == FILL_OR_KILL) {
            let filled = 0u64;
            let side = if (is_bid) { &mut market.asks } else { &mut market.bids };
            if (critbit::size(side) == 0) {
                // Just emit the event
                event::emit_event<OrderCancelEvent>(
                    &mut market.cancel_events,
                    OrderCancelEvent {
                        order_id,
                        owner: order.owner_id,
                        cancel_qty: order.quantity,
                        timestamp,
                        client_order_id: client_order_id, // this is same given the invariant
                        order_type: order_type, // this is same given the invariant
                    }
                );
                destroy_order(order);
                return (0,0)
            };

            let idx = if (is_bid) { critbit::get_min_index(side) } else { critbit::get_max_index(side) };

            while(idx != CRITBIT_NULL_INDEX && filled < quantity) {
                let (_, level) = critbit::borrow_at_index(side, idx);
                let can_fill = (is_bid && level.price <= limit_price) || (!is_bid && level.price >= limit_price);
                if (can_fill) {
                    // now walk the book.
                    // since some orders have already expired, we need to check the orders one by one.
                    let order_idx = critbit_v::get_min_index(&level.orders);
                    while (order_idx != CRITBIT_NULL_INDEX && filled < quantity) {
                        let (_, passive_order) = critbit_v::borrow_at_index(&level.orders, order_idx);
                        if (passive_order.owner_id == order_owner) {
                            if (stp_action_type == CANCEL_AGGRESSIVE) {
                                // Just emit the event
                                event::emit_event<OrderCancelEvent>(
                                    &mut market.cancel_events,
                                    OrderCancelEvent {
                                        order_id,
                                        owner: order.owner_id,
                                        cancel_qty: order.quantity,
                                        timestamp,
                                        client_order_id: client_order_id, // this is same given the invariant
                                        order_type: order_type, // this is same given the invariant
                                    }
                                );
                                destroy_order(order);
                                return (0,0)
                            } else if (stp_action_type == CANCEL_BOTH) {
                                let (_, level) = critbit::borrow_at_index_mut(side, idx);
                                let (_, cancelled) = critbit_v::remove(&mut level.orders, order_idx);
                                level.total_quantity = level.total_quantity - (cancelled.quantity as u128);
                                process_cancel_order<B, Q>(cancelled, timestamp, (lot_size as u128), &mut market.cancel_events);
                                // Just emit the event
                                event::emit_event<OrderCancelEvent>(
                                    &mut market.cancel_events,
                                    OrderCancelEvent {
                                        order_id,
                                        owner: order.owner_id,
                                        cancel_qty: order.quantity,
                                        timestamp,
                                        client_order_id: client_order_id, // this is same given the invariant
                                        order_type: order_type, // this is same given the invariant
                                    }
                                );
                                destroy_order(order);
                                return (0,0)
                            };
                        };
                        if (passive_order.timeout_timestamp >= timestamp) {
                            let remaining = quantity - filled;
                            if (remaining < passive_order.quantity) {
                                filled = quantity;
                            } else {
                                filled = filled + passive_order.quantity;
                            };
                        };
                        order_idx = critbit_v::next_in_order(&level.orders, order_idx);
                    };
                    idx = if (is_bid) {
                        critbit::next_in_order(side, idx)
                    } else {
                        critbit::next_in_reverse_order(side, idx)
                    };
                } else {
                    break
                }
            };

            if (filled < quantity) {
                // Just emit the event
                event::emit_event<OrderCancelEvent>(
                    &mut market.cancel_events,
                    OrderCancelEvent {
                        order_id,
                        owner: order.owner_id,
                        cancel_qty: order.quantity,
                        timestamp,
                        client_order_id: client_order_id, // this is same given the invariant
                        order_type: order_type, // this is same given the invariant
                    }
                );
                destroy_order(order);
                return (0,0)
            }
        };
        // Check for orders that should be cancelled immediately
        if (
            // order timed out
            timeout_timestamp <= timestamp
                // If the order is passive join, it will use ticks_to_slide and market to determine join price, and if join_price is not worse than limit_price, place the order, otherwise cancel
                || (order_type == PASSIVE_JOIN
                && order_price_worse_than_limit(market, &mut order, ticks_to_slide, direction_aggressive))
                // If the order is a moc order and any amount can be filled, the order won't touch the market and immediately "cancelled" like a no-op
                || (order_type == POST_ONLY
                && order_will_fill<B, Q>(market, &mut order, ticks_to_slide))
        ) {
            // Just emit the event
            event::emit_event<OrderCancelEvent>(
                &mut market.cancel_events,
                OrderCancelEvent {
                    order_id,
                    owner: order.owner_id,
                    cancel_qty: order.quantity,
                    timestamp,
                    client_order_id: client_order_id, // this is same given the invariant
                    order_type: order_type, // this is same given the invariant
                }
            );
            destroy_order(order);
            // return base quantity filled, quote quantity filled
            return (0, 0)
        };

        // Check for matches
        let (base_qty_filled, quote_qty_filled) = match(market, &mut order, timestamp, stp_action_type);
        // Check for remaining order quantity
        if (order.quantity > 0) {
            assert!(order_type != FILL_OR_KILL, E_INVALID_STATE);
            if (order_type == IMMEDIATE_OR_CANCEL) {
                event::emit_event<OrderCancelEvent>(
                    &mut market.cancel_events,
                    OrderCancelEvent {
                        order_id,
                        owner: order.owner_id,
                        cancel_qty: order.quantity,
                        timestamp,
                        client_order_id: client_order_id, // this is same given the invariant
                        order_type: order_type, // this is same given the invariant
                    }
                );
                destroy_order(order);
            } else {
                handle_placed_order(market, &order, order_owner);
                insert_order(market, order);
            }
        } else {
            destroy_order(order);
        };
        (base_qty_filled, quote_qty_filled)
    }

    fun insert_order<B, Q>(market: &mut Market<B, Q>, order: Order) {
        let side = if (order.is_bid) { &mut market.bids } else { &mut market.asks };
        let price = (order.price as u128);
        let level_idx = critbit::find(side, price);
        if (level_idx == CRITBIT_NULL_INDEX) {
            let level = Level {
                orders: critbit_v::new(),
                total_quantity: (order.quantity as u128),
                price: order.price,
            };
            critbit_v::insert(&mut level.orders, order.id, order);
            critbit::insert(side, price, level);
        } else {
            let (_, level) = critbit::borrow_at_index_mut(side, level_idx);
            level.total_quantity = level.total_quantity + (order.quantity as u128);
            critbit_v::insert(&mut level.orders, order.id, order);
        }
    }

    fun generate_order_id<B, Q>(market: &mut Market<B, Q>, aux_au_to_burn_per_lot: u64): u128 {
        let aux_to_burn = ((MAX_U64 - aux_au_to_burn_per_lot) as u128);
        aux_to_burn = aux_to_burn << 64;
        let order_id = aux_to_burn + (market.next_order_id as u128);
        market.next_order_id = market.next_order_id + 1;
        order_id
    }
    fun handle_placed_order<B, Q>(market: &mut Market<B, Q>, order: &Order, vault_account_owner: address) acquires OpenOrderAccount {
        let timestamp = timestamp::now_microseconds();
        let placed_order_id = order.id;
        let lot_size = (market.lot_size as u128);

        let placed_order_owner = order.owner_id;
        assert!(placed_order_owner == vault_account_owner, E_INVALID_STATE);

        let qty = order.quantity;
        let price = order.price;
        let placed_quote_qty = quote_qty<B>(price, qty);

        if (order.is_bid) {
            vault::decrease_available_balance<Q>(vault_account_owner, (placed_quote_qty as u128));
        } else {
            vault::decrease_available_balance<B>(vault_account_owner, (qty as u128));
        };
        if (order.aux_au_to_burn_per_lot > 0) {
            vault::decrease_available_balance<AuxCoin>(vault_account_owner, (order.aux_au_to_burn_per_lot as u128) * (qty as u128) / lot_size);
        };
        event::emit_event<OrderPlacedEvent>(
            &mut market.placed_events,
            OrderPlacedEvent{
                order_id: placed_order_id,
                owner: placed_order_owner,
                price,
                qty,
                is_bid: order.is_bid,
                timestamp,
                client_order_id: order.client_order_id,
            }
        );

        let open_order_address = onchain_signer::get_signer_address(placed_order_owner);
        if (!exists<OpenOrderAccount<B, Q>>(open_order_address)) {
            move_to(
                &onchain_signer::get_signer(placed_order_owner),
                OpenOrderAccount<B, Q> {
                    open_orders: critbit::new(),
                }
            )
        };

        let open_order_account = borrow_global_mut<OpenOrderAccount<B, Q>>(open_order_address);
        critbit::insert(&mut open_order_account.open_orders, order.id, OpenOrderInfo {
            is_bid: order.is_bid,
            price: order.price,
        });
    }
    /// Returns value of order in quote AU
    fun quote_qty<B>(price: u64, quantity: u64): u64 {
        // TODO: pass in decimals for gas saving
        ((price as u128) * (quantity as u128) / exp(10, (coin::decimals<B>() as u128)) as u64)
    }
    public fun market_exists<B, Q>(): bool {
        exists<Market<B, Q>>(@aux)
    }
    // TODO: move to math lib
    // TODO: hardcode common powers of 10
    /// Returns a to the power of b. (adapted from https://github.com/pentagonxyz/movemate/blob/main/aptos/sources/math.move)
    public fun exp(a: u128, b: u128): u128 {
        let c = 1;

        while (b > 0) {
            if (b & 1 > 0) c = c * a;
            b = b >> 1;
            a = a * a;
        };

        c
    }
    fun destroy_order(order: Order) {
        let Order {
            id: _,
            client_order_id: _,
            price: _,
            quantity: _,
            aux_au_to_burn_per_lot: _,
            is_bid: _,
            owner_id: _,
            timeout_timestamp: _,
            order_type: _,
            timestamp: _,
        } = order;
    }
    fun process_cancel_order<B, Q>(cancelled: Order, timestamp: u64, lot_size: u128, cancel_events: &mut event::EventHandle<OrderCancelEvent>) acquires OpenOrderAccount {
        let open_order_account = borrow_global_mut<OpenOrderAccount<B, Q>>(
            onchain_signer::get_signer_address(cancelled.owner_id)
        );

        let order_idx = critbit::find(&open_order_account.open_orders, cancelled.id);

        assert!(order_idx != CRITBIT_NULL_INDEX, E_ORDER_NOT_IN_OPEN_ORDER_ACCOUNT);

        critbit::remove(&mut open_order_account.open_orders, order_idx);
        process_cancel_without_open_order_account<B, Q>(cancelled, timestamp, lot_size, cancel_events);
    }

    /*********************/
    /* PRIVATE FUNCTIONS */
    /*********************/

    fun process_cancel_without_open_order_account<B, Q>(
        cancelled: Order,
        timestamp: u64,
        lot_size: u128,
        cancel_events: &mut event::EventHandle<OrderCancelEvent>
    ) {
        let cancel_qty = cancelled.quantity;
        let event = OrderCancelEvent {
            order_id: cancelled.id,
            owner: cancelled.owner_id,
            cancel_qty: cancelled.quantity,
            timestamp,
            client_order_id: cancelled.client_order_id,
            order_type: cancelled.order_type,
        };

        event::emit_event(cancel_events, event);
        // Release hold on user funds
        if (cancelled.is_bid) {
            vault::increase_available_balance<Q>(
                cancelled.owner_id,
                (quote_qty<B>(cancelled.price, cancel_qty) as u128),
            );
        } else {
            vault::increase_available_balance<B>(
                cancelled.owner_id,
                (cancelled.quantity as u128),
            );
        };

        // When a cancel is successful, credit the unused AUX back to the user.
        let aux_burned = cancelled.aux_au_to_burn_per_lot;
        let remaining_qty = (cancelled.quantity as u128);
        let refund_aux_au = (aux_burned as u128) * remaining_qty / lot_size;
        if (refund_aux_au > 0) {
            vault::increase_available_balance<AuxCoin>(cancelled.owner_id, refund_aux_au);
        };

        destroy_order(cancelled);
    }
    // TODO: it's pretty unintuitive that this modifies the order. Maybe there's a better way to structure this.
    // return true if order_price is worse than limit (greater than limit when placing bid and smaller than limit when placing ask), otherwise false and change the order price to be specified price based on ticks and orderbook state
    fun order_price_worse_than_limit<B, Q>(market: &Market<B, Q>, order: &mut Order, ticks_to_slide: u64, direction_aggressive: bool) : bool {
        let tick_size = market.tick_size;
        let limit_price = order.price;
        let order_price;
        if (order.is_bid){
            // if there's no bids at all, then cannot passively join bids
            if (critbit::size(&market.bids) == 0) {
                return true
            };
            // derive the join price
            let best_bid_level_price =  best_bid_price(market);
            let best_ask_level_price = MAX_U64;
            if (critbit::size(&market.asks) > 0) {
                best_ask_level_price = best_ask_price(market);
            };
            if(direction_aggressive){
                order_price = best_bid_level_price + ticks_to_slide * tick_size;
                if (order_price >= best_ask_level_price) {
                    order_price = best_ask_level_price - tick_size;
                }
            } else {
                order_price = best_bid_level_price - ticks_to_slide * tick_size;
            };
            if (order_price <= limit_price) {
                order.price = order_price;
                return false
            };
            return true
        } else{
            // if there's no asks at all, then cannot passively join asks
            if (critbit::size(&market.asks) == 0) return true;
            // derive the join price
            let best_ask_level_price = best_ask_price(market);
            let best_bid_level_price = 0;
            if (critbit::size(&market.bids) > 0) {
                best_bid_level_price =  best_bid_price(market);
            };
            if(direction_aggressive){
                order_price = best_ask_level_price - ticks_to_slide * tick_size;
                if (order_price <= best_bid_level_price) {
                    order_price = best_bid_level_price + tick_size;
                }
            }else{
                order_price = best_ask_level_price + ticks_to_slide * tick_size;
            };
            if (order_price >= limit_price) {
                order.price = order_price;
                return false
            };
            return true
        }
    }

    fun match<B, Q>(market: &mut Market<B, Q>, taker_order: &mut Order, current_timestamp: u64, stp_action_type: u64): (u64, u64) acquires OpenOrderAccount {
        let side = if (taker_order.is_bid) { &mut market.asks } else { &mut market.bids };
        let order_price = taker_order.price;
        let total_base_quantity_owed_au = 0;
        let total_quote_quantity_owed_au = 0;

        let lot_size = (market.lot_size as u128);
        while (!critbit::empty(side) && taker_order.quantity > 0) {
            let min_level_index = if (taker_order.is_bid) {
                critbit::get_min_index(side)
            } else {
                critbit::get_max_index(side)
            };
            let (_, level) = critbit::borrow_at_index_mut(side, min_level_index);
            let level_price = level.price;

            if (
                (taker_order.is_bid && level_price <= order_price) ||   // match is an ask <= bid
                    (!taker_order.is_bid && level_price >= order_price)     // match is a bid >= ask
            ) {
                // match within level
                while (level.total_quantity > 0 && taker_order.quantity > 0) {
                    let min_order_idx = critbit_v::get_min_index(&level.orders);
                    let (_, maker_order) = critbit_v::borrow_at_index(&level.orders, min_order_idx);
                    // cancel the maker orde if it's already timed out.
                    if (maker_order.timeout_timestamp <= current_timestamp) {
                        let (_, min_order) = critbit_v::remove(&mut level.orders, min_order_idx);
                        level.total_quantity = level.total_quantity - (min_order.quantity as u128);
                        process_cancel_order<B, Q>(min_order, current_timestamp, lot_size, &mut market.cancel_events);
                        continue
                    };

                    // Check whether self-trade occurs
                    if (taker_order.owner_id == maker_order.owner_id) {
                        // Follow the specification to cancel
                        if (stp_action_type == CANCEL_PASSIVE){
                            let (_, cancelled) = critbit_v::remove(&mut level.orders, min_order_idx);
                            level.total_quantity = level.total_quantity - (cancelled.quantity as u128);
                            process_cancel_order<B, Q>(cancelled, current_timestamp, lot_size, &mut market.cancel_events);
                        } else if (stp_action_type == CANCEL_AGGRESSIVE){
                            // Cancel the rest unfilled amount of taker order
                            let event = OrderCancelEvent {
                                order_id: taker_order.id,
                                owner: taker_order.owner_id,
                                cancel_qty: taker_order.quantity,
                                timestamp: current_timestamp,
                                client_order_id: taker_order.client_order_id,
                                order_type: taker_order.order_type,
                            };
                            event::emit_event(&mut market.cancel_events, event);
                            taker_order.quantity = 0;
                            break
                        } else if (stp_action_type == CANCEL_BOTH){
                            // Cancel the maker order
                            let (_, cancelled) = critbit_v::remove(&mut level.orders, min_order_idx);
                            level.total_quantity = level.total_quantity - (cancelled.quantity as u128);
                            process_cancel_order<B, Q>(cancelled, current_timestamp, lot_size, &mut market.cancel_events);
                            // Cancel the taker order
                            let event = OrderCancelEvent {
                                order_id: taker_order.id,
                                owner: taker_order.owner_id,
                                cancel_qty: taker_order.quantity,
                                timestamp: current_timestamp,
                                client_order_id: taker_order.client_order_id,
                                order_type: taker_order.order_type,
                            };
                            event::emit_event(&mut market.cancel_events, event);
                            taker_order.quantity = 0;
                            break
                        }else{
                            abort(E_UNSUPPORTED_STP_ACTION_TYPE)
                        };
                        // If maker order is cancelled, we want to continue matching
                        continue
                    };
                    let current_maker_quantity = maker_order.quantity;
                    if (current_maker_quantity <= taker_order.quantity) {
                        // emit fill event
                        let (base, quote) = handle_fill<B, Q>(&mut market.fill_events, taker_order, maker_order, current_maker_quantity, lot_size);
                        total_base_quantity_owed_au = total_base_quantity_owed_au + base;
                        total_quote_quantity_owed_au = total_quote_quantity_owed_au + quote;
                        // update taker quantity
                        taker_order.quantity = taker_order.quantity - current_maker_quantity;
                        // delete maker order (order was fully filled)
                        let (_, filled) = critbit_v::remove(&mut level.orders, min_order_idx);
                        level.total_quantity = level.total_quantity - (filled.quantity as u128);
                        destroy_order(filled);
                    } else {
                        // emit fill event
                        let quantity = taker_order.quantity;
                        let (base, quote) = handle_fill<B, Q>(&mut market.fill_events, taker_order, maker_order, quantity, lot_size);
                        total_base_quantity_owed_au = total_base_quantity_owed_au + base;
                        total_quote_quantity_owed_au = total_quote_quantity_owed_au + quote;

                        let (_, maker_order) = critbit_v::borrow_at_index_mut(&mut level.orders, min_order_idx);
                        maker_order.quantity = maker_order.quantity - taker_order.quantity;
                        level.total_quantity = level.total_quantity - (taker_order.quantity as u128);
                        taker_order.quantity = 0;
                    };
                };
                if (level.total_quantity == 0) {
                    let (_, level) = critbit::remove(side, min_level_index);
                    destroy_empty_level(level);
                };
            } else {
                // if the order doesn't cross, stop looking for a match
                break
            };
        };
        (total_base_quantity_owed_au, total_quote_quantity_owed_au)
    }
    fun destroy_empty_level(level: Level) {
        assert!(level.total_quantity == 0, E_LEVEL_NOT_EMPTY);
        let Level {
            price: _,
            total_quantity: _,
            orders
        } = level;

        critbit_v::destroy_empty(orders);
    }

    // TODO: it's pretty unintuitive that this modifies the order. Maybe there's a better way to structure this.
    // true if any amount of the order can be filled by orderbook even after the maximum ticks_to_slide specified, otherwise return false and change the order.price_ticks by minimum_ticks_to_slide to make it not fill
    fun order_will_fill<B, Q>(market: &Market<B, Q>, order: &mut Order, ticks_to_slide: u64): bool {
        let tick_size = market.tick_size;
        let order_price = order.price;
        if (order.is_bid){
            // if there's no ask at all, then cannot fill with 0 ticks_to_slide
            if (critbit::size(&market.asks) == 0) return false;
            // TODO: confirm this level_price is also ticks?
            let level_price = best_ask_price(market);

            if (order_price < level_price) {
                return false
            };
            // TODO: confirm - 1 tick should be decrement 1 tick
            if ((order_price - level_price + tick_size) <= ticks_to_slide * tick_size) {
                assert!(level_price - tick_size > 0, E_SLIDE_TO_ZERO_PRICE);
                order.price = level_price - tick_size;
                return false
            };
            return true
        } else{
            // if there's no bid at all, then cannot fill with 0 ticks_to_slide
            if (critbit::size(&market.bids) == 0) {
                return false
            };
            let level_price = best_bid_price(market);
            if (order_price > level_price) {
                return false
            };
            // TODO: confirm + 1 should be increment 1 tick
            if ((level_price - order_price + tick_size) <= ticks_to_slide * tick_size) {
                order.price = level_price + tick_size;
                return false
            };
            return true
        }
    }
    public fun best_bid_price<B, Q>(market: &Market<B, Q>): u64 {
        assert!(critbit::size(&market.bids) > 0, E_NO_BIDS_IN_BOOK);
        let index = critbit::get_max_index(&market.bids);
        let (_, level) = critbit::borrow_at_index(&market.bids, index);
        level.price
    }

    public fun best_ask_price<B, Q>(market: &Market<B, Q>): u64 {
        assert!(critbit::size(&market.asks) > 0, E_NO_ASKS_IN_BOOK);
        let index = critbit::get_min_index(&market.asks);
        let (_, level) = critbit::borrow_at_index(&market.asks, index);
        level.price
    }
    /// Returns (total_base_quantity_owed_au, quote_quantity_owed_au), the amounts that must be credited/debited to the sender.
    /// Emits OrderFill events
    fun handle_fill<B, Q>(
        fill_events: &mut event::EventHandle<OrderFillEvent>,
        taker_order: &Order,
        maker_order: &Order,
        base_qty: u64,
        lot_size: u128
    ): (u64, u64) acquires OpenOrderAccount {
        let timestamp = timestamp::now_microseconds();
        let resource_addr = @aux;

        let taker = taker_order.owner_id;
        let maker = maker_order.owner_id;
        let price = maker_order.price;
        let quote_qty = quote_qty<B>(price, base_qty);
        let taker_is_bid = taker_order.is_bid;
        let (taker_fee, maker_rebate) = if (ZERO_FEES) {
            (0, 0)
        } else {
            (fee::taker_fee(taker, quote_qty), fee::maker_rebate(maker, quote_qty))
        };
        let total_base_quantity_owed_au = 0;
        let total_quote_quantity_owed_au = 0;
        if (taker_is_bid) {
            // taker pays quote + fee, receives base
            total_base_quantity_owed_au = total_base_quantity_owed_au + base_qty;
            total_quote_quantity_owed_au = total_quote_quantity_owed_au + quote_qty + taker_fee;

            // maker receives quote - fee, pays base
            vault::increase_user_balance<Q>(maker, (quote_qty + maker_rebate as u128));
            vault::decrease_unavailable_balance<B>(maker, (base_qty as u128));
        } else {
            // maker pays quote + fee, receives base
            vault::increase_available_balance<Q>(maker, (quote_qty as u128));
            vault::decrease_user_balance<Q>(maker, (quote_qty - maker_rebate as u128));
            vault::increase_user_balance<B>(maker, (base_qty as u128));

            // taker receives quote - fee, pays base
            total_base_quantity_owed_au = total_base_quantity_owed_au + base_qty;
            total_quote_quantity_owed_au = total_quote_quantity_owed_au + quote_qty - taker_fee;
        };

        // The net proceeds go to the protocol. This implicitly asserts that
        // taker fees can cover the maker rebate.
        if (!ZERO_FEES) {
            vault::increase_user_balance<Q>(@aux, (taker_fee - maker_rebate as u128));
        };

        // Emit event for taker
        let taker_order_id = taker_order.id;
        event::emit_event<OrderFillEvent>(
            fill_events,
            OrderFillEvent{
                order_id: taker_order_id,
                owner: taker,
                base_qty,  // base qty filled
                price,
                fee: taker_fee,
                rebate: 0,
                remaining_qty: util::sub_min_0(taker_order.quantity, (base_qty as u64)),
                is_bid: taker_order.is_bid,
                timestamp,
                client_order_id: taker_order.client_order_id,
            }
        );
        let maker_remaining_qty = util::sub_min_0(maker_order.quantity, (base_qty as u64));
        if (maker_order.aux_au_to_burn_per_lot > 0) {
            let aux_to_burn = (maker_order.aux_au_to_burn_per_lot as u128) * (base_qty as u128) / lot_size;
            vault::increase_available_balance<AuxCoin>(maker, aux_to_burn);
            vault::decrease_user_balance<AuxCoin>(maker, aux_to_burn);
        };

        // Emit event for maker
        event::emit_event<OrderFillEvent>(
            fill_events,
            OrderFillEvent{
                order_id: maker_order.id,
                owner: maker,
                base_qty,  // base qty filled
                price,
                fee: 0,
                rebate: maker_rebate,
                remaining_qty: maker_remaining_qty,
                is_bid: !taker_is_bid,
                timestamp,
                client_order_id: maker_order.client_order_id,
            },
        );

        if (maker_remaining_qty == 0) {
            let open_order_address = onchain_signer::get_signer_address(maker);
            assert!(exists<OpenOrderAccount<B, Q>>(open_order_address), E_NO_OPEN_ORDERS_ACCOUNT);
            let open_order_account = borrow_global_mut<OpenOrderAccount<B, Q>>(
                open_order_address,
            );

            let order_idx = critbit::find(&open_order_account.open_orders, maker_order.id);

            assert!(order_idx != CRITBIT_NULL_INDEX, E_ORDER_NOT_IN_OPEN_ORDER_ACCOUNT);

            critbit::remove(&mut open_order_account.open_orders, order_idx);
        };

        // record the volume filled / traded
        // update global volume for such base coin
        volume_tracker::update_volume_tracker<Q>(resource_addr, timestamp::now_seconds(), quote_qty);

        // update taker's volume, if they have a registered volume tracker
        // TODO: this is kind of clunky, but necessary since not everyone trading against clob has a vault account (e.g. coming from router)
        if (volume_tracker::global_volume_tracker_registered(taker)) {
            if (!volume_tracker::is_coin_volume_tracked<Q>(taker)){
                volume_tracker::register_coin_for_volume_track<Q>(taker);
            };
            volume_tracker::update_volume_tracker<Q>(taker, timestamp::now_seconds(), quote_qty);
        };

        // update maker's volume
        if (!volume_tracker::is_coin_volume_tracked<Q>(maker) && volume_tracker::global_volume_tracker_registered(maker)){
            volume_tracker::register_coin_for_volume_track<Q>(maker);
        };
        volume_tracker::update_volume_tracker<Q>(maker, timestamp::now_seconds(), quote_qty);
        (total_base_quantity_owed_au, total_quote_quantity_owed_au)
    }

    /*********/
    /* ORDER */
    /*********/

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

    /*********/
    /* LEVEL */
    /*********/

    struct Level has store {
        // price
        price: u64,
        // total quantity
        total_quantity: u128,
        orders: CritbitTreeV<Order>,
    }

    /**********/
    /* MARKET */
    /**********/

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
    /**********/
    /* EVENTS */
    /**********/

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

    struct OpenOrderInfo has store, drop {
        price: u64,
        is_bid: bool,
    }

    struct OpenOrderAccount<phantom B, phantom Q> has key {
        open_orders: CritbitTree<OpenOrderInfo>,
    }

}
