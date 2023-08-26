#[starknet::contract]
mod Multicall {
    use starknet::{call_contract_syscall, ContractAddress};
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use clone::Clone;

    use expectium::interfaces::{IMulticall, IMarketDispatcher, IMarketDispatcherTrait, IOrderbookDispatcher, IOrderbookDispatcherTrait};
    use expectium::types::{MarketData, OrdersData};

    #[storage]
    struct Storage {}

    // Todo multicall düzenle, market vs okuyabilsin
    #[external(v0)]
    impl Multicall of IMulticall<ContractState> {
        fn aggregateMarketData(self: @ContractState, market_address: ContractAddress, orderbook_address: ContractAddress) -> MarketData {
            _aggregate_market_data(market_address, orderbook_address)
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

            MarketData {
                collateral_amount, happens_resolve, not_resolve, orders
            }
    }
}