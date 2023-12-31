#[test_only]
module suilette::test_display {
    
    use std::vector;
    use std::option;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::table;
    use sui::test_scenario as ts;
    use suilette::drand_based_roulette::{Self as sgame, HouseData, HouseCap};
    use suilette::bet_manager as bm;
    use suilette::init_tool::{Self, house};

    #[test]
    fun test_player_bets() {
        let scenario_val = init_tool::new_scenario();
        let scenario = &mut scenario_val;
        let init_house_balance = 5_000_000_000_000;
        init_tool::setup_house_for_test<SUI>(scenario, init_house_balance);

        ts::next_tx(scenario, house());
        let game_id = {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            let house_cap = ts::take_from_address<HouseCap>(scenario, house());
            let clock = ts::take_shared<Clock>(scenario);

            sgame::update_rebate_rate(&house_cap, &mut house_data, 5_000_000, 5_000_000);
            let game_id = sgame::create<SUI>(&clock, 0, &mut house_data, &house_cap, ts::ctx(scenario));

            ts::return_shared(house_data);
            ts::return_shared(clock);
            ts::return_to_address<HouseCap>(house(), house_cap);
            game_id
        };

        let player_1: address = @0x11111;
        ts::next_tx(scenario, player_1);
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);

            // multi bets
            let bet = coin::mint_for_testing(1_000_000_000, ts::ctx(scenario));
            let bet_type = bm::black();
            let bet_number = option::none();
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            let bet = coin::mint_for_testing(2_000_000_000, ts::ctx(scenario));
            let bet_type = bm::even();
            let bet_number = option::none();
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            let bet = coin::mint_for_testing(3_000_000_000, ts::ctx(scenario));
            let bet_type = bm::number();
            let bet_number = option::some(5);
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            ts::return_shared(house_data);
            ts::return_shared(clock);
        };

        let player_2: address = @0x22222;
        ts::next_tx(scenario, player_2);
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);

            // multi bets
            let bet = coin::mint_for_testing(2_000_000_000, ts::ctx(scenario));
            let bet_type = bm::red();
            let bet_number = option::none();
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            let bet = coin::mint_for_testing(4_000_000_000, ts::ctx(scenario));
            let bet_type = bm::odd();
            let bet_number = option::none();
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            let bet = coin::mint_for_testing(6_000_000_000, ts::ctx(scenario));
            let bet_type = bm::number();
            let bet_number = option::some(7);
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            let bet = coin::mint_for_testing(12_000_000_000, ts::ctx(scenario));
            let bet_type = bm::first_twelve();
            let bet_number = option::none();
            sgame::place_bet(&clock, bet, bet_type, bet_number, game_id, &mut house_data, option::none(), option::none(), option::none(), ts::ctx(scenario));

            ts::return_shared(house_data); 
            ts::return_shared(clock);
        };

        // check
        ts::next_tx(scenario, house());
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);

            // std::debug::print(sgame::risk_manager(&game));
            // std::debug::print(&game);
            assert!(sgame::house_risk(&house_data) == 132_000_000_000, 0);
            let game = sgame::borrow_game(&house_data, game_id);
            assert!(sgame::game_risk(game) == 132_000_000_000, 0);
            let player_bets_table = sgame::player_bets_table(game);
            assert!(table::length(player_bets_table) == 2, 0);
            let player_1_bets = table::borrow(player_bets_table, player_1);
            assert!(vector::length(player_1_bets) == 3, 0);
            // std::debug::print(player_1_bets);
            let player_2_bets = table::borrow(player_bets_table, player_2);
            assert!(vector::length(player_2_bets) == 4, 0);
            // std::debug::print(player_2_bets);

            ts::return_shared(house_data);     
        };

        ts::next_tx(scenario, house());
        {
            // std::debug::print(sgame::risk_manager(&game));
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            let house_cap = ts::take_from_sender<HouseCap>(scenario);
            let result_roll = 0;

            sgame::complete_for_testing(game_id, &house_cap, &mut house_data, result_roll, 0, 100, ts::ctx(scenario));

            ts::return_shared(house_data);
            ts::return_to_sender<HouseCap>(scenario, house_cap);
        };

        // check
        ts::next_tx(scenario, house());
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            let game = sgame::borrow_game(&house_data, game_id);
            // std::debug::print(sgame::risk_manager(&game));
            // std::debug::print(&game);
            assert!(sgame::game_risk(game) == 132_000_000_000, 0);
            assert!(sgame::house_risk(&house_data) == 0, 0);
            let player_bets_table = sgame::player_bets_table(game);
            assert!(table::length(player_bets_table) == 0, 0);

            ts::return_shared(house_data);     
        };

        ts::next_tx(scenario, player_1);
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            sgame::claim_rebate(&mut house_data, ts::ctx(scenario));
            ts::return_shared(house_data);
        };

        ts::next_tx(scenario, player_1);
        {
            let rebate = ts::take_from_sender<Coin<SUI>>(scenario);
            assert!(coin::value(&rebate) == 30_000_000, 0);
            sui::balance::destroy_for_testing(coin::into_balance(rebate));
        };

        ts::next_tx(scenario, player_2);
        {
            let house_data = ts::take_shared<HouseData<SUI>>(scenario);
            sgame::set_referrer(&mut house_data, player_1, ts::ctx(scenario));
            sgame::claim_rebate(&mut house_data, ts::ctx(scenario));
            ts::return_shared(house_data);
        };

        ts::next_tx(scenario, player_2);
        {
            let referrer_rebate = ts::take_from_address<Coin<SUI>>(scenario, player_1);
            assert!(coin::value(&referrer_rebate) == 120_000_000, 0);
            sui::balance::destroy_for_testing(coin::into_balance(referrer_rebate));

            let player_rebate = ts::take_from_address<Coin<SUI>>(scenario, player_2);
            assert!(coin::value(&player_rebate) == 120_000_000, 0);
            sui::balance::destroy_for_testing(coin::into_balance(player_rebate));
        };

        ts::end(scenario_val);
    }
}