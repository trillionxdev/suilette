/// A sui based implementation of roulette with american roulette edge
module suilette::drand_based_roulette {

    use std::vector::{Self as vec};
    use std::option::{Self, Option};
    use std::string::String;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::table_vec::{Self as tvec, TableVec};
    use sui::dynamic_object_field as dof;

    use suilette::drand_lib::{derive_randomness, verify_drand_signature, safe_selection};
    use suilette::events::{Self, BetResult};
    use suilette::game_status::{Self as status};
    use suilette::risk_manager::{Self as rm, RiskManager};
    use suilette::bet_manager::{Self as bm};
    use suilette::rebate_manager::{Self as rem, RebateManager};

    /// Error codes
    const EGameNotInProgress: u64 = 0;
    const EGameAlreadyCompleted: u64 = 1;
    const ECallerNotHouse: u64 = 4;
    const EInsufficientBalance: u64 = 6;
    const EInsufficientHouseBalance: u64 = 8;
    const EInvalidBetType: u64 = 10;
    const EInvalidBetNumber: u64 = 12;
    const EGameNotFound: u64 = 13;

    // 1 SUI is the default min bet
    const DEFAULT_MIN_BET: u64 = 1000000000;
    const DEFAULT_PLAYER_REBATE_RATE: u64 = 0; // 0.5%
    const DEFAULT_REFERRER_REBATE_RATE: u64 = 0; // 0.5%

    struct Bet<phantom Asset> has key, store {
        id: UID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: Balance<Asset>,
        player: address,
        is_settled: bool,
        name: Option<String>,
        avatar: Option<ID>,
        image_url: Option<String>,
    }

    struct BetDisplay<phantom Asset> has store, drop {
        id: ID,
        bet_type: u8,
        bet_number: Option<u64>,
        bet_size: u64,
        player: address,
        name: Option<String>,
        avatar: Option<ID>,
        image_url: Option<String>,
    }

    struct HouseData<phantom Asset> has key {
        id: UID,
        balance: Balance<Asset>,
        house: address,
        house_risk: u64,
        max_risk_per_game: u64,
        rebate_manager: RebateManager,
    }

    struct HouseCap has key, store {
        id: UID,
        /// The owner of this AccountCap. Note: this is
        /// derived from an object ID, not a user address
        owner: address,
    }

    struct RouletteGame<phantom Asset> has key, store {
        id: UID,
        owner: address,
        status: u8,
        round: u64,
        bets: TableVec<Bet<Asset>>,
        risk_manager: RiskManager,
        result_roll: u64,
        min_bet: u64,
        settled_bets_count: u64,
        player_bets_table: Table<address, vector<BetDisplay<Asset>>>,
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

    /// Returns the risk of the game
    /// @param house_data: The HouseData object
    public fun game_risk<Asset>(game: &RouletteGame<Asset>): u64 {
        rm::total_risk(&game.risk_manager)
    }

    /// Return the owner of an HouseCap
    public fun account_owner(house_cap: &HouseCap): address {
        house_cap.owner
    }

    public fun bets<Asset>(game: &RouletteGame<Asset>): &TableVec<Bet<Asset>> {
        &game.bets
    }

    public fun player_bets_table<Asset>(game: &RouletteGame<Asset>): &Table<address, vector<BetDisplay<Asset>>> {
        &game.player_bets_table
    }

    public fun risk_manager<Asset>(game: &RouletteGame<Asset>): &RiskManager {
        &game.risk_manager
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
            rebate_manager: rem::new(DEFAULT_PLAYER_REBATE_RATE, DEFAULT_REFERRER_REBATE_RATE, ctx),
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
        events::emit_house_deposit<Asset>(coin_value);
        balance::join(&mut house_data.balance, coin_balance);
    }

    /// House can withdraw the entire balance of the house object
    /// @param house_data: The HouseData object
    public entry fun withdraw<Asset>(house_data: &mut HouseData<Asset>, quantity: u64, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);
        events::emit_house_withdraw<Asset>(quantity);
        let coin = coin::take(&mut house_data.balance, quantity, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    public entry fun update_rebate_rate<Asset>(
        house_cap: &HouseCap,
        house_data: &mut HouseData<Asset>,
        player_rate: u64,
        referrer_rate: u64,
        ctx: &TxContext,
    ) {
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);
        rem::update_rate(&mut house_data.rebate_manager, player_rate, referrer_rate);
    }

    /// Create a shared-object roulette Game. 
    /// Only a house can create games currently to ensure that we cannot be hacked
    public entry fun create<Asset>(
        round: u64,
        house_data: &mut HouseData<Asset>,
        house_cap: &HouseCap,
        ctx: &mut TxContext
    ): ID {
        assert!(account_owner(house_cap) == house_data.house, ECallerNotHouse);

        // Initialize the number_risk to be a vector of size 38, starting from 0.
        let game_uid = object::new(ctx);
        let game = RouletteGame<Asset> {
            id: game_uid,
            owner: tx_context::sender(ctx), 
            round,
            status: status::in_progress(),
            bets: tvec::empty(ctx),
            risk_manager: rm::new_manager(),
            result_roll: 0,
            min_bet: DEFAULT_MIN_BET,
            settled_bets_count: 0,
            player_bets_table: table::new(ctx),
        };
        let game_id = *object::uid_as_inner(&game.id);
        dof::add(&mut house_data.id, game_id, game);
        events::emit_game_created<Asset>(game_id);
        game_id
    }

    public entry fun create_with_min_bet<Asset>(
        round: u64,
        house_data: &mut HouseData<Asset>,
        house_cap: &HouseCap,
        min_bet: u64,
        ctx: &mut TxContext
    ): ID {
        assert!(account_owner(house_cap) == house_data.house, ECallerNotHouse);

        // Initialize the number_risk to be a vector of size 38, starting from 0.
        let game_uid = object::new(ctx);
        let game = RouletteGame<Asset> {
            id: game_uid,
            owner: tx_context::sender(ctx), 
            round,
            status: status::in_progress(),
            bets: tvec::empty(ctx),
            risk_manager: rm::new_manager(),
            result_roll: 0,
            min_bet,
            settled_bets_count: 0,
            player_bets_table: table::new(ctx),
        };
        let game_id = *object::uid_as_inner(&game.id);
        dof::add(&mut house_data.id, game_id, game);
        events::emit_game_created<Asset>(game_id);
        game_id
    }

    public fun borrow_game<Asset>(house_data: &HouseData<Asset>, game_id: ID): &RouletteGame<Asset> {
        assert!(dof::exists_with_type<ID, RouletteGame<Asset>>(&house_data.id, game_id), EGameNotFound);
        dof::borrow<ID, RouletteGame<Asset>>(&house_data.id, game_id)
    }

    fun borrow_game_mut<Asset>(house_data: &mut HouseData<Asset>, game_id: ID): &mut RouletteGame<Asset> {
        assert!(dof::exists_with_type<ID, RouletteGame<Asset>>(&house_data.id, game_id), EGameNotFound);
        dof::borrow_mut<ID, RouletteGame<Asset>>(&mut house_data.id, game_id)
    }

    /// Anyone can participate in the betting of the game, could consider allowing different bet sizes
    /// A user can only place a bet in the current round and the next round
    public entry fun place_bet<Asset>(
        coin: Coin<Asset>,
        bet_type: u8,
        bet_number: Option<u64>,
        game_id: ID,
        house_data: &mut HouseData<Asset>,
        name: Option<String>,
        avatar: Option<ID>,
        image_url: Option<String>,
        ctx: &mut TxContext
    ) {
        // Assert that the bet type is valid and within the range of bets
        assert!(bet_type >= 0 && bet_type <= 12, EInvalidBetType);
        if (bet_type == 2) {
            assert!(option::is_some(&bet_number), EInvalidBetNumber);
            assert!(*option::borrow(&bet_number) <= 37, EInvalidBetNumber);
        };
        let coin_value = coin::value(&coin);
        let bet_payout = bm::get_bet_payout(coin_value, bet_type);

        // add risk
        let game = borrow_game_mut(house_data, game_id);
        let (risk_increased, risk_change) = rm::add_risk(&mut game.risk_manager, bet_type, bet_number, bet_payout);
        if (risk_increased) {
            house_data.house_risk = house_data.house_risk + risk_change;
        } else {
            house_data.house_risk = house_data.house_risk - risk_change;
        };

        let max_risk_per_game = house_data.max_risk_per_game;
        assert!(house_risk(house_data) <= balance(house_data), EInsufficientHouseBalance);
        let game = borrow_game_mut(house_data, game_id);
        assert!(rm::total_risk(&game.risk_manager) <= max_risk_per_game, EInsufficientHouseBalance);
        assert!(game.status == status::in_progress(), EGameNotInProgress);

        // Check that the coin value is above the minimum bet
        assert!(coin_value >= game.min_bet, EInsufficientBalance);

        let bet_size = coin::into_balance(coin);
        let player = tx_context::sender(ctx);

        let new_bet = Bet {
            id: object::new(ctx),
            bet_type,
            bet_number,
            bet_size,
            player,
            is_settled: false,
            name,
            avatar,
            image_url,
        };
        let bet_balance_value = balance::value(&new_bet.bet_size);
        let bet_id = *object::uid_as_inner(&new_bet.id);
        events::emit_place_bet<Asset>(
            bet_id, new_bet.bet_type, new_bet.bet_number, bet_balance_value, new_bet.player,
        );

        tvec::push_back(&mut game.bets, new_bet);

        let bet_display = BetDisplay<Asset> {
            id: bet_id,
            bet_type,
            bet_number,
            bet_size: bet_balance_value,
            player,
            name,
            avatar,
            image_url,
        };
        let player_bets_table = &mut game.player_bets_table;
        if (table::contains(player_bets_table, player)) {
            let player_bets = table::borrow_mut(player_bets_table, player);
            vec::push_back(player_bets, bet_display);
        } else {
            table::add(player_bets_table, player, vec::singleton(bet_display));
        };

        // add volume
        rem::add_volume_v4<Asset>(&mut house_data.rebate_manager, player, coin_value);
    }

    /// Anyone can close the game by providing the randomness of round - 1. 
    public entry fun close<Asset>(
        house_data: &mut HouseData<Asset>,
        game_id: ID,
        drand_sig: vector<u8>,
        drand_prev_sig: vector<u8>
    ) {
        let game = borrow_game_mut(house_data, game_id);
        assert!(game.status == status::in_progress(), EGameNotInProgress);
        verify_drand_signature(drand_sig, drand_prev_sig, closing_round(game.round));
        game.status = status::closed();
        let game_id = *object::uid_as_inner(&game.id);
        events::emit_game_closed<Asset>(game_id);
    }

    /// Anyone can complete the game by providing the randomness of round.
    /// - Anyone can *close* the game to new participants by providing drand's randomness of round N-2 (i.e., 1 minute before
    ///   round N). The randomness of round X can be retrieved using
    ///  `curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/X'.
    /// TODO: update risks and remove bets
    public entry fun complete<Asset>(
        game_id: ID, 
        house_cap: &HouseCap,        
        house_data: &mut HouseData<Asset>, 
        drand_sig: vector<u8>, 
        drand_prev_sig: vector<u8>,
        cursor: u64,
        page_size: u64,
        ctx: &mut TxContext
    ) {
        let game = borrow_game(house_data, game_id);
        assert!(game.status != status::completed(), EGameAlreadyCompleted);
        complete_partial(game_id, house_cap, house_data, drand_sig, drand_prev_sig, cursor, page_size, false, ctx);
        complete_partial(game_id, house_cap, house_data, drand_sig, drand_prev_sig, cursor, page_size, true, ctx);
    }

    fun complete_partial<Asset>(
        game_id: ID, 
        house_cap: &HouseCap,        
        house_data: &mut HouseData<Asset>, 
        drand_sig: vector<u8>, 
        drand_prev_sig: vector<u8>,
        cursor: u64,
        page_size: u64,
        player_won_part: bool,
        ctx: &mut TxContext
    ) {
        let game = borrow_game_mut(house_data, game_id);
        if (game.status == status::completed()) return;
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);
        verify_drand_signature(drand_sig, drand_prev_sig, game.round);

        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);

        // We accept some small amount of bias with safe selection
        // 0 or 37 are both losses unless they picked a number
        let win_roll = safe_selection(38, &digest);
        game.result_roll = win_roll;

        let game_id = *object::uid_as_inner(&game.id);
        
        // let bet_index = 0;
        let bet_index = cursor;
        let end_index = cursor + page_size;
        let bets_length = tvec::length(&game.bets);
        if (end_index > bets_length) end_index = bets_length;

        let bet_results = vector<BetResult<Asset>>[];

        // Deduct the house risk of the max number bet since we theoretically pay it off
        game.status = status::in_settlement();
        
        while (bet_index < end_index) {
            let game = borrow_game_mut(house_data, game_id);
            let bet = tvec::borrow_mut(&mut game.bets, bet_index);
            let player_won = bm::won_bet(bet.bet_type, win_roll, bet.bet_number);
            if (player_won_part != player_won) {
                bet_index = bet_index + 1;
                continue
            };
            if (bet.is_settled) {
                bet_index = bet_index + 1;
                continue
            };
            let player = bet.player;
            let player_bet = balance::value(&bet.bet_size);
            let bet_payout = bm::get_bet_payout(player_bet, bet.bet_type);

            let bet_id = *object::uid_as_inner(&bet.id);
            let bet_result = events::new_bet_result(
                bet_id,
                player_won,
                bet.bet_type,
                bet.bet_number,
                player_bet,
                bet.player,
            );
            vec::push_back(&mut bet_results, bet_result);
            let player_coin = coin::take(&mut bet.bet_size, player_bet, ctx);
            bet.is_settled = true;

            // remove player bet IDs
            let player_bets_mut = &mut game.player_bets_table;
            if (table::contains(player_bets_mut, player)) {
                table::remove(player_bets_mut, player);
            };
            game.settled_bets_count = game.settled_bets_count + 1;

            // Deal with house and payout
            if (player_won) {
                let house_payment = coin::take(&mut house_data.balance, bet_payout, ctx);
                coin::join(&mut player_coin, house_payment);
                transfer::public_transfer(player_coin, player);
            } else {
                // Send money to the house in losing bet
                coin::put(&mut house_data.balance, player_coin);
            };

            // Increment bet index
            bet_index = bet_index + 1;
        };

        let game = borrow_game_mut(house_data, game_id);
        let settled_bets_count = game.settled_bets_count;
        if (settled_bets_count == bets_length) {
            game.status = status::completed();
        };
        let game_total_risk = rm::total_risk(&game.risk_manager);
        if (settled_bets_count == bets_length) {
            house_data.house_risk = house_data.house_risk - game_total_risk;
        };

        events::emit_game_completed<Asset>(
            game_id, win_roll, bet_results,
        );
    }

    public entry fun refund_all_bets<Asset>(
        house_cap: &HouseCap,
        house_data: &mut HouseData<Asset>,
        game_id: ID,
        page_size: u64,
        ctx: &mut TxContext
    ) {
        // Only owner can delete a game
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);

        let game = borrow_game_mut(house_data, game_id);
        if(page_size > tvec::length(&game.bets))
            page_size = tvec::length(&game.bets);
        let counter = 0;
        while (counter < page_size) {
            let bets_mut = &mut game.bets;
            let bet = tvec::pop_back(bets_mut);
            delete_bet(bet, ctx);
            counter = counter + 1;
        };
        if (tvec::is_empty(&game.bets)) {
            let game = dof::remove<ID, RouletteGame<Asset>>(&mut house_data.id, game_id);
            delete_game(game);
        };
    }

    fun delete_bet<Asset>(bet: Bet<Asset>, ctx: &mut TxContext) {
        let Bet<Asset> { id, bet_type: _, bet_number: _, bet_size, player, is_settled: _, name: _, avatar: _, image_url: _} = bet;
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

    fun delete_game<Asset>(game: RouletteGame<Asset>) {
        let RouletteGame {
            id,
            owner: _,
            status: _,
            round: _,
            bets,
            risk_manager: _,
            result_roll: _,
            min_bet: _,
            settled_bets_count: _,
            player_bets_table,
        } = game;
        object::delete(id);
        tvec::destroy_empty(bets);
        table::drop(player_bets_table);
    }

    /// Rebate & Referral
    public fun set_referrer<Asset>(
        house: &mut HouseData<Asset>,
        referrer: address,
        ctx: &TxContext,
    ) {
        let player = tx_context::sender(ctx);
        rem::register_v4<Asset>(&mut house.rebate_manager, player, option::some(referrer));
    }

    public fun claim_rebate<Asset>(
        house: &mut HouseData<Asset>,
        ctx: &mut TxContext,
    ) {
        let player = tx_context::sender(ctx);
        let (
            player_rebate_amount,
            referrer,
            referrer_rebate_amount
        ) = rem::claim_rebate_v4<Asset>(&mut house.rebate_manager, player);
        if (player_rebate_amount > 0) {
            transfer::public_transfer(
                coin::take(&mut house.balance, player_rebate_amount, ctx),
                player,
            );
        };
        if (option::is_some(&referrer) && referrer_rebate_amount > 0) {
            transfer::public_transfer(
                coin::take(&mut house.balance, player_rebate_amount, ctx),
                option::destroy_some(referrer),
            );
        };
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
    ): ID {
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
        let game_id = {
            // Top up the house
            let house_data = test_scenario::take_shared<HouseData<SUI>>(scenario);
            let house_cap = test_scenario::take_from_address<HouseCap>(scenario, house);
            top_up(&mut house_data, mint_for_testing<SUI>(1000 * 1000000000, test_scenario::ctx(scenario)));

            // Test create
            let game_id = create<SUI>(3125272, &mut house_data, &house_cap, test_scenario::ctx(scenario));
            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
            game_id
        };
        game_id
    }

    #[test] fun test_max_number_bets_ok() { test_max_number_bets_ok_(scenario()); }
    #[test] fun test_house_wins_red_bet() { test_house_wins_red_bet_(scenario()); }
    #[test] fun test_bets_are_refundable() { test_bets_are_refunded(scenario()); }
    #[test] fun test_cannot_exceed_max_risk() {}
    #[test] fun test_bet_type_pay_out_as_expected() {}

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // begin with house address
    #[test_only]
    fun scenario(): Scenario { test_scenario::begin(@0xAAAA) }
    
    #[test_only]
    fun test_house_wins_red_bet_(test: Scenario) {
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;

        let game_id = setup_house_for_test(&mut test);
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on red
            place_bet<SUI>(
                mint_for_testing<SUI>(5 * 1000000000, test_scenario::ctx(&mut test)),
                0,
                option::none<u64>(),
                game_id,
                &mut house_data,
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut test),
            );
            test_scenario::return_shared(house_data);
        };
            test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            complete<SUI>(game_id, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 0, 10, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
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
        let game_id = setup_house_for_test(&mut test);
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on 2
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(2),
                game_id,
                &mut house_data,
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut test)
            );

            // Place bet on 4
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(4),
                game_id,
                &mut house_data,
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            let roulette_game = borrow_game(&house_data, game_id);
            assert!(roulette_game.status == status::in_progress(), 0);
            complete<SUI>(game_id, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 0, 1, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            let drand_sig = x"ad11b336ad8ca2fefeb75dfa9a7de842ac139c7c199f2e73e118c82b8919ceec27b1066724382d6a6571a0d129be9e7413873cd629720063e6b5147aab5836f076ea30a1bb142f50ed99074d206a78efb9e0091152c73dcfffdfd4927bbb88a4";
            let drand_previous_sig = x"a62f85451dbe80351a3a847f660fe987a5c518b97c0e00cdfef9b4050fc44d29a3a557285413970d492f3acb903d8c720cee37873c8ffab3d64edaa546b59233bdeeb6990aea76989c3c6f10312be62ece9706fca1f40d946fe066c4929c1ac3";

            let roulette_game = borrow_game(&house_data, game_id);
            assert!(roulette_game.status == status::in_settlement(), 0);
            complete<SUI>(game_id, &house_cap, &mut house_data, drand_sig, drand_previous_sig, 1, 1, test_scenario::ctx(&mut test));

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
        test_scenario::next_tx(&mut test, player);
        {
            // Check that the house gained the bet that the player made
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let roulette_game = borrow_game(&house_data, game_id);
            // sui::test_utils::assert_eq(balance::value(&house_data.balance), 105 * 1000000000);
            assert!(roulette_game.status == status::completed(), 0);
            test_scenario::return_shared(house_data);
        };
        test_scenario::end(test);
    }

    #[test_only]
    fun test_bets_are_refunded(test: Scenario) {
        let house: address = @0xAAAA;
        let player: address = @0xBBBB;
        let game_id = setup_house_for_test(&mut test);
        test_scenario::next_tx(&mut test, player);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);

            // Place a bet on 2
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(2),
                game_id,
                &mut house_data,
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut test)
            );

            // Place bet on 4
            place_bet<SUI>(
                mint_for_testing<SUI>(27 * 1000000000, test_scenario::ctx(&mut test)),
                2,
                option::some<u64>(4),
                game_id,
                &mut house_data,
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            // Delete
            refund_all_bets<SUI>(
                &house_cap,
                &mut house_data,
                game_id,
                1,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
        test_scenario::next_tx(&mut test, house);
        {
            // Get the game
            let house_data = test_scenario::take_shared<HouseData<SUI>>(&mut test);
            let house_cap = test_scenario::take_from_address<HouseCap>(&test, house);

            // Delete
            refund_all_bets<SUI>(
                &house_cap,
                &mut house_data,
                game_id,
                1,
                test_scenario::ctx(&mut test)
            );

            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
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

    #[test_only]
    public entry fun complete_parital_for_testing<Asset>(
        game_id: ID, 
        house_cap: &HouseCap,        
        house_data: &mut HouseData<Asset>, 
        win_roll: u64,
        cursor: u64,
        page_size: u64,
        player_won_part: bool,
        ctx: &mut TxContext
    ) {
        let game = borrow_game_mut(house_data, game_id);
        if (game.status == status::completed()) return;
        assert!(account_owner(house_cap) == tx_context::sender(ctx), ECallerNotHouse);

        // We accept some small amount of bias with safe selection
        // 0 or 37 are both losses unless they picked a number
        game.result_roll = win_roll;

        let game_id = *object::uid_as_inner(&game.id);
        
        // let bet_index = 0;
        let bet_index = cursor;
        let end_index = cursor + page_size;
        let bets_length = tvec::length(&game.bets);
        if (end_index > bets_length) end_index = bets_length;

        let bet_results = vector<BetResult<Asset>>[];

        // Deduct the house risk of the max number bet since we theoretically pay it off
        game.status = status::in_settlement();
        
        while (bet_index < end_index) {
            let game = borrow_game_mut(house_data, game_id);
            let bet = tvec::borrow_mut(&mut game.bets, bet_index);
            let player_won = bm::won_bet(bet.bet_type, win_roll, bet.bet_number);
            if (player_won_part != player_won) {
                bet_index = bet_index + 1;
                continue
            };
            if (bet.is_settled) {
                bet_index = bet_index + 1;
                continue
            };
            
            let player = bet.player;
            let player_bet = balance::value(&bet.bet_size);
            let bet_payout = bm::get_bet_payout(player_bet, bet.bet_type);

            let bet_id = *object::uid_as_inner(&bet.id);
            let bet_result = events::new_bet_result(
                bet_id,
                player_won,
                bet.bet_type,
                bet.bet_number,
                player_bet,
                bet.player,
            );
            vec::push_back(&mut bet_results, bet_result);
            let player_coin = coin::take(&mut bet.bet_size, player_bet, ctx);
            bet.is_settled = true;

            // remove player bet IDs
            let player_bets_mut = &mut game.player_bets_table;
            if (table::contains(player_bets_mut, player)) {
                table::remove(player_bets_mut, player);
            };
            game.settled_bets_count = game.settled_bets_count + 1;

            // Deal with house and payout
            if (player_won) {
                let house_payment = coin::take(&mut house_data.balance, bet_payout, ctx);
                coin::join(&mut player_coin, house_payment);
                transfer::public_transfer(player_coin, player);
            } else {
                // Send money to the house in losing bet
                coin::put(&mut house_data.balance, player_coin);
            };

            // Increment bet index
            bet_index = bet_index + 1;
        };

        let game = borrow_game_mut(house_data, game_id);
        let settled_bets_count = game.settled_bets_count;
        if (settled_bets_count == bets_length) {
            game.status = status::completed();
        };
        let game_total_risk = rm::total_risk(&game.risk_manager);
        if (settled_bets_count == bets_length) {
            house_data.house_risk = house_data.house_risk - game_total_risk;
        };

        events::emit_game_completed<Asset>(
            game_id, win_roll, bet_results,
        );
    }

    #[test_only]
    public entry fun complete_for_testing<Asset>(
        game_id: ID, 
        house_cap: &HouseCap,        
        house_data: &mut HouseData<Asset>, 
        win_roll: u64,
        cursor: u64,
        page_size: u64,
        ctx: &mut TxContext
    ) {
        let game = borrow_game(house_data, game_id);
        assert!(game.status != status::completed(), EGameAlreadyCompleted);
        complete_parital_for_testing(game_id, house_cap, house_data, win_roll, cursor, page_size, false, ctx);
        complete_parital_for_testing(game_id, house_cap, house_data, win_roll, cursor, page_size, true, ctx);
    }
}