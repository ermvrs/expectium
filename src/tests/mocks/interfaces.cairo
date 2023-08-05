use starknet::{ContractAddress, ClassHash};
use expectium::config::Asset;

#[starknet::interface]
trait IAccount<TContractState> {
    fn erc20_balance_of(            
            self: @TContractState,
            contract_address: ContractAddress,
            account: ContractAddress
    ) -> u256;
    
    fn erc20_transfer(
        self: @TContractState,
        contract_address: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    );

    fn erc20_approve(
        self: @TContractState,
        contract_address: ContractAddress,
        spender: ContractAddress,
        amount: u256
    );

    fn erc20_transfer_from(
        self: @TContractState,
        contract_address: ContractAddress,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    );

    fn factory_transfer_operator(
            self: @TContractState,
            contract_address: ContractAddress,
            new_operator: ContractAddress
    );

    fn factory_change_current_classhash(
            self: @TContractState,
            contract_address: ContractAddress,
            new_hash: ClassHash
    );

    fn factory_create_market(
            self: @TContractState,
            contract_address: ContractAddress,
            resolver: ContractAddress,
            collateral: ContractAddress
    ) -> (u64, ContractAddress);

    fn market_approve(
            self: @TContractState,
            contract_address: ContractAddress,
            spender: ContractAddress
    );
    
    fn market_revoke_approval(
            self: @TContractState,
            contract_address: ContractAddress,
            spender: ContractAddress
    );

    fn market_transfer_from(
            self: @TContractState,
            contract_address: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            asset: Asset,
            amount: u256
    );
    
    fn market_mint_shares(
            self: @TContractState,
            contract_address: ContractAddress,
            amount: u256
    );

    fn market_merge_shares(
            self: @TContractState,
            contract_address: ContractAddress,
            amount: u256
    );
    fn market_resolve_market(
            self: @TContractState,
            contract_address: ContractAddress,
            happens: u16,
            not: u16
        );

    fn market_convert_shares(
            self: @TContractState,
            contract_address: ContractAddress,
            asset: Asset,
            amount: u256
        );

}