module suilette::bet_manager {

    use std::option::{Self, Option};
    use suilette::math;

    // Errors
    const EInvalidBetType: u64 = 0;

    const RED_BET: u8 = 0;
    const BLACK_BET: u8 = 1;
    const NUMBER_BET: u8 = 2;
    const EVEN_BET: u8 = 3;
    const ODD_BET: u8 = 4;
    const FIRST_TWELVE: u8 = 5;
    const SECOND_TWELVE: u8 = 6;
    const THIRD_TWELVE: u8 = 7;
    const FIRST_EIGHTEEN:u8 = 8;
    const SECOND_EIGHTEEN: u8 = 9;
    const FIRST_COLUMN: u8 = 10;
    const SECOND_COLUMN: u8 = 11;
    const THIRD_COLUMN: u8 = 12;

    public fun red(): u8 { RED_BET }
    public fun black(): u8 { BLACK_BET }
    public fun number(): u8 { NUMBER_BET }
    public fun even(): u8 { EVEN_BET }
    public fun odd(): u8 { ODD_BET }
    public fun first_twelve(): u8 { FIRST_TWELVE }
    public fun second_twelve(): u8 { SECOND_TWELVE }
    public fun third_twelve(): u8 { THIRD_TWELVE }
    public fun first_eighteen(): u8 { FIRST_EIGHTEEN }
    public fun second_eighteen(): u8 { SECOND_EIGHTEEN }
    public fun first_column(): u8 { FIRST_COLUMN }
    public fun second_column(): u8 { SECOND_COLUMN }
    public fun third_column(): u8 { THIRD_COLUMN }

    /// Get the potential payout / loss of the bet This should cover all of the bets
    public fun get_bet_payout(
        bet_size: u64,
        bet_type: u8,
    ): u64 {
        // red/black/odd/even/first_eighteen/second_eighteen pays out 1-1
        if (bet_type == RED_BET || bet_type == BLACK_BET || bet_type == EVEN_BET || bet_type == ODD_BET || bet_type == FIRST_EIGHTEEN || bet_type == SECOND_EIGHTEEN) {
            return math::unsafe_mul(bet_size, 1_000_000_000)
        };

        // the twelve multiple bets pays out 2-1
        if (bet_type == FIRST_TWELVE || bet_type == SECOND_TWELVE || bet_type == THIRD_TWELVE || bet_type == FIRST_COLUMN || bet_type == SECOND_COLUMN || bet_type == THIRD_COLUMN) {
            return math::unsafe_mul(bet_size, 2_000_000_000)
        };

        // 35-1 payout for a single number
        if (bet_type == NUMBER_BET) {
            return math::unsafe_mul(bet_size, 35_000_000_000)
        };

        abort EInvalidBetType
    }

    public fun won_bet(bet_type: u8, result_roll: u64, bet_number: Option<u64>): bool {
        // Number bet has won. Note that our board represents 0 as 0, and 00 as 37
        if (bet_type == NUMBER_BET) {
            return option::contains(&bet_number, &result_roll)
        };

        // Auto loss based on american roulette system
        if (result_roll == 0 || result_roll == 37) {
            return false
        };

        // Even numbers
        if (bet_type == EVEN_BET) {
            return (result_roll % 2) == 0
        };

        // Odd numbers
        if (bet_type == ODD_BET) {
            return (result_roll % 2) == 1
        };

        // red numbers (1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36)
        if (bet_type == RED_BET) {
            return 
                (result_roll == 1 ||
                result_roll == 3 ||
                result_roll == 5 ||
                result_roll == 7 ||
                result_roll == 9 ||
                result_roll == 12 ||
                result_roll == 14 ||
                result_roll == 16 ||
                result_roll == 18 ||
                result_roll == 19 ||
                result_roll == 21 ||
                result_roll == 23 ||
                result_roll == 25 ||
                result_roll == 27 ||
                result_roll == 30 ||
                result_roll == 32 ||
                result_roll == 34 ||
                result_roll == 36)
        };

        // blacks numbers (2,4,6,8,10,11,13,15,17,20,22,24,26,28,29,31,33,35)
        if (bet_type == BLACK_BET) {
            return 
                (result_roll == 2 ||
                result_roll == 4 ||
                result_roll == 6 ||
                result_roll == 8 ||
                result_roll == 10 ||
                result_roll == 11 ||
                result_roll == 13 ||
                result_roll == 15 ||
                result_roll == 17 ||
                result_roll == 20 ||
                result_roll == 22 ||
                result_roll == 24 ||
                result_roll == 26 ||
                result_roll == 28 ||
                result_roll == 29 ||
                result_roll == 31 ||
                result_roll == 33 ||
                result_roll == 35)
        };

        if (bet_type == FIRST_EIGHTEEN) {
            return result_roll >= 1 && result_roll <= 18
        };

        if (bet_type == SECOND_EIGHTEEN) {
            return result_roll >= 19 && result_roll <= 36
        };

        if (bet_type == FIRST_TWELVE) {
            return result_roll >= 1 && result_roll <= 12
        };

        if (bet_type == SECOND_TWELVE) {
            return result_roll >= 13 && result_roll <= 24
        };

        if (bet_type == THIRD_TWELVE) {
            return result_roll >= 25 && result_roll <= 36
        };

        if (bet_type == FIRST_COLUMN) {
            return (result_roll + 2) % 3 == 0
        };

        if (bet_type == SECOND_COLUMN) {
            return (result_roll + 1) % 3 == 0
        };

        if (bet_type == THIRD_COLUMN) {
            return result_roll % 3 == 0
        };
        false
    }
}