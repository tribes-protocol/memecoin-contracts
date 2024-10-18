// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MemeEventTracker.sol";
import "../src/MemeStorage.sol";
import "../src/MemeCoin.sol";
import "../src/MemeDeployer.sol";
import "../src/FeeDistribution.sol";

import {MemePool} from "../src/MemePool.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {LpLockDeployer} from "../src/LpLockDeployer.sol";

contract Deploy is Script {
    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on BASE
    address WETH = 0x4200000000000000000000000000000000000006; // WETH on BASE
    address Uniswap_V2_Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2 Router on BASE

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        CreationFeeContract feeDistributionContract = new CreationFeeContract();
        MemeCoin memeCoinContract = new MemeCoin();
        LpLockDeployer lpLockDeployer = new LpLockDeployer();

        MemeStorage memeStorage = new MemeStorage();
        MemeEventTracker memeEventTracker = new MemeEventTracker(address(memeStorage));

        MemePool memePool = new MemePool(
            address(memeCoinContract),
            address(feeDistributionContract),
            address(lpLockDeployer),
            USDC,
            address(memeEventTracker),
            100
        );

        MemeDeployer memeDeployer = new MemeDeployer(
            address(memePool), address(feeDistributionContract), address(memeStorage), address(memeEventTracker)
        );

        RewardPool rewardPool = new RewardPool(address(memePool));

        memePool.updateRewardPool(address(rewardPool));

        memeDeployer.addRouter(Uniswap_V2_Router);
        memeDeployer.addBaseToken(WETH);

        memePool.addDeployer(address(memeDeployer));
        memeStorage.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memePool));

        memeDeployer.updateListThreshold(69420);

        vm.stopBroadcast();

        console.log("FeeDistributionContract address:", address(feeDistributionContract));
        console.log("MemeCoinContract address:", address(memeCoinContract));
        console.log("LpLockDeployer address:", address(lpLockDeployer));
        console.log("MemeStorage address:", address(memeStorage));
        console.log("MemeEventTracker address:", address(memeEventTracker));
        console.log("MemePool address:", address(memePool));
        console.log("MemeDeployer address:", address(memeDeployer));
        console.log("RewardPool address:", address(rewardPool));
    }
}
