use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IFactory<TContractState> {
    // externals
    fn create_market(ref self: TContractState) -> u64; // market id döndürür.
    // views
    fn get_market_from_id(self: @TContractState, market_id: u64) -> ContractAddress;
    fn is_market_registered(self: @TContractState, market: ContractAddress) -> bool;
    // operators
    fn change_current_classhash(ref self: TContractState, new_hash: ClassHash);
    fn upgrade_factory(ref self: TContractState, new_hash: ClassHash);
    fn upgrade_market(self: @TContractState, market_id: u64); // marketi mevcut hashe yükseltir.
    fn transfer_operator(ref self: TContractState, new_operator: ContractAddress);
}

#[starknet::contract]
mod Factory {
    use starknet::{ContractAddress, ClassHash, replace_class_syscall, get_caller_address};
    use expectium::interfaces::{IMarketDispatcher, IMarketDispatcherTrait};
    use super::IFactory;
    use zeroable::Zeroable;

    #[storage]
    struct Storage {
        markets: LegacyMap<u64, ContractAddress>,
        is_market: LegacyMap<ContractAddress, bool>, // registered market tracking
        current_class: ClassHash, // yeni marketler bu hash ile kurulacak.
        operator: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, operator: ContractAddress) {
        self.operator.write(operator);
    }

    #[external(v0)]
    impl Factory of IFactory<ContractState> {
        fn create_market(ref self: ContractState) -> u64 {
            0_u64 // TODO 
        }

        fn get_market_from_id(self: @ContractState, market_id: u64) -> ContractAddress {
            self.markets.read(market_id)
        }

        fn is_market_registered(self: @ContractState, market: ContractAddress) -> bool {
            self.is_market.read(market)
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