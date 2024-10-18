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

contract MemePoolTest is Test {
    MemeDeployer public memeDeployer;
    MemePool public memePool;
    MemeStorage public memeStorage;
    MemeEventTracker public memeEventTracker;
    MemeCoin public memeCoin;
    CreationFeeContract public feeDistributionContract;
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
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        vm.startPrank(contractDeployer);

        feeDistributionContract = new CreationFeeContract();
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

        rewardPool = new RewardPool(address(memePool));

        memePool.updateRewardPool(address(rewardPool));

        memeDeployer.addRouter(Uniswap_V2_Router);
        memeDeployer.addBaseToken(WETH);

        memePool.addDeployer(address(memeDeployer));
        memeStorage.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memeDeployer));
        memeEventTracker.addDeployer(address(memePool));

        memeDeployer.updateListThreshold(69420);

        vm.stopPrank();
    }

    function test_createMeme() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
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
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        uint256 initialBalance = IERC20(memeToken).balanceOf(user2);

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract));
        vm.stopPrank();

        uint256 finalBalance = IERC20(memeToken).balanceOf(user2);
        assertGt(finalBalance, initialBalance);
    }

    function test_sellTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(feeDistributionContract));

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
            "MEME1", "MEME1", "MEME1", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        address memeToken2 = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME2", "MEME2", "MEME2", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
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
        memePool.buyManyTokens{value: 0.001 ether}(tokens, minTokens, ethAmounts, address(feeDistributionContract));
        vm.stopPrank();

        assertGt(IERC20(memeToken1).balanceOf(user2), 0);
        assertGt(IERC20(memeToken2).balanceOf(user2), 0);
    }

    function test_getAmountOutTokens() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        uint256 amountOut = memePool.getAmountOutTokens(memeToken, 0.001 ether);
        assertGt(amountOut, 0);
    }

    function test_getAmountOutETH() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        uint256 amountOut = memePool.getAmountOutETH(memeToken, 1000 ether);
        assertGt(amountOut, 0);
    }

    function test_getCurrentCap() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        uint256 currentCap = memePool.getCurrentCap(memeToken);
        assertGt(currentCap, 0);
    }

    function testFail_changeNativePerUnauthorized() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, USDC, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        vm.prank(user2);
        memePool.changeNativePer(memeToken, 75);
    }

    function testFail_changeNativePerInvalidPer() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, USDC, Uniswap_V2_Router, false, 0
        );
        memePool.changeNativePer(memeToken, 101);
        vm.stopPrank();
    }

    function test_RewardPool_buyMemecoinRewards() public {
        vm.startPrank(user1);
        address memeToken = memeDeployer.CreateMeme{value: 0.0002 ether}(
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
        );
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 initialMemePoolBalance = IERC20(memeToken).balanceOf(address(memePool));
        memePool.buyTokens{value: 0.001 ether}(memeToken, 0, address(0));
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
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
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
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
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
            "MEME", "MEME", "MEME", 1_000_000_000 ether, 0.0001 ether, WETH, Uniswap_V2_Router, false, 0
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
}
