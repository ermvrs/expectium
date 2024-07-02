#[starknet::contract]
mod MockShares {
    use expectium::tests::mocks::interfaces::IMockShares;
    use starknet::ContractAddress;


    #[storage]
    struct Storage {
        owners: LegacyMap<u256, ContractAddress>
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[external(v0)]
    impl MockShares of IMockShares<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            0_u256
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(token_id)
        }

        fn set_owner(ref self: ContractState, token_id: u256, owner: ContractAddress) {
            self.owners.write(token_id, owner)
        }
    }
}
