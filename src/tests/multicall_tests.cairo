use expectium::interfaces::{IMulticallDispatcher, IMulticallDispatcherTrait, IMarketDispatcher, 
                            IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IFactoryDispatcher};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait};
use expectium::tests::deploy;
use expectium::types::{Call, Response};
use expectium::contracts::market::Market;
use starknet::{ContractAddress, contract_address_const, ClassHash};
use traits::{Into, TryInto};
use option::OptionTrait;
use array::{ArrayTrait, SpanTrait};
use debug::PrintTrait;

#[derive(Drop)]
struct Config {
    multicall: IMulticallDispatcher,
    market: IMarketDispatcher,
    operator: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    factory: IFactoryDispatcher
}

fn setup() -> Config {
    let operator = deploy::deploy_account();
    let multicall = deploy::deploy_multicall();
    let collateral = deploy::deploy_erc20(
        'TEST USDC',
        'TUSDC',
        18,
        10000000000000000000, // 10 ether
        operator.contract_address
    );
    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    let (_, market_address) = operator.factory_create_market(factory.contract_address, operator.contract_address, collateral.contract_address);

    Config { operator, multicall, collateral, factory, market: IMarketDispatcher { contract_address: market_address }}
}


// TODO: rewrite