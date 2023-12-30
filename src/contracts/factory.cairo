#[starknet::contract]
mod Factory {
    use starknet::{ContractAddress, ClassHash, replace_class_syscall, get_caller_address, deploy_syscall, get_contract_address};
    use expectium::interfaces::{IMarketDispatcher, IMarketDispatcherTrait, IFactory};
    use zeroable::Zeroable;
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use traits::Into;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MarketCreated: MarketCreated,
        MarketUpgraded: MarketUpgraded
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct MarketCreated {
        creator: ContractAddress,
        id: u64,
        resolver: ContractAddress,
        address: ContractAddress,
        orderbook: ContractAddress
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct MarketUpgraded {
        operator: ContractAddress,
        id: u64
    }

    #[storage]
    struct Storage {
        markets: LegacyMap<u64, ContractAddress>,
        is_market: LegacyMap<ContractAddress, bool>, // registered market tracking
        current_class: ClassHash, // yeni marketler bu hash ile kurulacak.
        orderbook_class: ClassHash,
        distributor: ContractAddress,
        operator: ContractAddress,
        market_ids: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, operator: ContractAddress, market_hash: ClassHash) {
        self.operator.write(operator);
        self.current_class.write(market_hash);
    }

    #[external(v0)]
    impl Factory of IFactory<ContractState> {
        fn create_market(ref self: ContractState, resolver: ContractAddress, collateral: ContractAddress) -> (u64, ContractAddress) {
            assert_only_operator(@self);
            let current_id = self.market_ids.read(); // first id 0
            self.market_ids.write(current_id + 1);

            let mut constructor = ArrayTrait::new();
            constructor.append(get_contract_address().into());
            constructor.append(collateral.into());
            constructor.append(current_id.into());
            constructor.append(resolver.into());

            let result = deploy_syscall(self.current_class.read(), current_id.into(), constructor.span(), false);
            let (deployed_address, _) = result.unwrap();

            self.markets.write(current_id, deployed_address);
            self.is_market.write(deployed_address, true);

            // create orderbook for market

            let mut orderbook_calldata = ArrayTrait::new();
            orderbook_calldata.append(deployed_address.into());
            orderbook_calldata.append(self.operator.read().into());
            orderbook_calldata.append(collateral.into());
            orderbook_calldata.append(self.distributor.read().into());

            let orderbook_result = deploy_syscall(self.orderbook_class.read(), current_id.into(), orderbook_calldata.span(), false);
            let (orderbook_deployed_address, _) = orderbook_result.unwrap();

            self.emit(Event::MarketCreated(
                MarketCreated { creator: get_caller_address(), id: current_id, resolver: resolver, address: deployed_address, orderbook: orderbook_deployed_address }
            ));

            (current_id, deployed_address)
        }

        fn get_market_from_id(self: @ContractState, market_id: u64) -> ContractAddress {
            self.markets.read(market_id)
        }

        fn is_market_registered(self: @ContractState, market: ContractAddress) -> bool {
            self.is_market.read(market)
        }

        fn operator(self: @ContractState) -> ContractAddress {
            self.operator.read()
        }

        fn current_hash(self: @ContractState) -> ClassHash {
            self.current_class.read()
        }

        fn change_current_classhash(ref self: ContractState, new_hash: ClassHash) {
            assert_only_operator(@self);

            self.current_class.write(new_hash);
        }

        fn change_orderbook_classhash(ref self: ContractState, new_hash: ClassHash) {
            assert_only_operator(@self);

            self.orderbook_class.write(new_hash);
        }

        fn change_distributor_contract(ref self: ContractState, new_distributor: ContractAddress) {
            assert_only_operator(@self);

            self.distributor.write(new_distributor);
        }

        fn upgrade_factory(ref self: ContractState, new_hash: ClassHash) {
            assert_only_operator(@self);

            replace_class_syscall(new_hash);
        }

        fn upgrade_market(ref self: ContractState, market_id: u64) {
            assert_only_operator(@self);

            let latest_hash = self.current_class.read();

            let market: ContractAddress = self.markets.read(market_id);

            assert(market.is_non_zero(), 'market zero');

            IMarketDispatcher{ contract_address: market }.upgrade_market(latest_hash);

            self.emit(Event::MarketUpgraded(
                MarketUpgraded { operator: get_caller_address(), id: market_id }
            ));
        }

        fn transfer_operator(ref self: ContractState, new_operator: ContractAddress) {
            assert_only_operator(@self);

            self.operator.write(new_operator);
        }
    }

    fn assert_only_operator(self: @ContractState) {
        let caller = get_caller_address();
        let operator = self.operator.read();

        assert(caller == operator, 'only operator');
    }
}