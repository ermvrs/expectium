#[starknet::contract]
mod Account {
    use starknet::{ContractAddress, ClassHash};
    use expectium::config::Asset;
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, 
            IFactoryDispatcher, IFactoryDispatcherTrait,
            IMarketDispatcher, IMarketDispatcherTrait,
            IOrderbookDispatcher, IOrderbookDispatcherTrait};
    use expectium::tests::mocks::interfaces::{IAccount};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl IAccountImpl of IAccount<ContractState> {
        fn erc20_balance_of(            
            self: @ContractState,
            contract_address: ContractAddress,
            account: ContractAddress
        ) -> u256 {
                IERC20Dispatcher { contract_address }.balanceOf(account)
        }

        fn erc20_transfer(
            self: @ContractState,
            contract_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            IERC20Dispatcher { contract_address }.transfer(recipient, amount);
        }

        fn erc20_approve(
            self: @ContractState,
            contract_address: ContractAddress,
            spender: ContractAddress,
            amount: u256
        ) {
            IERC20Dispatcher { contract_address }.approve(spender, amount);
        }

        fn erc20_transfer_from(
            self: @ContractState,
            contract_address: ContractAddress,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            IERC20Dispatcher { contract_address }.transferFrom(sender, recipient, amount);
        }

        fn factory_transfer_operator(
            self: @ContractState,
            contract_address: ContractAddress,
            new_operator: ContractAddress
        ) {
            IFactoryDispatcher { contract_address }.transfer_operator(new_operator);
        }

        fn factory_change_current_classhash(
            self: @ContractState,
            contract_address: ContractAddress,
            new_hash: ClassHash
        ) {
            IFactoryDispatcher { contract_address }.change_current_classhash(new_hash);
        }

        fn factory_create_market(
            self: @ContractState,
            contract_address: ContractAddress,
            resolver: ContractAddress,
            collateral: ContractAddress
        ) -> (u64, ContractAddress) {
            IFactoryDispatcher { contract_address }.create_market(resolver, collateral)
        }

        fn factory_upgrade_market(
            self: @ContractState,
            contract_address: ContractAddress,
            market_id: u64
        ) {
            IFactoryDispatcher { contract_address }.upgrade_market(market_id);
        }

        fn market_approve(
            self: @ContractState,
            contract_address: ContractAddress,
            spender: ContractAddress
        ) {
            IMarketDispatcher { contract_address }.approve(spender);
        }

        fn market_revoke_approval(
            self: @ContractState,
            contract_address: ContractAddress,
            spender: ContractAddress
        ) {
            IMarketDispatcher { contract_address }.revoke_approval(spender);
        }

        fn market_transfer_from(
            self: @ContractState,
            contract_address: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            asset: Asset,
            amount: u256
        ) {
            IMarketDispatcher { contract_address }.transfer_from(from, to, asset, amount);
        }

        fn market_mint_shares(
            self: @ContractState,
            contract_address: ContractAddress,
            amount: u256
        ) {
            IMarketDispatcher { contract_address }.mint_shares(amount);
        }

        fn market_merge_shares(
            self: @ContractState,
            contract_address: ContractAddress,
            amount: u256
        ) {
            IMarketDispatcher { contract_address }.merge_shares(amount);
        }

        fn market_resolve_market(
            self: @ContractState,
            contract_address: ContractAddress,
            happens: u16,
            not: u16
        ) {
            IMarketDispatcher { contract_address }.resolve_market(happens, not);
        }

        fn market_convert_shares(
            self: @ContractState,
            contract_address: ContractAddress,
            asset: Asset,
            amount: u256
        ) {
            IMarketDispatcher { contract_address }.convert_shares(asset, amount);
        }

        fn orderbook_insert_buy_order(
            self: @ContractState,
            contract_address: ContractAddress,
            asset: Asset,
            amount: u256,
            price: u16
        ) -> u32 {
            IOrderbookDispatcher { contract_address }.insert_buy_order(asset, amount, price)
        }

        fn orderbook_insert_sell_order(
            self: @ContractState,
            contract_address: ContractAddress,
            asset: Asset,
            amount: u256,
            price: u16
        ) -> u32 {
            IOrderbookDispatcher { contract_address }.insert_sell_order(asset, amount, price)
        }
    }
}