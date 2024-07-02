#[starknet::contract]
mod Orderbook {
    use starknet::{
        ContractAddress, ClassHash, get_block_timestamp, get_caller_address, get_contract_address,
        replace_class_syscall
    };
    use expectium::types::{Order, Asset, PlatformFees, FeeType, OrderStatus};
    use expectium::utils::{pack_order, unpack_order};
    use expectium::implementations::{StoreFelt252Array, StoreU32Array, AssetLegacyHash};
    use expectium::interfaces::{
        IOrderbook, IMarketDispatcher, IMarketDispatcherTrait, IERC20Dispatcher,
        IERC20DispatcherTrait, IDistributorDispatcher, IDistributorDispatcherTrait,
        IStatisticsDispatcher, IStatisticsDispatcherTrait
    };
    use expectium::sort::{_sort_orders_descending, _sort_orders_ascending};
    use array::{ArrayTrait, SpanTrait};
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use clone::Clone;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrderInserted: OrderInserted,
        Matched: Matched,
        Cancelled: Cancelled
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct OrderInserted {
        maker: ContractAddress,
        asset: Asset,
        side: u8,
        amount: u256,
        price: u16,
        id: u32,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct Matched {
        maker_order_id: u32,
        maker: ContractAddress,
        asset: Asset,
        matched_amount: u256,
        price: u16,
        taker: ContractAddress,
        taker_side: u8
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct Cancelled {
        id: u32,
        canceller: ContractAddress,
    }


    #[storage]
    struct Storage {
        market: ContractAddress, // connected market address
        quote_token: ContractAddress,
        distributor: ContractAddress, // Fee distributor contract // TODO !!
        happens: LegacyMap<u8, Array<felt252>>, // 0 buy 1 sell
        not: LegacyMap<u8, Array<felt252>>,
        market_makers: LegacyMap<u32, ContractAddress>, // Orderid -> Order owner
        user_orders: LegacyMap<ContractAddress, Array<u32>>, // User -> Order id array
        order_count: u32,
        fees: PlatformFees, // 10000 bp. TODO: set fees
        is_emergency: bool,
        operator: ContractAddress, // Orderbook operator: Will have superrights until testnet.
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        market: ContractAddress,
        operator: ContractAddress,
        quote_token: ContractAddress,
        distributor: ContractAddress
    ) {
        self.operator.write(operator);
        self.market.write(market);
        self.quote_token.write(quote_token);
        self.distributor.write(distributor);

        IERC20Dispatcher { contract_address: quote_token }
            .approve(distributor, integer::BoundedInt::max());
    }

    #[abi(embed_v0)]
    impl Orderbook of IOrderbook<ContractState> {
        fn get_order(self: @ContractState, asset: Asset, side: u8, order_id: u32) -> felt252 {
            assert(side < 2_u8, 'side wrong');
            _find_order(self, asset, side, order_id)
        }

        fn get_orders(self: @ContractState, asset: Asset, side: u8) -> Array<felt252> {
            assert(side < 2_u8, 'side wrong');
            match asset {
                Asset::Happens(()) => self.happens.read(side),
                Asset::Not(()) => self.not.read(side)
            }
        }

        fn market(self: @ContractState) -> ContractAddress {
            self.market.read()
        }

        fn operator(self: @ContractState) -> ContractAddress {
            self.operator.read()
        }

        fn distributor(self: @ContractState) -> ContractAddress {
            self.distributor.read()
        }

        fn get_order_owner(self: @ContractState, order_id: u32) -> ContractAddress {
            self.market_makers.read(order_id)
        }

        // Returns order packed, if order not exist returns 0
        fn get_order_with_id(self: @ContractState, order_id: u32) -> (Asset, u8, felt252) {
            let mut found_order: felt252 = 0;

            found_order = _find_order(self, Asset::Happens(()), 0_u8, order_id);
            if (found_order != 0) {
                return (Asset::Happens(()), 0_u8, found_order);
            }

            found_order = _find_order(self, Asset::Happens(()), 1_u8, order_id);
            if (found_order != 0) {
                return (Asset::Happens(()), 1_u8, found_order);
            }

            found_order = _find_order(self, Asset::Not(()), 0_u8, order_id);
            if (found_order != 0) {
                return (Asset::Not(()), 0_u8, found_order);
            }

            found_order = _find_order(self, Asset::Not(()), 1_u8, order_id);
            return (Asset::Not(()), 1_u8, found_order);
        }

        fn get_user_orders(self: @ContractState, user: ContractAddress) -> Array<u32> {
            self.user_orders.read(user)
        }

        // quote_amount: usdc miktarı
        // price : fiyat
        fn insert_buy_order(
            ref self: ContractState, asset: Asset, quote_amount: u256, price: u16
        ) -> u32 {
            assert(!_is_emergency(@self), 'in emergency');
            // 1 $ = 10000

            let caller = get_caller_address();
            let time = get_block_timestamp();

            assert(price > 0_u16, 'price zero');
            assert(price <= 10000_u16, 'price too high');

            assert(quote_amount.high == 0, 'quote too high');

            _receive_quote_token(ref self, caller, quote_amount);

            let quote_left = _match_incoming_buy_order(
                ref self, caller, asset, quote_amount, price
            );

            if (quote_left == 0) {
                return 0_u32;
            }
            let order_id = self.order_count.read() + 1;
            self.order_count.write(order_id);

            let order_amount = quote_left / price.into();

            let mut order: Order = Order {
                order_id: order_id,
                date: time,
                amount: order_amount.low,
                price: price,
                status: OrderStatus::Initialized(
                    ()
                ) // Eğer amount değiştiyse partially filled yap.
            };

            let order_packed = pack_order(order);
            self.market_makers.write(order_id, caller);
            _add_user_order_ids(ref self, caller, order_id);

            match asset {
                Asset::Happens(()) => {
                    let mut current_orders = self.happens.read(0_u8);
                    current_orders.append(order_packed);

                    let sorted_orders = _sort_orders(false, current_orders);
                    self.happens.write(0_u8, sorted_orders);
                },
                Asset::Not(()) => {
                    let mut current_orders = self.not.read(0_u8);
                    current_orders.append(order_packed);

                    let sorted_orders = _sort_orders(false, current_orders);
                    self.not.write(0_u8, sorted_orders);
                }
            };

            self
                .emit(
                    Event::OrderInserted(
                        OrderInserted {
                            maker: caller,
                            asset: asset,
                            side: 0_u8,
                            amount: order_amount,
                            price: price,
                            id: order_id
                        }
                    )
                );

            return order_id;
        }


        // Market order için price 1 gönderilebilir.
        fn insert_sell_order(
            ref self: ContractState, asset: Asset, amount: u256, price: u16
        ) -> u32 {
            assert(!_is_emergency(@self), 'in emergency');

            let caller = get_caller_address();
            let time = get_block_timestamp();

            assert(
                price > 0_u16, 'price zero'
            ); // Fiyat sadece 0 ile 10000 arasında olabilir. 10000 = 1$
            assert(price <= 10000_u16, 'price too high');

            assert(amount.high == 0, 'amount too high'); // sadece u128 supportu var
            let amount_low = amount.low;

            // asseti alalım
            _receive_assets(ref self, asset, caller, amount);

            // loop ile eşleşecek order var mı bakalım.
            let amount_left = _match_incoming_sell_order(
                ref self, caller, asset, amount_low, price
            );

            if (amount_left == 0) {
                return 0_u32;
            }

            let order_id = self.order_count.read()
                + 1; // 0. order id boş bırakılıyor. 0 döner ise order tamamen eşleşti demek.
            self.order_count.write(order_id);

            let mut order: Order = Order {
                order_id: order_id,
                date: time,
                amount: amount_left,
                price: price,
                status: OrderStatus::Initialized(
                    ()
                ) // Eğer amount değiştiyse partially filled yap.
            };

            let order_packed = pack_order(order);
            self.market_makers.write(order_id, caller); // market maker olarak ekleyelim.
            _add_user_order_ids(ref self, caller, order_id);

            match asset {
                Asset::Happens(()) => {
                    let mut current_orders = self.happens.read(1_u8);
                    current_orders.append(order_packed);

                    let sorted_orders = _sort_orders(true, current_orders);
                    self.happens.write(1_u8, sorted_orders);
                },
                Asset::Not(()) => {
                    let mut current_orders = self.not.read(1_u8);
                    current_orders.append(order_packed);

                    let sorted_orders = _sort_orders(true, current_orders);
                    self.not.write(1_u8, sorted_orders);
                }
            };

            self
                .emit(
                    Event::OrderInserted(
                        OrderInserted {
                            maker: caller,
                            asset: asset,
                            side: 1_u8,
                            amount: u256 { high: 0, low: amount_left },
                            price: price,
                            id: order_id
                        }
                    )
                );

            return order_id;
        }

        fn cancel_buy_order(ref self: ContractState, asset: Asset, order_id: u32) {
            assert(!_is_emergency(@self), 'in emergency');

            // TODO Kontrol
            let caller = get_caller_address();
            let order_owner: ContractAddress = self.market_makers.read(order_id);

            assert(order_owner == caller, 'owner wrong');

            _cancel_buy_order(ref self, order_owner, asset, order_id);

            _remove_user_order_ids(ref self, order_owner, order_id);

            self.emit(Event::Cancelled(Cancelled { id: order_id, canceller: caller }));
        }

        fn cancel_sell_order(ref self: ContractState, asset: Asset, order_id: u32) {
            assert(!_is_emergency(@self), 'in emergency');
            // TODO Kontrol
            let caller = get_caller_address();

            let order_owner: ContractAddress = self.market_makers.read(order_id);

            // Order varmı kontrol etmeye gerek yok zaten caller ile kontrol ettik.
            assert(order_owner == caller, 'owner wrong');

            _cancel_sell_order(ref self, order_owner, asset, order_id);
            _remove_user_order_ids(ref self, order_owner, order_id);

            self.emit(Event::Cancelled(Cancelled { id: order_id, canceller: caller }));
        }

        fn emergency_toggle(ref self: ContractState) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            self.is_emergency.write(!self.is_emergency.read())
        }

        fn refresh_distributor_approval(ref self: ContractState) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            let distributor = self.distributor.read();

            IERC20Dispatcher { contract_address: self.quote_token.read() }
                .approve(distributor, integer::BoundedInt::max());
        }

        fn set_fees(ref self: ContractState, fees: PlatformFees) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            assert(fees.taker <= 1000_u32, 'taker too much');
            assert(fees.maker <= 1000_u32, 'maker too much'); // Max fee %10

            self.fees.write(fees);
        }

        fn upgrade_contract(ref self: ContractState, new_class: ClassHash) {
            let caller = get_caller_address();
            assert(caller == self.operator.read(), 'only operator');

            replace_class_syscall(new_class);
        }
    }

    fn _add_user_order_ids(ref self: ContractState, user: ContractAddress, new_order_id: u32) {
        let mut current_order_ids: Array<u32> = self.user_orders.read(user);

        let mut new_order_ids_array = ArrayTrait::<u32>::new();
        new_order_ids_array.append(new_order_id);

        loop {
            match current_order_ids.pop_front() {
                Option::Some(v) => {
                    // v orderid u32
                    new_order_ids_array.append(v);
                },
                Option::None(()) => { break; }
            };
        };

        self.user_orders.write(user, new_order_ids_array);
    }

    fn _remove_user_order_ids(ref self: ContractState, user: ContractAddress, order_id: u32) {
        let mut current_order_ids: Array<u32> = self.user_orders.read(user);

        let mut new_order_ids_array = ArrayTrait::<u32>::new();

        loop {
            match current_order_ids.pop_front() {
                Option::Some(v) => {
                    if (v == order_id) {
                        continue;
                    };
                    new_order_ids_array.append(v);
                },
                Option::None(()) => { break; }
            };
        };

        self.user_orders.write(user, new_order_ids_array);
    }

    fn _match_incoming_sell_order(
        ref self: ContractState, taker: ContractAddress, asset: Asset, amount: u128, price: u16
    ) -> u128 {
        // TODO: Kontrol edilmeli.
        // Mevcut buy emirleriyle eşleştirelim.
        match asset {
            Asset::Happens(()) => {
                let mut amount_left = amount;
                let mut current_orders: Array<felt252> = self
                    .happens
                    .read(0_u8); // mevcut happens alış emirleri.

                if (current_orders.len() == 0) { // order yoksa direk emri girelim.
                    return amount_left;
                }

                let mut orders_modified = ArrayTrait::<felt252>::new();

                loop {
                    match current_orders.pop_front() {
                        Option::Some(v) => {
                            let mut order: Order = unpack_order(v);

                            if (amount_left == 0
                                || order
                                    .price < price) { // Satış geldiği için order fiyatı bu fiyattan yüksek veya eşitlerle eşleşmeli.
                                // bundan sonraki orderlar eşleşemez.
                                // sadece listeye geri ekleyip devam edelim.
                                orders_modified.append(v); // direk packli hali gönderelim.
                                continue;
                            };
                            let order_owner: ContractAddress = self
                                .market_makers
                                .read(order.order_id);

                            if (order.amount < amount_left) {
                                let spent_amount = order.amount;
                                amount_left -= spent_amount;

                                order.status = OrderStatus::Filled(());
                                order.amount = 0;

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), u256 { high: 0, low: spent_amount }
                                ); // Gönderilecek net miktar ve fee hesaplayalım.
                                _transfer_assets(
                                    ref self, Asset::Happens(()), order_owner, net_amount
                                ); // Net miktarı emir sahibine gönderelim (maker)
                                _transfer_assets(
                                    ref self, Asset::Happens(()), self.operator.read(), maker_fee
                                ); // Fee miktarını operatore gönderelim

                                let quote_amount: u256 = u256 { high: 0, low: spent_amount }
                                    * order
                                        .price
                                        .into(); // quote_amount hesaplayalım (price * amount)
                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), quote_amount / 10000
                                ); // emir giren satıcı olduğu için taker fee hesaplayalım
                                _transfer_quote_token(
                                    ref self, taker, net_amount
                                ); // net miktarı callera gönderelim.
                                //IDistributorDispatcher { contract_address: self.distributor.read() }.new_distribution(self.quote_token.read(), taker_fee); // kalan taker fee yi distribution registerlayalım.
                                _distribute_fees(@self, taker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Happens(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 1_u8
                                            }
                                        )
                                    );

                                // Orderı geri eklemeye gerek yok zaten tamamlandı.
                                continue;
                            };

                            if (order.amount >= amount_left) {
                                let spent_amount = amount_left;
                                amount_left = 0;

                                if (order.amount == spent_amount) {
                                    order.status = OrderStatus::Filled(());
                                    order.amount = 0;
                                // amount 0 olunca eklemeye gerek yok.
                                } else {
                                    order.status = OrderStatus::PartiallyFilled(());
                                    order.amount -= spent_amount;
                                    orders_modified
                                        .append(
                                            pack_order(order)
                                        ); // güncellenen orderi ekleyelim.
                                };

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), u256 { high: 0, low: spent_amount }
                                ); // Satılacak amounttan fee hesaplayalım
                                _transfer_assets(
                                    ref self, Asset::Happens(()), order_owner, net_amount
                                ); // net miktarı emir sahibine gönderelim
                                _transfer_assets(
                                    ref self, Asset::Happens(()), self.operator.read(), maker_fee
                                ); // assetleri operatore gönderelim fee

                                // Yeni order girene(Taker), quote gönderelim.
                                let quote_amount: u256 = u256 { high: 0, low: spent_amount }
                                    * order.price.into(); // quote hesaplayalım
                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), quote_amount / 10000
                                ); // fee hesaplayalım taker
                                _transfer_quote_token(
                                    ref self, taker, net_amount
                                ); // net miktarı emir girene gönderelim.
                                // IDistributorDispatcher { contract_address: self.distributor.read() }.new_distribution(self.quote_token.read(), taker_fee); // register fee distro
                                _distribute_fees(@self, taker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Happens(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 1_u8
                                            }
                                        )
                                    );
                            };
                        },
                        Option::None(()) => {
                            // burada order listesini güncelleyebiliriz.
                            let last_orders = orders_modified.clone();
                            let sorted_orders = _sort_orders(
                                false, last_orders
                            ); // buy emirleri sıralanacağı için fiyat yukardan aşağı olmalı.
                            self.happens.write(0_u8, sorted_orders); // order listesi güncellendi.
                            break;
                        }
                    };
                };
                // en son harcanmayan miktar geri dönmeli.
                return amount_left;
            },
            Asset::Not(()) => { // TODO
                let mut amount_left = amount;
                let mut current_orders: Array<felt252> = self
                    .not
                    .read(0_u8); // mevcut not alış emirleri.

                if (current_orders.len() == 0) { // order yoksa direk emri girelim.
                    return amount_left;
                }

                let mut orders_modified = ArrayTrait::<felt252>::new();

                loop {
                    match current_orders.pop_front() {
                        Option::Some(v) => {
                            let mut order: Order = unpack_order(v);

                            if (amount_left == 0
                                || order
                                    .price < price) { // Satış geldiği için order fiyatı bu fiyattan yüksek veya eşitlerle eşleşmeli.
                                // bundan sonraki orderlar eşleşemez.
                                // sadece listeye geri ekleyip devam edelim.
                                orders_modified.append(v); // direk packli hali gönderelim.
                                continue;
                            };
                            let order_owner: ContractAddress = self
                                .market_makers
                                .read(order.order_id);

                            if (order.amount < amount_left) {
                                let spent_amount = order.amount;
                                amount_left -= spent_amount;

                                order.status = OrderStatus::Filled(());
                                order.amount = 0;

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), u256 { high: 0, low: spent_amount }
                                );
                                _transfer_assets(ref self, Asset::Not(()), order_owner, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Not(()), self.operator.read(), maker_fee
                                ); // TODO: Daha sonrasında assetide nft holderlarına dağıtacağız.

                                // Yeni order girene(Taker), quote gönderelim.
                                let quote_amount: u256 = u256 { high: 0, low: spent_amount }
                                    * order.price.into(); // TODO: FEE
                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), quote_amount / 10000
                                );
                                _transfer_quote_token(ref self, taker, net_amount);
                                //IDistributorDispatcher { contract_address: self.distributor.read() }.new_distribution(self.quote_token.read(), taker_fee); // register fee distro
                                _distribute_fees(@self, taker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Not(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 1_u8
                                            }
                                        )
                                    );

                                // Orderı geri eklemeye gerek yok zaten tamamlandı.
                                continue;
                            };

                            if (order.amount >= amount_left) {
                                let spent_amount = amount_left;
                                amount_left = 0;

                                if (order.amount == spent_amount) {
                                    order.status = OrderStatus::Filled(());
                                    order.amount = 0;
                                // amount 0 olunca eklemeye gerek yok.
                                } else {
                                    order.status = OrderStatus::PartiallyFilled(());
                                    order.amount -= spent_amount;
                                    orders_modified
                                        .append(
                                            pack_order(order)
                                        ); // güncellenen orderi ekleyelim.
                                };

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), u256 { high: 0, low: spent_amount }
                                );
                                _transfer_assets(ref self, Asset::Not(()), order_owner, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Not(()), self.operator.read(), maker_fee
                                ); // TODO: Daha sonrasında assetide nft holderlarına dağıtacağız.

                                // Yeni order girene(Taker), quote gönderelim.
                                let quote_amount: u256 = u256 { high: 0, low: spent_amount }
                                    * order.price.into(); // TODO: FEE
                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), quote_amount / 10000
                                );
                                _transfer_quote_token(ref self, taker, net_amount);
                                // IDistributorDispatcher { contract_address: self.distributor.read() }.new_distribution(self.quote_token.read(), taker_fee); // register fee distro
                                _distribute_fees(@self, taker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Not(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 1_u8
                                            }
                                        )
                                    );
                            };
                        },
                        Option::None(()) => {
                            // burada order listesini güncelleyebiliriz.
                            let last_orders = orders_modified.clone();
                            let sorted_orders = _sort_orders(
                                false, last_orders
                            ); // buy emirleri sıralanacağı için fiyat yukardan aşağı olmalı.
                            self.not.write(0_u8, sorted_orders); // order listesi güncellendi.
                            break;
                        }
                    };
                };
                // en son harcanmayan miktar geri dönmeli.
                return amount_left;
            }
        }
    }

    // returns harcanmayan quote_amount * 10000
    // returnlenen değer 100000 ile çarpılmış. price cinsinden değer.
    fn _match_incoming_buy_order(
        ref self: ContractState,
        taker: ContractAddress,
        asset: Asset,
        quote_amount: u256,
        price: u16
    ) -> u256 {
        match asset {
            Asset::Happens(()) => {
                let mut quote_left = quote_amount
                    * 10000; // 10000 ile çarpınca 1 usd price bp eşit oluyor. 10000 price = 1 usdc
                let mut current_orders: Array<felt252> = self
                    .happens
                    .read(1_u8); // mevcut satış emirleri

                if (current_orders.len() == 0) {
                    return quote_left;
                }

                let mut orders_modified = ArrayTrait::<felt252>::new();

                loop {
                    match current_orders.pop_front() {
                        Option::Some(v) => {
                            let mut order: Order = unpack_order(v);

                            if (quote_left == 0 || order.price > price) {
                                orders_modified.append(v);
                                continue;
                            }

                            let order_owner: ContractAddress = self
                                .market_makers
                                .read(order.order_id);

                            let max_amount: u256 = quote_left
                                / order
                                    .price
                                    .into(); // hesaplama doğru quoteleft zaten çarpılmış.
                            assert(max_amount.high == 0, 'amount too high');

                            let maximum_amount_can_be_bought: u128 = max_amount.low;

                            if (order.amount < maximum_amount_can_be_bought) {
                                // bu order yeterli değil devam edecek.
                                let spent_amount = order.amount;
                                let quote_spent = spent_amount * order.price.into();

                                quote_left -= quote_spent.into();

                                order.status = OrderStatus::Filled(());
                                order.amount = 0;

                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), u256 { high: 0, low: spent_amount }
                                );

                                _transfer_assets(ref self, Asset::Happens(()), taker, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Happens(()), self.operator.read(), taker_fee
                                );

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), quote_spent.into() / 10000
                                );

                                _transfer_quote_token(
                                    ref self, order_owner, net_amount
                                ); // gönderilecek miktarı tekrar usdc çevirelim.
                                _distribute_fees(@self, maker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Happens(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 0_u8
                                            }
                                        )
                                    );

                                continue;
                            };

                            if (order.amount >= maximum_amount_can_be_bought) {
                                let spent_amount = maximum_amount_can_be_bought;
                                let quote_spent: u256 = u256 { high: 0, low: spent_amount }
                                    * order.price.into();

                                quote_left = 0;

                                if (order.amount == spent_amount) {
                                    order.status = OrderStatus::Filled(());
                                    order.amount = 0;
                                } else {
                                    order.status = OrderStatus::PartiallyFilled(());
                                    order.amount -= spent_amount;
                                    orders_modified.append(pack_order(order));
                                };

                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), u256 { high: 0, low: spent_amount }
                                );

                                _transfer_assets(ref self, Asset::Happens(()), taker, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Happens(()), self.operator.read(), taker_fee
                                );

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), quote_spent / 10000
                                );

                                _transfer_quote_token(ref self, order_owner, net_amount);
                                _distribute_fees(@self, maker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Happens(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 0_u8
                                            }
                                        )
                                    );
                            };
                        },
                        Option::None(()) => {
                            let last_orders = orders_modified.clone();
                            let sorted_orders = _sort_orders(true, last_orders);
                            self.happens.write(1_u8, sorted_orders);
                            break;
                        }
                    };
                };
                return quote_left;
            },
            Asset::Not(()) => {
                let mut quote_left = quote_amount * 10000;
                let mut current_orders: Array<felt252> = self
                    .not
                    .read(1_u8); // mevcut satış emirleri

                if (current_orders.len() == 0) {
                    return quote_left;
                }

                let mut orders_modified = ArrayTrait::<felt252>::new();

                loop {
                    match current_orders.pop_front() {
                        Option::Some(v) => {
                            let mut order: Order = unpack_order(v);

                            if (quote_left == 0 || order.price > price) {
                                orders_modified.append(v);
                                continue;
                            }

                            let order_owner: ContractAddress = self
                                .market_makers
                                .read(order.order_id);

                            let max_amount: u256 = quote_left / order.price.into();
                            assert(max_amount.high == 0, 'amount too high');

                            let maximum_amount_can_be_bought: u128 = max_amount.low;

                            if (order.amount < maximum_amount_can_be_bought) {
                                // bu order yeterli değil devam edecek.
                                let spent_amount = order.amount;
                                let quote_spent = spent_amount * order.price.into();

                                quote_left -= quote_spent.into();

                                order.status = OrderStatus::Filled(());
                                order.amount = 0;

                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), u256 { high: 0, low: spent_amount }
                                );

                                _transfer_assets(ref self, Asset::Not(()), taker, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Not(()), self.operator.read(), taker_fee
                                );

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), quote_spent.into() / 10000
                                );

                                _transfer_quote_token(ref self, order_owner, net_amount);
                                _distribute_fees(@self, maker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Not(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 0_u8
                                            }
                                        )
                                    );

                                continue;
                            };

                            if (order.amount >= maximum_amount_can_be_bought) {
                                let spent_amount = maximum_amount_can_be_bought;
                                let quote_spent: u256 = u256 { high: 0, low: spent_amount }
                                    * order.price.into();

                                quote_left = 0;

                                if (order.amount == spent_amount) {
                                    order.status = OrderStatus::Filled(());
                                    order.amount = 0;
                                } else {
                                    order.status = OrderStatus::PartiallyFilled(());
                                    order.amount -= spent_amount;
                                    orders_modified.append(pack_order(order));
                                };

                                let (net_amount, taker_fee) = _apply_fee(
                                    @self, FeeType::Taker(()), u256 { high: 0, low: spent_amount }
                                );

                                _transfer_assets(ref self, Asset::Not(()), taker, net_amount);
                                _transfer_assets(
                                    ref self, Asset::Not(()), self.operator.read(), taker_fee
                                );

                                let (net_amount, maker_fee) = _apply_fee(
                                    @self, FeeType::Maker(()), quote_spent / 10000
                                );

                                _transfer_quote_token(ref self, order_owner, net_amount);
                                _distribute_fees(@self, maker_fee);

                                self
                                    .emit(
                                        Event::Matched(
                                            Matched {
                                                maker_order_id: order.order_id,
                                                maker: order_owner,
                                                asset: Asset::Not(()),
                                                matched_amount: u256 { high: 0, low: spent_amount },
                                                price: order.price,
                                                taker: taker,
                                                taker_side: 0_u8
                                            }
                                        )
                                    );
                            };
                        },
                        Option::None(()) => {
                            let last_orders = orders_modified.clone();
                            let sorted_orders = _sort_orders(true, last_orders);
                            self.not.write(1_u8, sorted_orders);
                            break;
                        }
                    };
                };
                return quote_left;
            }
        }
    }

    fn _cancel_buy_order(
        ref self: ContractState, owner: ContractAddress, asset: Asset, order_id: u32
    ) {
        // gönderilecek miktar price * amount
        match asset {
            Asset::Happens(()) => {
                let mut orders = self.happens.read(0_u8);
                let mut new_orders = ArrayTrait::<felt252>::new();
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let unpacked_order: Order = unpack_order(v);

                            if (unpacked_order.order_id != order_id) {
                                new_orders.append(v);
                                continue;
                            }

                            let transfer_amount: u256 = unpacked_order.price.into()
                                * unpacked_order.amount.into();

                            _transfer_quote_token(ref self, owner, transfer_amount / 10000);
                        },
                        Option::None(()) => { break; }
                    };
                };

                let sorted_orders: Array<felt252> = _sort_orders(false, new_orders);
                self.happens.write(0_u8, sorted_orders);
            },
            Asset::Not(()) => {
                let mut orders = self.not.read(0_u8);
                let mut new_orders = ArrayTrait::<felt252>::new();
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let unpacked_order: Order = unpack_order(v);

                            if (unpacked_order.order_id != order_id) {
                                new_orders.append(v);
                                continue;
                            }

                            let transfer_amount: u256 = unpacked_order.price.into()
                                * unpacked_order.amount.into();

                            _transfer_quote_token(ref self, owner, transfer_amount / 10000);
                        },
                        Option::None(()) => { break; }
                    };
                };

                let sorted_orders: Array<felt252> = _sort_orders(false, new_orders);
                self.not.write(0_u8, sorted_orders);
            }
        };
    }

    fn _cancel_sell_order(
        ref self: ContractState, owner: ContractAddress, asset: Asset, order_id: u32
    ) {
        match asset {
            Asset::Happens(()) => {
                let mut orders = self.happens.read(1_u8);
                let mut new_orders = ArrayTrait::<felt252>::new();
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let unpacked_order: Order = unpack_order(v);

                            if (unpacked_order.order_id != order_id) {
                                new_orders.append(v);
                                continue;
                            };

                            _transfer_assets(
                                ref self, Asset::Happens(()), owner, unpacked_order.amount.into()
                            );
                        },
                        Option::None(()) => { break; }
                    };
                };

                let sorted_orders: Array<felt252> = _sort_orders(true, new_orders);
                self.happens.write(1_u8, sorted_orders);
            },
            Asset::Not(()) => {
                let mut orders = self.not.read(1_u8);
                let mut new_orders = ArrayTrait::<felt252>::new();
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let unpacked_order: Order = unpack_order(v);

                            if (unpacked_order.order_id != order_id) {
                                new_orders.append(v);
                                continue;
                            };

                            _transfer_assets(
                                ref self, Asset::Not(()), owner, unpacked_order.amount.into()
                            );
                        },
                        Option::None(()) => { break; }
                    };
                };

                let sorted_orders: Array<felt252> = _sort_orders(true, new_orders);
                self.not.write(1_u8, sorted_orders);
            }
        }
    }

    fn _find_order(self: @ContractState, asset: Asset, side: u8, order_id: u32) -> felt252 {
        match asset {
            Asset::Happens(()) => {
                let mut orders = self.happens.read(side);
                if (orders.len() == 0) {
                    return 0;
                }
                let mut found_order: felt252 = 0;
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let order = unpack_order(v);
                            if (order.order_id == order_id) {
                                found_order = v;
                                break;
                            };
                        },
                        Option::None(()) => { break; }
                    };
                };
                return found_order;
            },
            Asset::Not(()) => {
                let mut orders = self.not.read(side);
                if (orders.len() == 0) {
                    return 0;
                }
                let mut found_order: felt252 = 0;
                loop {
                    match orders.pop_front() {
                        Option::Some(v) => {
                            let order = unpack_order(v);
                            if (order.order_id == order_id) {
                                found_order = v;
                                break;
                            };
                        },
                        Option::None(()) => { break; }
                    };
                };
                return found_order;
            }
        }
    }

    fn _sort_orders(ascending: bool, orders: Array<felt252>) -> Array<felt252> {
        if (ascending) {
            _sort_orders_ascending(orders)
        } else {
            _sort_orders_descending(orders)
        }
    }

    fn _distribute_fees(self: @ContractState, amount: u256) {
        if (amount > 0) {
            IDistributorDispatcher { contract_address: self.distributor.read() }
                .new_distribution(self.quote_token.read(), amount);
        }
    }

    fn _receive_quote_token(ref self: ContractState, from: ContractAddress, amount: u256) {
        let this_addr = get_contract_address();
        let quote = self.quote_token.read();

        let balanceBefore = IERC20Dispatcher { contract_address: quote }.balanceOf(this_addr);

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

        let balance_before = IMarketDispatcher { contract_address: market }
            .balance_of(this_addr, asset);
        IMarketDispatcher { contract_address: market }
            .transfer_from(from, this_addr, asset, amount);
        let balance_after = IMarketDispatcher { contract_address: market }
            .balance_of(this_addr, asset);

        assert((balance_after - amount) >= balance_before, 'EXPO: transfer fail')
    }

    fn _is_emergency(self: @ContractState) -> bool {
        self.is_emergency.read()
    }

    // returns (fee_deducted, fee_mount)
    fn _apply_fee(self: @ContractState, fee_type: FeeType, amount: u256) -> (u256, u256) {
        let fees: PlatformFees = self.fees.read();

        match fee_type {
            FeeType::Maker(()) => {
                let fee_amount: u256 = (amount * fees.maker.into()) / 10000;
                let fee_deducted: u256 = amount - fee_amount;

                assert((fee_deducted + fee_amount) <= amount, 'fee wrong');

                return (fee_deducted, fee_amount);
            },
            FeeType::Taker(()) => {
                let fee_amount: u256 = (amount * fees.taker.into()) / 10000;
                let fee_deducted: u256 = amount - fee_amount;

                assert((fee_deducted + fee_amount) <= amount, 'fee wrong');

                return (fee_deducted, fee_amount);
            }
        }
    }
}
