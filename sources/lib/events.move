module suilette::events {

    use std::option::Option;
    use sui::object::ID;
    use sui::event::emit;

    friend suilette::drand_based_roulette;

    /// Event for placed bets
    struct PlaceBet<phantom T> has copy, store, drop {
        bet_id: ID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    }

    public(friend) fun emit_place_bet<T>(
        bet_id: ID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    ) {
        emit(PlaceBet<T> {
            bet_id,
            bet_type,
            bet_number,
            bet_size,
            player,
        });
    }

    /// Event for game close
    struct GameCreated<phantom T> has copy, store, drop {
        game_id: ID,
    }

    public(friend) fun emit_game_created<T>(
        game_id: ID,
    ) {
        emit(GameCreated<T> {
            game_id,
        });
    }

    /// Event for game close
    struct GameClosed<phantom T> has copy, store, drop {
        game_id: ID,
    }

    public(friend) fun emit_game_closed<T>(
        game_id: ID,
    ) {
        emit(GameClosed<T> {
            game_id,
        });
    }

    struct BetResult<phantom T> has copy, store, drop {
        bet_id: ID,
        is_win: bool,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    }

    public(friend) fun new_bet_result<T>(
        bet_id: ID,
        is_win: bool,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    ): BetResult<T> {
        BetResult {
            bet_id,
            is_win,
            bet_type,
            bet_number,
            bet_size,
            player,
        }
    }

    /// Event for game completion
    struct GameCompleted<phantom T> has copy, store, drop {
        game_id: ID,
        result_roll: u64,
        bet_results: vector<BetResult<T>>,
    }

    public(friend) fun emit_game_completed<T>(
        game_id: ID,
        result_roll: u64,
        bet_results: vector<BetResult<T>>,
    ) {
        emit(GameCompleted<T> {
            game_id,
            result_roll,
            bet_results,
        });
    }

    /// Event for house deposit
    struct HouseDeposit<phantom T> has copy, store, drop {
        amount: u64
    }

    public(friend) fun emit_house_deposit<T>(amount: u64) {
        emit(HouseDeposit<T> {
            amount,
        });
    }

    /// Event for house withdraw
    struct HouseWithdraw<phantom T> has copy, store, drop {
        amount: u64
    }

    public(friend) fun emit_house_withdraw<T>(amount: u64) {
        emit(HouseWithdraw<T> {
            amount,
        });
    }
}