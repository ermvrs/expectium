use starknet::ContractAddress;
#[starknet::interface]
trait IDistributor<TContractState> {
    fn new_distribution(ref self: TContractState, token: ContractAddress, amount: u256); // Distributiona para ekler.
    fn claim(ref self: TContractState, token: ContractAddress, share_id: u256); // tokenid ye ait token fee yi claim eder.
    // views
    fn get_claimable_amount(self: @TContractState, token: ContractAddress, share_id: u256) -> u256;
    fn total_distribution(self: @TContractState, token: ContractAddress) -> u256;
    fn total_distribution_per_share(self: @TContractState, token: ContractAddress) -> u256;
    fn is_claims_available(self: @TContractState) -> bool;
    // operator
    fn toggle_claims(ref self: TContractState);
}

#[starknet::contract]
mod Distributor {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, ISharesDispatcher, ISharesDispatcherTrait};

    #[storage]
    struct Storage {
        shares: ContractAddress, // expectium shares
        registered_tokens: LegacyMap<ContractAddress, bool>, // tokenaddr -> bool
        total_distributions: LegacyMap<ContractAddress, u256>, // tokenaddr -> amount
        claims: LegacyMap<u256, u256>, // share_id -> amount
        operator: ContractAddress,
        available: bool, // is claims available
    }

    #[external(v0)]
    impl Distributor of IDistributor<ContractState> {
        fn get_claimable_amount(self: @ContractState, token: ContractAddress, share_id: u256) -> u256 {
            assert(self.registered_tokens.read(token), 'token is not registered');
            assert(share_id <= 10000, 'share id wrong');

            let total_distribution: u256 = _total_distribution_per_share(self, token);
            let already_claimed: u256 = self.claims.read(share_id);

            total_distribution - already_claimed
        }

        fn total_distribution(self: @TContractState, token: ContractAddress) -> u256 {
            self.total_distributions.read(token)
        }

        fn total_distribution_per_share(self: @TContractState, token: ContractAddress) -> u256 {
            _total_distribution_per_share(token)
        }

        fn is_claims_available(self: @TContractState) -> bool {
            self.available.read()
        }

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

        fn claim(ref self: ContractState, token: ContractAddress, share_id: u256) {
            assert(self.registered_tokens.read(token), 'token is not registered');

            assert(share_id <= 10000, 'share id wrong');
            let owner: ContractAddress = ISharesDispatcher { contract_address: self.shares.read() }.owner_of(share_id);

            let caller = get_caller_address();

            assert(caller == owner, 'only owner can claim');

            let already_claimed = self.claims.read(share_id);

            let total_distribution = _total_distribution_per_share(@self, token);

            assert(total_distribution >= 0, 'no claimable');

            let net_amount = total_distribution - already_claimed;

            assert(net_amount >= 0, 'already claimed');

            self.claims.write(share_id, total_distribution);

            IERC20Dispatcher{ contract_address: token }.transfer(owner, net_amount);

            // event emit
        }

        fn toggle_claims(ref self: TContractState) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            self.available.write(!self.available.read())
        }
    }

    fn _total_distribution_per_share(self: @ContractState, token: ContractAddress) -> u256 {
        assert(self.registered_tokens.read(token), 'token is not registered');

        let total_distribution: u256 = self.total_distributions.read(token);
        
        if(total_distribution <= 10000) {
            return 0;
        }

        total_distribution - 1 / 10000
    }
}