use expectium::config::{Asset};
use starknet::{ContractAddress};

#[starknet::interface]
trait IMarket<TContractState> {
    // Views
    fn balance_of(self: TContractState, account: ContractAddress, asset: Asset);
    fn total_supply(self: TContractState, asset: Asset) -> u256;
    fn resolver(self: TContractState) -> ContractAddress;
    fn collateral(self: TContractState) -> ContractAddress; // returns usdc
    fn resolve_rate(self: TContractState) -> (u16, u16);
    // Externals
    fn split_shares(ref self: TContractState, invest: u256); // usdc -> shares
    fn merge_shares(ref self: TContractState, shares: u256); // shares -> usdc
    // Resolvers
    fn resolve_market(ref self: TContractState, happens: u16, not: u16); // 10000 üzerinden resolve rate
}

#[starknet::contract]
mod Market {
    use expectium::config::{Asset};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        balances: LegacyMap<(Asset, ContractAddress), u256>, // TODO: Asset tipi için legacy hash
        supplies: LegacyMap<Asset, u256>,
        collateral: ContractAddress,
        resolver: ContractAddress,
        resolve_ratio: LegacyMap<Asset, u16>
    }

    #[external(v0)]
    #[generate_trait]
    impl Market of IMarket {
        fn balance_of(self: @ContractState, account: ContractAddress, asset: Asset) -> u256 {
            self.balances.read((asset, account))
        }

        fn total_supply(self: @ContractState, asset: Asset) -> u256 {
            self.supplies.read(asset)
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

        // Externals
        fn split_shares(ref self: ContractState, invest: u256) {
            // 1) Receive collateral with invest amount to this contract.
            // 2) Increase caller balance of both assets (happens & not)
        }

        fn merge_shares(ref self: ContractState, shares: u256) {
            // 1) Burn shares amount of on both assets from caller balance
            // 2) send shares amount collateral
        }

        // Only Resolver
        fn resolve_market(ref self: ContractState, happens: u16, not: u16) {
            let caller = get_caller_address();
            assert(caller == self.resolver.read(), 'only resolver');
            assert((happens + not) == 10000, 'wrong ratio');
            assert(_is_resolved(@self), 'already resolved'); // Kontrol et çalışıyor mu?

            self.resolve_ratio.write(Asset::Happens(()), happens);
            self.resolve_ratio.write(Asset::Not(()), not);
        }
    }


    fn _is_resolved(self: @ContractState) -> bool {
        let happens_ratio = self.resolve_ratio.read(Asset::Happens(()));
        let not_ratio = self.resolve_ratio.read(Asset::Not(()));

        (happens_ratio + not_ratio) == 10000
    }


}