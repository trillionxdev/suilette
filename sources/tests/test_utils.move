#[test_only]
module suilette::player_generator {

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

    public fun gen_coin<T>(
        generator: &mut PlayerGenerator,
        ctx: &mut TxContext,
    ): (address, Coin<T>) {
        let random = &mut generator.random;
        let player = sui::address::from_u256(test_random::next_u256(random));
        let stake_amount_diff = generator.max_stake_amount - generator.min_stake_amount;
        let stake_amount = generator.min_stake_amount + test_random::next_u64(random) % stake_amount_diff;
        let stake = coin::mint_for_testing<T>(stake_amount, ctx);
        (player, stake)
    }
}

#[test_only]
module suilette::init_tool {

    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};
    use suilette::drand_based_roulette::{Self as dbr, HouseData, HouseCap};

    const HOUSE: address = @0xAAAA;

    public fun new_scenario(): Scenario { ts::begin(HOUSE) }

    public fun setup_house_for_test<T>(
        scenario: &mut Scenario,
        init_pool_size: u64,
    ) {
        ts::next_tx(scenario, house());
        {
            dbr::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, house());
        {
            let house_cap = ts::take_from_address<HouseCap>(scenario, house());
            // Create the housedata
            dbr::initialize_house_data<T>(&house_cap, ts::ctx(scenario));

            ts::return_to_address<HouseCap>(house(), house_cap);
        };

        ts::next_tx(scenario, house());
        {
            // Top up the house
            let house_data = ts::take_shared<HouseData<T>>(scenario);
            let house_cap = ts::take_from_address<HouseCap>(scenario, house());
            dbr::top_up(
                &mut house_data,
                coin::mint_for_testing<T>(
                    init_pool_size,
                    ts::ctx(scenario),
                ),
            );

            // Test create
            dbr::create<T>(3125272, &mut house_data, &house_cap, ts::ctx(scenario));
            ts::return_shared(house_data);
            ts::return_to_address<HouseCap>(house(), house_cap);
        };
    }

    public fun house(): address { HOUSE }
}