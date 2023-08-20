use starknet::{ContractAddress, ClassHash};
use expectium::config::{Asset, PlatformFees};

#[starknet::interface]
trait IOrderbook<TContractState> {
    fn insert_buy_order(ref self: TContractState, asset: Asset, quote_amount: u256, price: u16) -> u32; // order_id döndürür
    fn insert_sell_order(ref self: TContractState, asset: Asset, amount: u256, price: u16) -> u32;
    fn cancel_buy_order(ref self: TContractState, asset: Asset, order_id: u32);
    fn cancel_sell_order(ref self: TContractState, asset: Asset, order_id: u32);

    // views
    fn get_order(self: @TContractState, asset: Asset, side: u8, order_id: u32) -> felt252; // packed order döndürür. TODO: direk order döndürülebilir.
    fn get_orders(self: @TContractState, asset: Asset, side: u8) -> Array<felt252>;
    fn get_order_owner(self: @TContractState, order_id: u32) -> ContractAddress;
    fn get_user_orders(self: @TContractState, user: ContractAddress) -> Array<u32>;
    fn get_order_with_id(self: @TContractState, order_id: u32) -> felt252;
    fn market(self: @TContractState) -> ContractAddress;
    fn operator(self: @TContractState) -> ContractAddress;
    fn distributor(self: @TContractState) -> ContractAddress;

    // operators
    fn emergency_toggle(ref self: TContractState);
    fn refresh_distributor_approval(ref self: TContractState);
    fn set_fees(ref self: TContractState, fees: PlatformFees);
    fn upgrade_contract(ref self: TContractState, new_class: ClassHash);
}

#[starknet::interface]
trait IMarket<TContractState> {
    // view methods
    fn balance_of(self: @TContractState, account: ContractAddress, asset: Asset) -> u256;
    fn total_supply(self: @TContractState, asset: Asset) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> bool;
    fn resolver(self: @TContractState) -> ContractAddress;
    fn collateral(self: @TContractState) -> ContractAddress;
    fn factory(self: @TContractState) -> ContractAddress;
    fn resolve_rate(self: @TContractState) -> (u16, u16);
    fn is_resolved(self: @TContractState) -> bool;
    fn market_id(self: @TContractState) -> u64;
    // externals
    fn mint_shares(ref self: TContractState, invest: u256);
    fn merge_shares(ref self: TContractState, shares: u256);
    fn convert_shares(ref self: TContractState, asset: Asset, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress);
    fn revoke_approval(ref self: TContractState, spender: ContractAddress);
    fn transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, asset: Asset, amount: u256);
    fn transfer(ref self: TContractState, to: ContractAddress, asset: Asset, amount: u256);
    // operator or access controlled
    fn resolve_market(ref self: TContractState, happens: u16, not: u16);
    fn upgrade_market(ref self: TContractState, new_class: ClassHash);
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;

    // support camelcase
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IShares<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
}

#[starknet::interface]
trait IFactory<TContractState> {
    // externals
    fn create_market(ref self: TContractState, resolver: ContractAddress, collateral: ContractAddress) -> (u64, ContractAddress); // market id döndürür.
    // views
    fn get_market_from_id(self: @TContractState, market_id: u64) -> ContractAddress;
    fn is_market_registered(self: @TContractState, market: ContractAddress) -> bool;
    fn operator(self: @TContractState) -> ContractAddress;
    fn current_hash(self: @TContractState) -> ClassHash;
    // operators
    fn change_current_classhash(ref self: TContractState, new_hash: ClassHash);
    fn upgrade_factory(ref self: TContractState, new_hash: ClassHash);
    fn upgrade_market(ref self: TContractState, market_id: u64); // marketi mevcut hashe yükseltir.
    fn transfer_operator(ref self: TContractState, new_operator: ContractAddress);
}

#[starknet::interface]
trait IDistributor<TContractState> {
    fn new_distribution(ref self: TContractState, token: ContractAddress, amount: u256); // Distributiona para ekler.
    fn claim(ref self: TContractState, token: ContractAddress, share_id: u256); // tokenid ye ait token fee yi claim eder.
    // views
    fn get_claimable_amount(self: @TContractState, token: ContractAddress, share_id: u256) -> u256;
    fn total_distribution(self: @TContractState, token: ContractAddress) -> u256;
    fn total_distribution_per_share(self: @TContractState, token: ContractAddress) -> u256;
    fn is_claims_available(self: @TContractState) -> bool;
    fn shares(self: @TContractState) -> ContractAddress;
    // operator
    fn toggle_claims(ref self: TContractState);
    fn register_token(ref self: TContractState, token: ContractAddress);
    fn upgrade_contract(ref self: TContractState, new_class: ClassHash);
    fn transfer_operator(ref self: TContractState, new_operator: ContractAddress);
}