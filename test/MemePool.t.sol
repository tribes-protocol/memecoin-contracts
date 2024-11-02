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

contract MemePoolTest is Test {
    MemeDeployer public memeDeployer;
    MemePool public memePool;
    MemeStorage public memeStorage;
    MemeEventTracker public memeEventTracker;
    MemeCoin public memeCoin;
    FeeDistribution public feeDistributionContract;
    LpLockDeployer public lpLockDeployer;
    RewardPool public rewardPool;

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
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);
        vm.deal(user3, 5 ether);

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

        memeDeployer = new MemeDeployer(
            address(memePool), address(feeDistributionContract), address(memeStorage), address(memeEventTracker)
        );

        MemeSwap memeSwap_ = new MemeSwap(Uniswap_V2_Router, address(memePool));

        rewardPool = new RewardPool(address(memePool));

        memePool.updateRewardPool(address(rewardPool));
        memePool.updateMemeSwap(address(memeSwap_));

        memeDeployer.addRouter(Uniswap_V2_Router);
        memeDeployer.addBaseToken(WETH);
        memeDeployer.updateListThreshold(12000);

        memePool.addDeployer(address(memeDeployer));
        memeStorage.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memePool));

        vm.stopPrank();
    }

    function test_createMeme() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        assertEq(IERC20(memeToken).name(), "MEME");
        assertEq(IERC20(memeToken).symbol(), "MEME");
        assertEq(IERC20(memeToken).totalSupply(), 1_000_000_000 ether);

        MemePool.MemeTokenPool memory pool = memePool.getMemeTokenPool(memeToken);
        assertEq(pool.creator, user1);
        assertEq(pool.baseToken, WETH);
        assertEq(pool.router, Uniswap_V2_Router);
        assertTrue(pool.pool.tradeActive);
    }

    function test_buyTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        uint256 initialBalance = IERC20(memeToken).balanceOf(user2);

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 0);
        vm.stopPrank();

        uint256 finalBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(finalBalance, initialBalance);
    }

    function test_sellTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 0);

        uint256 initialBalance = IERC20(memeToken).balanceOf(user2);
        uint256 initialEthBalance = user2.balance;

        IERC20(memeToken).approve(address(memePool), initialBalance);
        memePool.sellTokens(memeToken, initialBalance, 0, address(feeDistributionContract));
        vm.stopPrank();

        assertEq(IERC20(memeToken).balanceOf(user2), 0);
        assertGt(user2.balance, initialEthBalance);
    }

    function test_buyManyTokens() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = memeToken1;
        tokens[1] = memeToken2;

        uint256[] memory minTokens = new uint256[](2);
        minTokens[0] = 0;
        minTokens[1] = 0;

        uint256[] memory ethAmounts = new uint256[](2);
        ethAmounts[0] = 0.0005 ether;
        ethAmounts[1] = 0.0005 ether;

        vm.startPrank(user2);
        memePool.buyManyTokens{value: 0.001 ether}(tokens, minTokens, ethAmounts, address(feeDistributionContract), 0);
        vm.stopPrank();

        assertGt(IERC20(memeToken1).balanceOf(user2), 0);
        assertGt(IERC20(memeToken2).balanceOf(user2), 0);
    }

    function test_getAmountOutTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        uint256 amountOut = memePool.getAmountOutTokens(memeToken, 0.001 ether);
        assertGt(amountOut, 0);
    }

    function test_getAmountOutETH() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        uint256 amountOut = memePool.getAmountOutETH(memeToken, 1000 ether);
        assertGt(amountOut, 0);
    }

    function test_getCurrentCap() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        uint256 currentCap = memePool.getCurrentCap(memeToken);
        assertGt(currentCap, 0);
    }

    function testFail_changeNativePerUnauthorized() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, USDC, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.prank(user2);
        memePool.changeNativePer(memeToken, 75);
    }

    function testFail_changeNativePerInvalidPer() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, USDC, Uniswap_V2_Router, false, 0, 0
        );
        memePool.changeNativePer(memeToken, 101);
        vm.stopPrank();
    }

    function test_RewardPool_buyMemecoinRewards() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 initialMemePoolBalance = IERC20(memeToken).balanceOf(address(memePool));
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(0), 0);
        uint256 afterUser2BuyMemePoolBalance = IERC20(memeToken).balanceOf(address(memePool));
        assertLt(
            afterUser2BuyMemePoolBalance, initialMemePoolBalance, "MemePool balance should decrease after user2 buy"
        );
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 initialRewardPoolBalance = IERC20(memeToken).balanceOf(address(rewardPool));
        uint256 initialMemePoolBalanceBeforeRewardBuy = IERC20(memeToken).balanceOf(address(memePool));

        rewardPool.buyMemecoinRewards{value: 0.001 ether}(memeToken, user1);

        uint256 finalRewardPoolBalance = IERC20(memeToken).balanceOf(address(rewardPool));
        uint256 finalMemePoolBalance = IERC20(memeToken).balanceOf(address(memePool));

        assertGt(finalRewardPoolBalance, initialRewardPoolBalance, "RewardPool balance should increase");
        assertLt(finalMemePoolBalance, initialMemePoolBalanceBeforeRewardBuy, "MemePool balance should decrease");

        uint256 rewardPoolBalance = IERC20(memeToken).balanceOf(address(rewardPool));
        assertEq(
            rewardPoolBalance,
            finalRewardPoolBalance - initialRewardPoolBalance,
            "RewardPool balance should match the difference"
        );

        vm.stopPrank();
    }

    function test_RewardPool_rewardRecipients() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );

        rewardPool.buyMemecoinRewards{value: 0.001 ether}(memeToken, user1);

        address[] memory recipients = new address[](2);
        recipients[0] = user2;
        recipients[1] = user3;
        address[] memory memecoinAddresses = new address[](2);
        memecoinAddresses[0] = memeToken;
        memecoinAddresses[1] = memeToken;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;

        uint256 initialBalanceUser2 = IERC20(memeToken).balanceOf(user2);
        uint256 initialBalanceUser3 = IERC20(memeToken).balanceOf(user3);

        vm.stopPrank();

        vm.startPrank(contractDeployer);
        rewardPool.rewardRecipients(recipients, memecoinAddresses, amounts);

        uint256 finalBalanceUser2 = IERC20(memeToken).balanceOf(user2);
        assertEq(finalBalanceUser2, initialBalanceUser2 + amounts[0]);

        uint256 finalBalanceUser3 = IERC20(memeToken).balanceOf(user3);
        assertEq(finalBalanceUser3, initialBalanceUser3 + amounts[1]);

        vm.stopPrank();
    }

    function testFail_RewardPool_rewardRecipientsUnauthorized() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );

        rewardPool.buyMemecoinRewards{value: 0.001 ether}(memeToken, user1);

        uint256 rewardAmount = 1000 ether;
        address[] memory recipients = new address[](1);
        recipients[0] = user2;
        address[] memory memecoinAddresses = new address[](1);
        memecoinAddresses[0] = memeToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;

        rewardPool.rewardRecipients(recipients, memecoinAddresses, amounts);

        vm.stopPrank();
    }

    function test_RewardPool_withdrawEth() public {
        vm.deal(address(rewardPool), 1 ether);

        uint256 initialBalance = contractDeployer.balance;

        vm.prank(contractDeployer);
        rewardPool.withdrawEth();

        uint256 finalBalance = contractDeployer.balance;
        assertEq(finalBalance, initialBalance + 1 ether);
        assertEq(address(rewardPool).balance, 0);
    }

    function testFail_RewardPool_withdrawEthUnauthorized() public {
        vm.deal(address(rewardPool), 1 ether);

        vm.prank(user1); // Unauthorized user
        rewardPool.withdrawEth();
    }

    function test_RewardPool_setMemePool() public {
        address newMemePool = address(0x123);

        vm.prank(contractDeployer);
        rewardPool.setMemePool(newMemePool);

        assertEq(rewardPool.memePool(), newMemePool);
    }

    function testFail_RewardPool_setMemePoolUnauthorized() public {
        address newMemePool = address(0x123);

        vm.prank(user1); // Unauthorized user
        rewardPool.setMemePool(newMemePool);
    }

    function testFail_DifferentRewardPool() public {
        address newRewardPool = address(0x123);

        vm.prank(contractDeployer);
        memePool.updateRewardPool(newRewardPool);
        vm.stopPrank();

        vm.startPrank(user1);

        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );

        rewardPool.buyMemecoinRewards{value: 0.001 ether}(memeToken, user1);

        address[] memory recipients = new address[](2);
        recipients[0] = user2;
        recipients[1] = user3;
        address[] memory memecoinAddresses = new address[](2);
        memecoinAddresses[0] = memeToken;
        memecoinAddresses[1] = memeToken;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;

        uint256 initialBalanceUser2 = IERC20(memeToken).balanceOf(user2);
        uint256 initialBalanceUser3 = IERC20(memeToken).balanceOf(user3);

        vm.stopPrank();

        vm.startPrank(contractDeployer);
        rewardPool.rewardRecipients(recipients, memecoinAddresses, amounts);

        uint256 finalBalanceUser2 = IERC20(memeToken).balanceOf(user2);
        assertEq(finalBalanceUser2, initialBalanceUser2 + amounts[0]);

        uint256 finalBalanceUser3 = IERC20(memeToken).balanceOf(user3);
        assertEq(finalBalanceUser3, initialBalanceUser3 + amounts[1]);

        vm.stopPrank();
    }

    function test_DexInitation() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        memePool.buyTokens{value: 4 ether}(memeToken, 0, address(feeDistributionContract), 0);
        vm.stopPrank();

        bool isDexInitialized = IMemeCoin(memeToken).dexInitiated();
        assertTrue(isDexInitialized);
    }

    function test_AntiSnipe() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, true, 0.01 ether, 0
        );
        vm.stopPrank();

        assertGt(IERC20(memeToken).balanceOf(user1), 0);
    }

    function test_LockTokensDexInitiated() public {
        vm.startPrank(user1);
        uint256 lockDeadline = 365;
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            lockDeadline
        );
        assertGt(IERC20(memeToken).balanceOf(user1), 0);
        assertEq(IMemeCoin(memeToken).lockedDeadlineOf(user1), block.timestamp + lockDeadline * 1 days);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 initialBalance = IERC20(memeToken).balanceOf(user1);
        IERC20(memeToken).approve(address(memePool), initialBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalance, 0, address(feeDistributionContract));
        vm.stopPrank();

        bool dexInitiated = IMemeCoin(memeToken).dexInitiated();
        assertFalse(dexInitiated);

        vm.startPrank(user2);
        memePool.buyTokens{value: 4 ether}(memeToken, 0, address(feeDistributionContract), 0);
        vm.stopPrank();

        bool isDexInitialized = IMemeCoin(memeToken).dexInitiated();
        assertTrue(isDexInitialized);

        vm.startPrank(user1);
        IERC20(memeToken).transfer(user3, 1 ether);
        vm.stopPrank();
    }

    function test_LockTokensTimeLock() public {
        vm.startPrank(user1);
        uint256 lockDeadline = 7;

        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            lockDeadline
        );
        assertEq(IMemeCoin(memeToken).lockedDeadlineOf(user1), block.timestamp + lockDeadline * 1 days);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 initialBalance = IERC20(memeToken).balanceOf(user1);

        IERC20(memeToken).approve(address(memePool), initialBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalance, 0, address(feeDistributionContract));

        skip(7 days + 1);

        memePool.sellTokens(memeToken, initialBalance - 1, 0, address(feeDistributionContract));
        vm.stopPrank();

        bool dexInitiated = IMemeCoin(memeToken).dexInitiated();
        assertFalse(dexInitiated);

        vm.startPrank(user2);
        memePool.buyTokens{value: 4 ether}(memeToken, 0, address(feeDistributionContract), 0);
        vm.stopPrank();

        bool isDexInitialized = IMemeCoin(memeToken).dexInitiated();
        assertTrue(isDexInitialized);

        vm.startPrank(user1);
        IERC20(memeToken).transfer(user3, 1);
        vm.stopPrank();
    }

    function test_MultipleLockTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, true, 0.01 ether, 0
        );
        assertEq(IMemeCoin(memeToken).lockedDeadlineOf(user1), 0);

        skip(1 days);

        uint256 initialBalance = IERC20(memeToken).balanceOf(user1);
        IERC20(memeToken).approve(address(memePool), initialBalance);
        memePool.sellTokens(memeToken, initialBalance, 0, address(feeDistributionContract));
        vm.stopPrank();

        uint256 lockDeadline1 = 7;
        uint256 lockDeadline2 = 30;

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.01 ether}(memeToken, 0, address(feeDistributionContract), lockDeadline1);

        skip(1 days);

        uint256 initialBalanceUser2 = IERC20(memeToken).balanceOf(user2);
        IERC20(memeToken).approve(address(memePool), initialBalanceUser2);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalanceUser2, 0, address(feeDistributionContract));

        skip(1 days);

        memePool.buyTokens{value: 0.01 ether}(memeToken, 0, address(feeDistributionContract), lockDeadline2);

        skip(1 days);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalanceUser2, 0, address(feeDistributionContract));

        skip(20 days);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalanceUser2, 0, address(feeDistributionContract));

        skip(10 days);
        memePool.sellTokens(memeToken, initialBalanceUser2 - 1, 0, address(feeDistributionContract));

        vm.startPrank(user2);
        uint256 lockDeadline3 = 60;
        memePool.buyTokens{value: 4 ether}(memeToken, 0, address(feeDistributionContract), lockDeadline3);
        vm.stopPrank();

        bool isDexInitialized = IMemeCoin(memeToken).dexInitiated();
        assertTrue(isDexInitialized);

        vm.startPrank(user2);
        IERC20(memeToken).transfer(user3, 1);
        vm.stopPrank();
    }

    function testFail_DifferentLockDeadline() public {
        vm.startPrank(user1);
        uint256 lockDeadline1 = 30;
        uint256 lockDeadline2 = 7;

        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            lockDeadline1
        );

        skip(1 days);

        uint256 initialBalance = IERC20(memeToken).balanceOf(user1);
        IERC20(memeToken).approve(address(memePool), initialBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, initialBalance, 0, address(feeDistributionContract));

        skip(1 days);

        memePool.buyTokens{value: 0.01 ether}(memeToken, 0, address(feeDistributionContract), lockDeadline2);
    }

    function testFail_LockedMoreThan365Days() public {
        vm.startPrank(user1);
        memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, true, 0.01 ether, 366
        );
        vm.stopPrank();
    }

    function test_LockTokensWithTimeProgression() public {
        // Create meme token
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            0 // No initial lock
        );
        vm.stopPrank();

        // User2 buys tokens with 1 day lock
        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 1); // 1 day lock

        uint256 tokenBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(tokenBalance, 0, "User should have tokens after buying");

        // Try to sell immediately - should fail
        IERC20(memeToken).approve(address(memePool), tokenBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        // Fast forward 2 days
        skip(2 days);

        // Try to sell after lock period - should succeed
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        assertEq(IERC20(memeToken).balanceOf(user2), 0, "User should have no tokens after selling");
        vm.stopPrank();
    }

    function test_LockTokensWithExtension() public {
        console.log("Creating meme token...");
        // Create meme token
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            0 // No initial lock
        );
        vm.stopPrank();

        console.log("User2 buying tokens with 1 day lock...");
        // User2 buys tokens with 1 day lock
        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 1); // 1 day lock
        uint256 firstLockDeadline = IMemeCoin(memeToken).lockedDeadlineOf(user2);
        console.log("First lock deadline: %s", firstLockDeadline);

        // Extend lock to 3 days
        console.log("Extending lock to 3 days...");
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 3);
        uint256 secondLockDeadline = IMemeCoin(memeToken).lockedDeadlineOf(user2);
        assertGt(secondLockDeadline, firstLockDeadline, "Lock deadline should be extended");

        console.log("Fast forwarding 2 days...");
        // Fast forward 2 days
        skip(2 days);

        // Try to sell after 2 days - should fail because we extended to 3 days
        uint256 tokenBalance = IERC20(memeToken).balanceOf(user2);
        console.log("Attempting to sell after 2 days (should fail)... %s", tokenBalance);
        assertGt(tokenBalance, 0, "User should have tokens after buying");
        IERC20(memeToken).approve(address(memePool), tokenBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        console.log("Extending lock by 2 more days...");
        // Extend lock by 2 more days (total 5 days from start)
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 5);
        uint256 thirdLockDeadline = IMemeCoin(memeToken).lockedDeadlineOf(user2);
        assertGt(thirdLockDeadline, secondLockDeadline, "Lock deadline should be extended again");

        console.log("Fast forwarding 6 more days...");
        // Fast forward 6 more days (total 6 days elapsed)
        skip(6 days);

        // Try to sell after total lock period - should succeed
        tokenBalance = IERC20(memeToken).balanceOf(user2);
        console.log("Attempting final sell after lock period... %s", tokenBalance);
        IERC20(memeToken).approve(address(memePool), tokenBalance);
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        assertEq(IERC20(memeToken).balanceOf(user2), 0, "User should have no tokens after selling");
        vm.stopPrank();
        console.log("Test completed successfully");
    }

    function test_LockDurationValidation() public {
        // Create meme token
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            0 // No initial lock
        );
        vm.stopPrank();

        console.log("User2 buying tokens with 7 day lock...");
        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 7);
        uint256 initialBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(initialBalance, 0, "User should have tokens after buying");

        console.log("Fast forwarding 5 days...");
        skip(5 days);

        console.log("Attempting to buy with 6 day lock (should fail)...");
        vm.expectRevert("New duration must be greater than current duration");
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 6);

        console.log("Fast forwarding 3 more days...");
        skip(3 days);

        console.log("Buying with 2 day lock...");
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 2);

        console.log("Fast forwarding 1 day...");
        skip(1 days);

        console.log("Attempting to sell tokens (should fail)...");
        uint256 tokenBalance = IERC20(memeToken).balanceOf(user2);
        IERC20(memeToken).approve(address(memePool), tokenBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        console.log("Fast forwarding 2 more days...");
        skip(2 days);

        console.log("Attempting final sell...");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        assertEq(IERC20(memeToken).balanceOf(user2), 0, "User should have no tokens after selling");
        vm.stopPrank();
        console.log("Test completed successfully");
    }

    function test_DirectLockTokens() public {
        // Create meme token
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            0 // No initial lock
        );
        vm.stopPrank();

        // User2 buys tokens without lock
        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract), 0);

        uint256 tokenBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(tokenBalance, 0, "User should have tokens after buying");

        // User2 directly locks their tokens for 1 day
        vm.expectEmit(true, true, false, true);
        emit IMemeEventTracker.LockedDeadlineUpdated(user2, memeToken, 1);
        memePool.lockTokens(user2, memeToken, 1);

        // try to lock a different user's tokens
        vm.expectRevert("unauthorized account");
        memePool.lockTokens(user3, memeToken, 1);

        // Try to sell immediately - should fail
        IERC20(memeToken).approve(address(memePool), tokenBalance);
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        // Fast forward 2 days
        skip(2 days);

        // User extends their lock to 3 days
        memePool.lockTokens(user2, memeToken, 3);

        // Try to sell after 2 days - should fail because we extended to 3 days
        vm.expectRevert("Balance is locked");
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        // Fast forward 2 more days (total 4 days elapsed)
        skip(4 days);

        // Try to sell after lock period - should succeed
        memePool.sellTokens(memeToken, tokenBalance, 0, address(feeDistributionContract));

        assertEq(IERC20(memeToken).balanceOf(user2), 0, "User should have no tokens after selling");
        vm.stopPrank();
    }

    function test_transferUnlockedTokens() public {
        // Create meme token
        vm.startPrank(user3);
        address memeToken = memeDeployer.CreateMeme{value: 0.0102 ether}(
            "MEME",
            "MEME",
            "MEME",
            1_000_000_000 ether,
            0.0001 ether,
            WETH,
            Uniswap_V2_Router,
            true,
            0.01 ether,
            0 // No initial lock
        );
        vm.stopPrank();

        // Initialize DEX by adding sufficient liquidity
        vm.startPrank(user2);
        memePool.buyTokens{value: 4 ether}(memeToken, 0, address(feeDistributionContract), 0);
        vm.stopPrank();

        // Verify DEX is initialized
        bool isDexInitialized = IMemeCoin(memeToken).dexInitiated();
        assertTrue(isDexInitialized, "DEX should be initialized");

        // User3 buys tokens without lock
        vm.startPrank(user2);
        uint256 tokenBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(tokenBalance, 0, "User should have tokens after buying");

        // Transfer half the tokens to user1
        uint256 transferAmount = tokenBalance / 2;
        IERC20(memeToken).transfer(user1, transferAmount);
        console.log("Token balance of user2: %s", tokenBalance);
        console.log("Transferred %s tokens to user1", transferAmount);
        console.log("User2 balance: %s", IERC20(memeToken).balanceOf(user2));
        console.log("User1 balance: %s", IERC20(memeToken).balanceOf(user1));

        // Verify balances
        assertEq(IERC20(memeToken).balanceOf(user2), transferAmount, "User2 should have half their tokens");
        assertEq(
            IERC20(memeToken).balanceOf(user1),
            tokenBalance - transferAmount,
            "User1 should have received half the tokens"
        );
        vm.stopPrank();
    }

    function test_buyManyTokensInvalidTotal() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = memeToken1;
        tokens[1] = memeToken2;

        uint256[] memory minTokens = new uint256[](2);
        minTokens[0] = 0;
        minTokens[1] = 0;

        uint256[] memory ethAmounts = new uint256[](2);
        ethAmounts[0] = 0.6 ether; // Sum of ethAmounts (1.1 ether)
        ethAmounts[1] = 0.5 ether; // is greater than msg.value (1 ether)

        vm.startPrank(user2);
        vm.expectRevert("Invalid total buy value");
        memePool.buyManyTokens{value: 1 ether}(tokens, minTokens, ethAmounts, address(feeDistributionContract), 0);
        vm.stopPrank();
    }

    function test_buyManyTokensExcessValue() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = memeToken1;
        tokens[1] = memeToken2;

        uint256[] memory minTokens = new uint256[](2);
        minTokens[0] = 0;
        minTokens[1] = 0;

        uint256[] memory ethAmounts = new uint256[](2);
        ethAmounts[0] = 0.4 ether; // Sum of ethAmounts (0.9 ether)
        ethAmounts[1] = 0.5 ether; // is less than msg.value (1 ether)

        vm.startPrank(user2);
        vm.expectRevert("Invalid total buy value");
        memePool.buyManyTokens{value: 1 ether}(tokens, minTokens, ethAmounts, address(feeDistributionContract), 0);
        vm.stopPrank();
    }

    function test_buyManyTokensValidTotal() public {
        vm.startPrank(user1);
        address memeToken1 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0, 0
        );
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = memeToken1;
        tokens[1] = memeToken2;

        uint256[] memory minTokens = new uint256[](2);
        minTokens[0] = 0;
        minTokens[1] = 0;

        uint256[] memory ethAmounts = new uint256[](2);
        ethAmounts[0] = 0.6 ether; // Sum of ethAmounts (1 ether)
        ethAmounts[1] = 0.4 ether; // exactly matches msg.value (1 ether)

        uint256 initialBalance = user2.balance;

        vm.startPrank(user2);
        memePool.buyManyTokens{value: 1 ether}(tokens, minTokens, ethAmounts, address(feeDistributionContract), 0);
        vm.stopPrank();

        // Verify the transaction succeeded by checking token balances
        assertGt(IERC20(memeToken1).balanceOf(user2), 0, "Should have received memeToken1");
        assertGt(IERC20(memeToken2).balanceOf(user2), 0, "Should have received memeToken2");
        assertEq(user2.balance, initialBalance - 1 ether, "Should have spent exactly 1 ether");
    }
}
