use expectium::config::{Asset};

#[starknet::interface]
trait IOrderbook<TContractState> {

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
}