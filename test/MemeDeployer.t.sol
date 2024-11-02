// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeDeployer.sol";
import "../src/MemeStorage.sol";
import "../src/MemeEventTracker.sol";
import "../src/MemeCoin.sol";
import "../src/FeeDistribution.sol";

import {MemePool} from "../src/MemePool.sol";
import {LpLockDeployer} from "../src/LpLockDeployer.sol";

contract MemeDeployerTest is Test {
    MemeDeployer public memeDeployer;
    MemePool public memePool;
    MemeStorage public memeStorage;
    MemeEventTracker public eventTracker;
    MemeCoin public memeCoin;
    FeeDistribution public feeDistributionContract;
    LpLockDeployer public lpLockDeployer;

    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on BASE
    address WETH = 0x4200000000000000000000000000000000000006; // WETH on BASE
    address Uniswap_V2_Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2 Router on BASE

    function setUp() public {
        feeDistributionContract = new FeeDistribution();
        memeCoin = new MemeCoin();
        lpLockDeployer = new LpLockDeployer();

        memeStorage = new MemeStorage();
        eventTracker = new MemeEventTracker(address(memeStorage));

        memePool = new MemePool(
            address(memeCoin),
            address(feeDistributionContract),
            address(lpLockDeployer),
            USDC,
            address(eventTracker),
            100
        );

        memeDeployer = new MemeDeployer(
            address(memePool), address(feeDistributionContract), address(memeStorage), address(eventTracker)
        );

        memeDeployer.addRouter(Uniswap_V2_Router);
        memeDeployer.addBaseToken(WETH);

        memePool.addDeployer(address(memeDeployer));
        memeStorage.addDeployer(address(memeDeployer));
        eventTracker.addDeployer(address(memeDeployer));
    }

    function testUpdateFees() public {
        uint256 newTeamFee = 1 ether;
        uint256 newOwnerFee = 500; // 5%

        memeDeployer.updateTeamFee(newTeamFee);
        memeDeployer.updateCreatorFee(newOwnerFee);

        assertEq(memeDeployer.teamFee(), newTeamFee);
        assertEq(memeDeployer.getCreatorPer(), newOwnerFee);
    }

    function testUpdateSupplyValue() public {
        uint256 newSupplyValue = 2000000000 ether;

        memeDeployer.updateSupplyValue(newSupplyValue);

        assertEq(memeDeployer.supplyValue(), newSupplyValue);
    }
}
