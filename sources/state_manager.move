module suilette::state_manager {
    
    /// The genesis time of chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
    const GENESIS: u64 = 1595431050_000; // ms
    const OFFSET: u64 = 1_000; // ms

    const STATE_OF_PLACING_BET: u8 = 0;
    const STATE_OF_ROLLING: u8 = 1;
    const STATE_OF_SETTLEMENT: u8 = 2;

    public fun state_of_place_bet(): u8 { STATE_OF_PLACING_BET }
    public fun state_of_rolling(): u8 { STATE_OF_ROLLING }
    public fun state_of_settlement(): u8 { STATE_OF_SETTLEMENT }
}