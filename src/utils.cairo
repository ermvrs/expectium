use integer::{u256_from_felt252};
use traits::{Into, TryInto};
use result::ResultTrait;
use option::OptionTrait;
use expectium::types::{Order};
use expectium::constants::{SHIFT_32, SHIFT_96, SHIFT_224, SHIFT_240, UNSHIFT_32, UNSHIFT_64, UNSHIFT_128, UNSHIFT_16, UNSHIFT_8};
use expectium::implementations::{OrderStatusIntoU256, OrderStatusIntoFelt252, Felt252TryIntoOrderStatus};

fn pack_order(order: Order) -> felt252 { // TEST EDİLDİ DOĞRU GİBİ DURUYOR.
    let mut shifted: u256 = order.order_id.into(); // u32
    shifted = shifted | (u256_from_felt252(order.date.into()) * SHIFT_32);
    shifted = shifted | (u256_from_felt252(order.amount.into()) * SHIFT_96);
    shifted = shifted | (u256_from_felt252(order.price.into()) * SHIFT_224);
    shifted = shifted | (u256_from_felt252(order.status.into()) * SHIFT_240); // KONTROL EDİLMELİ PACK DÜZGÜN MÜ.

    shifted.try_into().unwrap()
}

fn unpack_order(packed_order: felt252) -> Order { // TEST EDİLDİ DOĞRU GİBİ DURUYOR. EN YÜKSEK DEĞERLERLE TEST EDİLMELİ.
    // TODO
    let unshifted: u256 = packed_order.into();

    let order_id: u32 = (unshifted & UNSHIFT_32).try_into().unwrap();
    let date: u64 = ((unshifted / SHIFT_32) & UNSHIFT_64).try_into().unwrap(); // burada libfuncs problemi var
    let amount: u128 = ((unshifted / SHIFT_96) & UNSHIFT_128).try_into().unwrap();
    let price: u16 = ((unshifted / SHIFT_224) & UNSHIFT_16).try_into().unwrap();
    let status: felt252 = ((unshifted / SHIFT_240) & UNSHIFT_8).try_into().unwrap();

    Order {
        order_id : order_id, 
        date: date,
        amount: amount,
        price: price,
        status: status.try_into().unwrap()
    }
}