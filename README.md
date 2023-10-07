# Suilette
Roulette game using DRAND on Sui Network

# Commands for 
~/sui/target/debug/sui client publish --gas-budget 1000000000 sources

SUI_HOUSE_CAP=0xe62cb3339cd69145fcf272004054f388e69b76644d26282359fb2ee51c088867
PACKAGE=0xc0bfc90b3a663357d63878cef0ec80b623624eb0127300f3accda005cf155a73
SUI_COIN_TYPE=0x2::sui::SUI

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function initialize_house_data --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_CAP --gas-budget 1000000000

SUI_HOUSE_DATA=0xd6af8952697ba02000bf87e4c55cd69d54e96c7474d2a9f905e2537d9183fb5c

# 2000 SUI per game max bet
~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function set_max_risk_per_game --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_CAP $SUI_HOUSE_DATA 2000000000000 --gas-budget 500000000

sui client split-coin --amounts 100000000000 --coin-id 0xa1ba7df6033a80d7b6c95787e73120ad4ccaab8661f13ec26971a476d0b8951b --gas-budget 1000000000

# Pay SUI option
sui client pay-sui --amounts 100000000000 --recipients 0xc1a8b53226b1325a0502e5a202ed23c8a73df6054b8e94680af9d100b06d411f --input-coins 0xa1ba7df6033a80d7b6c95787e73120ad4ccaab8661f13ec26971a476d0b8951b --gas-budget 100000000

# Deposit into house balance 
SUI_COIN=0xa45714bf17ef5675686c4e7d0dce9a23db722ad196590fb64a119790b7c86ef8

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function top_up --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_DATA $SUI_COIN --gas-budget 500000000
