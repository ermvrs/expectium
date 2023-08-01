use option::OptionTrait;
use array::{ArrayTrait, SpanTrait};
use traits::{TryInto, Into};
use expectium::config::{pack_order, unpack_order};

fn _sort_orders_descending(
    mut proposals: Array<felt252>
) -> Array<felt252> {
    _mergesort_orders_by_price_desc(proposals) // span gerekmeyebilir.
}

fn _sort_orders_ascending(
    mut proposals: Array<felt252>
) -> Array<felt252> {
    _mergesort_orders_by_price_asc(proposals) // span gerekmeyebilir.
}

fn _mergesort_orders_by_price_asc(mut arr: Array<felt252>) -> Array<felt252>{
    let len = arr.len();
    if len <= 1 {
        return arr;
    }

    let middle = len / 2;
    let (mut left_arr, mut right_arr) = _split_array(ref arr, middle);
    
    let mut sorted_left = _mergesort_orders_by_price_asc(
        left_arr
    );
    let mut sorted_right = _mergesort_orders_by_price_asc(
        right_arr
    );

    let mut result_arr = Default::default();
    _merge_and_slice_recursive_ascending(
        sorted_left, sorted_right, ref result_arr, 0, 0
    );
    result_arr
}

fn _mergesort_orders_by_price_desc(mut arr: Array<felt252>) -> Array<felt252>{
    let len = arr.len();
    if len <= 1 {
        return arr;
    }

    let middle = len / 2;
    let (mut left_arr, mut right_arr) = _split_array(ref arr, middle);

    let mut sorted_left = _mergesort_orders_by_price_desc(
        left_arr
    );
    let mut sorted_right = _mergesort_orders_by_price_desc(
        right_arr
    );

    let mut result_arr = Default::default();
    _merge_and_slice_recursive_descending(
        sorted_left, sorted_right, ref result_arr, 0, 0
    );
    result_arr
}

fn _merge_and_slice_recursive_descending( // orderları price yüksekten düşüğe doğru sıralar, eşit ise tarihe göre
    mut left_arr: Array<felt252>,
    mut right_arr: Array<felt252>,
    ref result_arr: Array<felt252>,
    left_arr_ix: usize,
    right_arr_ix: usize,
) {
    if result_arr.len() == left_arr.len() + right_arr.len() {
        return;
    }

    let (append, next_left_ix, next_right_ix) = if left_arr_ix == left_arr.len() {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    } else if right_arr_ix == right_arr.len() {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else if unpack_order(*left_arr[left_arr_ix]).price > unpack_order(*right_arr[right_arr_ix]).price {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else if unpack_order(*left_arr[left_arr_ix]).price < unpack_order(*right_arr[right_arr_ix]).price {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    } else if unpack_order(*left_arr[left_arr_ix]).date <= unpack_order(*right_arr[right_arr_ix]).date {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    };

    result_arr.append(append);
    _merge_and_slice_recursive_descending(left_arr, right_arr, ref result_arr, next_left_ix, next_right_ix);
}

fn _merge_and_slice_recursive_ascending( // orderları price yüksekten düşüğe doğru sıralar, eşit ise tarihe göre
    mut left_arr: Array<felt252>,
    mut right_arr: Array<felt252>,
    ref result_arr: Array<felt252>,
    left_arr_ix: usize,
    right_arr_ix: usize,
) {
    if result_arr.len() == left_arr.len() + right_arr.len() {
        return;
    }

    let (append, next_left_ix, next_right_ix) = if left_arr_ix == left_arr.len() {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    } else if right_arr_ix == right_arr.len() {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else if unpack_order(*left_arr[left_arr_ix]).price < unpack_order(*right_arr[right_arr_ix]).price {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else if unpack_order(*left_arr[left_arr_ix]).price > unpack_order(*right_arr[right_arr_ix]).price {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    } else if unpack_order(*left_arr[left_arr_ix]).date <= unpack_order(*right_arr[right_arr_ix]).date {
        (*left_arr[left_arr_ix], left_arr_ix + 1, right_arr_ix)
    } else {
        (*right_arr[right_arr_ix], left_arr_ix, right_arr_ix + 1)
    };

    result_arr.append(append);
    _merge_and_slice_recursive_ascending(left_arr, right_arr, ref result_arr, next_left_ix, next_right_ix);
}

fn _split_array<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>>(
    ref arr: Array<T>, index: usize
) -> (Array::<T>, Array::<T>) {
    let mut arr1 = Default::default();
    let mut arr2 = Default::default();
    let len = arr.len();

    _fill_array(ref arr1, ref arr, 0, index);
    _fill_array(ref arr2, ref arr, index, len - index);

    (arr1, arr2)
}

fn _fill_array<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>>(
    ref arr: Array<T>, ref fill_arr: Array<T>, index: usize, count: usize
) {
    if count == 0 {
        return;
    }

    arr.append(*fill_arr[index]);

    _fill_array(ref arr, ref fill_arr, index + 1, count - 1)
}