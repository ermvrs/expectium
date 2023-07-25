use expectium::config::{Asset};

#[starknet::interface]
trait IOrderbook<TContractState> {
    fn get_orders(self: TContractState, side: u8, asset: Asset) -> Array<felt252>;
    fn set(ref self: TContractState, value: u32);
    fn insert_order(ref self: TContractState, price: u16, amount: u128, asset: Asset);
}

#[starknet::contract]
mod Orderbook {
    use starknet::{ContractAddress, get_block_timestamp};
    use expectium::config::{Order, Asset, StorageAccessFelt252Array, pack_order};
    use array::{ArrayTrait, SpanTrait};

    #[storage]
    struct Storage {
        _happens: LegacyMap<u8, Array<felt252>>, // 0 buy 1 sell
        _not: LegacyMap<u8, Array<felt252>>,
        _order_count: u32,
    }

    #[external(v0)]
    #[generate_trait]
    impl Orderbook of IOrderbook {
        fn get_orders(self: @ContractState, side: u8, asset: Asset) -> Array<felt252> {
            match asset {
                Asset::Happens(()) => {
                    self._happens.read(side)
                },
                Asset::Not(()) => {
                    self._not.read(side)
                }
            }
        }

        fn insert_order(ref self: ContractState, price: u16, amount: u128, asset: Asset) {
            match asset {
                Asset::Happens(()) => {
                    let mut current = self._happens.read(0);
                    current.append(pack_order(Order { order_id: self._order_count.read(), date: get_block_timestamp(), amount: amount, price: price}));

                    self._happens.write(0, current);
                },
                Asset::Not(()) => {
                    let mut current = self._not.read(0);
                    current.append(pack_order(Order { order_id: self._order_count.read(), date: get_block_timestamp(), amount: amount, price: price}));

                    self._not.write(0, current);
                } 
            }
        }

        fn set(ref self: ContractState, value: u32) {
            PrivateFunctionsTrait::_increase_order_count(ref self);
        }
        fn get(self: @ContractState) -> u32 {
            // We can call an internal function from any functions within the contract
            self._order_count.read()
        }
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        // The `_read_value` function is outside the implementation that is marked as `#[external(v0)]`, so it's an _internal_ function
        // and can only be called from within the contract.
        // It can modify the contract's state as it is passed as a reference.
        fn _increase_order_count(ref self: ContractState) -> u32 {
            let current_order = self._order_count.read();

            self._order_count.write(current_order + 1);
            current_order
        }
    }


}