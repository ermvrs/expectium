use expectium::tests::mocks::interfaces::{IAccountDispatcher, IAccountDispatcherTrait, 
                                        IMockSharesDispatcher, IMockSharesDispatcherTrait};
use expectium::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait,
                            IOrderbookDispatcher, IOrderbookDispatcherTrait,
                            IDistributorDispatcher, IDistributorDispatcherTrait};
#[derive(Drop)]
struct Setup {
    operator: IAccountDispatcher,
    alice: IAccountDispatcher,
    bob: IAccountDispatcher,
    collateral: IERC20Dispatcher,
    distributor: IDistributorDispatcher
}

fn setup() -> Setup {
    // TODO
}