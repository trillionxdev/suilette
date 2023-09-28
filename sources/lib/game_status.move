module suilette::game_status {

    /// Game status
    const IN_PROGRESS: u8 = 0;
    const CLOSED: u8 = 1;
    const IN_SETTLEMENT: u8 = 2; // REVIEW: add a status
    const COMPLETED: u8 = 3;

    public fun in_progress(): u8 { IN_PROGRESS }
    public fun closed(): u8 { CLOSED }
    public fun in_settlement(): u8 { IN_SETTLEMENT }
    public fun completed(): u8 { COMPLETED }
}