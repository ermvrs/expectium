use starknet::{Store, ContractAddress, StorageBaseAddress, SyscallResult};
use array::{ArrayTrait, SpanTrait};
use traits::{Into, TryInto};
use result::ResultTrait;
use integer::{u256_from_felt252};
use option::OptionTrait;
use hash::LegacyHash;

const ORDER_STRUCT_STORAGE_SIZE: u8 = 4;

#[derive(Drop, Copy, starknet::Store)]
struct Order { // TODO: cancel order için orderid gerekecek.
    // asset: Asset, // Gerek kalmaya bilir zaten mapli
    // side: OrderSide, // Zaten mapli
    order_id : u32,
    date: u64,
    // user: ContractAddress, // Ayrı mappingde tut.
    amount: u128, // max length çok yüksek decimals düşük tutabiliriz
    price: u16,
    status: OrderStatus // u8 length yeter
}

const SHIFT_8: u256 = 0x100;
const SHIFT_16: u256 = 0x10000;
const SHIFT_32: u256 = 0x100000000;
const SHIFT_64: u256 = 0x10000000000000000;
const SHIFT_96: u256 = 0x1000000000000000000000000;
const SHIFT_224: u256 = 0x100000000000000000000000000000000000000000000000000000000;
const SHIFT_240: u256 = 0x1000000000000000000000000000000000000000000000000000000000000;

const UNSHIFT_8: u256 = 0xFF;
const UNSHIFT_16: u256 = 0xFFFF;
const UNSHIFT_32: u256 = 0xFFFFFFFF;
const UNSHIFT_64: u256 = 0xFFFFFFFFFFFFFFFF;
const UNSHIFT_128: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

fn safe_u32_to_u128(val: u32) -> u128 {
    let val_felt: felt252 = val.into();

    val_felt.try_into().unwrap()
}

fn safe_u64_to_u128(val: u64) -> u128 {
    let val_felt: felt252 = val.into();

    val_felt.try_into().unwrap()
}

fn safe_u16_to_u128(val: u16) -> u128 {
    let val_felt: felt252 = val.into();

    val_felt.try_into().unwrap()
}

fn safe_status_to_u128(val: OrderStatus) -> u128 {
    let val_felt: felt252 = val.into();

    val_felt.try_into().unwrap()
}

fn pack_order(order: Order) -> felt252 { // TEST EDİLDİ DOĞRU GİBİ DURUYOR.
    let mut shifted: u256 = safe_u32_to_u128(order.order_id).into(); // u32
    shifted = shifted | (u256_from_felt252(safe_u64_to_u128(order.date).into()) * SHIFT_32);
    shifted = shifted | (u256_from_felt252(order.amount.into()) * SHIFT_96);
    shifted = shifted | (u256_from_felt252(safe_u16_to_u128(order.price).into()) * SHIFT_224);
    shifted = shifted | (u256_from_felt252(safe_status_to_u128(order.status).into()) * SHIFT_240); // KONTROL EDİLMELİ PACK DÜZGÜN MÜ.

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

impl OrderStatusIntoFelt252 of Into<OrderStatus, felt252> {
    fn into(self: OrderStatus) -> felt252 {
        match self {
            OrderStatus::Initialized(()) => 0,
            OrderStatus::PartiallyFilled(()) => 1,
            OrderStatus::Filled(()) => 2,
            OrderStatus::Cancelled(()) => 3,
        }
    }
}

impl Felt252TryIntoOrderStatus of TryInto<felt252, OrderStatus> {
    fn try_into(self: felt252) -> Option<OrderStatus> {
        if(self == 0) {
            return Option::Some(OrderStatus::Initialized(()));
        }
        if(self == 1) {
            return Option::Some(OrderStatus::PartiallyFilled(()));
        }
        if(self == 2) {
            return Option::Some(OrderStatus::Filled(()));
        }
        if(self == 3) {
            return Option::Some(OrderStatus::Cancelled(()));
        }

        Option::None(())
    }
}

impl StoreFelt252Array of Store<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        StoreFelt252Array::read_at_offset(address_domain, base, 0)
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Array<felt252>) -> SyscallResult<()> {
        StoreFelt252Array::write_at_offset(address_domain, base, 0, value)
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8
    ) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        let len: u8 = Store::<u8>::read_at_offset(address_domain, base, offset) // 0. offsette array length
            .expect('Storage arr too large');
        offset += 1;

        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = Store::<felt252>::read_at_offset(
                address_domain, base, offset
            )
                .unwrap();
            arr.append(value);
            offset += Store::<felt252>::size();
        };

        // Return the array.
        Result::Ok(arr)
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8, mut value: Array<felt252>
    ) -> SyscallResult<()> {
        let len: u8 = value.len().try_into().expect('Storage - Span too large');
        Store::<u8>::write_at_offset(address_domain, base, offset, len);
        offset += 1;

        // Store the array elements sequentially
        loop {
            match value.pop_front() {
                Option::Some(element) => {
                    Store::<felt252>::write_at_offset(
                        address_domain, base, offset, element
                    )?;
                    offset += Store::<felt252>::size();
                },
                Option::None(_) => {
                    break Result::Ok(());
                }
            };
        }
    }

    fn size() -> u8 {
        1_u8 // Nasıl okuyacağız? aptal starknet
    }
}

impl AssetLegacyHash of LegacyHash<Asset> {
    fn hash(state: felt252, value: Asset) -> felt252 {
        LegacyHash::<felt252>::hash(state, value.into())
    }
}

impl AssetIntoFelt252 of Into<Asset, felt252> {
    fn into(self: Asset) -> felt252 {
        match self {
            Asset::Happens(()) => 0,
            Asset::Not(()) => 1,
        }
    }
}

impl Felt252TryIntoAsset of TryInto<felt252, Asset> {
    fn try_into(self: felt252) -> Option<Asset> {
        if(self == 0) {
            return Option::Some(Asset::Happens(()));
        }
        if(self == 1) {
            return Option::Some(Asset::Not(()));
        }

        Option::None(())
    }
}