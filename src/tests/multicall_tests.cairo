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

#[test]
#[available_gas(1000000000)]
fn mint_shares_and_multicall() {
    let setup = setup();
    let market = setup.market;
    let multicall = setup.multicall;
    let operator = setup.operator;

    operator.erc20_approve(setup.collateral.contract_address, market.contract_address, integer::BoundedInt::max());
    operator.market_mint_shares(market.contract_address, 100000000000000000);


    let mut calls = ArrayTrait::<Call>::new();

    let call: Call = Call {
        contract: market.contract_address,
        entrypoint : 0x1557182e4359a1f0c6301278e8f5b35a776ab58d39892581e357578fb287836,
        calldata: array![0x0]
    };

    calls.append(call);

    let multicall_result: Span<Response> = multicall.multicall(calls);

    let mut i = 0;
    loop {
        if(i == multicall_result.len()) {
            break;
        }

        let result: Span<felt252> = *multicall_result.at(i).result;

        let result_first = *result.at(0);
        result_first.print();
        i += 1;
    }
}

#[test]
#[available_gas(1000000000)]
fn mint_shares_and_multicall_different_contracts() {
    let setup = setup();
    let market = setup.market;
    let multicall = setup.multicall;
    let factory = setup.factory;
    let operator = setup.operator;

    operator.erc20_approve(setup.collateral.contract_address, market.contract_address, integer::BoundedInt::max());
    operator.market_mint_shares(market.contract_address, 100000000000000000);


    let mut calls = ArrayTrait::<Call>::new();

    let call_f: Call = Call {
        contract: market.contract_address,
        entrypoint : 0x1557182e4359a1f0c6301278e8f5b35a776ab58d39892581e357578fb287836, // total_supply
        calldata: array![0x0]
    };

    calls.append(call_f);

    let call_s: Call = Call {
        contract: factory.contract_address,
        entrypoint : 0x2a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622, // operator()
        calldata: array![]
    };

    calls.append(call_s);

    let multicall_result: Span<Response> = multicall.multicall(calls);

    let mut i = 0;
    loop {
        if(i == multicall_result.len()) {
            break;
        }

        let result: Span<felt252> = *multicall_result.at(i).result;
        if(i == 0) {
            let result_first = *result.at(0);
            assert(result_first.into() == 100000000000000000, 'total supply wrong');
        }

        if(i == 1) {
            let result_first = *result.at(0);
            assert(result_first == operator.contract_address.into(), 'operator address wrong');
        }

        i += 1;
    }
}