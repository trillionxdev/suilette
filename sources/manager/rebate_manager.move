module suilette::rebate_manager {
    
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use suilette::math::unsafe_mul;

    const EReferrerAlreadySet: u64 = 0;
    const ENoRegistration: u64 = 1;

    struct RebateData has store, drop {
        amount_for_player: u64,
        referrer: Option<address>,
        amount_for_referrer: u64,
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

    public fun update_rate(
        manager: &mut RebateManager,
        player_rate: u64,
        referrer_rate: u64,
    ) {
        manager.player_rate = player_rate;
        manager.referrer_rate = referrer_rate;
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
                amount_for_player: 0,
                referrer,
                amount_for_referrer: 0,
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

        let amount_for_player = unsafe_mul(bet_size, manager.player_rate);
        let amount_for_referrer = unsafe_mul(bet_size, manager.referrer_rate);

        let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
        rebate_data.amount_for_player = rebate_data.amount_for_player + amount_for_player;
        rebate_data.amount_for_referrer = rebate_data.amount_for_referrer + amount_for_referrer;
    }

    public fun claim_rebate(
        manager: &mut RebateManager,
        player: address,
    ): (u64, Option<address>, u64) {
        assert!(table::contains(&manager.rebate_table, player), ENoRegistration);
        let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
        let player_rebate_amount = rebate_data.amount_for_player;
        let referrer = rebate_data.referrer;
        let referrer_rebate_amount = rebate_data.amount_for_referrer;
        rebate_data.amount_for_player = 0;
        rebate_data.amount_for_referrer = 0;
        (player_rebate_amount, referrer, referrer_rebate_amount)
    }
}