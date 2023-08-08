use starknet::syscalls::deploy_syscall;
use array::ArrayTrait;
use option::OptionTrait;
use result::ResultTrait;
use traits::{Into, TryInto};
use debug::PrintTrait;

use starknet::{ContractAddress, ClassHash};

use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait};
use expectium::interfaces::{IFactoryDispatcher, IERC20Dispatcher, IOrderbookDispatcher};
use expectium::contracts::factory::Factory;
use expectium::contracts::orderbook::Orderbook;
use expectium::tests::mocks::erc20::ERC20;

fn deploy_account() -> IAccountDispatcher {
    let (contract_address, _) = deploy_syscall(
        expectium::tests::mocks::account::Account::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        Default::default().span(),
        false
    )
        .unwrap();

    IAccountDispatcher { contract_address }
}

fn deploy_factory(operator: ContractAddress, market_hash: ClassHash) -> IFactoryDispatcher {
    let (contract_address, _) = deploy_syscall(
        Factory::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        array![operator.into(), market_hash.into()].span(),
        false
    ).unwrap();

    IFactoryDispatcher { contract_address }
}

fn deploy_orderbook(market: ContractAddress, operator: ContractAddress, quote: ContractAddress) -> IOrderbookDispatcher {
    let (contract_address, _) = deploy_syscall(
        Orderbook::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        array![market.into(), operator.into(), quote.into()].span(),
        false
    ).unwrap();

    IOrderbookDispatcher { contract_address }
}

fn deploy_erc20(
    name: felt252, symbol: felt252, decimals: u8, initial_supply: u256, recipient: ContractAddress
) -> IERC20Dispatcher {
    let (contract_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        array![
            name,
            symbol,
            decimals.into(),
            initial_supply.low.into(),
            initial_supply.high.into(),
            recipient.into()
        ]
            .span(),
        false
    )
        .unwrap();

    IERC20Dispatcher { contract_address }
}