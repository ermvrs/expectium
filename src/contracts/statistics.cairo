// Who needs backend if calculation is cheap.
#[starknet::contract]
mod Statistics {
    use expectium::interfaces::{IStatistics};
    use expectium::types::{Asset, Trade};
    use expectium::utils::{pack_trade};
    use expectium::implementations::{StoreFelt252Array};

    use starknet::{ContractAddress, ClassHash, replace_class_syscall, get_block_timestamp, get_caller_address};
    use array::{ArrayTrait, SpanTrait};
    use traits::{TryInto,Into};
    use clone::Clone;

    #[storage]
    struct Storage {
        operator: ContractAddress,
        orderbooks: LegacyMap<ContractAddress, bool>,
        orderbooks_market: LegacyMap<ContractAddress, ContractAddress>, // Orderbook -> Market
        volumes: LegacyMap<ContractAddress, u256>, // Orderbook -> Volume
        trades_count: LegacyMap<ContractAddress, u64>, // Orderbook -> trade count
        last_trades: LegacyMap<ContractAddress, Array<felt252>>
    }

    #[constructor]
    fn constructor(ref self: ContractState, operator: ContractAddress) {
        self.operator.write(operator);
    }

    impl Statistics of IStatistics<ContractState> {
        // view
        fn get_volume(self: @ContractState, orderbook: ContractAddress) -> u256 {
            self.volumes.read(orderbook)
        }
        
        fn get_trades_count(self: @ContractState, orderbook: ContractAddress) -> u64 {
            self.trades_count.read(orderbook)
        }

        fn get_trades(self: @ContractState, orderbook: ContractAddress) -> Array<felt252> {
            self.last_trades.read(orderbook)
        }

        // external writes
        fn insert_trade(ref self: ContractState, asset: Asset, price: u16, amount: u256, taker_side: u8) {
            let orderbook = get_caller_address();
            assert(self.orderbooks.read(orderbook), 'orderbook not registered.');
            let market = self.orderbooks_market.read(orderbook);

            let volume = (amount * price.into()) / 10000;

            self.volumes.write(orderbook, self.volumes.read(orderbook) + volume);
            self.trades_count.write(orderbook, self.trades_count.read(orderbook) + 1);

            let date = get_block_timestamp();

            let trade: Trade = Trade {
                asset, price, amount: amount.low, side: taker_side, date
            };

            let packed_trade: felt252 = pack_trade(trade);

            let new_trades_array = _prepare_trades_array(self.last_trades.read(orderbook), packed_trade);

            self.last_trades.write(orderbook, new_trades_array);
        }

        // Operator methods
        fn register_market(ref self: ContractState, orderbook: ContractAddress, market: ContractAddress) {
            _assert_only_operator(@self, get_caller_address());

            self.orderbooks.write(orderbook, true);
            self.orderbooks_market.write(orderbook, market);
        }

        fn transfer_operator(ref self: ContractState, new_operator: ContractAddress) {
            _assert_only_operator(@self, get_caller_address());

            self.operator.write(new_operator);
        }

        fn upgrade_contract(ref self: ContractState, new_class: ClassHash) {
            _assert_only_operator(@self, get_caller_address());

            replace_class_syscall(new_class);
        }
    }

    fn _prepare_trades_array(current: Array<felt252>, trade: felt252) -> Array<felt252> {
        let mut new_array = current.clone();
        if(new_array.len() > 30) {
            new_array.pop_front();
            new_array.append(trade);
            new_array
        } else {
            new_array.append(trade);
            new_array
        }
    }

    fn _assert_only_operator(self: @ContractState, caller: ContractAddress) {
        let operator = self.operator.read();
        assert(operator == caller, 'only operator');
    }
}