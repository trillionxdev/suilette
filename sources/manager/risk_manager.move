module suilette::risk_manager {

    use std::vector;
    use std::option::{Self, Option};
    use suilette::bet_manager as bm;

    // Errros
    const EInvalidBetType: u64 = 0;
    const EInvalidBetNumber: u64 = 1;

    // Constants
    const COLOR_COUNT: u64 = 2; // red, black
    const PARITY_COUNT: u64 = 2; // even, odd
    const EIGHTEEN_COUNT: u64 = 2; // 1~18, 19~36
    const TWELVE_COUNT: u64 = 3; // 1~12, 13~24, 25~36
    const COLUMN_COUNT: u64 = 3; // 3n, 3n+1, 3n+2
    const NUMBER_COUNT: u64 = 38; // 0, 1~36, 00

    struct RiskHeap has store, drop {
        max_risk: u64,
        sum_risk: u64,
        risks: vector<u64>,
    }

    struct RiskManager has store, drop {
        total_risk: u64,
        color_heap: RiskHeap,
        parity_heap: RiskHeap,
        eighteen_heap: RiskHeap,
        twelve_heap: RiskHeap,
        column_heap: RiskHeap,
        number_heap: RiskHeap,
    }

    public fun new_manager(): RiskManager {
        RiskManager {
            total_risk: 0,
            color_heap: new_risk_heap(COLOR_COUNT),
            parity_heap: new_risk_heap(PARITY_COUNT),
            eighteen_heap: new_risk_heap(EIGHTEEN_COUNT),
            twelve_heap: new_risk_heap(TWELVE_COUNT),
            column_heap: new_risk_heap(COLUMN_COUNT),
            number_heap: new_risk_heap(NUMBER_COUNT),
        }
    }

    public fun add_risk(
        manager: &mut RiskManager,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_payout: u64,
    ): (bool, u64) {
        let bet_type_u64 = (bet_type as u64);

        let (risk_increased, risk_change) = if (bet_type == bm::red() || bet_type == bm::black()) {
            add_risk_to_heap(&mut manager.color_heap, bet_type_u64 % COLOR_COUNT, bet_payout)
        } else if (bet_type == bm::even() || bet_type == bm::odd()) {
            add_risk_to_heap(&mut manager.parity_heap, bet_type_u64 % PARITY_COUNT, bet_payout)
        } else if (bet_type == bm::first_eighteen() || bet_type == bm::second_eighteen()) {
            add_risk_to_heap(&mut manager.eighteen_heap, bet_type_u64 % EIGHTEEN_COUNT, bet_payout)
        } else if (bet_type == bm::first_twelve() || bet_type == bm::second_twelve() || bet_type == bm::third_twelve()) {
            add_risk_to_heap(&mut manager.twelve_heap, bet_type_u64 % TWELVE_COUNT, bet_payout)
        } else if (bet_type == bm::first_column() || bet_type == bm::second_column() || bet_type == bm::third_column()) {
            add_risk_to_heap(&mut manager.column_heap, bet_type_u64 % COLUMN_COUNT, bet_payout)
        } else if (bet_type == bm::number()) {
            let num = option::destroy_some(bet_number);
            assert!(num < NUMBER_COUNT, EInvalidBetNumber);
            add_risk_to_heap(&mut manager.number_heap, num, bet_payout)
        } else {
            abort EInvalidBetType
        };

        if (risk_increased) {
            manager.total_risk = manager.total_risk + risk_change;
        } else {
            manager.total_risk = manager.total_risk - risk_change;
        };

        // return the risk change
        (risk_increased, risk_change)
    }

    public fun total_risk(risk_manager: &RiskManager): u64 {
        risk_manager.total_risk
    }

    fun new_risk_heap(size: u64): RiskHeap {
        let risks = vector::empty<u64>();
        let idx: u64 = 0;
        while(idx < size) {
            vector::push_back(&mut risks, 0);
            idx = idx + 1;
        };
        RiskHeap {
            max_risk: 0,
            sum_risk: 0,
            risks,
        }
    }

    fun add_risk_to_heap(
        heap: &mut RiskHeap,
        index: u64,
        bet_payout: u64,
    ): (bool, u64) {
        let previous_risk = heap_risk(heap);
        heap.sum_risk = heap.sum_risk + bet_payout;
        let risk = vector::borrow_mut(&mut heap.risks, index);
        *risk = *risk + bet_payout;
        if (*risk > heap.max_risk) {
            heap.max_risk = *risk;
        };
        let current_risk = heap_risk(heap);
        if (current_risk > previous_risk) {
            (true, current_risk - previous_risk)
        } else {
            (false, previous_risk - current_risk)
        }
    }

    fun heap_risk(heap: &RiskHeap): u64 {
        if (2 * heap.max_risk > heap.sum_risk) {
            2 * heap.max_risk - heap.sum_risk
        } else {
            0
        }
    }

}