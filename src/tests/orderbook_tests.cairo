use starknet::{ContractAddress, contract_address_const, ClassHash};
use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait, IMockSharesDispatcher, IMockSharesDispatcherTrait};
use expectium::interfaces::{IFactoryDispatcher, IFactoryDispatcherTrait, IMarketDispatcher, 
                            IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
                            IOrderbookDispatcher, IOrderbookDispatcherTrait,
                            IDistributorDispatcher, IDistributorDispatcherTrait, ISharesDispatcherTrait};
use expectium::types::{Asset, Order};
use expectium::utils::{unpack_order, pack_order};
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
struct Config {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    cindy: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    market: IMarketDispatcher,
    factory: IFactoryDispatcher,
    orderbook: IOrderbookDispatcher,
    distributor: IDistributorDispatcher,
    shares: IMockSharesDispatcher
}

fn setup_with_mergeshares() -> Config {
    let operator = deploy::deploy_account();
    let alice = deploy::deploy_account();
    let bob = deploy::deploy_account();
    let cindy = deploy::deploy_account();

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
    operator.erc20_transfer(collateral.contract_address, cindy.contract_address, 2000000000000000000);

    let market_classhash: ClassHash = Market::TEST_CLASS_HASH.try_into().unwrap();

    let factory = deploy::deploy_factory(operator.contract_address, market_classhash);
    let (_, market) = operator.factory_create_market(factory.contract_address, operator.contract_address, collateral.contract_address);

    let orderbook = deploy::deploy_orderbook(market, operator.contract_address, collateral.contract_address, distributor.contract_address);

    alice.erc20_approve(collateral.contract_address, market, integer::BoundedInt::max()); // 1 ether
    alice.market_mint_shares(market, 1000000000000000000);

    bob.erc20_approve(collateral.contract_address, market, integer::BoundedInt::max()); // 0.1 ether
    bob.market_mint_shares(market, 100000000000000000);

    cindy.erc20_approve(collateral.contract_address, market, integer::BoundedInt::max()); // 0.2 ether
    cindy.market_mint_shares(market, 200000000000000000);

    Config { operator, alice, bob, cindy, collateral, market: IMarketDispatcher { contract_address: market }, factory, orderbook, distributor, shares: mock_shares }
}

fn setup_with_shares_merged_and_fee_set() -> Config {
    let setup = setup_with_mergeshares();

    let operator = setup.operator;
    let book = setup.orderbook;

    let fees = expectium::types::PlatformFees { maker: 300, taker: 500 }; // taker %5, maker % 3
    operator.orderbook_set_fee(book.contract_address, fees);

    setup
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

    let collateral = setup.collateral;

    let allowance = collateral.allowance(book.contract_address, setup.distributor.contract_address);
    assert(allowance == integer::BoundedInt::max(), 'allowance wrong');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('taker too much', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED',))]
fn test_set_fee_taker_high() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let operator = setup.operator;

    let fees = expectium::types::PlatformFees { maker: 0, taker: 2000 };
    operator.orderbook_set_fee(book.contract_address, fees);
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('maker too much', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED',))]
fn test_set_fee_maker_high() {
    let setup = setup_with_mergeshares();

    let book = setup.orderbook;
    let operator = setup.operator;

    let fees = expectium::types::PlatformFees { maker: 1001, taker: 0 };
    operator.orderbook_set_fee(book.contract_address, fees);
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

    // toplam usdc : 1000000000000000
    // fiyat: 200bp
    // total amount = 1000000000000000 * 10000 / 200

    assert(order_id == 1, 'order_id wrong');

    let order = book.get_order(Asset::Happens(()), 0_u8, order_id);
    let unpacked_order: Order = unpack_order(order);

    let order_amount:u128 = 1000000000000000 * 10000 / 200;

    assert(unpacked_order.price == 200_u16, 'order price wrong');
    assert(unpacked_order.order_id == 1_u32, 'order id wrong');
    assert(unpacked_order.date == 0x0, 'order date wrong');
    assert(unpacked_order.amount == order_amount, 'order amount wrong');

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

    let first_amount: u128 = 100000000000000 * 10000 / 150;
    let second_amount: u128 = 70000000000000 * 10000 / 125;
    let third_amount: u128 = 1000000000000000 * 10000 / 100;

    assert(first_order.amount == first_amount, 'first amount wrong');
    assert(second_order.amount == second_amount, 'second amount wrong');
    assert(third_order.amount == third_amount, 'third amount wrong');
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

    let order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 100000000, 100_u16);
    // 100000000 usdc ödendi 100000000 * 10000 / 100 = amount
    let alice_order_amount = (100000000 * 10000) / 100;

    assert(order_id == 1, '1st order_id wrong');

    bob.market_approve(setup.market.contract_address, book.contract_address);

    let before_trade_alice_commodity_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let before_trade_bob_collateral_balance = collateral.balanceOf(bob.contract_address);

    let order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), alice_order_amount * 2, 75_u16);
    assert(order_id == 2, '2nd order_id wrong');
    
    let after_trade_alice_commodity_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let after_trade_bob_collateral_balance = collateral.balanceOf(bob.contract_address);

    let commodity_bought = alice_order_amount; // 10aaa usdc ödedim, miktar bp = 10aaa * 10000, tanesine 100 ödedim 10aaa* 100 olması lazım
    // Alice commodity balance arttı çünkü alım emri girmişti
    assert((after_trade_alice_commodity_balance - before_trade_alice_commodity_balance) == commodity_bought, 'commodity transfer wrong');
    // Bobun collateral miktarı sadece alicin emri kadar arttı çünkü hepsi satılmadı.
    let collateral_taken = (alice_order_amount * 100) / 10000;
    assert((after_trade_bob_collateral_balance - before_trade_bob_collateral_balance) == collateral_taken, 'collateral transfer wrong');

    let orders_packed = book.get_orders(Asset::Happens(()), 1_u8);

    let order = unpack_order(*orders_packed.at(0));

    assert(order.order_id == 2, 'order wrong');
    assert(order.amount == ((alice_order_amount * 2) - commodity_bought).try_into().unwrap(), 'amount wrong');

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
// TODO: Aynı emir birden fazla eşleşme.
// Birden fazla emir aynı txde eşleşmesi.
#[test]
#[available_gas(1000000000)]
fn test_trade_with_fees() {
    let setup = setup_with_shares_merged_and_fee_set();
    // let fees = expectium::config::PlatformFees { maker: 300, taker: 500 }; // taker %5, maker % 3

    let market = setup.market;
    let collateral = setup.collateral;
    let alice = setup.alice;
    let book = setup.orderbook;
    let bob = setup.bob;
    let distributor = setup.distributor;

    let initial_distribution = distributor.total_distribution(collateral.contract_address);
    assert(initial_distribution == 0, 'initial dist wrong');

    let alice_initial_share_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let bob_initial_share_balance = market.balance_of(bob.contract_address, Asset::Happens(()));

    let alice_initial_collateral_balance = collateral.balanceOf(alice.contract_address);
    let bob_initial_collateral_balance = collateral.balanceOf(bob.contract_address);

    alice.erc20_approve(collateral.contract_address, book.contract_address, 1000000000000000 * 200);

    let first_order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), 100000000, 1000); // 100000000 usdc paid
    // 100000000 ödenen usdc => amount = usdc_paid * 10000 / price;

    let alice_buy_amount = (100000000 * 10000) / 1000;

    assert(first_order_id > 0, 'error init order');

    bob.market_approve(market.contract_address, book.contract_address);

    // bob sells 20000000000 amount of happens with price of 0.1$

    let second_order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), 20000000000, 1000);
    assert(second_order_id > 0, 'error init second order');

    // after that,
    // bob should have 1 offer left with order.amount - alice_buy_amount;
    // bob should received alice_quote_amount minus fee
    // alice should received alice_buy_amount -> minus maker fee amount of happens

    let bob_collateral_balance_after = collateral.balanceOf(bob.contract_address);

    let sale_quote_amount: u256 = alice_buy_amount * 1000 / 10000;
    let sale_taker_fee: u256 = (sale_quote_amount * 500) / 10000;

    assert((bob_collateral_balance_after - bob_initial_collateral_balance) == (sale_quote_amount - sale_taker_fee), 'bob collateral wrong');

    let alice_share_balance_after = market.balance_of(alice.contract_address, Asset::Happens(()));
    let sale_shares_fee: u256 = (alice_buy_amount * 300) / 10000;

    assert((alice_share_balance_after - alice_initial_share_balance) == (alice_buy_amount - sale_shares_fee), 'alice shares wrong');

    let packed_second_order = book.get_order(Asset::Happens(()),1_u8, second_order_id);
    let unpacked_second_order = unpack_order(packed_second_order);

    assert(unpacked_second_order.amount == (20000000000 - alice_buy_amount).try_into().unwrap(), 'order amount left wrong');

    // check distributor registers
    let final_distribution = distributor.total_distribution(collateral.contract_address);

    assert(final_distribution == sale_taker_fee, 'distribution wrong');
}

#[test]
#[available_gas(100000000000)]
fn test_taker_match_with_multiple_orders() {
    let setup = setup_with_shares_merged_and_fee_set();

    let alice = setup.alice;
    let bob = setup.bob;
    let cindy = setup.cindy;

    let book = setup.orderbook;
    let market = setup.market;
    let collateral = setup.collateral;
    let distributor = setup.distributor;

    // alice and bob creates 2 and 1 buy orders. Cindy will take all of them and insert sell order

    // initial balances

    let alice_initial_share_balance = market.balance_of(alice.contract_address, Asset::Not(()));
    let bob_initial_share_balance = market.balance_of(bob.contract_address, Asset::Not(()));
    let cindy_initial_share_balance = market.balance_of(cindy.contract_address, Asset::Not(()));

    let cindy_initial_collateral_balance = collateral.balanceOf(cindy.contract_address);

    alice.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());
    bob.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());

    alice.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), 10000000, 2000); // buy with 10000000 usdc
    bob.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), 50000000, 1750); // buy with 50000000 usdc
    alice.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), 20000000, 1500); // buy with 20000000 usdc

    // total 80000000 on sale

    cindy.market_approve(market.contract_address, book.contract_address);

    let cindys_order_id = cindy.orderbook_insert_sell_order(book.contract_address, Asset::Not(()), 1000000000, 1000); // sells 100000000 with price 0.1$

    let alice_first_order_amount = 10000000 * 10000 / 2000;
    let bob_first_order_amount = 50000000 * 10000 / 1750;
    let alice_second_order_amount = 20000000 * 10000 / 1500;

    // cindy will spend like following
    // 1st sell 10000000 to Alice 1st order with price of 0.2$ 
    // 2nd sell 50000000 to Bob 1st order with price of 0.175$
    // 3rd sell 20000000 to Alice 2nd order with price of 0.15$
    // finally she creates order with rest amount. 20000000

    // first check cindys order

    let packed_cindys_order = book.get_order(Asset::Not(()), 1_u8, cindys_order_id);
    let cindys_order = unpack_order(packed_cindys_order);

    assert(cindys_order.amount == (1000000000 - (alice_first_order_amount + bob_first_order_amount + alice_second_order_amount)), 'cindys order amount wrong');

    // cindy wants to sell 100000000 amount with price of 0.1$ but she sold them higher price so she should get
    // (10000000 * 2000) + (50000000 * 1750) + (20000000 * 1500) amount of collateral(minus fee)

    let cindy_return_without_fee: u256 = (((alice_first_order_amount * 2000) + (bob_first_order_amount * 1750) + (alice_second_order_amount * 1500)).into()) / 10000;
    let cindy_taker_fee = (cindy_return_without_fee * 500) / 10000;

    let cindy_final_balance = collateral.balanceOf(cindy.contract_address);
    assert((cindy_final_balance - cindy_initial_collateral_balance) == (cindy_return_without_fee - cindy_taker_fee), 'cindy coll balance wrong');

    // check makers share balances

    let alice_after_share_balance = market.balance_of(alice.contract_address, Asset::Not(()));
    let bob_after_share_balance = market.balance_of(bob.contract_address, Asset::Not(()));

    let alice_maker_fee: u256 = (((alice_first_order_amount + alice_second_order_amount) * 300) / 10000).into();
    let bob_maker_fee: u256 = ((bob_first_order_amount * 300) / 10000).into();

    assert((alice_after_share_balance - alice_initial_share_balance) == ((alice_first_order_amount + alice_second_order_amount) - alice_maker_fee.try_into().unwrap()).into(), 'alice fee wrong');
    assert((bob_after_share_balance - bob_initial_share_balance) == (bob_first_order_amount.into() - bob_maker_fee), 'bob fee wrong');

    // check distribution.

    let total_distribution = distributor.total_distribution(collateral.contract_address);
    assert(total_distribution <= cindy_taker_fee, 'distributed fee wrong'); // +- 1
}

#[test]
#[available_gas(100000000000)]
fn test_taker_match_with_multiple_orders_but_final_remains() { // TODO
    let setup = setup_with_shares_merged_and_fee_set();

    let alice = setup.alice;
    let bob = setup.bob;
    let cindy = setup.cindy;

    let book = setup.orderbook;
    let market = setup.market;
    let collateral = setup.collateral;
    let distributor = setup.distributor;

    let alice_initial_share_balance = market.balance_of(alice.contract_address, Asset::Not(()));
    let bob_initial_share_balance = market.balance_of(bob.contract_address, Asset::Not(()));
    let cindy_initial_share_balance = market.balance_of(cindy.contract_address, Asset::Not(()));

    let cindy_initial_collateral_balance = collateral.balanceOf(cindy.contract_address);

    alice.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());
    bob.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());

    let alice_first_order_amount: u256 = 10000000;
    let alice_first_order_quote: u256 = alice_first_order_amount * 2000 / 10000;

    let bob_first_order_amount: u256 = 50000000;
    let bob_first_order_quote: u256 = bob_first_order_amount * 1750 / 10000;

    let alice_second_order_amount: u256 = 20000000;
    let alice_second_order_quote: u256 = alice_second_order_amount * 1500 / 10000;

    alice.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), alice_first_order_quote, 2000); // buy with 10000000 usdc 
    bob.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), bob_first_order_quote, 1750); // buy with 50000000 usdc
    let final_order_id = alice.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), alice_second_order_quote, 1500); // buy with 20000000 usdc


    cindy.market_approve(market.contract_address, book.contract_address);

    let cindys_order_id = cindy.orderbook_insert_sell_order(book.contract_address, Asset::Not(()), 70000000, 1000); // sells 70000000 with price 0.1$
    assert(cindys_order_id == 0, 'cindy order id wrong');

    let packed_final_order = book.get_order(Asset::Not(()), 0_u8, final_order_id);
    let final_order = unpack_order(packed_final_order);

    let spent_on_two = alice_first_order_amount + bob_first_order_amount;
    let left_for_final_order: u256 = 70000000 - spent_on_two; // TODO

    assert(final_order.amount == (alice_second_order_amount - left_for_final_order).try_into().unwrap(), 'final order amount wrong');

    let cindy_return_without_fee: u256 = (((alice_first_order_amount * 2000) + (bob_first_order_amount * 1750) + (left_for_final_order * 1500)).into()) / 10000;
    let cindy_taker_fee = (cindy_return_without_fee * 500) / 10000;

    let cindy_final_balance = collateral.balanceOf(cindy.contract_address);

    assert((cindy_final_balance - cindy_initial_collateral_balance) == (cindy_return_without_fee - cindy_taker_fee), 'cindy coll balance wrong');

    let alice_after_share_balance = market.balance_of(alice.contract_address, Asset::Not(()));
    let bob_after_share_balance = market.balance_of(bob.contract_address, Asset::Not(()));

    let alice_maker_fee: u256 = (((alice_first_order_amount + (left_for_final_order)) * 300) / 10000).into();
    let bob_maker_fee: u256 = ((bob_first_order_amount * 300) / 10000).into();

    assert((alice_after_share_balance - alice_initial_share_balance) == ((alice_first_order_amount + (left_for_final_order)) - alice_maker_fee).into(), 'alice fee wrong');
    assert((bob_after_share_balance - bob_initial_share_balance) == (bob_first_order_amount - bob_maker_fee).into(), 'bob fee wrong');

    let total_distribution = distributor.total_distribution(collateral.contract_address);

    assert(total_distribution == cindy_taker_fee, 'distributed fee wrong');

    let orders_buy = book.get_orders(Asset::Not(()), 0_u8);
    let orders_sell = book.get_orders(Asset::Not(()), 1_u8);

    assert(orders_buy.len() == 1, 'buy orders len wrong');
    assert(orders_sell.len() == 0, 'sell orders len wrong');
}

// TODO: yukarıdaki 2 metodun aynısı ancak sell order ile başlanıp buy ile eşleşecek şekilde. Dağıtımda kontrol edilmeli

#[test]
#[available_gas(100000000000)]
fn test_taker_match_with_multiple_orders_but_maker_is_seller_and_final_remains() {
    let setup = setup_with_shares_merged_and_fee_set();

    let alice = setup.alice;
    let bob = setup.bob;
    let cindy = setup.cindy;

    let book = setup.orderbook;
    let market = setup.market;
    let collateral = setup.collateral;
    let distributor = setup.distributor;

    // alice and bob creates sell orders.

    alice.market_approve(market.contract_address, book.contract_address);
    bob.market_approve(market.contract_address, book.contract_address);

    // cindy will enter buy order.

    cindy.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());

    // initial balances

    let alice_initial_collateral_balance = collateral.balanceOf(alice.contract_address);
    let bob_initial_collateral_balance = collateral.balanceOf(bob.contract_address);
    let cindy_initial_collateral_balance = collateral.balanceOf(cindy.contract_address);

    let alice_initial_share_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let bob_initial_share_balance = market.balance_of(bob.contract_address, Asset::Happens(()));
    let cindy_initial_share_balance = market.balance_of(cindy.contract_address, Asset::Happens(()));

    // alice insert to sell orders with 6000000 amount per 0.225$ and 1000000 per 0.1$

    let alice_first_order_amount: u256 = 6000000;
    let bob_first_order_amount: u256 = 4000000;
    let alice_second_order_amount: u256 = 1000000;

    let alice_first_order_id = alice.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), alice_first_order_amount, 2250);
    assert(alice_first_order_id == 1, 'alice first orderid wrong');

    // bob sells 4000000 per 0.07$

    let bob_first_order_id = bob.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), bob_first_order_amount, 700);
    assert(bob_first_order_id == 2, 'bob orderid wrong');

    let alice_second_order_id = alice.orderbook_insert_sell_order(book.contract_address, Asset::Happens(()), alice_second_order_amount, 1000);
    assert(alice_second_order_id == 3, 'alice second orderid wrong');

    let orders = book.get_orders(Asset::Happens(()), 1_u8);
    assert(orders.len() == 3, 'order count wrong');

    // check order arrangement 
    // 1st = bob, 2nd = alice 2nd, 3rd = alice 1st

    let packed_first_order: felt252 = *orders.at(0);
    let unpacked_first_order: Order = unpack_order(packed_first_order);

    assert(unpacked_first_order.order_id == 2, 'first order wrong');

    let packed_second_order: felt252 = *orders.at(1);
    let unpacked_second_order: Order = unpack_order(packed_second_order);

    assert(unpacked_second_order.order_id == 3, 'first order wrong');

    let packed_third_order: felt252 = *orders.at(2);
    let unpacked_third_order: Order = unpack_order(packed_third_order);

    assert(unpacked_third_order.order_id == 1, 'first order wrong');

    // all orders correct. Now cindy enters buy order.
    // She buy with 11000000 * 2500 usdc so last order should remain 1000000
    let cindy_spend_quote = (((alice_first_order_amount - 1000000) * 2250) / 10000) + ((bob_first_order_amount * 700) / 10000) + ((alice_second_order_amount * 1000) / 10000);


    let cindy_order_id = cindy.orderbook_insert_buy_order(book.contract_address, Asset::Happens(()), cindy_spend_quote, 2500);
    assert(cindy_order_id == 0, 'cindy order entered'); // orderid should return 0 bcs it already matches all amount

    let final_buy_order_count = book.get_orders(Asset::Happens(()), 0_u8);
    assert(final_buy_order_count.len() == 0, 'wrong buy order count');
    let final_sell_order_count = book.get_orders(Asset::Happens(()), 1_u8);
    assert(final_sell_order_count.len() == 1, 'wrong sell order count');

    let packed_remaining_order = book.get_order(Asset::Happens(()), 1_u8, alice_first_order_id);
    let remaining_order: Order = unpack_order(packed_remaining_order);

    assert(remaining_order.amount == 1000000, 'remaining order amount wrong');
    assert(remaining_order.price == 2250, 'remaining order price wrong');

    // final balances

    let alice_final_collateral_balance = collateral.balanceOf(alice.contract_address);
    let bob_final_collateral_balance = collateral.balanceOf(bob.contract_address);
    let cindy_final_collateral_balance = collateral.balanceOf(cindy.contract_address);

    let alice_final_share_balance = market.balance_of(alice.contract_address, Asset::Happens(()));
    let bob_final_share_balance = market.balance_of(bob.contract_address, Asset::Happens(()));
    let cindy_final_share_balance = market.balance_of(cindy.contract_address, Asset::Happens(()));

    // cindys final share balance should be higher than expected, because she bought with lower price then she expected
    // so cindy
    let cindy_bought_amount = (4000000 + 1000000 + 5000000).into();
    let cindy_taker_fee: u256 = (cindy_bought_amount * 500) / 10000;

    assert((cindy_final_share_balance) == (cindy_initial_share_balance + (cindy_bought_amount - cindy_taker_fee)), 'cindy final share wrong');
    
    let alice_collateral_receive_without_fee: u256 = (((alice_first_order_amount - 1000000) * 2250) / 10000) + ((alice_second_order_amount * 1000) / 10000);
    let alice_maker_fee: u256 = (alice_collateral_receive_without_fee) * 300 / 10000;

    let bob_collateral_receive_without_fee: u256 = bob_first_order_amount * 700 / 10000;
    let bob_maker_fee: u256 = (bob_collateral_receive_without_fee) * 300 / 10000;

    assert((alice_final_collateral_balance - alice_initial_collateral_balance) == (alice_collateral_receive_without_fee - alice_maker_fee), 'alice coll wrong');
    assert((bob_final_collateral_balance - bob_initial_collateral_balance) == (bob_collateral_receive_without_fee - bob_maker_fee), 'bob coll wrong');
    
    let total_distribution = distributor.total_distribution(collateral.contract_address);

    assert(total_distribution == (bob_maker_fee + alice_maker_fee), 'distributed fee wrong');
}

#[test]
#[available_gas(100000000000)]
fn test_taker_match_with_multiple_orders_and_taker_is_seller() {
    // taker matches with 3 orders and then adds order finally
    let setup = setup_with_shares_merged_and_fee_set();

    let alice = setup.alice;
    let bob = setup.bob;
    let cindy = setup.cindy;

    let book = setup.orderbook;
    let market = setup.market;
    let collateral = setup.collateral;
    let distributor = setup.distributor;

    // alice and bob creates 2 and 1 buy orders. Cindy will take all of them and insert sell order

    // initial balances

    let alice_initial_share_balance = market.balance_of(alice.contract_address, Asset::Not(()));
    let bob_initial_share_balance = market.balance_of(bob.contract_address, Asset::Not(()));
    let cindy_initial_share_balance = market.balance_of(cindy.contract_address, Asset::Not(()));


    let alice_initial_collateral_balance = collateral.balanceOf(alice.contract_address);
    let bob_initial_collateral_balance = collateral.balanceOf(bob.contract_address);
    let cindy_initial_collateral_balance = collateral.balanceOf(cindy.contract_address);

    alice.market_approve(market.contract_address, book.contract_address);
    bob.market_approve(market.contract_address, book.contract_address);
    cindy.erc20_approve(collateral.contract_address, book.contract_address, integer::BoundedInt::max());

    let alice_first_order_amount = 10000000;
    let bob_first_order_amount = 20000000;
    let alice_second_order_amount = 40000000;

    alice.orderbook_insert_sell_order(book.contract_address, Asset::Not(()), alice_first_order_amount, 1000); // sell for 0.1$
    

    bob.orderbook_insert_sell_order(book.contract_address, Asset::Not(()), bob_first_order_amount, 450);
    

    alice.orderbook_insert_sell_order(book.contract_address, Asset::Not(()), alice_second_order_amount, 1250);

    let total_amount_on_sale = alice_first_order_amount + bob_first_order_amount + alice_second_order_amount;

    let total_quote_needed: u256 = 1000000 + 900000 + 5000000;
    let cindy_total_quote: u256 = total_quote_needed + 1000000;

    let cindys_order_id = cindy.orderbook_insert_buy_order(book.contract_address, Asset::Not(()), cindy_total_quote, 2000);
    assert(cindys_order_id > 0, 'cindy orderid wrong');

    let packed_cindys_order = book.get_order(Asset::Not(()), 0_u8, cindys_order_id);
    let cindys_order = unpack_order(packed_cindys_order);

    let cindy_quote_left = cindy_total_quote - total_quote_needed;
    

    assert(cindys_order.amount == (cindy_quote_left * 10000 / 2000).try_into().unwrap(), 'cindys order amount wrong');

    let cindy_return_without_fee: u256 = (10000000 + 20000000 + 40000000).into();
    let cindy_taker_fee = (cindy_return_without_fee * 500) / 10000;

    let cindy_final_share_balance = market.balance_of(cindy.contract_address, Asset::Not(()));
    let cindy_final_collateral_balance = collateral.balanceOf(cindy.contract_address);

    assert((cindy_final_share_balance - cindy_initial_share_balance) == (cindy_return_without_fee - cindy_taker_fee), 'cindy share balance wrong');

    assert((cindy_initial_collateral_balance - cindy_final_collateral_balance) == cindy_total_quote, 'cindy coll balance wrong');

    // check makers share balances

    let alice_after_collateral_balance = collateral.balanceOf(alice.contract_address);
    let bob_after_collateral_balance = collateral.balanceOf(bob.contract_address);

    let alice_return_without_fee: u256 = ((10000000 * 1000) / 10000) + ((40000000 * 1250) / 10000);
    let bob_return_without_fee: u256 = (20000000 * 450) / 10000;

    let alice_maker_fee: u256 = (((((10000000 * 1000) / 10000) + ((40000000 * 1250) / 10000)) * 300_u256) / 10000).into();
    let bob_maker_fee: u256 = ((((20000000 * 450) / 10000) * 300_u256) / 10000).into();

    assert((alice_after_collateral_balance - alice_initial_collateral_balance) == (alice_return_without_fee - alice_maker_fee), 'alice coll wrong');
    assert((bob_after_collateral_balance - bob_initial_collateral_balance) == (bob_return_without_fee - bob_maker_fee), 'bob coll wrong');
    // check distribution.

    let total_distribution = distributor.total_distribution(collateral.contract_address);

    assert(total_distribution == (bob_maker_fee + alice_maker_fee), 'distributed fee wrong');
}