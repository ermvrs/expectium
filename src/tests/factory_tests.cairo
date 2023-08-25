use starknet::{ContractAddress, contract_address_const, ClassHash};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait};
use expectium::interfaces::{IFactoryDispatcher, IFactoryDispatcherTrait, IMarketDispatcher, IMarketDispatcherTrait};
use debug::PrintTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use expectium::tests::deploy;
use expectium::contracts::market::Market;
use expectium::contracts::distributor::Distributor;

#[derive(Drop)]
struct Config {
    operator: IAccountDispatcher,
    initial_hash: ClassHash,
    factory: IFactoryDispatcher
}

fn setup() -> Config {
    let operator = deploy::deploy_account();
    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    Config { initial_hash: market_classhash, operator, factory }
}

#[test]
#[available_gas(1000000000)]
fn test_operator() {
    let setup = setup();
    assert(setup.factory.operator() == setup.operator.contract_address.into(), 'operator wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_operator_transfer() {
    let setup = setup();
    let new_operator = deploy::deploy_account();

    setup.operator.factory_transfer_operator(setup.factory.contract_address, new_operator.contract_address);

    assert(setup.factory.operator() == new_operator.contract_address.into(), 'operator transfer fails');
}

#[test]
#[available_gas(10000000000)]
fn test_market_hash() {
    let setup = setup();

    let current_hash: ClassHash = setup.factory.current_hash();

    assert(current_hash == setup.initial_hash, 'init hash wrong');

    let new_hash: ClassHash = Distributor::TEST_CLASS_HASH.try_into().unwrap();

    setup.operator.factory_change_current_classhash(setup.factory.contract_address, new_hash);

    assert(setup.factory.current_hash() == new_hash, 'change hash wrong');
}

#[test]
#[available_gas(10000000000)]
fn test_create_market() {
    let setup = setup();

    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        1000000000000000000, // 1 ether
        setup.operator.contract_address
    );

    let (market_id, market) = setup.operator.factory_create_market(setup.factory.contract_address, setup.operator.contract_address, collateral.contract_address);

    assert(market_id == 0, 'market id wrong');

    let resolver: ContractAddress = IMarketDispatcher { contract_address: market }.resolver();
    let market_id_from_contract: u64 = IMarketDispatcher { contract_address: market }.market_id();

    assert(resolver == setup.operator.contract_address, 'resolver wrong');
    assert(market_id_from_contract == 0, 'market id cont wrong');
}

#[test]
#[available_gas(10000000000)]
fn test_market_linking() {
    let setup = setup();

    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        1000000000000000000, // 1 ether
        setup.operator.contract_address
    );
    
    let (market_id, market) = setup.operator.factory_create_market(setup.factory.contract_address, setup.operator.contract_address, collateral.contract_address);

    let market_addr_on_factory = setup.factory.get_market_from_id(market_id);
    assert(market_addr_on_factory == market, 'addr wrong');

    let is_market = setup.factory.is_market_registered(market);
    assert(is_market, 'is market wrong');

    let market: IMarketDispatcher = IMarketDispatcher { contract_address: market };

    let factory_addr_from_market = market.factory();
    assert(factory_addr_from_market == setup.factory.contract_address, 'factory addr wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('only operator', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_operator_assertion() {
    let setup = setup();
    let new_operator = deploy::deploy_account();

    new_operator.factory_transfer_operator(setup.factory.contract_address, setup.operator.contract_address);
}