use traits::{Into, TryInto};
use debug::PrintTrait;
use expectium::config::{Order};
impl OrderPrint of PrintTrait<Order> {
    fn print(self: Order) {
        Into::<_, felt252>::into(self.order_id).print();
        Into::<_, felt252>::into(self.date).print();
        Into::<_, felt252>::into(self.amount).print();
        Into::<_, felt252>::into(self.price).print();
        Into::<_, felt252>::into(self.status).print();
    }
}

#[cfg(test)]
mod tests {
    use expectium::config::{pack_order, unpack_order, Order};
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use debug::PrintTrait;
    use super::OrderPrint;

    #[test]
    #[available_gas(30000000)]
    fn test_packing() {
        let unpacked_order_id: u32 = 120_u32;
        let unpacked_date: u64 = 12718736211_u64;
        let unpacked_amount: u128 = 1391739747178378912341134_u128;
        let unpacked_price: u16 = 4388_u16;
        let unpacked_status: felt252 = 3;

        let sample_order: Order = Order {
            order_id : unpacked_order_id,
            date: unpacked_date,
            amount: unpacked_amount,
            price: unpacked_price,
            status: unpacked_status.try_into().unwrap()
        };
        let packed_order: felt252 = pack_order(sample_order);

        packed_order.print();

        let unpacked_order: Order = unpack_order(packed_order);

        unpacked_order.print();

        assert(unpacked_order_id == unpacked_order.order_id, 'orderid wrong');
        assert(unpacked_date == unpacked_order.date, 'orderid wrong');
        assert(unpacked_amount == unpacked_order.amount, 'orderid wrong');
        assert(unpacked_price == unpacked_order.price, 'orderid wrong');
        assert(unpacked_status.try_into().unwrap() == unpacked_order.status, 'orderid wrong');
    }
}