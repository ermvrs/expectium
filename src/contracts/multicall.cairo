use starknet::ContractAddress;
use expectium::types::{MarketData, OrdersData, UserData, UserOrders, SharesState};

#[derive(Drop, Serde)]
struct SharesInfoResponse {
    total_supply: u256,
    total_distribution: u256,
    state: SharesState,
}

#[derive(Drop, Serde, PartialEq)]
struct SharesUserInfoResponse {
    user_share_ids: Array<(u128, u256)> 
}

#[starknet::interface]
trait IMulticall<TState> {
    fn get_shares_user_info(self: @TState, shares: ContractAddress, user: ContractAddress, distributor: ContractAddress, distribution_token: ContractAddress) -> SharesUserInfoResponse; // u256 gerek yok
    fn get_shares_info(self: @TState, shares: ContractAddress, distributor: ContractAddress, distribution_token: ContractAddress, state_id: u32) -> SharesInfoResponse;
    fn aggregateUserData(self: @TState, user: ContractAddress, market: ContractAddress, orderbook: ContractAddress) -> UserData;
    fn aggregateMarketData(self: @TState, market: ContractAddress, orderbook: ContractAddress) -> MarketData;
    fn upgrade_contract(ref self: TState, new_hash: starknet::ClassHash);
}

#[starknet::contract]
mod Multicall {
    use expectium::interfaces::{IMarketDispatcher, IMarketDispatcherTrait, 
                                IOrderbookDispatcher, IOrderbookDispatcherTrait,
                                ISharesDispatcher, ISharesDispatcherTrait, 
                                IDistributorDispatcher, IDistributorDispatcherTrait};
    use expectium::types::{MarketData, OrdersData, UserData, UserOrders};
    use starknet::{ContractAddress, ClassHash, get_caller_address, replace_class_syscall};
    use array::{ArrayTrait, SpanTrait};
    use super::{SharesUserInfoResponse, SharesInfoResponse};

    #[storage]
    struct Storage {
        upgrader: ContractAddress
    }
    
    #[constructor]
    fn constructor(ref self: ContractState, operator: ContractAddress) {
        self.upgrader.write(operator);
    }

    #[external(v0)]
    impl Multicall of super::IMulticall<ContractState> {
        fn upgrade_contract(ref self: ContractState, new_hash: starknet::ClassHash) {
            assert(get_caller_address() == self.upgrader.read(), 'only operator');
            replace_class_syscall(new_hash).unwrap();
        }

        fn get_shares_info(self: @ContractState, shares: ContractAddress, distributor: ContractAddress, distribution_token: ContractAddress, state_id: u32) -> SharesInfoResponse {
            let dispatcher = ISharesDispatcher { contract_address: shares };
            let distributor_dispatcher = IDistributorDispatcher { contract_address: distributor };
            let total_supply = dispatcher.total_supply();
            let state = dispatcher.get_state(state_id);
            let total_distribution = distributor_dispatcher.total_distribution(distribution_token);

            SharesInfoResponse {
                total_supply: total_supply,
                total_distribution: total_distribution,
                state: state
            }
        }

        fn get_shares_user_info(self: @ContractState, shares: ContractAddress, user: ContractAddress, distributor: ContractAddress, distribution_token: ContractAddress) -> SharesUserInfoResponse {
            let mut i = 1;
            let dispatcher = ISharesDispatcher { contract_address: shares };
            let distributor_dispatcher = IDistributorDispatcher { contract_address: distributor };
            let total_supply = dispatcher.total_supply();
            let mut owned_by = ArrayTrait::<(u128, u256)>::new();

            loop {
                if(total_supply < i) {
                    break;
                }
                let owner = dispatcher.owner_of(i.into());
                if(owner == user) {
                    let available_claim = distributor_dispatcher.get_claimable_amount(distribution_token, i);
                    owned_by.append((i.low, available_claim));
                }
                i = i + 1;
            };

            return SharesUserInfoResponse {
                user_share_ids: owned_by
            };
        }

        fn aggregateUserData(self: @ContractState, user: ContractAddress, market: ContractAddress, orderbook: ContractAddress) -> UserData {
            _aggregate_user_data(user, market, orderbook)
        }

        fn aggregateMarketData(self: @ContractState, market: ContractAddress, orderbook: ContractAddress) -> MarketData {
            _aggregate_market_data(market, orderbook)
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

        MarketData { collateral_amount, happens_resolve, not_resolve, orders}
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

        UserData {happens_balance, not_balance, user_orders }
    }
}