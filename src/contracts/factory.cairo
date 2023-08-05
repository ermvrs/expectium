#[starknet::contract]
mod Factory {
    use starknet::{ContractAddress, ClassHash, replace_class_syscall, get_caller_address, deploy_syscall, get_contract_address};
    use expectium::interfaces::{IMarketDispatcher, IMarketDispatcherTrait, IFactory};
    use zeroable::Zeroable;
    use array::{ArrayTrait, SpanTrait};
    use traits::Into;

    #[storage]
    struct Storage {
        markets: LegacyMap<u64, ContractAddress>,
        is_market: LegacyMap<ContractAddress, bool>, // registered market tracking
        current_class: ClassHash, // yeni marketler bu hash ile kurulacak.
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
            let (deployed_address, _) = result.unwrap_syscall();

            self.markets.write(current_id, deployed_address);
            self.is_market.write(deployed_address, true);

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

        fn upgrade_factory(ref self: ContractState, new_hash: ClassHash) {
            assert_only_operator(@self);

            replace_class_syscall(new_hash);
        }

        fn upgrade_market(self: @ContractState, market_id: u64) {
            assert_only_operator(self);

            let latest_hash = self.current_class.read();

            let market: ContractAddress = self.markets.read(market_id);

            assert(market.is_non_zero(), 'market zero');

            IMarketDispatcher{ contract_address: market }.upgrade_market(latest_hash);
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