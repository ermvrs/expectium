use starknet::ContractAddress;
use expectium::config::{Asset};

#[starknet::interface]
trait IOrderbook<TContractState> {
    fn insert_buy_order(ref self: TContractState, asset: Asset, amount: u256, price: u16) -> u32; // order_id döndürür
    fn insert_sell_order(ref self: TContractState, asset: Asset, amount: u256, price: u16) -> u32;
    fn cancel_buy_order(ref self: TContractState, asset: Asset, order_id: u32);
    fn cancel_sell_order(ref self: TContractState, asset: Asset, order_id: u32);

    // views
    fn get_order(self: @TContractState, asset: Asset, side: u8, order_id: u32) -> felt252; // packed order döndürür. TODO: direk order döndürülebilir.
    fn get_order_owner(self: @TContractState, order_id: u32) -> ContractAddress;

    // operators
    fn emergency_toggle(ref self: TContractState);
}

#[starknet::interface]
trait IMarket<TContractState> {
    // view methods
    fn balance_of(self: @TContractState, account: ContractAddress, asset: Asset) -> u256;
    fn total_supply(self: @TContractState, asset: Asset) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> bool;
    fn resolver(self: @TContractState) -> ContractAddress;
    fn collateral(self: @TContractState) -> ContractAddress;
    fn resolve_rate(self: @TContractState) -> (u16, u16);
    // externals
    fn split_shares(ref self: TContractState, invest: u256);
    fn merge_shares(ref self: TContractState, shares: u256);
    fn approve(ref self: TContractState, spender: ContractAddress);
    fn revoke_approval(ref self: TContractState, spender: ContractAddress);
    fn transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, asset: Asset, amount: u256);
    fn transfer(ref self: TContractState, to: ContractAddress, asset: Asset, amount: u256);
    // operator or access controlled
    fn resolve_market(ref self: TContractState, happens: u16, not: u16);
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn set_value(self: TContractState, value: u128) -> u128;
    fn name(self: TContractState) -> felt252;
    fn symbol(self: TContractState) -> felt252;
    fn decimals(self: TContractState) -> u8;
    fn total_supply(self: TContractState) -> u256;
    fn balance_of(self: TContractState, account: ContractAddress) -> u256;
    fn allowance(self: TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;

    // support camelcase
    fn totalSupply(self: TContractState) -> u256;
    fn balanceOf(self: TContractState, account: ContractAddress) -> u256;
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}
