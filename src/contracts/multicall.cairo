use starknet::ContractAddress;

#[derive(Drop, Serde, PartialEq)]
struct SharesUserInfoResponse {
    user_share_ids: Array<u128>
}

#[starknet::interface]
trait IMulticall<TState> {
    fn get_shares_user_info(self: @TState, shares: ContractAddress, user: ContractAddress) -> SharesUserInfoResponse; // u256 gerek yok
}

#[starknet::contract]
mod Multicall {
    use expectium::interfaces::{ISharesDispatcher, ISharesDispatcherTrait};
    use starknet::ContractAddress;
    use array::{ArrayTrait, SpanTrait};
    use super::SharesUserInfoResponse;

    #[storage]
    struct Storage {}
    
    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[external(v0)]
    impl Multicall of super::IMulticall<ContractState> {
        fn get_shares_user_info(self: @ContractState, shares: ContractAddress, user: ContractAddress) -> SharesUserInfoResponse {
            let mut i = 1;
            let dispatcher = ISharesDispatcher { contract_address: shares };
            let total_supply = dispatcher.total_supply();
            let mut owned_by = ArrayTrait::<u128>::new();

            loop {
                if(total_supply < i) {
                    break;
                }
                let owner = dispatcher.owner_of(i.into());
                if(owner == user) {
                    owned_by.append(i.low);
                }
                i = i + 1;
            };

            return SharesUserInfoResponse {
                user_share_ids: owned_by
            };
        }
    }
}