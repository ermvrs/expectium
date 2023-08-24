

#[derive(Drop, Copy, starknet::Store)]
struct Order {
    order_id : u32,
    date: u64,
    amount: u128,
    price: u16,
    status: OrderStatus
}

#[derive(Copy, Drop, Serde, PartialEq)]
enum FeeType {
    Maker: (),
    Taker: (),
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct PlatformFees {
    maker: u32,
    taker: u32
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