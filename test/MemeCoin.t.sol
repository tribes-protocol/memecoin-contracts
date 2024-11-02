// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeCoin.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "../src/MemePool.sol";
import "../src/MemeCoin.sol";
import "../src/MemeStorage.sol";
import "../src/MemeEventTracker.sol";
import "../src/FeeDistribution.sol";

import {MemeDeployer} from "../src/MemeDeployer.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {LpLockDeployer} from "../src/LpLockDeployer.sol";
import {MemeSwap} from "../src/MemeSwap.sol";

contract MemeCoinTest is Test {
    MemeCoin public memeCoin;
    address public deployer;
    address public memePool;
    address public rewardPool;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18; // 1 million tokens

    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on BASE
    address WETH = 0x4200000000000000000000000000000000000006; // WETH on BASE
    address Uniswap_V2_Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2 Router on BASE

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        FeeDistribution feeDistributionContract_ = new FeeDistribution();
        MemeCoin memeCoinContract_ = new MemeCoin();
        LpLockDeployer lpLockDeployer_ = new LpLockDeployer();

        MemeStorage memeStorage_ = new MemeStorage();
        MemeEventTracker memeEventTracker_ = new MemeEventTracker(address(memeStorage_));

        MemePool memePool_ = new MemePool(
            address(memeCoinContract_),
            address(feeDistributionContract_),
            address(lpLockDeployer_),
            USDC,
            address(memeEventTracker_),
            100
        );

        MemeDeployer memeDeployer_ = new MemeDeployer(
            address(memePool_), address(feeDistributionContract_), address(memeStorage_), address(memeEventTracker_)
        );

        MemeSwap memeSwap_ = new MemeSwap(Uniswap_V2_Router, address(memePool));

        RewardPool rewardPool_ = new RewardPool(address(memePool));

        memePool_.updateRewardPool(address(rewardPool_));

        memeDeployer_.addRouter(Uniswap_V2_Router);
        memeDeployer_.addBaseToken(WETH);

        memePool_.addDeployer(address(memeDeployer_));
        memePool_.updateMemeSwap(address(memeSwap_));
        memeDeployer_.updateListThreshold(69420);

        memeCoin = memeCoinContract_;
        memePool = address(memePool_);
        rewardPool = address(rewardPool_);
        deployer = address(memeDeployer_);

        memeCoin.initialize(INITIAL_SUPPLY, "MemeCoin", "MEME", memePool, deployer);
    }

    function testInitialization() public view {
        assertEq(memeCoin.name(), "MemeCoin");
        assertEq(memeCoin.symbol(), "MEME");
        assertEq(memeCoin.decimals(), 18);
        assertEq(memeCoin.totalSupply(), INITIAL_SUPPLY);
        assertEq(memeCoin.balanceOf(memePool), INITIAL_SUPPLY);
        assertTrue(memeCoin.isInitialized());
    }

    function testTransferBeforeDexInitiation() public {
        vm.prank(memePool);
        assertTrue(memeCoin.transfer(user1, 1000));
        assertEq(memeCoin.balanceOf(user1), 1000);

        vm.prank(user1);
        vm.expectRevert("not dex listed");
        memeCoin.transfer(user2, 500);
    }

    function testDexInitiation() public {
        vm.prank(memePool);
        memeCoin.initiateDex();
        assertTrue(memeCoin.dexInitiated());
    }

    function testApproveAndTransferAfterDexInitiation() public {
        vm.prank(memePool);
        memeCoin.initiateDex();
        vm.prank(memePool);
        memeCoin.approve(user1, 1000);
        assertEq(memeCoin.allowance(memePool, user1), 1000);

        vm.prank(user1);
        memeCoin.transferFrom(memePool, user2, 500);
        assertEq(memeCoin.balanceOf(user2), 500);
        assertEq(memeCoin.allowance(memePool, user1), 500);
    }

    function testBurn() public {
        uint256 initialSupply = memeCoin.totalSupply();
        vm.prank(memePool);
        memeCoin.Burn(1000);
        assertEq(memeCoin.totalSupply(), initialSupply - 1000);
        assertEq(memeCoin.balanceOf(memePool), initialSupply - 1000);
    }

    function testIncreaseAndDecreaseAllowance() public {
        vm.prank(memePool);
        memeCoin.approve(user1, 1000);
        assertEq(memeCoin.allowance(memePool, user1), 1000);

        vm.prank(memePool);
        memeCoin.increaseAllowance(user1, 500);
        assertEq(memeCoin.allowance(memePool, user1), 1500);

        vm.prank(memePool);
        memeCoin.decreaseAllowance(user1, 200);
        assertEq(memeCoin.allowance(memePool, user1), 1300);
    }

    function testFailReinitialize() public {
        memeCoin.initialize(INITIAL_SUPPLY, "NewMemeCoin", "NMEME", memePool, deployer);
    }

    function testDelegateVotes() public {
        vm.prank(memePool);
        memeCoin.transfer(user1, 1000);
        vm.prank(user1);
        memeCoin.delegate(user2);
        assertEq(memeCoin.getVotes(user1), 0);
        assertEq(memeCoin.getVotes(user2), 1000);
    }

    function testCheckpoints() public {
        vm.prank(memePool);
        memeCoin.transfer(user1, 1000);
        vm.prank(user1);
        memeCoin.delegate(user1);

        assertEq(memeCoin.numCheckpoints(user1), 1);
        Checkpoints.Checkpoint208 memory checkpoint = memeCoin.checkpoints(user1, 0);
        assertEq(checkpoint._key, block.number);
        assertEq(checkpoint._value, 1000);
    }
}
