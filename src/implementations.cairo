use starknet::{Store, ContractAddress, StorageBaseAddress, SyscallResult};
use array::{ArrayTrait, SpanTrait};
use traits::{Into, TryInto};
use result::ResultTrait;
use option::OptionTrait;
use hash::LegacyHash;
use expectium::types::{OrderStatus, Asset};

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

impl OrderStatusIntoU256 of Into<OrderStatus, u256> {
    fn into(self: OrderStatus) -> u256 {
        match self {
            OrderStatus::Initialized(()) => 0_u256,
            OrderStatus::PartiallyFilled(()) => 1_u256,
            OrderStatus::Filled(()) => 2_u256,
            OrderStatus::Cancelled(()) => 3_u256,
        }
    }
}

impl Felt252TryIntoOrderStatus of TryInto<felt252, OrderStatus> {
    fn try_into(self: felt252) -> Option<OrderStatus> {
        if (self == 0) {
            return Option::Some(OrderStatus::Initialized(()));
        }
        if (self == 1) {
            return Option::Some(OrderStatus::PartiallyFilled(()));
        }
        if (self == 2) {
            return Option::Some(OrderStatus::Filled(()));
        }
        if (self == 3) {
            return Option::Some(OrderStatus::Cancelled(()));
        }

        Option::None(())
    }
}

impl StoreU32Array of Store<Array<u32>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<u32>> {
        StoreU32Array::read_at_offset(address_domain, base, 0)
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Array<u32>
    ) -> SyscallResult<()> {
        StoreU32Array::write_at_offset(address_domain, base, 0, value)
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8
    ) -> SyscallResult<Array<u32>> {
        let mut arr: Array<u32> = ArrayTrait::new();

        let len: u8 = Store::<
            u8
        >::read_at_offset(address_domain, base, offset) // 0. offsette array length
            .expect('Storage arr too large');
        offset += 1;

        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = Store::<u32>::read_at_offset(address_domain, base, offset).unwrap();
            arr.append(value);
            offset += Store::<u32>::size();
        };

        // Return the array.
        Result::Ok(arr)
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8, mut value: Array<u32>
    ) -> SyscallResult<()> {
        let len: u8 = value.len().try_into().expect('Storage - Span too large');
        Store::<u8>::write_at_offset(address_domain, base, offset, len);
        offset += 1;

        // Store the array elements sequentially
        loop {
            match value.pop_front() {
                Option::Some(element) => {
                    Store::<u32>::write_at_offset(address_domain, base, offset, element).unwrap();
                    offset += Store::<u32>::size();
                },
                Option::None(_) => { break Result::Ok(()); }
            };
        }
    }
    fn size() -> u8 {
        1_u8 // Nasıl okuyacağız? aptal starknet
    }
}

impl StoreFelt252Array of Store<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        StoreFelt252Array::read_at_offset(address_domain, base, 0)
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Array<felt252>
    ) -> SyscallResult<()> {
        StoreFelt252Array::write_at_offset(address_domain, base, 0, value)
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8
    ) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        let len: u8 = Store::<
            u8
        >::read_at_offset(address_domain, base, offset) // 0. offsette array length
            .expect('Storage arr too large');
        offset += 1;

        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = Store::<felt252>::read_at_offset(address_domain, base, offset).unwrap();
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
                    Store::<felt252>::write_at_offset(address_domain, base, offset, element)
                        .unwrap();
                    offset += Store::<felt252>::size();
                },
                Option::None(_) => { break Result::Ok(()); }
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

impl AssetIntoU8 of Into<Asset, u8> {
    fn into(self: Asset) -> u8 {
        match self {
            Asset::Happens(()) => 0_u8,
            Asset::Not(()) => 1_u8,
        }
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
        if (self == 0) {
            return Option::Some(Asset::Happens(()));
        }
        if (self == 1) {
            return Option::Some(Asset::Not(()));
        }

        Option::None(())
    }
}
