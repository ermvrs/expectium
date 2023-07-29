use starknet::{StorageAccess, ContractAddress, StorageBaseAddress, SyscallResult};
use array::{ArrayTrait, SpanTrait};
use traits::{Into, TryInto};
use result::ResultTrait;
use integer::{u256_from_felt252};
use option::OptionTrait;
use hash::LegacyHash;

const ORDER_STRUCT_STORAGE_SIZE: u8 = 4;

#[derive(Drop, Copy)]
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

const TWO_POW_8: u256 = 0x100;
const TWO_POW_16: u256 = 0x10000;
const TWO_POW_32: u256 = 0x100000000;
const TWO_POW_64: u256 = 0x10000000000000000;
const TWO_POW_96: u256 = 0x1000000000000000000000000;
const TWO_POW_224: u256 = 0x100000000000000000000000000000000000000000000000000000000;
const TWO_POW_240: u256 = 0x1000000000000000000000000000000000000000000000000000000000000;

const MASK_8: u256 = 0xFF;
const MASK_16: u256 = 0xFFFF;
const MASK_32: u256 = 0xFFFFFFFF;
const MASK_64: u256 = 0xFFFFFFFFFFFFFFFF;
const MASK_128: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

fn pack_order(order: Order) -> felt252 {
    let mut packed: u256 = order.order_id.into(); // u32
    packed = packed | (u256_from_felt252(order.date.into()) * TWO_POW_32);
    packed = packed | (u256_from_felt252(order.amount.into()) * TWO_POW_96);
    packed = packed | (u256_from_felt252(order.price.into()) * TWO_POW_224);
    packed = packed | (u256_from_felt252(order.status.into()) * TWO_POW_240); // KONTROL EDİLMELİ PACK DÜZGÜN MÜ.

    packed.try_into().unwrap()
}

fn unpack_order(packed_order: felt252) -> Order {
    // TODO
    let packed: u256 = packed_order.into();

    let order_id: u32 = (packed & MASK_32).try_into().unwrap();
    let date: u64 = ((packed / TWO_POW_32) & MASK_64).try_into().unwrap();
    let amount: u128 = ((packed / TWO_POW_96) & MASK_128).try_into().unwrap();
    let price: u16 = ((packed / TWO_POW_224) & MASK_16).try_into().unwrap();
    let status: felt252 = ((packed / TWO_POW_240) & MASK_8).try_into().unwrap();

    Order {
        order_id : order_id, 
        date: date,
        amount: amount,
        price: price,
        status: status.try_into().unwrap()
    }
}


#[derive(Copy, Drop, Serde, PartialEq)]
enum Asset {
    Happens: (),
    Not: (),
}

#[derive(Copy, Drop, Serde, PartialEq)]
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

impl StorageAccessFelt252Array of StorageAccess<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        StorageAccessFelt252Array::read_at_offset_internal(address_domain, base, 0)
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Array<felt252>
    ) -> SyscallResult<()> {
        StorageAccessFelt252Array::write_at_offset_internal(address_domain, base, 0, value)
    }

    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8
    ) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        // Read the stored array's length. If the length is superior to 255, the read will fail.
        let len: u8 = StorageAccess::<u8>::read_at_offset_internal(address_domain, base, offset)
            .expect('Storage Span too large');
        offset += 1;

        // Sequentially read all stored elements and append them to the array.
        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = StorageAccess::<felt252>::read_at_offset_internal(
                address_domain, base, offset
            )
                .unwrap();
            arr.append(value);
            offset += StorageAccess::<felt252>::size_internal(value);
        };

        // Return the array.
        Result::Ok(arr)
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8, mut value: Array<felt252>
    ) -> SyscallResult<()> {
        // // Store the length of the array in the first storage slot.
        let len: u8 = value.len().try_into().expect('Storage - Span too large');
        StorageAccess::<u8>::write_at_offset_internal(address_domain, base, offset, len);
        offset += 1;

        // Store the array elements sequentially
        loop {
            match value.pop_front() {
                Option::Some(element) => {
                    StorageAccess::<felt252>::write_at_offset_internal(
                        address_domain, base, offset, element
                    )?;
                    offset += StorageAccess::<felt252>::size_internal(element);
                },
                Option::None(_) => {
                    break Result::Ok(());
                }
            };
        }
    }

    fn size_internal(value: Array<felt252>) -> u8 {
        if value.len() == 0 {
            return 1;
        }
        1_u8 + StorageAccess::<felt252>::size_internal(*value[0]) * value.len().try_into().unwrap()
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