#[starknet::contract]
mod Market {
    use expectium::config::{Asset};
    use starknet::{ContractAddress, get_caller_address, get_contract_address, ClassHash, replace_class_syscall};
    use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, IMarket};
    use traits::{Into, TryInto};

    #[storage]
    struct Storage {
        balances: LegacyMap<(Asset, ContractAddress), u256>, 
        supplies: LegacyMap<Asset, u256>,
        allowances: LegacyMap<(ContractAddress, ContractAddress), bool>, // owner -> spender -> bool
        collateral: ContractAddress,
        resolver: ContractAddress,
        resolve_ratio: LegacyMap<Asset, u16>,
        factory: ContractAddress,
        market_id: u64, // defined market id from factory
    }

    #[constructor]
    fn constructor(ref self: ContractState, id: u64) {
        let caller = get_caller_address();

        self.factory.write(caller);
        self.market_id.write(id);
    }

    #[external(v0)]
    impl Market of IMarket<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress, asset: Asset) -> u256 {
            self.balances.read((asset, account))
        }

        fn total_supply(self: @ContractState, asset: Asset) -> u256 {
            self.supplies.read(asset)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> bool {
            self.allowances.read((owner, spender))
        }

        fn resolver(self: @ContractState) -> ContractAddress {
            self.resolver.read()
        }

        fn collateral(self: @ContractState) -> ContractAddress {
            self.collateral.read()
        }

        fn resolve_rate(self: @ContractState) -> (u16, u16) {
            let happens_ratio = self.resolve_ratio.read(Asset::Happens(()));
            let not_ratio = self.resolve_ratio.read(Asset::Not(()));

            (happens_ratio, not_ratio)
        }

        fn market_id(self: @ContractState) -> u64 {
            self.market_id.read()
        }

        // Externals
        fn split_shares(ref self: ContractState, invest: u256) {
            // 1) Receive collateral with invest amount to this contract.
            // 2) Increase caller balance of both assets (happens & not)
            let caller = get_caller_address();
            _receive_collateral(ref self, caller, invest);

            self.balances.write((Asset::Happens(()), caller), self.balances.read((Asset::Happens(()), caller)) + invest);
            self.balances.write((Asset::Not(()), caller), self.balances.read((Asset::Not(()), caller)) + invest);

            self.supplies.write(Asset::Happens(()), self.supplies.read(Asset::Happens(())) + invest);
            self.supplies.write(Asset::Not(()), self.supplies.read(Asset::Not(())) + invest);
        }

        fn merge_shares(ref self: ContractState, shares: u256) {
            // 1) Burn shares amount of on both assets from caller balance
            // 2) send shares amount collateral

            let caller = get_caller_address();

            self.balances.write((Asset::Happens(()), caller), self.balances.read((Asset::Happens(()), caller)) - shares);
            self.balances.write((Asset::Not(()), caller), self.balances.read((Asset::Not(()), caller)) - shares);

            self.supplies.write(Asset::Happens(()), self.supplies.read(Asset::Happens(())) - shares);
            self.supplies.write(Asset::Not(()), self.supplies.read(Asset::Not(())) - shares);

            _transfer_collateral(ref self, caller, shares);
        }

        fn convert_shares(ref self: ContractState, asset: Asset, amount: u256) {
            assert(_is_resolved(@self), 'already resolved');

            let caller = get_caller_address();

            self.balances.write((asset, caller), self.balances.read((asset, caller)) - amount); // remove asset
            self.supplies.write(asset, self.supplies.read(asset) - amount); // remove supply

            let resolve_ratio = self.resolve_ratio.read(asset);

            let collateral_turnback: u256 = (resolve_ratio.into() * amount) / 10000;
            assert(collateral_turnback <= amount, 'turnback higher'); // turnback amounttan fazla olamaz.

            _transfer_collateral(ref self, caller, collateral_turnback);
        }

        fn approve(ref self: ContractState, spender: ContractAddress) {
            let caller = get_caller_address();

            self.allowances.write((caller, spender), true);
        }

        fn revoke_approval(ref self: ContractState, spender: ContractAddress) {
            let caller = get_caller_address();

            self.allowances.write((caller, spender), false);
        }

        fn transfer_from(ref self: ContractState, from: ContractAddress, to: ContractAddress, asset: Asset, amount: u256) {
            let caller = get_caller_address();
            assert(_is_allowed_spender(@self, from, caller), 'not allowed spender');

            let owner_balance = self.balances.read((asset, from));
            assert(owner_balance >= amount, 'amount exceeds bal');

            self.balances.write((asset, from), owner_balance - amount);
            self.balances.write((asset, to), self.balances.read((asset, to)) + amount);
        }

        fn transfer(ref self: ContractState, to: ContractAddress, asset: Asset, amount: u256) {
            let caller = get_caller_address();
            let current_balance = self.balances.read((asset, caller));

            assert(current_balance >= amount, 'amount exceeds bal');

            self.balances.write((asset, caller), current_balance - amount);
            self.balances.write((asset, to), self.balances.read((asset, to)) + amount);
        }

        // Only Resolver
        fn resolve_market(ref self: ContractState, happens: u16, not: u16) {
            let caller = get_caller_address();
            assert(caller == self.resolver.read(), 'only resolver');
            assert((happens + not) == 10000, 'wrong ratio');
            assert(!_is_resolved(@self), 'already resolved'); // Kontrol et çalışıyor mu?

            self.resolve_ratio.write(Asset::Happens(()), happens);
            self.resolve_ratio.write(Asset::Not(()), not);
        }

        fn upgrade_market(ref self: ContractState, new_class: ClassHash) {
            _assert_only_factory(@self);

            replace_class_syscall(new_class);
        }
    }

    fn _is_resolved(self: @ContractState) -> bool {
        let happens_ratio = self.resolve_ratio.read(Asset::Happens(()));
        let not_ratio = self.resolve_ratio.read(Asset::Not(()));

        (happens_ratio + not_ratio) == 10000
    }

    fn _receive_collateral(ref self: ContractState, from: ContractAddress, amount: u256) {
        let this_addr = get_contract_address();
        let balanceBefore = IERC20Dispatcher { contract_address: self.collateral.read()}.balanceOf(this_addr);

        IERC20Dispatcher { contract_address: self.collateral.read() }.transferFrom(from, this_addr, amount);

        let balanceAfter = IERC20Dispatcher { contract_address: self.collateral.read()}.balanceOf(this_addr);
        assert((balanceAfter - amount) >= balanceBefore, 'EXPM: transfer fail')
    }

    fn _transfer_collateral(ref self: ContractState, to: ContractAddress, amount: u256) {
        IERC20Dispatcher { contract_address: self.collateral.read() }.transfer(to, amount);
    }

    fn _is_allowed_spender(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> bool {
        if(owner == spender) {
            return true;
        }
        self.allowances.read((owner, spender))
    }

    fn _assert_only_factory(self: @ContractState) {
        let caller = get_caller_address();
        let factory = self.factory.read();

        assert(caller == factory, 'only factory');
    }
}