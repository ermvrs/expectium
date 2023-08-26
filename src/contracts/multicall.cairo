#[starknet::contract]
mod Multicall {
    use starknet::{call_contract_syscall, ContractAddress};
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use clone::Clone;

    use expectium::interfaces::{IMulticall, IMarketDispatcher, IMarketDispatcherTrait, IOrderbookDispatcher, IOrderbookDispatcherTrait};
    use expectium::types::{MarketData, OrdersData, UserData, UserOrders};

    #[storage]
    struct Storage {}

    // Todo multicall düzenle, market vs okuyabilsin
    #[external(v0)]
    impl Multicall of IMulticall<ContractState> {
        fn aggregateUserData(self: @ContractState, user: ContractAddress, market: ContractAddress, orderbook: ContractAddress) -> UserData {
            _aggregate_user_data(user, market, orderbook)
        }

        fn aggregateMarketData(self: @ContractState, market: ContractAddress, orderbook: ContractAddress) -> MarketData {
            _aggregate_market_data(market, orderbook)
        }

        fn aggregateMultipleMarketsData(self: @ContractState, orderbooks: Array<ContractAddress>) -> Array<MarketData> {
            let mut _orderbooks = orderbooks.clone();
            let mut result = ArrayTrait::<MarketData>::new();
            loop {
                match _orderbooks.pop_front() {
                    Option::Some(v) => {
                        let orderbook = IOrderbookDispatcher { contract_address: v };
                        let market_address = orderbook.market();
                        let data = _aggregate_market_data(market_address, v);
                        result.append(data);
                    },
                    Option::None(()) => {
                        break;
                    }
                };
            };

            result
        }
    }

    fn _aggregate_market_data(market_address: ContractAddress, orderbook_address: ContractAddress) -> MarketData {
        let orderbook = IOrderbookDispatcher { contract_address: orderbook_address };
        let market = IMarketDispatcher { contract_address: market_address };

        let collateral_amount = market.total_supply(expectium::types::Asset::Happens(())) * 2;
        let (happens_resolve, not_resolve) = market.resolve_rate();

        let happens_buy_orders = orderbook.get_orders(expectium::types::Asset::Happens(()), 0_u8);
        let happens_sell_orders = orderbook.get_orders(expectium::types::Asset::Happens(()), 1_u8);

        let not_buy_orders = orderbook.get_orders(expectium::types::Asset::Not(()), 0_u8);
        let not_sell_orders = orderbook.get_orders(expectium::types::Asset::Not(()), 1_u8);

        let orders: OrdersData = OrdersData {
            happens_buy: happens_buy_orders,
            happens_sell: happens_sell_orders,
            not_buy: not_buy_orders,
            not_sell: not_sell_orders
        };

        MarketData { collateral_amount, happens_resolve, not_resolve, orders }
    }

    fn _aggregate_user_data(user: ContractAddress, market_address: ContractAddress, orderbook_address: ContractAddress) -> UserData {
        let orderbook = IOrderbookDispatcher { contract_address: orderbook_address };
        let market = IMarketDispatcher { contract_address: market_address };

        let happens_balance = market.balance_of(user, expectium::types::Asset::Happens(()));
        let not_balance = market.balance_of(user, expectium::types::Asset::Not(()));

        let mut user_orderids = orderbook.get_user_orders(user);

        let mut happens_buy = ArrayTrait::<felt252>::new();
        let mut happens_sell = ArrayTrait::<felt252>::new();

        let mut not_buy = ArrayTrait::<felt252>::new();
        let mut not_sell = ArrayTrait::<felt252>::new();

        loop {
            match user_orderids.pop_front() {
                Option::Some(v) => {
                    let (asset, side, order) = orderbook.get_order_with_id(v);
                    
                    if(order.into() == 0) { // Order sıfır ise order yok.
                        continue;
                    };

                    match asset {
                        expectium::types::Asset::Happens(()) => {
                            if(side == 0_u8) {
                                happens_buy.append(order)
                            } else {
                                happens_sell.append(order)
                            };
                        },
                        expectium::types::Asset::Not(()) => {
                            if(side == 0_u8) {
                                not_buy.append(order)
                            } else {
                                not_sell.append(order)
                            };
                        }
                    };
                },
                Option::None(()) => {
                    break;
                }
            };
        };
        let user_orders = UserOrders {
            happens_buy, happens_sell, not_buy, not_sell
        };
        UserData { happens_balance, not_balance, user_orders }
    }
}