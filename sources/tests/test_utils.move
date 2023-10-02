#[test_only]
module suilette::player_generator {

    use std::option::{Self, Option};
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;
    use sui::test_random::{Self, Random};

    struct PlayerGenerator has store, drop {
        random: Random,
        min_stake_amount: u64,
        max_stake_amount: u64,
    }

    public fun new(
        seed: vector<u8>,
        min_stake_amount: u64,
        max_stake_amount: u64,
    ): PlayerGenerator {
        PlayerGenerator {
            random: test_random::new(seed),
            min_stake_amount,
            max_stake_amount,
        }
    }

    public fun gen_player_bet<T>(
        generator: &mut PlayerGenerator,
        ctx: &mut TxContext,
    ): (address, Coin<T>, u8, Option<u64>) {
        let random = &mut generator.random;
        let player = sui::address::from_u256(test_random::next_u256(random));
        let stake_amount_diff = generator.max_stake_amount - generator.min_stake_amount;
        let stake_amount = generator.min_stake_amount + test_random::next_u64(random) % stake_amount_diff;
        let stake = coin::mint_for_testing<T>(stake_amount, ctx);
        let bet_type = test_random::next_u8(random) % 13;
        let bet_number: Option<u64> = if (bet_type == 2) {
            option::some(test_random::next_u64(random) % 38)
        } else {
            option::none()
        };
        (player, stake, bet_type, bet_number)
    }
}

#[test_only]
module suilette::init_tool {

    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};
    use suilette::drand_based_roulette::{Self as sgame, HouseData, HouseCap};

    const HOUSE: address = @0xAAAA;

    public fun new_scenario(): Scenario { ts::begin(HOUSE) }

    public fun setup_house_for_test<T>(
        scenario: &mut Scenario,
        init_house_balance: u64,
    ) {
        ts::next_tx(scenario, house());
        {
            sgame::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, house());
        {
            let house_cap = ts::take_from_address<HouseCap>(scenario, house());
            // Create the housedata
            sgame::initialize_house_data<T>(&house_cap, ts::ctx(scenario));

            ts::return_to_address<HouseCap>(house(), house_cap);
        };

        ts::next_tx(scenario, house());
        {
            // Top up the house
            let house_data = ts::take_shared<HouseData<T>>(scenario);
            
            sgame::top_up(
                &mut house_data,
                coin::mint_for_testing<T>(
                    init_house_balance,
                    ts::ctx(scenario),
                ),
            );

            ts::return_shared(house_data);
        };
    }

    public fun house(): address { HOUSE }
}