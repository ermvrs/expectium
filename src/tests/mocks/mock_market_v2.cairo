#[starknet::contract]
mod MockMarket {
    use expectium::tests::mocks::interfaces::IMockMarketV2;


    #[storage]
    struct Storage {
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[external(v0)]
    impl MockMarket of IMockMarketV2<ContractState> {
        fn market_id(self: @ContractState) -> u64 {
            2_u64
        }
    }

}