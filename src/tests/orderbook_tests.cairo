use starknet::{ContractAddress, contract_address_const, ClassHash};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait};
use expectium::interfaces::{IFactoryDispatcher, IFactoryDispatcherTrait, IMarketDispatcher, 
                            IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
                            IOrderbookDispatcher, IOrderbookDispatcherTrait};
use expectium::config::{Asset, Order, unpack_order, pack_order};
use debug::PrintTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use expectium::tests::deploy;
use expectium::contracts::market::Market;
use expectium::contracts::distributor::Distributor;
use expectium::contracts::orderbook::Orderbook;

#[derive(Drop)]
struct Setup {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    market: IMarketDispatcher,
    factory: IFactoryDispatcher,
    orderbook: IOrderbookDispatcher
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

    let orderbook = deploy::deploy_orderbook(market, operator.contract_address, collateral.contract_address);

    alice.erc20_approve(collateral.contract_address, market, 1000000000000000000); // 1 ether
    alice.market_mint_shares(market, 1000000000000000000);

    Setup { operator, alice, bob, collateral, market: IMarketDispatcher { contract_address: market }, factory, orderbook }
}

#[test]
#[available_gas(1000000000)]
fn test_initial_values() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;

    let op = book.operator();
    assert(op == setup.operator.contract_address, 'operator set wrong');
    assert(book.market() == setup.market.contract_address, 'market set wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('ERC20_INSUFFICIENT_ALLOWANCE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_insert_buy_order_without_approval() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;

    alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 100000_u256, 1000_u16);
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_insert_buy_order_exceeds_balance() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let collateral = setup.collateral;

    
    let balance = collateral.balanceOf(alice.contract_address);

    alice.erc20_approve(collateral.contract_address, book.contract_address, balance * 550);
    alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), balance * 5, 10_u16);
}

#[test]
#[available_gas(1000000000)]
fn test_insert_buy_order() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let collateral = setup.collateral;

    alice.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 1000000000000000, 200_u16);

    assert(order_id == 1, 'order_id wrong');

    let order = book.get_order(Asset::Happens(()), 0_u8, order_id);
    let unpacked_order: Order = unpack_order(order);

    assert(unpacked_order.price == 200_u16, 'order price wrong');
    assert(unpacked_order.order_id == 1_u32, 'order id wrong');
    assert(unpacked_order.date == 0x0, 'order date wrong');
    unpacked_order.amount.print();
    assert(unpacked_order.amount == 1000000000000000_u128, 'order amount wrong');
}