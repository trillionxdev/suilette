module suilette::rebate_manager {
    
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use suilette::math::mul;

    const EReferrerAlreadySet: u64 = 0;
    const ENoRegistration: u64 = 1;

    struct RebateData has store, drop {
        referrer: Option<address>,
        total_volume: u64,
        claimed_volume: u64, 
    }

    struct RebateManager has store {
        player_rate: u64,
        referrer_rate: u64,
        rebate_table: Table<address, RebateData>,
    }

    public fun new(
        player_rate: u64,
        referrer_rate: u64,
        ctx: &mut TxContext,
    ): RebateManager {
        RebateManager {
            player_rate,
            referrer_rate,
            rebate_table: table::new(ctx)
        }
    }

    public fun register(
        manager: &mut RebateManager,
        player: address,
        referrer: Option<address>,
    ) {
        let rebate_table = &mut manager.rebate_table;
        if (table::contains(rebate_table, player)) {
            let rebate_data = table::borrow_mut(rebate_table, player);
            assert!(option::is_none(&rebate_data.referrer), EReferrerAlreadySet);
            rebate_data.referrer = referrer;
        } else {
            table::add(rebate_table, player, RebateData {
                referrer,
                total_volume: 0,
                claimed_volume: 0,
            })
        };
    }

    public fun add_volume(
        manager: &mut RebateManager,
        player: address,
        bet_size: u64,
    ) {
        if (!table::contains(&manager.rebate_table, player)) {
            register(manager, player, option::none());
        };

        let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
        rebate_data.total_volume = rebate_data.total_volume + bet_size;
    }

    public fun claim_rebate(
        manager: &mut RebateManager,
        player: address,
    ): (u64, Option<address>, u64) {
        assert!(table::contains(&manager.rebate_table, player), ENoRegistration);
        let player_rate = manager.player_rate;
        let referrer_rate = manager.referrer_rate;
        let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
        let referrer = rebate_data.referrer;
        let claimable_volume = rebate_data.total_volume - rebate_data.claimed_volume;
        let player_rebate_amount = mul(claimable_volume, player_rate);
        let referrer_rebate_amount = if (option::is_some(&referrer)) {
            mul(claimable_volume, referrer_rate)
        } else {
            0
        };
        rebate_data.claimed_volume = rebate_data.total_volume;
        (player_rebate_amount, referrer, referrer_rebate_amount)
    }
}