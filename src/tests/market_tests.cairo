use starknet::{ContractAddress, contract_address_const, ClassHash};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait};
use expectium::tests::mocks::mock_market_v2::MockMarket;
use expectium::interfaces::{IFactoryDispatcher, IFactoryDispatcherTrait, IMarketDispatcher, 
                            IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
                            };
use expectium::tests::deploy;
use expectium::types::Asset;
use expectium::contracts::market::Market;
use expectium::contracts::distributor::Distributor;
use traits::{Into, TryInto};
use option::OptionTrait;

#[derive(Drop)]
struct Setup {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    market: IMarketDispatcher,
    factory: IFactoryDispatcher
}

fn setup() -> Setup {
    let operator = deploy::deploy_account();
    let alice = deploy::deploy_account();
    let bob = deploy::deploy_account();

    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        10000000000000000000, // 10 ether
        operator.contract_address
    );

    operator.erc20_transfer(collateral.contract_address, alice.contract_address, 5000000000000000000);

    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    let (_, market) = operator.factory_create_market(factory.contract_address, operator.contract_address, collateral.contract_address);

    Setup { operator, alice, bob, collateral, market: IMarketDispatcher { contract_address: market}, factory }
}

fn setup_with_mergeshares() -> Setup {
    let operator = deploy::deploy_account();
    let alice = deploy::deploy_account();
    let bob = deploy::deploy_account();

    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        10000000000000000000, // 10 ether
        operator.contract_address
    );

    operator.erc20_transfer(collateral.contract_address, alice.contract_address, 5000000000000000000);

    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    let (_, market) = operator.factory_create_market(factory.contract_address, operator.contract_address, collateral.contract_address);

    alice.erc20_approve(collateral.contract_address, market, 1000000000000000000); // 1 ether
    alice.market_mint_shares(market, 1000000000000000000);

    Setup { operator, alice, bob, collateral, market: IMarketDispatcher { contract_address: market }, factory }
}

#[test]
#[available_gas(1000000000)]
fn test_initial_values() {
    let setup = setup();

    assert(setup.collateral.balance_of(setup.operator.contract_address) == 5000000000000000000, 'init bal wrong');
    assert(setup.collateral.balance_of(setup.alice.contract_address) == 5000000000000000000, 'init bal wrong');

    assert(setup.market.balance_of(setup.operator.contract_address, Asset::Happens(())) == 0, 'init mrk bal wrong');
    assert(setup.market.balance_of(setup.operator.contract_address, Asset::Not(())) == 0, 'init mrk bal wrong');
    
    assert(setup.market.total_supply(Asset::Not(())) == 0, 'init supply wrong');

    assert(setup.market.collateral() == setup.collateral.contract_address, 'collateral wrong');
    assert(setup.market.resolver() == setup.operator.contract_address, 'operator wrong');
    assert(setup.market.factory() == setup.factory.contract_address, 'factory wrong');
    assert(setup.market.is_resolved() == false, 'resolved wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_mint_merge_shares() {
    let setup = setup();

    setup.alice.erc20_approve(setup.collateral.contract_address, setup.market.contract_address, 1000000000000000000); // 1 ether
    setup.alice.market_mint_shares(setup.market.contract_address, 1000000000000000000);

    assert(setup.market.balance_of(setup.alice.contract_address, Asset::Happens(())) == 1000000000000000000, 'wrong happens bal');
    assert(setup.market.balance_of(setup.alice.contract_address, Asset::Not(())) == 1000000000000000000, 'wrong not bal');

    // merge_shares

    assert(setup.collateral.balance_of(setup.alice.contract_address) == 4000000000000000000, 'usdc bal wrong');

    setup.alice.market_merge_shares(setup.market.contract_address, 1000000000000000000);

    assert(setup.market.balance_of(setup.alice.contract_address, Asset::Happens(())) == 0, 'MRG wrong happens bal');
    assert(setup.market.balance_of(setup.alice.contract_address, Asset::Not(())) == 0, 'MRG wrong not bal');
    assert(setup.collateral.balance_of(setup.alice.contract_address) == 5000000000000000000, 'MRG usdc bal wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('not allowed spender', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_transfer_without_approval() {
    let setup = setup();

    let alice = setup.alice;
    let bob = setup.bob;
    let spender = setup.operator;
    let collateral = setup.collateral;
    let market = setup.market;

    spender.market_transfer_from(market.contract_address, alice.contract_address, bob.contract_address, Asset::Happens(()), 1000000000000000000);
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('amount exceeds bal', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_transfer_exceeds_balance() {
    let setup = setup();

    let alice = setup.alice;
    let bob = setup.bob;
    let spender = setup.operator;
    let collateral = setup.collateral;
    let market = setup.market;

    alice.market_approve(market.contract_address, spender.contract_address);

    spender.market_transfer_from(market.contract_address, alice.contract_address, bob.contract_address, Asset::Happens(()), 1000000000000000000);
}

#[test]
#[available_gas(1000000000)]
fn test_transfer_from() {
    let setup = setup_with_mergeshares();

    let alice = setup.alice;
    let bob = setup.bob;
    let spender = setup.operator;
    let collateral = setup.collateral;
    let market = setup.market;

    assert(market.balance_of(alice.contract_address, Asset::Happens(())) == 1000000000000000000, 'alice bal wrong');
    assert(market.balance_of(bob.contract_address, Asset::Happens(())) == 0, 'bob bal wrong');

    alice.market_approve(market.contract_address, spender.contract_address);

    spender.market_transfer_from(market.contract_address, alice.contract_address, bob.contract_address, Asset::Happens(()), 1000000000000000000);

    assert(market.balance_of(alice.contract_address, Asset::Happens(())) == 0, 'alice bal wrong');
    assert(market.balance_of(bob.contract_address, Asset::Happens(())) == 1000000000000000000, 'bob bal wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_resolve_market() {
    let setup = setup();

    setup.operator.market_resolve_market(setup.market.contract_address, 10000_u16, 0_u16);

    assert(setup.market.is_resolved(), 'resolved wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_convert_shares() {
    let setup = setup_with_mergeshares();

    let alice = setup.alice;
    let bob = setup.bob;
    let operator = setup.operator;
    let collateral = setup.collateral;
    let market = setup.market;
    
    operator.market_resolve_market(market.contract_address, 10000_u16, 0_u16);

    assert(setup.market.is_resolved(), 'resolved wrong');

    
    let balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    assert(balance == 1000000000000000000, 'alice bal wrong');

    let usdc_bal = collateral.balance_of(alice.contract_address);

    alice.market_convert_shares(market.contract_address, Asset::Happens(()), balance);

    assert(market.balance_of(alice.contract_address, Asset::Happens(())) == 0, 'alice bal wrong');

    let usdc_bal_after = collateral.balance_of(alice.contract_address);

    assert((usdc_bal_after - usdc_bal) == 1000000000000000000, 'convert collat wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('only resolver', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_try_resolve_unauthorized() {
    let setup = setup_with_mergeshares();

    let alice = setup.alice;
    let market = setup.market;

    alice.market_resolve_market(market.contract_address, 10000_u16, 0_u16);
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('wrong ratio', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_try_resolve_wrong_ratio() {
    let setup = setup_with_mergeshares();

    let operator = setup.operator;
    let market = setup.market;

    operator.market_resolve_market(market.contract_address, 5000_u16, 4000_u16);
}

#[test]
#[available_gas(1000000000)]
fn test_upgrade_via_factory() {
    let setup = setup_with_mergeshares();

    let operator = setup.operator;
    let market = setup.market;
    let factory = setup.factory;

    let current_market_id = market.market_id();
    assert(current_market_id == 0, 'market id wrong');

    let new_hash: ClassHash = MockMarket::TEST_CLASS_HASH.try_into().unwrap();

    operator.factory_change_current_classhash(factory.contract_address, new_hash);

    operator.factory_upgrade_market(factory.contract_address, current_market_id);

    let final_market_id = market.market_id();

    assert(final_market_id == 2, 'final id wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('ERC20_INSUFFICIENT_ALLOWANCE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_mint_without_approval() {
    let setup = setup();

    setup.alice.market_mint_shares(setup.market.contract_address, 1000000000000000000);
}