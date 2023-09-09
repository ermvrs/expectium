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
        last_trades: LegacyMap<ContractAddress, Array<felt252>>,
        user_total_trades_count: LegacyMap<ContractAddress, u64>, // User -> trade count
        user_total_volume: LegacyMap<ContractAddress, u256>, // User -> Volume
        user_market_trades_count: LegacyMap<(ContractAddress, ContractAddress), u64>, // Orderbook -> User -> trade count
        user_market_volume: LegacyMap<(ContractAddress, ContractAddress), u256>, // Orderbook -> User -> volume
        // Volume ve trade sayısı sadece emir eşleşince değişir.
    }

    #[constructor]
    fn constructor(ref self: ContractState, operator: ContractAddress) {
        self.operator.write(operator);
    }
    
    #[external(v0)]
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

        fn get_user_total_trades_count(self: @ContractState, user: ContractAddress) -> u64 {
            self.user_total_trades_count.read(user)
        }

        fn get_user_total_volume(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_total_volume.read(user)
        }

        fn get_user_market_trades_count(self: @ContractState, user: ContractAddress, orderbook: ContractAddress) -> u64 {
            self.user_market_trades_count.read((orderbook, user))
        }

        fn get_user_market_volume(self: @ContractState, user: ContractAddress, orderbook: ContractAddress) -> u256 {
            self.user_market_volume.read((orderbook, user))
        }

        // external writes
        fn insert_trade(ref self: ContractState, asset: Asset, price: u16, amount: u256, taker_side: u8, maker: ContractAddress, taker: ContractAddress) {
            let orderbook = get_caller_address();
            assert(self.orderbooks.read(orderbook), 'orderbook not registered.');
            let market = self.orderbooks_market.read(orderbook);

            let volume = (amount * price.into()) / 10000;

            _update_user_stats(ref self, maker, taker, volume, orderbook);

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

    fn _update_user_stats(ref self: ContractState, maker: ContractAddress, taker: ContractAddress, volume: u256, orderbook: ContractAddress) {

        self.user_total_trades_count.write(maker, self.user_total_trades_count.read(maker) + 1);
        self.user_total_trades_count.write(taker, self.user_total_trades_count.read(taker) + 1);

        self.user_total_volume.write(maker, self.user_total_volume.read(maker) + volume);
        self.user_total_volume.write(taker, self.user_total_volume.read(taker) + volume);

        self.user_market_trades_count.write((orderbook, maker), self.user_market_trades_count.read((orderbook, maker)) + 1);
        self.user_market_trades_count.write((orderbook, taker), self.user_market_trades_count.read((orderbook, taker)) + 1);

        self.user_market_volume.write((orderbook, maker), self.user_market_volume.read((orderbook, maker)) + volume);
        self.user_market_volume.write((orderbook, taker), self.user_market_volume.read((orderbook, taker)) + volume);
    }
}