use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait, 
                                        IMockSharesDispatcher, IMockSharesDispatcherTrait};
use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait,
                            IOrderbookDispatcher, IOrderbookDispatcherTrait,
                            IDistributorDispatcher, IDistributorDispatcherTrait};
use expectium::tests::deploy;

use debug::PrintTrait;

#[derive(Drop)]
struct Setup {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    shares: IMockSharesDispatcher,
    distributor: IDistributorDispatcher
}

fn setup() -> Setup {
    let operator = deploy::deploy_account();
    let alice = deploy::deploy_account();
    let bob = deploy::deploy_account();

    let mock_shares = deploy::deploy_mock_shares();
    let distributor = deploy::deploy_distributor(operator.contract_address, mock_shares.contract_address);

    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        10000000000000000000, // 10 ether
        operator.contract_address
    );

    operator.distributor_register_token(distributor.contract_address, collateral.contract_address); // Register usdc as distribution token.

    Setup { operator, alice, bob, collateral, shares: mock_shares, distributor }
}

fn setup_with_nfts_minted() -> Setup {
    let setup = setup();

    setup.operator.mock_shares_set_owner(setup.shares.contract_address, 0, setup.alice.contract_address); //0,1,2 alice
    setup.operator.mock_shares_set_owner(setup.shares.contract_address, 1, setup.alice.contract_address);
    setup.operator.mock_shares_set_owner(setup.shares.contract_address, 2, setup.alice.contract_address);
    setup.operator.mock_shares_set_owner(setup.shares.contract_address, 3, setup.bob.contract_address); // 4,5 bob
    setup.operator.mock_shares_set_owner(setup.shares.contract_address, 4, setup.bob.contract_address);

    setup
}

fn setup_with_nfts_minted_and_distribution_added() -> Setup {
    let setup = setup_with_nfts_minted();

    let operator = setup.operator;
    let distributor = setup.distributor;

    operator.erc20_approve(setup.collateral.contract_address, distributor.contract_address, integer::BoundedInt::max());

    operator.distributor_new_distribution(distributor.contract_address, setup.collateral.contract_address, 1000000000000000000); // 1 ether

    operator.distributor_toggle_claims(distributor.contract_address);

    setup
}

#[test]
#[available_gas(1000000000)]
fn test_initial_values() {
    let setup = setup();

    let distributor = setup.distributor;
    let shares = setup.shares;

    assert(shares.contract_address == distributor.shares(), 'Shares address wrong');
    assert(!distributor.is_claims_available(), 'initial claims wrong');
    assert(distributor.get_claimable_amount(setup.collateral.contract_address, 0) == 0 , 'initial claims wrong');
    assert(distributor.total_distribution(setup.collateral.contract_address) == 0, 'total dist wrong');
    assert(distributor.total_distribution_per_share(setup.collateral.contract_address) == 0, 'total dist per share wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_new_distribution() {
   let setup = setup_with_nfts_minted_and_distribution_added();

   let operator = setup.operator;
   let distributor = setup.distributor;

   assert(distributor.total_distribution(setup.collateral.contract_address) == 1000000000000000000, 'distribution wrong');
   assert(distributor.total_distribution_per_share(setup.collateral.contract_address) <= 100000000000000, 'distribution per wrong'); // 1/10000 * total -1
   assert(distributor.get_claimable_amount(setup.collateral.contract_address, 0) <= 100000000000000, 'availabe claim wrong');
   // Per share returns a little bit lower than exact value bcs of rounding issues,
}

#[test]
#[available_gas(1000000000)]
fn test_claim_and_check_available() {
    let setup = setup_with_nfts_minted_and_distribution_added();

    let alice = setup.alice;
    let distributor = setup.distributor;
    let collateral = setup.collateral;

    let balance_before = collateral.balanceOf(alice.contract_address);

    let claim_amount = distributor.get_claimable_amount(setup.collateral.contract_address, 0);

    alice.distributor_claim(distributor.contract_address, collateral.contract_address, 0);

    let balance_after = collateral.balanceOf(alice.contract_address);

    assert((balance_after - balance_before) == claim_amount, 'claim wrong');

    let claims_left = distributor.get_claimable_amount(setup.collateral.contract_address, 0);

    assert(claims_left == 0, 'claim left wrong');

    let claims_second = distributor.get_claimable_amount(setup.collateral.contract_address, 1);
    assert(claims_second == claim_amount, 'second claim wrong');

}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('already claimed', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_zero_claim() {
    let setup = setup_with_nfts_minted_and_distribution_added();
    let alice = setup.alice;
    let distributor = setup.distributor;
    let collateral = setup.collateral;

    alice.distributor_claim(distributor.contract_address, collateral.contract_address, 0); // first claim ok
    alice.distributor_claim(distributor.contract_address, collateral.contract_address, 0);
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('only owner can claim', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_claim_non_owner() {
    let setup = setup_with_nfts_minted_and_distribution_added();

    let bob = setup.bob;
    let distributor = setup.distributor;
    let collateral = setup.collateral;

    bob.distributor_claim(distributor.contract_address, collateral.contract_address, 0);
}

#[test]
#[available_gas(1000000000)]
fn test_claim_and_reclaim_with_new_distribution() {
    let setup = setup_with_nfts_minted_and_distribution_added();

    let alice = setup.alice;
    let operator = setup.operator;
    let distributor = setup.distributor;
    let collateral = setup.collateral;

    let balance_before = collateral.balanceOf(alice.contract_address);

    let claim_amount = distributor.get_claimable_amount(setup.collateral.contract_address, 0);

    alice.distributor_claim(distributor.contract_address, collateral.contract_address, 0);

    let balance_after = collateral.balanceOf(alice.contract_address);

    assert((balance_after - balance_before) == claim_amount, 'claim wrong');

    let claims_left = distributor.get_claimable_amount(setup.collateral.contract_address, 0);

    assert(claims_left == 0, 'claim left wrong');

    let claims_second = distributor.get_claimable_amount(setup.collateral.contract_address, 1);
    assert(claims_second == claim_amount, 'second claim wrong');

    operator.distributor_new_distribution(distributor.contract_address, setup.collateral.contract_address, 1000000000000000000); // 1 ether more distro.

    let first_share_claims = distributor.get_claimable_amount(setup.collateral.contract_address, 0);
    let second_share_claims = distributor.get_claimable_amount(setup.collateral.contract_address, 1);

    assert(first_share_claims <= 100000000000000, 'first share claim wrong');
    assert(second_share_claims <= 200000000000000, 'second share claim wrong');

    alice.distributor_claim(distributor.contract_address, collateral.contract_address, 0);

    let balance_after_second_claim = collateral.balanceOf(alice.contract_address);

    assert((balance_after_second_claim - balance_after) == first_share_claims, 'second claim wrong');

    let claims_left = distributor.get_claimable_amount(setup.collateral.contract_address, 0);

    assert(claims_left == 0, 'claim left wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_contract_solvency() {
    let setup = setup_with_nfts_minted_and_distribution_added();

    let alice = setup.alice;
    let operator = setup.operator;
    let distributor = setup.distributor;
    let collateral = setup.collateral;

    let total_distribution_per_share = distributor.total_distribution_per_share(collateral.contract_address);

    let contract_balance = collateral.balanceOf(distributor.contract_address);

    assert(contract_balance >= (total_distribution_per_share * 10000), 'insolvent');
}