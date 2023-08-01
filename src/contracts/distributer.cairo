use starknet::ContractAddress;
#[starknet::interface]
trait IDistributor<TContractState> {
    fn new_distribution(ref self: TContractState, token: ContractAddress, amount: u256); // Distributiona para ekler.
    fn claim(ref self: TContractState, token: ContractAddress, share_id: u256); // tokenid ye ait token fee yi claim eder.
    // views
    fn get_claimable_amount(self: @TContractState, token: ContractAddress, share_id: u256) -> u256;
    fn total_distribution(self: @TContractState, token: ContractAddress) -> u256;
    fn total_distribution_per_share(self: @TContractState, token: ContractAddress) -> u256;
    // operator
}

#[starknet::contract]
mod Distributor {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        registered_tokens: LegacyMap<ContractAddress, bool>, // tokenaddr -> bool
        total_distributions: LegacyMap<ContractAddress, u256>, // tokenaddr -> amount
        claims: LegacyMap<u256, u256>, // share_id -> amount
        operator: ContractAddress
    }

    #[external(v0)]
    impl Distributor of IDistributor<ContractState> {
        fn new_distribution(ref self: ContractState, token: ContractAddress, amount: u256) {
            assert(self.registered_tokens.read(token), 'token is not registered');
            assert(amount > 0, 'amount too low');

            let caller = get_caller_address();
            let this_addr = get_contract_address();

            let balance_before = IERC20Dispatcher { contract_address: token }.balanceOf(this_addr);
            IERC20Dispatcher { contract_address: token }.transferFrom(caller, this_addr, amount);
            let balance_after = IERC20Dispatcher { contract_address: token }.balanceOf(this_addr);

            assert((balance_before + amount) >= balance_after, 'transfer failed');

            self.total_distributions.write(token, self.total_distributions.read(token) + amount);

            let time = get_block_timestamp();
            // event emit
        }

        fn claim(ref self: ContractState, share_id: u256) {

        }
    }
}