use starknet::{ContractAddress, contract_address_const, ClassHash};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait, IMockSharesDispatcher, IMockSharesDispatcherTrait};
use expectium::interfaces::{IFactoryDispatcher, IFactoryDispatcherTrait, IMarketDispatcher, 
                            IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
                            IOrderbookDispatcher, IOrderbookDispatcherTrait,
                            IDistributorDispatcher, ISharesDispatcherTrait};
use expectium::config::{Asset, Order, unpack_order, pack_order};
use debug::PrintTrait;
use array::ArrayTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use expectium::tests::deploy;
use expectium::contracts::market::Market;
use expectium::contracts::distributor::Distributor;
use expectium::contracts::orderbook::Orderbook;

impl ArrayPrint of PrintTrait<Array<felt252>> {
    fn print(self: Array<felt252>) {
        let mut values = self;
        loop {
            match values.pop_front() {
                Option::Some(v) => {
                    let val: felt252 = v.into();
                    val.print();
                },
                Option::None(())=> {
                    break;
                }
            };
        }
    }
}

#[derive(Drop)]
struct Setup {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    market: IMarketDispatcher,
    factory: IFactoryDispatcher,
    orderbook: IOrderbookDispatcher,
    distributor: IDistributorDispatcher,
    shares: IMockSharesDispatcher
}

fn setup_with_mergeshares() -> Setup {
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

    // register token to distribution.

    operator.distributor_register_token(distributor.contract_address, collateral.contract_address);

    operator.erc20_transfer(collateral.contract_address, alice.contract_address, 5000000000000000000);
    operator.erc20_transfer(collateral.contract_address, bob.contract_address, 1000000000000000000);

    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    let (_, market) = operator.factory_create_market(factory.contract_address, operator.contract_address, collateral.contract_address);

    let orderbook = deploy::deploy_orderbook(market, operator.contract_address, collateral.contract_address, distributor.contract_address);

    alice.erc20_approve(collateral.contract_address, market, 1000000000000000000); // 1 ether
    alice.market_mint_shares(market, 1000000000000000000);

    bob.erc20_approve(collateral.contract_address, market, 100000000000000000); // 0.1 ether
    bob.market_mint_shares(market, 100000000000000000);

    Setup { operator, alice, bob, collateral, market: IMarketDispatcher { contract_address: market }, factory, orderbook, distributor, shares: mock_shares }
}

#[test]
#[available_gas(1000000000)]
fn test_initial_values() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;

    let op = book.operator();
    assert(op == setup.operator.contract_address, 'operator set wrong');
    assert(book.market() == setup.market.contract_address, 'market set wrong');
    assert(book.distributor() == setup.distributor.contract_address, 'distributor wrong');
    // TODO: check approval to distribution contract
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
    assert(unpacked_order.amount == 1000000000000000_u128, 'order amount wrong');

    assert(book.get_order_owner(order_id) == alice.contract_address, 'order owner wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_insert_buy_orders_check_sorting() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let bob = setup.bob;
    let collateral = setup.collateral;

    alice.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 1000000000000000, 100_u16);

    assert(order_id == 1, 'order_id wrong');

    bob.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let order_id = bob.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 100000000000000, 150_u16);
    assert(order_id == 2, 'order_id wrong');

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 70000000000000, 125_u16);

    let orders_packed = book.get_orders(Asset::Happens(()), 0_u8);

    let first_order = unpack_order(*orders_packed.at(0));
    let second_order = unpack_order(*orders_packed.at(1));
    let third_order = unpack_order(*orders_packed.at(2));

    assert(first_order.order_id == 2, 'first order wrong');
    assert(second_order.order_id == 3, 'sec order wrong');
    assert(third_order.order_id == 1, 'third order wrong');

    assert(first_order.amount == 100000000000000, 'first amount wrong');
    assert(second_order.amount == 70000000000000, 'second amount wrong');
    assert(third_order.amount == 1000000000000000, 'third amount wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_insert_sell_order_check_match() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let bob = setup.bob;
    let collateral = setup.collateral;
    let market = setup.market;

    alice.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 10000000000000, 100_u16);

    assert(order_id == 1, 'order_id wrong');

    bob.market_approve(setup.market.contract_address, book.contract_address);

    let before_trade_alice_commodity_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let before_trade_bob_collateral_balance = collateral.balanceOf(bob.contract_address);

    let order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 15000000000000, 75_u16);
    assert(order_id == 2, 'order_id wrong');

    let after_trade_alice_commodity_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let after_trade_bob_collateral_balance = collateral.balanceOf(bob.contract_address);

    // Alice commodity balance arttı çünkü alım emri girmişti
    assert((after_trade_alice_commodity_balance - before_trade_alice_commodity_balance) == 10000000000000, 'commodity transfer wrong');
    // Bobun collateral miktarı sadece alicin emri kadar arttı çünkü hepsi satılmadı.
    assert((after_trade_bob_collateral_balance - before_trade_bob_collateral_balance) == (10000000000000 * 100), 'collateral transfer wrong');

    let orders_packed = book.get_orders(Asset::Happens(()), 1_u8);

    let order = unpack_order(*orders_packed.at(0));

    assert(order.order_id == 2, 'order wrong');
    assert(order.amount == 5000000000000, 'amount wrong');

    // check order removed

    let buy_orders_packed = book.get_orders(Asset::Happens(()), 0_u8);
    assert(buy_orders_packed.len() == 0 ,'order still exist');
}

#[test]
#[available_gas(1000000000)]
fn test_insert_buy_order_and_cancel() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let collateral = setup.collateral;

    let alice_before_collateral_balance = collateral.balanceOf(alice.contract_address);

    alice.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 1000000000000000, 200_u16);

    assert(order_id == 1, 'order_id wrong');

    alice.orderbook_cancel_buy_order(book.contract_address, Asset::Happens(()), order_id);

    let alice_after_collateral_balance = collateral.balanceOf(alice.contract_address);

    assert(alice_after_collateral_balance == alice_before_collateral_balance, 'cancel repay wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_insert_sell_order_and_cancel() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let bob = setup.bob;
    let market = setup.market;
    let collateral = setup.collateral;

    let bob_before_commodity_balance = market.balance_of(bob.contract_address, Asset::Happens(()));

    bob.market_approve(setup.market.contract_address, book.contract_address);

    let order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 15000000000000, 75_u16);
    assert(order_id == 1, 'order_id wrong');

    bob.orderbook_cancel_sell_order(book.contract_address, Asset::Happens(()), order_id);

    let bob_after_commodity_balance = market.balance_of(bob.contract_address, Asset::Happens(()));

    assert(bob_before_commodity_balance == bob_after_commodity_balance, 'cancel repay wrong');
}

#[test]
#[available_gas(1000000000)]
fn test_insert_sell_orders_check_sorting() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let alice = setup.alice;
    let bob = setup.bob;
    let collateral = setup.collateral;

    alice.market_approve(setup.market.contract_address, book.contract_address);

    let order_id = alice.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 4000000000000, 75_u16);

    assert(order_id == 1, 'order_id wrong');

    bob.market_approve(setup.market.contract_address, book.contract_address);

    let order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 100000000000000, 150_u16);
    assert(order_id == 2, 'order_id wrong');

    let order_id = alice.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 15000000000000, 125_u16);
    assert(order_id == 3, 'order_id wrong');

    let orders_packed = book.get_orders(Asset::Happens(()), 1_u8);

    let first_order = unpack_order(*orders_packed.at(0));
    let second_order = unpack_order(*orders_packed.at(1));
    let third_order = unpack_order(*orders_packed.at(2));

    assert(first_order.order_id == 1, 'first order wrong');
    assert(second_order.order_id == 3, 'sec order wrong');
    assert(third_order.order_id == 2, 'third order wrong');

    assert(first_order.amount == 4000000000000, 'first amount wrong');
    assert(second_order.amount == 15000000000000, 'second amount wrong');
    assert(third_order.amount == 100000000000000, 'third amount wrong');
}

// TODO: Fee set edilerek trade test edilsin.