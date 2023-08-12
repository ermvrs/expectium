#[starknet::contract]
mod Account {
    use starknet::{ContractAddress, ClassHash};
    use expectium::config::Asset;
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, 
            IFactoryDispatcher, IFactoryDispatcherTrait,
            IMarketDispatcher, IMarketDispatcherTrait,
            IOrderbookDispatcher, IOrderbookDispatcherTrait,
            IDistributorDispatcher, IDistributorDispatcherTrait};
    use expectium::tests::mocks::interfaces::{IAccount, IMockSharesDispatcher, IMockSharesDispatcherTrait};

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

        fn orderbook_cancel_buy_order(
            self: @ContractState,
            contract_address: ContractAddress,
            asset: Asset,
            order_id: u32
        ) {
            IOrderbookDispatcher { contract_address }.cancel_buy_order(asset, order_id);
        }

        fn orderbook_cancel_sell_order(
            self: @ContractState,
            contract_address: ContractAddress,
            asset: Asset,
            order_id: u32
        ) {
            IOrderbookDispatcher { contract_address }.cancel_sell_order(asset, order_id);
        }

        fn distributor_claim(
                self: @ContractState,
                contract_address: ContractAddress,
                token: ContractAddress,
                share_id: u256
        ) {
            IDistributorDispatcher { contract_address }.claim(token, share_id)
        }

        fn distributor_register_token(
                self: @ContractState,
                contract_address: ContractAddress,
                token: ContractAddress
        ) {
            IDistributorDispatcher { contract_address }.register_token(token)
        }

        fn distributor_toggle_claims(
                self: @ContractState,
                contract_address: ContractAddress
        ) {
            IDistributorDispatcher { contract_address }.toggle_claims()
        }

        fn distributor_upgrade_contract(
                self: @ContractState,
                contract_address: ContractAddress,
                new_class: ClassHash
        ) {
            IDistributorDispatcher { contract_address }.upgrade_contract(new_class)
        }

        fn distributor_transfer_operator(
                self: @ContractState,
                contract_address: ContractAddress,
                new_operator: ContractAddress
        ) {
            IDistributorDispatcher { contract_address }.transfer_operator(new_operator)
        }

        fn mock_shares_set_owner(
                self: @ContractState,
                contract_address: ContractAddress,
                token_id: u256,
                owner: ContractAddress
        ) {
            IMockSharesDispatcher { contract_address }.set_owner(token_id, owner)
        }
    }
}