#[test_only]
module suilette::test_play {

    use std::vector;
    use std::option::Option;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::test_scenario as ts;
    use suilette::drand_based_roulette::{Self as dbr, HouseData, RouletteGame, HouseCap};
    use suilette::player_generator as pg;
    use suilette::init_tool::{Self, house};

    #[test]
    fun test_many_players() {
        let scenario_val = init_tool::new_scenario();
        let scenario = &mut scenario_val;
        let init_house_balance = 5_000_000_000_000;
        init_tool::setup_house_for_test<SUI>(scenario, init_house_balance);
        let pgs = &mut pg::new(
            b"Suilette x Bucket",
            1_000_000_000,
            10_000_000_000,
        );

        let round_count: u64 = 190;
        let round_idx: u64 = 0;
        while(round_idx < round_count) {
            // std::debug::print(&round_idx);
            let result_roll = round_idx % 38;
            ts::next_tx(scenario, house());
            {
                let house_data = ts::take_shared<HouseData<SUI>>(scenario);
                let house_cap = ts::take_from_address<HouseCap>(scenario, house());
        
                dbr::create<SUI>(round_idx, &mut house_data, &house_cap, ts::ctx(scenario));

                ts::return_shared(house_data);
                ts::return_to_address<HouseCap>(house(), house_cap);
            };

            let player_count: u64 = 40;
            let player_idx: u64 = 0;
            let players = vector<address>[];
            let player_bet_sizes = vector<u64>[];
            let player_bet_types = vector<u8>[];
            let player_bet_numbers = vector<Option<u64>>[];
            while(player_idx < player_count) {
                let (player, bet, bet_type, bet_number) = pg::gen_player_bet<SUI>(pgs, ts::ctx(scenario));
                let bet_size = coin::value(&bet);
                ts::next_tx(scenario, player);
                {
                    let game = ts::take_shared<RouletteGame<SUI>>(scenario);
                    let house_data = ts::take_shared<HouseData<SUI>>(scenario);

                    dbr::place_bet(bet, bet_type, bet_number, &mut game, &mut house_data, ts::ctx(scenario));
                    vector::push_back(&mut players, player);
                    vector::push_back(&mut player_bet_sizes, bet_size);
                    vector::push_back(&mut player_bet_types, bet_type);
                    vector::push_back(&mut player_bet_numbers, bet_number);

                    ts::return_shared(game);
                    ts::return_shared(house_data);
                };

                player_idx = player_idx + 1;
            };

            ts::next_tx(scenario, house());
            {
                let game = ts::take_shared<RouletteGame<SUI>>(scenario);
                let house_data = ts::take_shared<HouseData<SUI>>(scenario);
                let house_cap = ts::take_from_sender<HouseCap>(scenario);

                dbr::complete_for_testing<SUI>(&mut game, &house_cap, &mut house_data, result_roll, 0, 100, ts::ctx(scenario));

                ts::return_shared(game);
                ts::return_shared(house_data);
                ts::return_to_sender<HouseCap>(scenario, house_cap);
            };

            ts::next_tx(scenario, house());
            let house_balance_before_refund = {
                let house_data = ts::take_shared<HouseData<SUI>>(scenario);

                let house_balance = dbr::balance(&house_data);
                std::debug::print(&house_balance);
                
                ts::return_shared(house_data);
                house_balance
            };

            ts::next_tx(scenario, house());
            {
                let game = ts::take_shared<RouletteGame<SUI>>(scenario);
                let house_data = ts::take_shared<HouseData<SUI>>(scenario);
                let house_cap = ts::take_from_sender<HouseCap>(scenario);

                dbr::refund_all_bets<SUI>(&house_cap,&mut game, 100, ts::ctx(scenario));

                ts::return_shared(game);
                ts::return_shared(house_data);
                ts::return_to_sender<HouseCap>(scenario, house_cap);
            };

            ts::next_tx(scenario, house());
            {
                let house_data = ts::take_shared<HouseData<SUI>>(scenario);

                assert!(house_balance_before_refund == dbr::balance(&house_data), 0);
                
                ts::return_shared(house_data);
            };

            let player_idx: u64 = 0;
            while(player_idx < player_count) {
                let player = *vector::borrow(&players, player_idx);
                ts::next_tx(scenario, player);
                {
                    let bet_size = *vector::borrow(&player_bet_sizes, player_idx);
                    let bet_type = *vector::borrow(&player_bet_types, player_idx);
                    let bet_number = *vector::borrow(&player_bet_numbers, player_idx);
                    if (dbr::won_bet(bet_type, result_roll, bet_number)) {
                        let payout = ts::take_from_sender<Coin<SUI>>(scenario);
                        assert!(dbr::get_bet_payout(bet_size, bet_type) + bet_size == coin::value(&payout), 0);
                        ts::return_to_sender(scenario, payout);
                    } else {
                        let coin_ids = ts::ids_for_sender<Coin<SUI>>(scenario);
                        assert!(vector::length(&coin_ids) == 0, 0);
                    };
                };

                player_idx = player_idx + 1;
            };

            round_idx = round_idx + 1;
        };

        ts::end(scenario_val);
    }
}