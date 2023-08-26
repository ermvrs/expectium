#[derive(Drop, Serde)]
struct MarketData {
    collateral_amount: u256,
    happens_resolve: u16,
    not_resolve: u16,
    orders: OrdersData
}

#[derive(Drop, Serde)]
struct OrdersData {
    happens_buy: Array<felt252>,
    happens_sell: Array<felt252>,
    not_buy: Array<felt252>,
    not_sell: Array<felt252>
}

#[derive(Drop, Serde)]
struct UserData {
    happens_balance: u256,
    not_balance: u256,
    user_orders: UserOrders
}

#[derive(Drop, Serde)]
struct UserOrders {
    happens_buy: Array<felt252>,
    happens_sell: Array<felt252>,
    not_buy: Array<felt252>,
    not_sell: Array<felt252>
}

#[derive(Drop, Copy, starknet::Store)]
struct Order {
    order_id : u32,
    date: u64,
    amount: u128,
    price: u16,
    status: OrderStatus
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct PlatformFees {
    maker: u32,
    taker: u32
}

#[derive(Copy, Drop, Serde, PartialEq)]
enum FeeType {
    Maker: (),
    Taker: (),
}



#[derive(Copy, Drop, Serde, PartialEq)]
enum Asset {
    Happens: (),
    Not: (),
}

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OrderStatus {
    Initialized: (),
    PartiallyFilled: (),
    Filled: (),
    Cancelled: ()
}