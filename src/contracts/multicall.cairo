#[starknet::contract]
mod Multicall {
    use starknet::{call_contract_syscall};
    use array::{ArrayTrait, SpanTrait};

    use expectium::interfaces::IMulticall;
    use expectium::types::{Call, Response};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl Multicall of IMulticall<ContractState> {
        // Her call için bi response döndürmeli
        fn multicall(self: @ContractState, calls: Array<Call>) -> Span<Response> {
            let mut i = 0;
            let mut responses = ArrayTrait::<Response>::new();
            loop {
                if (i == calls.len()) {
                    break;
                }
                responses.append(_call_contract(calls.at(i)));
                i += 1;
            };

            return responses.span();
        }
    }

    fn _call_contract(call: @Call) -> Response {
        let result = call_contract_syscall(*call.contract, *call.entrypoint, call.calldata.span());

        let mut call_response = ArrayTrait::<felt252>::new().span();

        let call_status = match result {
            Result::Ok(x) => {
                call_response = x;
                true
            },
            Result::Err(_) => false
        };

        Response {
            contract: *call.contract,
            status: call_status,
            result: call_response
        }
    }
}