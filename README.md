# Suilette
Roulette game using DRAND on Sui Network

# Commands for 
~/sui/target/debug/sui client publish --gas-budget 1000000000 sources

SUI_HOUSE_CAP=0xe62cb3339cd69145fcf272004054f388e69b76644d26282359fb2ee51c088867
PACKAGE=0xc0bfc90b3a663357d63878cef0ec80b623624eb0127300f3accda005cf155a73
SUI_COIN_TYPE=0x2::sui::SUI

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function initialize_house_data --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_CAP --gas-budget 1000000000

SUI_HOUSE_DATA=0xd6af8952697ba02000bf87e4c55cd69d54e96c7474d2a9f905e2537d9183fb5c

# Create Child account caps
~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function create_child_account_cap --args $SUI_HOUSE_CAP $TARGET_ADDRESS_BUCK --gas-budget 2000000000

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function create_child_account_cap --args $SUI_HOUSE_CAP $TARGET_ADDRESS_CETUS --gas-budget 2000000000

# 2000 SUI per game max bet
~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function set_max_risk_per_game --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_CAP $SUI_HOUSE_DATA 2000000000000 --gas-budget 500000000

sui client split-coin --amounts 100000000000 --coin-id 0xa1ba7df6033a80d7b6c95787e73120ad4ccaab8661f13ec26971a476d0b8951b --gas-budget 1000000000

# Pay SUI option
sui client pay-sui --amounts 32778453793816 --recipients 0xc1a8b53226b1325a0502e5a202ed23c8a73df6054b8e94680af9d100b06d411f --input-coins 0x862d440f2326df6da4bf8d1739534cd66c43b00380f424d1303c150fd7e6e9a3 --gas-budget 50000000

# Deposit into house balance 
SUI_COIN=0xb537ccc33e891682f22d64385dfd9d8d9b7e8d698ab7cf1435da63e0c9e44f58

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function top_up --type-args $SUI_COIN_TYPE --args $SUI_HOUSE_DATA $SUI_COIN --gas-budget 500000000

## BUCK UPGRADE

export MAINNET_BUCK_TYPE=0xce7ff77a83ea0cb6fd39bd8748e2ec89a3f41e8efdc3f4eb123e0ca37b184db2::buck::BUCK
export BUCK_HOUSE_CAP=0xc3e291d8c1d06bb816fd9115502e101d26585cac089cac35d017331fc65c0b14
TARGET_ADDRESS_BUCK=0x297cf38055419d0ce4b512a434adf8b377b9184781e32184a2d0e7dca9c7c35b

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function initialize_house_data --type-args $MAINNET_BUCK_TYPE --args $BUCK_HOUSE_CAP --gas-budget 2000000000

export BUCK_HOUSE_DATA=0x9886eca082317c02a741216ca6e9d0d0ea646b51e8497895f9ff4f5bb3814201
BUCK_COIN=0x9ad918f5d40d338bdef0d4f18206cb7ac437fdaee8af1091e73930eb31bedc53

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function top_up --type-args $MAINNET_BUCK_TYPE --args $BUCK_HOUSE_DATA $BUCK_COIN --gas-budget 2000000000

sui client call --package $PACKAGE --module drand_based_roulette --function create --type-args $MAINNET_BUCK_TYPE --args 3125272 $BUCK_HOUSE_DATA $HOUSE_CAP --gas-budget 2000000000


## CETUS UPGRADE

CETUS_COIN_TYPE=0x06864a6f921804860930db6ddbe2e16acdf8504495ea7481637a1c8b9a8fe54b::cetus::CETUS
CETUS_HOUSE_CAP=0xdb08c81c7d733dcdaa444db4f9783e5da1ef8e6cdb15f690a6291364e7bb5995
TARGET_ADDRESS_CETUS=0x404ea6f04e1832bf77c9a9e0d4f2c972eade5ba6d0d94a871c0d6e4cea95ad0a

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function initialize_house_data --type-args $CETUS_COIN_TYPE --args $CETUS_HOUSE_CAP --gas-budget 2000000000

export CETUS_HOUSE_DATA=0xa240f72896153b6251567ed80ef08ff86b26cc77ca2330bf860312701ab6c144
CETUS_COIN=0xd2b6c307ecb74f71f6a59b0d5989d0253ff4fc25f192a1611ce40be9845b3fad

~/sui/target/debug/sui client call --package $PACKAGE --module drand_based_roulette --function top_up --type-args $CETUS_COIN_TYPE --args $CETUS_HOUSE_DATA $CETUS_COIN --gas-budget 2000000000

Created new keypair for address with scheme ED25519: [0x297cf38055419d0ce4b512a434adf8b377b9184781e32184a2d0e7dca9c7c35b]

# BUCK TRANSFER
sui client transfer --to 0x297cf38055419d0ce4b512a434adf8b377b9184781e32184a2d0e7dca9c7c35b --object-id 0x9ad918f5d40d338bdef0d4f18206cb7ac437fdaee8af1091e73930eb31bedc53 --gas-budget 10000000

Created new keypair for address with scheme ED25519: [0x404ea6f04e1832bf77c9a9e0d4f2c972eade5ba6d0d94a871c0d6e4cea95ad0a]

# Cetus transfer
sui client transfer --to 0x404ea6f04e1832bf77c9a9e0d4f2c972eade5ba6d0d94a871c0d6e4cea95ad0a --object-id 0xd2b6c307ecb74f71f6a59b0d5989d0253ff4fc25f192a1611ce40be9845b3fad --gas-budget 1000
