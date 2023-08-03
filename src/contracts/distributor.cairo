use starknet::{ContractAddress, ClassHash};
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
    fn register_token(ref self: TContractState, token: ContractAddress);
    fn upgrade_contract(ref self: TContractState, new_class: ClassHash);
    fn transfer_operator(ref self: TContractState, new_operator: ContractAddress);
}

#[starknet::contract]
mod Distributor {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp, ClassHash, replace_class_syscall};
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, ISharesDispatcher, ISharesDispatcherTrait};
    use super::IDistributor;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Claimed: Claimed,
        NewDistribution: NewDistribution,
        OperatorChanged: OperatorChanged,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct Claimed {
        claimer: ContractAddress,
        token: ContractAddress,
        amount: u256,
        time: u64
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct NewDistribution {
        token: ContractAddress,
        amount: u256,
        time: u64
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct OperatorChanged {
        old_operator: ContractAddress,
        new_operator: ContractAddress,
    }

    #[storage]
    struct Storage {
        shares: ContractAddress, // expectium shares
        registered_tokens: LegacyMap<ContractAddress, bool>, // tokenaddr -> bool
        total_distributions: LegacyMap<ContractAddress, u256>, // tokenaddr -> amount
        claims: LegacyMap<u256, u256>, // share_id -> amount
        operator: ContractAddress,
        available: bool, // is claims available
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        operator: ContractAddress,
        shares: ContractAddress
    ) {
        self.shares.write(shares);
        self.operator.write(operator);
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

        fn total_distribution(self: @ContractState, token: ContractAddress) -> u256 {
            self.total_distributions.read(token)
        }

        fn total_distribution_per_share(self: @ContractState, token: ContractAddress) -> u256 {
            _total_distribution_per_share(self, token)
        }

        fn is_claims_available(self: @ContractState) -> bool {
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

            self.emit(Event::NewDistribution(
                        NewDistribution { token: token, amount: amount, time: time }
                    ));
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

            let time = get_block_timestamp();
            // event emit

            self.emit(Event::Claimed(
                        Claimed { claimer: owner, token: token, amount: net_amount, time: time }
                    ));
        }

        fn toggle_claims(ref self: ContractState) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            self.available.write(!self.available.read())
        }

        fn register_token(ref self: ContractState, token: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');
        }

        fn upgrade_contract(ref self: ContractState, new_class: ClassHash) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            replace_class_syscall(new_class);
        }

        fn transfer_operator(ref self: ContractState, new_operator: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            self.operator.write(new_operator);

            self.emit(Event::OperatorChanged(
                OperatorChanged { old_operator: caller, new_operator: new_operator }
            ));
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