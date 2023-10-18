module suilette::rebate_manager {
    
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::event;
    use suilette::math::unsafe_mul;

    friend suilette::drand_based_roulette;

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

    struct SetReferrer has copy, drop {
        player: address,
        referrer: address,
    }

    struct PlayerRebate has copy, drop {
        player: address,
        amount: u64,
    }

    struct ReferrerRebate has copy, drop {
        referrer: address,
        amount: u64,
    }

    struct Claim has copy, drop {
        user: address,
        amount: u64,
    }

    struct SetReferrerV4<phantom Asset> has copy, drop {
        player: address,
        referrer: address,
    }

    struct PlayerRebateV4<phantom Asset> has copy, drop {
        player: address,
        amount: u64,
    }

    struct ReferrerRebateV4<phantom Asset> has copy, drop {
        referrer: address,
        amount: u64,
    }

    struct ClaimV4<phantom Asset> has copy, drop {
        user: address,
        amount: u64,
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

    // public(friend) fun register_v3(
    //     manager: &mut RebateManager,
    //     player: address,
    //     referrer: Option<address>,
    // ) {
    //     let rebate_table = &mut manager.rebate_table;
    //     if (table::contains(rebate_table, player)) {
    //         let rebate_data = table::borrow_mut(rebate_table, player);
    //         if (option::is_some(&rebate_data.referrer)) return;
    //         rebate_data.referrer = referrer;
    //     } else {
    //         table::add(rebate_table, player, RebateData {
    //             amount_for_player: 0,
    //             referrer,
    //             amount_for_referrer: 0,
    //         });
    //     };
    //     if (option::is_some(&referrer)) {
    //         event::emit(SetReferrer {
    //             player,
    //             referrer: option::destroy_some(referrer),
    //         });
    //     };
    // }

    // public(friend) fun add_volume_v3(
    //     manager: &mut RebateManager,
    //     player: address,
    //     bet_size: u64,
    // ) {
    //     if (!table::contains(&manager.rebate_table, player)) {
    //         register(manager, player, option::none());
    //     };
    //     let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
    //     let amount_for_player = unsafe_mul(bet_size, manager.player_rate);
    //     rebate_data.amount_for_player = rebate_data.amount_for_player + amount_for_player;

    //     if (amount_for_player > 0) {
    //         event::emit(PlayerRebate {
    //             player,
    //             amount: amount_for_player,
    //         })
    //     };

    //     if (option::is_none(&rebate_data.referrer)) return;
        
    //     let referrer = *option::borrow(&rebate_data.referrer);
    //     if (!table::contains(&manager.rebate_table, referrer)) {
    //         register(manager, referrer, option::none());
    //     };
    //     let rebate_data = table::borrow_mut(&mut manager.rebate_table, referrer);
    //     let amount_for_referrer = unsafe_mul(bet_size, manager.referrer_rate);
    //     rebate_data.amount_for_player = rebate_data.amount_for_player + amount_for_referrer;
    //     if (amount_for_referrer > 0) {
    //         event::emit(ReferrerRebate {
    //             referrer,
    //             amount: amount_for_player,
    //         })
    //     };
    // }

    // public(friend) fun claim_rebate_v3(
    //     manager: &mut RebateManager,
    //     player: address,
    // ): (u64, Option<address>, u64) {
    //     assert!(table::contains(&manager.rebate_table, player), ENoRegistration);
    //     let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
    //     let player_rebate_amount = rebate_data.amount_for_player;
    //     let referrer = rebate_data.referrer;
    //     let referrer_rebate_amount = rebate_data.amount_for_referrer;
    //     rebate_data.amount_for_player = 0;
    //     rebate_data.amount_for_referrer = 0;
    //     if (player_rebate_amount > 0) {
    //         event::emit(Claim {
    //             user: player,
    //             amount: player_rebate_amount,
    //         });
    //     };
    //     (player_rebate_amount, referrer, referrer_rebate_amount)
    // }

        public(friend) fun register_v4<Asset>(
        manager: &mut RebateManager,
        player: address,
        referrer: Option<address>,
    ) {
        let rebate_table = &mut manager.rebate_table;
        if (table::contains(rebate_table, player)) {
            let rebate_data = table::borrow_mut(rebate_table, player);
            if (option::is_some(&rebate_data.referrer)) return;
            rebate_data.referrer = referrer;
        } else {
            table::add(rebate_table, player, RebateData {
                amount_for_player: 0,
                referrer,
                amount_for_referrer: 0,
            });
        };
        if (option::is_some(&referrer)) {
            event::emit(SetReferrerV4<Asset> {
                player,
                referrer: option::destroy_some(referrer),
            });
        };
    }

    public(friend) fun add_volume_v4<Asset>(
        manager: &mut RebateManager,
        player: address,
        bet_size: u64,
    ) {
        if (!table::contains(&manager.rebate_table, player)) {
            register(manager, player, option::none());
        };
        let rebate_data = table::borrow_mut(&mut manager.rebate_table, player);
        let amount_for_player = unsafe_mul(bet_size, manager.player_rate);
        rebate_data.amount_for_player = rebate_data.amount_for_player + amount_for_player;

        if (amount_for_player > 0) {
            event::emit(PlayerRebateV4<Asset> {
                player,
                amount: amount_for_player,
            })
        };

        if (option::is_none(&rebate_data.referrer)) return;
        
        let referrer = *option::borrow(&rebate_data.referrer);
        if (!table::contains(&manager.rebate_table, referrer)) {
            register(manager, referrer, option::none());
        };
        let rebate_data = table::borrow_mut(&mut manager.rebate_table, referrer);
        let amount_for_referrer = unsafe_mul(bet_size, manager.referrer_rate);
        rebate_data.amount_for_player = rebate_data.amount_for_player + amount_for_referrer;
        if (amount_for_referrer > 0) {
            event::emit(ReferrerRebateV4<Asset> {
                referrer,
                amount: amount_for_player,
            })
        };
    }

    public(friend) fun claim_rebate_v4<Asset>(
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
        if (player_rebate_amount > 0) {
            event::emit(ClaimV4<Asset> {
                user: player,
                amount: player_rebate_amount,
            });
        };
        (player_rebate_amount, referrer, referrer_rebate_amount)
    }
}