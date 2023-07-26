use expectium::config::{Asset};
use starknet::{ContractAddress};

#[starknet::interface]
trait IOrderbook<TContractState> {
    fn insert_buy_order(ref self: TContractState, asset: Asset, amount: u256, price: u16) -> u32; // order_id döndürür
    fn insert_sell_order(ref self: TContractState, asset: Asset, amount: u256, price: u16) -> u32;
}

#[starknet::contract]
mod Orderbook {
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use expectium::config::{Order, Asset, OrderStatus, StorageAccessFelt252Array, pack_order, unpack_order};
    use expectium::interfaces::{IMarketDispatcher, IMarketDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait};
    use array::{ArrayTrait, SpanTrait};
    use super::IOrderbook;
    use traits::{Into, TryInto};

    #[storage]
    struct Storage {
        market: ContractAddress, // connected market address
        quote_token: ContractAddress,
        happens: LegacyMap<u8, Array<felt252>>, // 0 buy 1 sell
        not: LegacyMap<u8, Array<felt252>>,
        market_makers: LegacyMap<u32, ContractAddress>, // Orderid -> Order owner
        order_count: u32,
    }

    #[external(v0)]
    impl Orderbook of IOrderbook<ContractState> {
        // Market order için price 1 gönderilebilir.
        fn insert_sell_order(ref self: ContractState, asset: Asset, amount: u256, price: u16) -> u32 {
            let caller = get_caller_address();
            let time = get_block_timestamp();

            assert(price > 0_u16, 'price zero');    // Fiyat sadece 0 ile 10000 arasında olabilir. 10000 = 1$
            assert(price <= 10000_u16, 'price too high');

            assert(amount.high == 0, 'amount too high'); // sadece u128 supportu var
            let amount_low = amount.low;

            // asseti alalım
            _receive_assets(ref self, asset, caller, amount);

            // loop ile eşleşecek order var mı bakalım.
            let amount_left = _match_incoming_sell_order(ref self, caller, asset, amount_low, price);

            if(amount_left == 0) {
                return 0_u32;
            }

            ///////////////////////////////////////////////////////////////
            /////// TODO: Burada bir yerde orderları tekrar sıralamalıyız.
            ///////////////////////////////////////////////////////////////

            if(amount_left < amount_low) {
                let order_id = self.order_count.read() + 1; // 0. order id boş bırakılıyor. 0 döner ise order tamamen eşleşti demek.
                self.order_count.write(order_id + 1); // order id arttır.

                let order: Order = Order {
                    order_id: order_id, date: time, amount: amount_left, price: price, status: OrderStatus::PartiallyFilled(()) // Eğer amount değiştiyse partially filled yap.
                };

                return order_id;
            }

            let order_id = self.order_count.read() + 1; // 0. order id boş bırakılıyor. 0 döner ise order tamamen eşleşti demek.
            self.order_count.write(order_id + 1); // order id arttır.

            let order: Order = Order {
                order_id: order_id, date: time, amount: amount_left, price: price, status: OrderStatus::Initialized(()) // Eğer amount değiştiyse partially filled yap.
            };

            return order_id;
        }
    }

    fn _match_incoming_sell_order(ref self: ContractState, taker: ContractAddress, asset: Asset, amount: u128, price: u16) -> u128 {
        // TODO: Kontrol edilmeli.
        // Mevcut buy emirleriyle eşleştirelim.
        match asset {
            Asset::Happens(()) => {
                let mut amount_left = amount;
                let current_orders: Array<felt252> = self.happens.read(0_u8); // mevcut happens alış emirleri.

                if(current_orders.len() == 0) { // order yoksa direk emri girelim.
                    return amount_left;
                }

                let mut i = 0;
                loop {
                    if(amount_left == 0) {
                        break;
                    }

                    let mut order: Order = unpack_order(*current_orders.at(i));
                    if(order.price < price) { // sıradaki orderin fiyatı limit fiyattan düşük. Return edelim.
                        break;
                    };
                    let order_owner: ContractAddress = self.market_makers.read(order.order_id);

                    if(order.amount < amount_left) {
                        // bu order yetersiz. amount_left azaltılıp devam edecek.
                        let spent_amount = order.amount;
                        amount_left -= spent_amount;


                        order.status = OrderStatus::Filled(());
                        order.amount = 0; // TODO bu orderları arraydede güncellemek lazım.

                        // complete transfers.

                        // Mevcut Order(Maker) sahibine, asseti gönderelim.
                        _transfer_assets(ref self, Asset::Happens(()), order_owner, u256 { high: 0, low: spent_amount }); // TODO: FEE
                        // Yeni order girene(Taker), quote gönderelim.
                        let quote_amount: u256 = u256 { high: 0, low: spent_amount } * order.price.into(); // TODO: FEE
                        _transfer_quote_token(ref self, taker, quote_amount);

                        continue;
                    };

                    // Eğer order miktarı amount_left büyükse burası çalışacak.
                    if(order.amount >= amount_left) { // matchle ve return zero
                        let spent_amount = amount_left;
                        amount_left = 0;

                        if(order.amount == spent_amount) {
                            order.status = OrderStatus::Filled(());
                            order.amount = 0;
                        } else {
                            order.status = OrderStatus::PartiallyFilled(());
                            order.amount -= spent_amount;
                        }
                        
                        _transfer_assets(ref self, Asset::Happens(()), order_owner, u256 { high: 0, low: spent_amount }); // TODO: FEE
                        let quote_amount: u256 = u256 { high: 0, low: spent_amount } * order.price.into(); // TODO: FEE
                        _transfer_quote_token(ref self, taker, quote_amount);
                        break;
                    };
                };

                return amount_left;
            },
            Asset::Not(()) => {
                let mut amount_left = amount;
                let current_orders: Array<felt252> = self.not.read(0_u8); // mevcut not alış emirleri.

                if(current_orders.len() == 0) { // order yoksa direk emri girelim.
                    return amount_left;
                }

                let mut i = 0;
                loop {
                    if(amount_left == 0) {
                        break;
                    }

                    let mut order: Order = unpack_order(*current_orders.at(i));
                    if(order.price < price) { // sıradaki orderin fiyatı limit fiyattan düşük. Return edelim.
                        break;
                    };
                    let order_owner: ContractAddress = self.market_makers.read(order.order_id);

                    if(order.amount < amount_left) {
                        // bu order yetersiz. amount_left azaltılıp devam edecek.
                        let spent_amount = order.amount;
                        amount_left -= spent_amount;


                        order.status = OrderStatus::Filled(());
                        order.amount = 0; // TODO bu orderları arraydede güncellemek lazım.

                        // complete transfers.

                        // Mevcut Order(Maker) sahibine, asseti gönderelim.
                        _transfer_assets(ref self, Asset::Not(()), order_owner, u256 { high: 0, low: spent_amount }); // TODO: FEE
                        // Yeni order girene(Taker), quote gönderelim.
                        let quote_amount: u256 = u256 { high: 0, low: spent_amount } * order.price.into(); // TODO: FEE
                        _transfer_quote_token(ref self, taker, quote_amount);

                        continue;
                    };

                    // Eğer order miktarı amount_left büyükse burası çalışacak.
                    if(order.amount >= amount_left) { // matchle ve return zero
                        let spent_amount = amount_left;
                        amount_left = 0;

                        if(order.amount == spent_amount) {
                            order.status = OrderStatus::Filled(());
                            order.amount = 0;
                        } else {
                            order.status = OrderStatus::PartiallyFilled(());
                            order.amount -= spent_amount;
                        }
                        
                        _transfer_assets(ref self, Asset::Not(()), order_owner, u256 { high: 0, low: spent_amount }); // TODO: FEE
                        let quote_amount: u256 = u256 { high: 0, low: spent_amount } * order.price.into(); // TODO: FEE
                        _transfer_quote_token(ref self, taker, quote_amount);
                        break;
                    };
                };

                return amount_left; 
            }
        }
    }

    fn _match_incoming_buy_order() -> u128 {
        // TODO
    }

    fn _receive_quote_token(ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256) {
        let this_addr = get_contract_address();
        let quote = self.quote_token.read();

        let balanceBefore = IERC20Dispatcher { contract_address: quote}.balanceOf(this_addr);

        IERC20Dispatcher { contract_address: quote }.transferFrom(from, this_addr, amount);

        let balanceAfter = IERC20Dispatcher { contract_address: quote }.balanceOf(this_addr);
        assert((balanceAfter - amount) >= balanceBefore, 'EXPM: transfer fail')
    }

    fn _transfer_quote_token(ref self: ContractState, to: ContractAddress, amount: u256) {
        IERC20Dispatcher { contract_address: self.quote_token.read() }.transfer(to, amount);
    }

    fn _transfer_assets(ref self: ContractState, asset: Asset, to: ContractAddress, amount: u256) {
        let market = self.market.read();
        let this_addr = get_contract_address();

        let balance = IMarketDispatcher { contract_address: market }.balance_of(this_addr, asset);
        assert(balance >= amount, 'EXPO: balance exceeds');

        IMarketDispatcher { contract_address: market }.transfer(to, asset, amount);
    }

    fn _receive_assets(ref self: ContractState, asset: Asset, from: ContractAddress, amount: u256) {
        let this_addr = get_contract_address();
        let market = self.market.read();

        let balance_before = IMarketDispatcher { contract_address: market }.balance_of(this_addr, asset);
        IMarketDispatcher { contract_address: market }.transfer_from(from, this_addr, asset, amount);
        let balance_after = IMarketDispatcher { contract_address: market }.balance_of(this_addr, asset);

        assert((balance_after - amount) >= balance_before, 'EXPO: transfer fail')
    }
}