// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemePool.sol";
import "../src/MemeCoin.sol";
import "../src/MemeStorage.sol";
import "../src/MemeEventTracker.sol";
import "../src/FeeDistribution.sol";

import {MemeDeployer} from "../src/MemeDeployer.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {LpLockDeployer} from "../src/LpLockDeployer.sol";
import {MemeSwap} from "../src/MemeSwap.sol";

contract MemeSwapTest is Test {
    MemeDeployer public memeDeployer;
    MemePool public memePool;
    MemeStorage public memeStorage;
    MemeEventTracker public memeEventTracker;
    MemeCoin public memeCoin;
    FeeDistribution public feeDistributionContract;
    LpLockDeployer public lpLockDeployer;
    RewardPool public rewardPool;
    MemeSwap public memeSwap;
    address public contractDeployer;
    address public user1;
    address public user2;
    address public user3;

    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on BASE
    address WETH = 0x4200000000000000000000000000000000000006; // WETH on BASE
    address Uniswap_V2_Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2 Router on BASE

    function setUp() public {
        contractDeployer = makeAddr("contractDeployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.deal(contractDeployer, 1 ether);
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        vm.startPrank(contractDeployer);

        feeDistributionContract = new FeeDistribution();
        memeCoin = new MemeCoin();
        lpLockDeployer = new LpLockDeployer();

        memeStorage = new MemeStorage();
        memeEventTracker = new MemeEventTracker(address(memeStorage));

        memePool = new MemePool(
            address(memeCoin),
            address(feeDistributionContract),
            address(lpLockDeployer),
            USDC,
            address(memeEventTracker),
            100
        );

        memeSwap = new MemeSwap(Uniswap_V2_Router, address(memePool));

        memeDeployer = new MemeDeployer(
            address(memePool), address(feeDistributionContract), address(memeStorage), address(memeEventTracker)
        );

        rewardPool = new RewardPool(address(memePool));

        memePool.updateRewardPool(address(rewardPool));
        memePool.updateMemeSwap(address(memeSwap));

        memeDeployer.addRouter(Uniswap_V2_Router);
        memeDeployer.addBaseToken(WETH);
        memeDeployer.updateListThreshold(69420);

        memePool.addDeployer(address(memeDeployer));
        memeStorage.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memePool));

        memeDeployer.updateListThreshold(69420);

        vm.stopPrank();
    }

    function test_swapMemeCoin() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken1, 0, address(0), 0);
        uint256 initialBalance = IERC20(memeToken1).balanceOf(user2);
        IERC20(memeToken1).approve(address(memeSwap), initialBalance);

        uint256 estimatedAmountOut = memeSwap.estimateSwap(memeToken1, memeToken2, initialBalance);
        uint256 minAmountOut = (estimatedAmountOut * 100) / 100;

        memeSwap.swap(memeToken1, memeToken2, initialBalance, minAmountOut, address(0));
        vm.stopPrank();

        assertEq(IERC20(memeToken1).balanceOf(user2), 0);
        assertGt(IERC20(memeToken2).balanceOf(user2), 0);
    }

    function testFail_swapMemeCoin_insufficientBalance() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 balance = IERC20(memeToken1).balanceOf(user2);
        IERC20(memeToken1).approve(address(memeSwap), balance);

        memeSwap.swap(memeToken1, memeToken2, balance + 1 ether, 0, address(0));
        vm.stopPrank();
    }

    function test_swapMemeCoinWithUniswap() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = 0xB928E5905872bda993a4ac054E1D129e658FaDBD; // MEME
        vm.stopPrank();

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.1 ether}(memeToken1, 0, address(0), 0);
        uint256 initialBalance = IERC20(memeToken1).balanceOf(user2);
        IERC20(memeToken1).approve(address(memeSwap), initialBalance);

        uint256 estimatedAmountOut = memeSwap.estimateSwap(memeToken1, memeToken2, initialBalance);
        uint256 minAmountOut = (estimatedAmountOut * 100) / 100;

        memeSwap.swap(memeToken1, memeToken2, initialBalance, minAmountOut, address(0));
        vm.stopPrank();

        assertEq(IERC20(memeToken1).balanceOf(user2), 0);
        assertGt(IERC20(memeToken2).balanceOf(user2), 0);
    }

    function test_swapUniswapWithMemeCoin() public {
        vm.startPrank(user1);
        address memeToken1 = 0xB928E5905872bda993a4ac054E1D129e658FaDBD; // MEME
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        address avp = 0xf4D70D2fd1DE59ff34aA0350263ba742cb94b1c8;

        vm.startPrank(avp);
        uint256 balance = IERC20(memeToken1).balanceOf(avp);
        IERC20(memeToken1).approve(address(memeSwap), balance);

        uint256 estimatedAmountOut = memeSwap.estimateSwap(memeToken1, memeToken2, balance);
        uint256 minAmountOut = estimatedAmountOut;

        memeSwap.swap(memeToken1, memeToken2, balance, minAmountOut, address(0));
        vm.stopPrank();

        assertEq(IERC20(memeToken1).balanceOf(avp), 0);
        assertGt(IERC20(memeToken2).balanceOf(avp), 0);
    }

    function test_swapUniswapToUniswap() public {
        address avp = 0xf4D70D2fd1DE59ff34aA0350263ba742cb94b1c8;
        vm.startPrank(avp);

        address memeToken1 = 0xB928E5905872bda993a4ac054E1D129e658FaDBD; // MEME
        address memeToken2 = 0x4db63aF7618AB7fe46Dc1bd71e897597dF9D1eC9; // PLAY

        uint256 estimatedAmountOut = memeSwap.estimateSwap(memeToken1, memeToken2, 1000 ether);
        uint256 minAmountOut = (estimatedAmountOut * 100) / 100;

        IERC20(memeToken1).approve(address(memeSwap), 1000 ether);
        memeSwap.swap(memeToken1, memeToken2, 1000 ether, minAmountOut, address(0));
        vm.stopPrank();

        assertGt(IERC20(memeToken2).balanceOf(avp), 0);
    }
}
