## memecoin.new smart contracts

Foundry provides the forge command, and you can install it via the Foundry installation script. Run the following command to install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash

# source the foundry environment then run

foundryup
```

Setup environment variables:

```bash
cp .env.example .env
```

To install the smart contract dependencies, run the following command:

```bash
forge install
```

To run the smart contract tests, run the following command:

```bash
forge test --via-ir --fork-url <BASE MAINNET RPC URL>
```

Deploy the smart contract with verification:

> Before deploying, update the deploy script `script/Deploy.s.sol` with the USDC, WETH, and Uniswap V2 Router addresses of the network you are deploying to.

```bash
source .env
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --via-ir --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

Deploy the smart contract without verification:

```bash
source .env
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --via-ir
```

# Bonding Curve LP

## Configurations

There are 7 contracts to deploy:

- `MemeCoin.sol` : All the memecoin will be cloned from this contract. There is no configuration needed for this contract.

- `MemeStorage.sol` : This contract is used to store the memecoin contracts. It is used to get the index of the memecoin contract. No configuration needed for this contract.

- `MemeEventTracker.sol` : This contract is used to track the events of the memecoin. It needs to be initialized with the address of the `MemeStorage.sol` contract.

- `MemePool.sol` : This contract is used to create the LP locker for the memecoin. It needs to be initialized with the following parameters:

  - `_implementation` : The address of the `MemeCoin.sol` contract.
  - `_feeContract` : The address of the contract that will be used to pay the fees.
  - `_lpLockDeployer` : The address of the `LpLockDeployer.sol` contract.
  - `_stableAddress` : The address of the stablecoin.
  - `_eventTracker` : The address of the `MemeEventTracker.sol` contract.
  - `_feePer` : The fee percentage for the memecoin in basis points (100 basis points = 1%).

  Configurable via setters:

  - `_nativePer` : The percentage of the native token to use for the LP. If using custom base token, can set how much of the LP would be in custom base token and how much would be in native token.

- `MemeDeployer.sol` : This contract is used to deploy the memecoin. It needs to be initialized with the following parameters:

  Configurable on constructor:

  - `_memePool` : The address of the `MemePool.sol` contract.
  - `_creationFeeContract` : The address of the contract that will be used to pay the creation fee.
  - `_memeStorage` : The address of the `MemeStorage.sol` contract.
  - `_eventTracker` : The address of the `MemeEventTracker.sol` contract.

  Configurable via setters

  - `_teamFee` : When a user creates a new meme, they must send enough ETH to cover the teamFee, the liquidity amount, and any anti-snipe amount. The teamFee is then sent to the creationFeeDistributionContract. Initially set to 10,000,000 wei (0.00001 ETH). Can be updated by the contract owner using the updateTeamFee function
  - `_ownerFee` : The fee percentage for the owner in basis points (1000 basis points = 1%).
  - `_affiliatePer` : The fee percentage for the affiliate in basis points (1000 basis points = 1%).
  - `_affiliateSpecial` : The address of the affiliate.
  - `_affiliateSpecialPer` : The fee percentage for the affiliate in basis points (1000 basis points = 1%).
  - `_supplyLock` : The state of the supply lock. This is used to lock the supply of the memecoin.
  - `_supplyValue` : The value of the supply. This is the supply that the memecoin will be locked at.
  - `_listThreshold` : The threshold for the list. This is market cap in dollars that must be reached to list the memecoin on the uniswap v2 pool.
  - `_antiSnipePer` : The percentage of the anti snipe. This is the percentage of the supply that must be sent to the memecoin contract to prevent sniping.
  - `_lpBurn` : The state of the LP burn. If true, the LP will be burned when the memecoin is created, otherwise it will be locked.
  - `_initialReserveEth` : The initial reserve of the memecoin in ETH.
  - `_supplyLock` : The state of the supply lock. If true, the supply will be locked, otherwise it will be unlocked.
  - `_addRouter` : The address of the router to add.
  - `_addBaseToken` : The address of the base token to add.
  - `_enableRouter` : The address of the router to enable.
  - `_enableBaseToken` : The address of the base token to enable.
  - `_disableRouter` : The address of the router to disable.
  - `_disableBaseToken` : The address of the base token to disable.
