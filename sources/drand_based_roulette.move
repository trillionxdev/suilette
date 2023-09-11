/// A sui based implementation of roulette with american roulette edge
module suilette::drand_based_roulette {
    use suilette::drand_lib::{derive_randomness, verify_drand_signature, safe_selection};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use sui::event;
    use sui::table_vec::{Self as tvec, TableVec};

    use std::vector as vec;
    use suilette::math::Self as math;

    /// Error codes
    const EGameNotInProgress: u64 = 0;
    const EGameAlreadyCompleted: u64 = 1;
    const EInvalidRandomness: u64 = 2;
    const ECallerNotHouse: u64 = 4;
    const ECanNotCancel: u64 = 5;
    const EInsufficientBalance: u64 = 6;
    const EGameHasAlreadyBeenCanceled: u64 = 7;
    const EInsufficientHouseBalance: u64 = 8;
    const ECoinBalanceNotEnough: u64 = 9;
    const EInvalidBetType: u64 = 10;
    const EGameCannotBeDeleted: u64 = 11;
    const EInvalidBet: u64 = 12;
    const ENotEnoughHouseRisk: u64 = 13;
    const ENotEnoughNumberRisk: u64 = 14;
    const EAdminAccountCapRequired: u64 = 15;

    /// Game status
    const IN_PROGRESS: u8 = 0;
    const CLOSED: u8 = 1;
    const IN_SETTLEMENT: u8 = 2; // REVIEW: add a status
    const COMPLETED: u8 = 3;

    // 1 SUI is the default min bet
    const DEFAULT_MIN_BET: u64 = 1000000000;

    /// Bet Types
    /// We can group different bets for cheaper computation
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

    struct Bet<phantom Asset> has key, store {
        id: UID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: Balance<Asset>,
        player: address,
        // REVIEW: add this field as bet status
        is_settled: bool,
    }

    /// Event for placed bets
    struct PlaceBet<phantom Asset> has copy, store, drop {
        bet_id: ID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    }

    /// Event for the bet result
    struct BetResult<phantom Asset> has copy, store, drop {
        bet_id: ID,
        is_win: bool,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
    }

    /// Event for game close
    struct GameCreated<phantom Asset> has copy, store, drop {
        game_id: ID,
    }

    /// Event for game close
    struct GameClosed<phantom Asset> has copy, store, drop {
        game_id: ID,
    }

    /// Event for game completion
    struct GameCompleted<phantom Asset> has copy, store, drop {
        game_id: ID,
        result_roll: u64,
        bet_results: vector<BetResult<Asset>>,
    }

    /// Event for house deposit
    struct HouseDeposit<phantom Asset> has copy, store, drop {
        amount: u64
    }

    /// Event for house withdraw
    struct HouseWithdraw<phantom Asset> has copy, store, drop {
        amount: u64
    }

    struct HouseData<phantom T> has key {
        id: UID,
        balance: Balance<T>,
        house: address,
        house_risk: u64,
        max_risk_per_game: u64,
    }

    struct HouseCap has key, store {
        id: UID,
        /// The owner of this AccountCap. Note: this is
        /// derived from an object ID, not a user address
        owner: address,
    }

    struct NumberRisk has copy, store, drop {
        risk: u64
    }

    struct RouletteGame<phantom T> has key, store {
        id: UID,
        owner: address,
        status: u8,
        round: u64,
        // REVIEW: use TableVec on bets instead of vector
        // bets: vector<Bet<T>>,
        bets: TableVec<Bet<T>>,
        // This is a vector mapping of specifically the total risk of the number vector
        numbers_risk: vector<NumberRisk>,
        total_risked: u64,
        result_roll: u64,
        min_bet: u64,
        // REVIEW: add this to count settled bets
        settled_bets_count: u64,
    }

    // Constructor
    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let owner = tx_context::sender(ctx);
        let house_cap = HouseCap {
            id,
            owner
        };

        transfer::transfer(house_cap, tx_context::sender(ctx))
    }

    /// Create a "child account cap" such that id != owner
    /// that can access funds, but cannot create new `AccountCap`s.
    public fun create_child_account_cap(admin_account_cap: &HouseCap, target_address: address, ctx: &mut TxContext) {
        // Mint a house cap object
        assert!(tx_context::sender(ctx) == admin_account_cap.owner, ECallerNotHouse);

        let new_house_cap = HouseCap {
            id: object::new(ctx),
            owner: target_address
        };

        transfer::transfer(new_house_cap, target_address)
    }

    // --------------- HouseData Accessors ---------------

    /// Returns the balance of the house
    /// @param house_data: The HouseData object
    public fun balance<Asset>(house_data: &HouseData<Asset>): u64 {
        balance::value(&house_data.balance)
    }

    /// Returns the address of the house
    /// @param house_data: The HouseData object
    public fun house<Asset>(house_data: &HouseData<Asset>): address {
        house_data.house
    }

    /// Returns how much the house can risk
    /// @param house_data: The HouseData object
    public fun house_risk<Asset>(house_data: &HouseData<Asset>): u64 {
        house_data.house_risk
    }

    /// Return the owner of an HouseCap
    public fun account_owner(house_cap: &HouseCap): address {
        house_cap.owner
    }

    /// Change the house cap owner 
    public entry fun set_account_owner(house_cap: &mut HouseCap, ctx: &mut TxContext) {
        house_cap.owner = tx_context::sender(ctx);
    }

    // Functions
    /// Initializes the house data object. This object is involed in all games created by the same instance of this package. 
    /// It holds the balance of the house (used for the house's stake as well as for storing the house's earnings), the house address, and the public key of the house.
    /// @param house_cap: The HouseCap object
    /// @param coin: The coin object that will be used to initialize the house balance. Acts as a treasury
    public entry fun initialize_house_data<Asset>(house_cap: &HouseCap, ctx: &mut TxContext) {
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);

        let house_data = HouseData<Asset> {
            id: object::new(ctx),
            balance: balance::zero(),
            house: tx_context::sender(ctx),
            house_risk: 0,
            // We just initialize to 1k Sui a game
            max_risk_per_game: 1000 * 1000000000,
        };

        // init function to create the game
        transfer::share_object(house_data);
    }

    /// Set the max risk per game that the house can take
    public entry fun set_max_risk_per_game<Asset>(house_cap: &HouseCap, house_data: &mut HouseData<Asset>, max_risk_per_game: u64, ctx: &mut TxContext) {
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);
        house_data.max_risk_per_game = max_risk_per_game;
    }

    /// Function used to top up the house balance. Can be called by anyone.
    /// House can have multiple accounts so giving the treasury balance is not limited.
    /// @param house_data: The HouseData object
    /// @param coin: The coin object that will be used to top up the house balance. The entire coin is consumed
    public entry fun top_up<Asset>(house_data: &mut HouseData<Asset>, coin: Coin<Asset>) {        
        let coin_value = coin::value(&coin);
        let coin_balance = coin::into_balance(coin);
        event::emit(HouseDeposit<Asset> { amount: coin_value });
        balance::join(&mut house_data.balance, coin_balance);
    }

    /// House can withdraw the entire balance of the house object
    /// @param house_data: The HouseData object
    public entry fun withdraw<Asset>(house_data: &mut HouseData<Asset>, quantity: u64, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);
        event::emit(HouseWithdraw<Asset> { amount: quantity });
        let coin = coin::take(&mut house_data.balance, quantity, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    /// Create a shared-object roulette Game. 
    /// Only a house can create games currently to ensure that we cannot be hacked
    public entry fun create<Asset>(
        round: u64,
        house_data: &mut HouseData<Asset>,
        house_cap: &HouseCap,
        ctx: &mut TxContext
        ) {
        assert!(account_owner(house_cap) == house_data.house, ECallerNotHouse);

        // Initialize the number_risk to be a vector of size 38, starting from 0.
        let numbers_risk = vector<NumberRisk>[];
        let idx = 0;
        while(idx < 38) {
            vec::push_back(&mut numbers_risk, NumberRisk { risk: 0 });
            idx = idx + 1;
        };

        let game_uid = object::new(ctx);
        let game = RouletteGame<Asset> {
            id: game_uid,
            owner: tx_context::sender(ctx), 
            round,
            status: IN_PROGRESS,
            bets: tvec::empty(ctx),
            numbers_risk: numbers_risk,
            total_risked: 0,
            result_roll: 0,
            min_bet: DEFAULT_MIN_BET,
            settled_bets_count: 0,
        };
        let game_id = *object::uid_as_inner(&game.id);
        transfer::public_share_object(game);
        event::emit(GameCreated<Asset> { game_id });
    }

    // Returns 0 if nothing is in the vector, and max otherwise
    public fun max_number_risk_vector(vect: &vector<NumberRisk>): u64 {
        let idx = 0;
        let current_max = 0;
        while (idx < vec::length(vect)) {
            let vect_num = vec::borrow(vect, idx);
            if (vect_num.risk > current_max) {
                current_max = vect_num.risk;
            };
            idx = idx + 1;
        };
        current_max
    }

    /// Anyone can participate in the betting of the game, could consider allowing different bet sizes
    /// A user can only place a bet in the current round and the next round
    public entry fun place_bet<Asset>(
        coin: Coin<Asset>,
        bet_type: u8,
        bet_number: Option<u64>,
        game: &mut RouletteGame<Asset>, 
        house_data: &mut HouseData<Asset>,
        ctx: &mut TxContext
    ) {
        // Assert that the bet type is valid and within the range of bets
        assert!(bet_type >= 0 && bet_type <= 12, EInvalidBetType);
        let coin_value = coin::value(&coin);
        let bet_payout = get_bet_payout(coin_value, bet_type);

        // Assert that we provide a bet number for individual number bets
        if (bet_type == NUMBER_BET) {
            assert!(!option::is_none(&bet_number), EInvalidBet);
            let target_bet_number = *option::borrow(&bet_number);
            // For number bets grab current max numbers_risk from the vector
            let current_max_number_bet = max_number_risk_vector(&game.numbers_risk);

            // Update numbers_risk by borrowing the index of the bet number
            let curr_number_risk = vec::borrow_mut(&mut game.numbers_risk, target_bet_number);
            curr_number_risk.risk = curr_number_risk.risk + bet_payout;

            // Update risk for number bets
            if (curr_number_risk.risk > current_max_number_bet) {
                house_data.house_risk = house_data.house_risk + curr_number_risk.risk - current_max_number_bet;
                game.total_risked = game.total_risked + curr_number_risk.risk - current_max_number_bet;
            }

        } else {
            // Update risk for other kinds of bets
            house_data.house_risk = house_data.house_risk + bet_payout;
            game.total_risked = game.total_risked + bet_payout;
        };

        assert!(house_risk(house_data) <= balance(house_data), EInsufficientHouseBalance);
        assert!(game.total_risked <= house_data.max_risk_per_game, EInsufficientHouseBalance);
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);

        // Check that the coin value is above the minimum bet
        assert!(coin_value >= game.min_bet, EInsufficientBalance);

        let bet_size = coin::into_balance(coin);

        let new_bet = Bet {
            id: object::new(ctx),
            bet_type,
            bet_number,
            bet_size,
            player: tx_context::sender(ctx),
            is_settled: false,
        };
        let bet_balance_value = balance::value(&new_bet.bet_size);
        let bet_id = *object::uid_as_inner(&new_bet.id);
        event::emit(PlaceBet<Asset>{
            bet_id,
            bet_type: new_bet.bet_type,
            bet_number: new_bet.bet_number,
            bet_size: bet_balance_value,
            player: new_bet.player
        });

        tvec::push_back(&mut game.bets, new_bet);
    }

    /// Anyone can close the game by providing the randomness of round - 1. 
    public entry fun close<Asset>(game: &mut RouletteGame<Asset>, drand_sig: vector<u8>, drand_prev_sig: vector<u8>) {
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);
        verify_drand_signature(drand_sig, drand_prev_sig, closing_round(game.round));
        game.status = CLOSED;
        let game_id = *object::uid_as_inner(&game.id);
        event::emit(GameClosed<Asset> { game_id });
    }

    /// Anyone can complete the game by providing the randomness of round.
    /// - Anyone can *close* the game to new participants by providing drand's randomness of round N-2 (i.e., 1 minute before
    ///   round N). The randomness of round X can be retrieved using
    ///  `curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/X'.
    /// TODO: update risks and remove bets
    public entry fun complete<Asset>(
        game: &mut RouletteGame<Asset>, 
        house_cap: &HouseCap,        
        house_data: &mut HouseData<Asset>, 
        drand_sig: vector<u8>, 
        drand_prev_sig: vector<u8>,
        // REVIEW: complete in pagination way
        cursor: u64,
        page_size: u64,
        ctx: &mut TxContext
    ) {
        assert!(game.status != COMPLETED, EGameAlreadyCompleted);
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);
        verify_drand_signature(drand_sig, drand_prev_sig, game.round);

        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);

        // We accept some small amount of bias with safe selection
        // 0 or 37 are both losses unless they picked a number
        let win_roll = safe_selection(38, &digest);
        game.result_roll = win_roll;
        std::debug::print(&win_roll);

        let game_id = *object::uid_as_inner(&game.id);

        // Pay out the bets or claim the balance to house
        let bets = &mut game.bets;
        
        // REVIEW: start from cursor, instead of starting from 0
        // let bet_index = 0;
        let bet_index = cursor;
        let end_index = cursor + page_size;
        let bets_length = tvec::length(bets);
        if (end_index > bets_length) end_index = bets_length;

        let bet_results = vector<BetResult<Asset>>[];

        // Deduct the house risk of the max number bet since we theoretically pay it off
        if (game.status != IN_SETTLEMENT) {
            let number_bet_risk = max_number_risk_vector(&game.numbers_risk);
            house_data.house_risk = house_data.house_risk - number_bet_risk;
        };
        game.status = IN_SETTLEMENT;
        
        while (bet_index < end_index) {
            let bet = tvec::borrow_mut(bets, bet_index);
            let player_bet = balance::value(&bet.bet_size);
            // REVIEW: if bet is settled then skip it
            if (bet.is_settled) {
                // Increment bet index
                bet_index = bet_index + 1;
                continue
            };
            let bet_payout = get_bet_payout(player_bet, bet.bet_type);
            // Deduct the house risk if its not a number bet
            if (bet.bet_type != NUMBER_BET) {
                house_data.house_risk = house_data.house_risk - bet_payout;
            };

            // Do number bets case first
            if (won_bet(bet.bet_type, win_roll, bet.bet_number)) {
                let house_payment = balance::split(&mut house_data.balance, bet_payout);
                let player_coin = coin::take(&mut bet.bet_size, player_bet, ctx);
                let player_bet_and_house_payment = coin::into_balance(player_coin);

                balance::join(&mut player_bet_and_house_payment, house_payment);
                
                let total_value = balance::value(&player_bet_and_house_payment);
                let payment_coin = coin::take(&mut player_bet_and_house_payment, total_value, ctx);
                transfer::public_transfer(payment_coin, bet.player);
                balance::destroy_zero(player_bet_and_house_payment);

                // Event emit for the bet results
                let bet_id = *object::uid_as_inner(&bet.id);
                let bet_result = BetResult<Asset> {
                    bet_id: bet_id,
                    is_win: true,
                    bet_type: bet.bet_type,
                    bet_number: bet.bet_number,
                    bet_size: player_bet,
                    player: bet.player,
                };
                vec::push_back(&mut bet_results, bet_result);

            } else {
                // Send money to the house in losing bet
                let player_coin = coin::take(&mut bet.bet_size, player_bet, ctx);
                balance::join(&mut house_data.balance, coin::into_balance(player_coin));

                // Event emit for the bet results
                let bet_id = *object::uid_as_inner(&bet.id);
                let bet_result = BetResult<Asset> {
                    bet_id: bet_id,
                    is_win: false,
                    bet_type: bet.bet_type,
                    bet_number: bet.bet_number,
                    bet_size: player_bet,
                    player: bet.player,
                };
                vec::push_back(&mut bet_results, bet_result);
            };
            // Increment bet index
            bet_index = bet_index + 1;
            // REVIEW: set bet settled and count it
            bet.is_settled = true;
            game.settled_bets_count = game.settled_bets_count + 1;
        };

        // REVIEW: if all bets settled then mark the game completed
        if (game.settled_bets_count == bets_length) {
            game.status = COMPLETED;            
        };

        event::emit(GameCompleted<Asset> {
            game_id,
            result_roll: win_roll,
            bet_results: bet_results,
        });

    }

    public entry fun refundAllBets<Asset>(
        house_cap: &HouseCap,
        game: &mut RouletteGame<Asset>,
        // REVIEW: refund in pagination way
        page_size: u64,
        ctx: &mut TxContext
    ) {
        let RouletteGame<Asset> { id: _, owner: _, status: _, numbers_risk: _, total_risked: _, round: _, bets, result_roll: _, min_bet: _, settled_bets_count: _} = game;
        // Only owner can delete a game
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);

        let bets_mut = bets;
        if(page_size > tvec::length(bets_mut))
            page_size = tvec::length(bets_mut);
        let counter = 0;
        while (counter < page_size) {
            let bet = tvec::pop_back(bets_mut);
            delete_bet(bet, ctx);
            counter = counter + 1;
        };
    }
 
    fun delete_bet<Asset>(bet: Bet<Asset>, ctx: &mut TxContext) {
        let Bet<Asset> { id, bet_type: _, bet_number: _, bet_size, player, is_settled: _} = bet;
        let player_bet = balance::value(&bet_size);
        if (player_bet > 0) {
            let player_coin = coin::take(&mut bet_size, player_bet, ctx);
            transfer::public_transfer(player_coin, player);
        };
        balance::destroy_zero(bet_size);
        object::delete(id);
    }

    /// close the round 1 turn before
    fun closing_round(round: u64): u64 {
        round - 1
    }
        
    /// Get the potential payout / loss of the bet This should cover all of the bets
    public fun get_bet_payout(
        coin_value: u64,
        bet_type: u8,
    ): u64 {
        // red/black/odd/even/first_eighteen/second eighteen pays out 1-1
        if (bet_type == RED_BET || bet_type == BLACK_BET || bet_type == EVEN_BET || bet_type == ODD_BET || bet_type == FIRST_EIGHTEEN || bet_type == SECOND_EIGHTEEN) {
            return math::unsafe_mul(coin_value, 1_000_000_000)
        };

        // the twelve multiple bets pays out 2 - 1
        if (bet_type == FIRST_TWELVE || bet_type == SECOND_TWELVE || bet_type == THIRD_TWELVE || bet_type == FIRST_COLUMN || bet_type == SECOND_COLUMN || bet_type == THIRD_COLUMN) {
            return math::unsafe_mul(coin_value, 2_000_000_000)
        };

        // 35- 1 payout for a single number
        if (bet_type == NUMBER_BET) {
            return math::unsafe_mul(coin_value, 35_000_000_000)
        };

        (0)
    }

    public fun won_bet(bet_type: u8, result_roll: u64, bet_number: Option<u64>): bool {
        // Number bet has won. Note that our board represents 0 as 0, and 00- as 37
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
            return (result_roll % 2) != 0
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

    #[test_only] use sui::coin::mint_for_testing;

    #[test_only] use sui::test_scenario::{Self, Scenario};
    #[test_only] use sui::sui::SUI;

    #[test_only]
    public fun mint_account_cap_transfer(
        user: address,
        ctx: &mut TxContext
    ) {
        let house_cap = HouseCap {
            id: object::new(ctx),
            owner: tx_context::sender(ctx)
        };
        transfer::transfer(house_cap, user);
    }

    // Write a test to test the deletion of a completed game
    // Test that no new bets can be placed in closed game
    // Test that no bets can be placed in a game with too much risk
    // Test when with a 37 or 0 roll on any bets besides the number bet
    // Write a number bet test that might fail
    // Test black / red
    // Test columns and 
    // test rows
    // Place a bet on every single number and check that only 1 of them gets paid out
    // Unit test withdraw

    #[test_only] 
    public fun setup_house_for_test (
        scenario: &mut Scenario,
    ) {
        let house: address = @0xAAAA;
        test_scenario::next_tx(scenario, house);
        {
            // Transfer the house cap
            mint_account_cap_transfer(house, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, house);
        {
            let house_cap = test_scenario::take_from_address<HouseCap>(scenario, house);
            // Create the housedata
            initialize_house_data<SUI>(&house_cap, test_scenario::ctx(scenario));

            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
        test_scenario::next_tx(scenario, house);
        {
            // Top up the house
            let house_data = test_scenario::take_shared<HouseData<SUI>>(scenario);
            let house_cap = test_scenario::take_from_address<HouseCap>(scenario, house);
            top_up(&mut house_data, mint_for_testing<SUI>(1000 * 1000000000, test_scenario::ctx(scenario)));

            // Test create
            create<SUI>(3125272, &mut house_data, &house_cap, test_scenario::ctx(scenario));
            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
    }

    #[test] fun test_max_number_bets_ok() { test_max_number_bets_ok_(scenario()); }
    #[test] fun test_house_wins_red_bet() { test_house_wins_red_bet_(scenario()); }
    #[test] fun test_bets_are_refundable() { test_bets_are_refunded(scenario()); }
    #[test] fun test_cannot_exceed_max_risk() {}
    #[test] fun test_bet_type_pay_out_as_expected() {}

    // begin with house address
    #[test_only]
    fun scenario(): Scenario { test_scenario::begin(@0xAAAA) }
    
    #[test_only]
    fun test_house_wins_red_bet_(test: Scenario) {
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;

        setup_house_for_test(&mut test);
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on red
            place_bet<SUI>(
                mint_for_testing<SUI>(5 * 1000000000, test_scenario::ctx(&mut test)),
                0,
                option::none<u64>(),
                &mut roulette_game,
                &mut house_data,
                test_scenario::ctx(&mut test)
            );
            test_scenario::return_shared(house_data);
            test_scenario::return_shared(roulette_game);
        };
            test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            // REVIEW: use pagination way to complete
            complete<SUI>(&mut roulette_game, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 0, 10, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
            test_scenario::return_shared(roulette_game);
        };
        test_scenario::next_tx(&mut test, player);
        {
            // Check that the house gained the bet that the player made
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            sui::test_utils::assert_eq(balance::value(&house_data.balance), 1005 * 1000000000);
            test_scenario::return_shared(house_data);
        };
        test_scenario::end(test);
    }

    #[test_only]
    fun test_max_number_bets_ok_(test: Scenario) {
        setup_house_for_test(&mut test);
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on 2
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(2),
                &mut roulette_game,
                &mut house_data,
                test_scenario::ctx(&mut test)
            );

            // Place bet on 4
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(4),
                &mut roulette_game,
                &mut house_data,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
            test_scenario::return_shared(roulette_game);
        };
        // REVIEW: complete first page and check the game status
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            // REVIEW: use pagination way to complete
            assert!(roulette_game.status == IN_PROGRESS, 0);
            complete<SUI>(&mut roulette_game, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 0, 1, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
            test_scenario::return_shared(roulette_game);
        };
        // REVIEW: complete second page and check the game status
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            // REVIEW: use pagination way to complete
            assert!(roulette_game.status == IN_SETTLEMENT, 0);
            complete<SUI>(&mut roulette_game, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 1, 1, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
            test_scenario::return_shared(roulette_game);
        };
        // REVIEW: check the game status
        test_scenario::next_tx(&mut test, player);
        {
            // Check that the house gained the bet that the player made
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            // sui::test_utils::assert_eq(balance::value(&house_data.balance), 105 * 1000000000);
            assert!(roulette_game.status == COMPLETED, 0);
            test_scenario::return_shared(house_data);
            test_scenario::return_shared(roulette_game);
        };
        test_scenario::end(test);
    }

    #[test_only]
    fun test_bets_are_refunded(test: Scenario) {
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;
        setup_house_for_test(&mut test);
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on 2
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(2),
                &mut roulette_game,
                &mut house_data,
                test_scenario::ctx(&mut test)
            );

            // Place bet on 4
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(4),
                &mut roulette_game,
                &mut house_data,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
            test_scenario::return_shared(roulette_game);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            // Delete
            refundAllBets<SUI>(
                &house_cap,
                &mut roulette_game,
                1,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_to_address<HouseCap>(house, house_cap);
            test_scenario::return_shared(roulette_game);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let roulette_game = test_scenario::take_shared<RouletteGame<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            // Delete
            refundAllBets<SUI>(
                &house_cap,
                &mut roulette_game,
                1,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_to_address<HouseCap>(house, house_cap);
            test_scenario::return_shared(roulette_game);
        };
        test_scenario::next_tx(&mut test, house);
        {
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            // Assert house data has original balance
            assert!(balance::value(&house_data.balance) == 1000 * 1000000000, 0);
            test_scenario::return_shared(house_data);
        };
        test_scenario::end(test);
    }
}