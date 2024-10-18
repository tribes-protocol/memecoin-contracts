// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeCoin.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

contract MemeCoinTest is Test {
    MemeCoin public memeCoin;
    address public deployer;
    address public midDeployer;
    address public rewardPool;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18; // 1 million tokens

    function setUp() public {
        deployer = address(this);
        midDeployer = address(0x1);
        rewardPool = address(0x2);
        user1 = address(0x3);
        user2 = address(0x4);

        memeCoin = new MemeCoin();
        memeCoin.initialize(INITIAL_SUPPLY, "MemeCoin", "MEME", midDeployer, deployer, rewardPool);
    }

    function testInitialization() public view {
        assertEq(memeCoin.name(), "MemeCoin");
        assertEq(memeCoin.symbol(), "MEME");
        assertEq(memeCoin.decimals(), 18);
        assertEq(memeCoin.totalSupply(), INITIAL_SUPPLY);
        assertEq(memeCoin.balanceOf(midDeployer), INITIAL_SUPPLY);
        assertTrue(memeCoin.isInitialized());
    }

    function testTransferBeforeDexInitiation() public {
        vm.prank(midDeployer);
        assertTrue(memeCoin.transfer(user1, 1000));
        assertEq(memeCoin.balanceOf(user1), 1000);

        vm.prank(user1);
        vm.expectRevert("not dex listed");
        memeCoin.transfer(user2, 500);
    }

    function testDexInitiation() public {
        vm.prank(midDeployer);
        memeCoin.initiateDex();
        assertTrue(memeCoin.dexInitiated());
    }

    function testApproveAndTransferAfterDexInitiation() public {
        vm.prank(midDeployer);
        memeCoin.initiateDex();
        vm.prank(midDeployer);
        memeCoin.approve(user1, 1000);
        assertEq(memeCoin.allowance(midDeployer, user1), 1000);

        vm.prank(user1);
        memeCoin.transferFrom(midDeployer, user2, 500);
        assertEq(memeCoin.balanceOf(user2), 500);
        assertEq(memeCoin.allowance(midDeployer, user1), 500);
    }

    function testBurn() public {
        uint256 initialSupply = memeCoin.totalSupply();
        vm.prank(midDeployer);
        memeCoin.Burn(1000);
        assertEq(memeCoin.totalSupply(), initialSupply - 1000);
        assertEq(memeCoin.balanceOf(midDeployer), initialSupply - 1000);
    }

    function testIncreaseAndDecreaseAllowance() public {
        vm.prank(midDeployer);
        memeCoin.approve(user1, 1000);
        assertEq(memeCoin.allowance(midDeployer, user1), 1000);

        vm.prank(midDeployer);
        memeCoin.increaseAllowance(user1, 500);
        assertEq(memeCoin.allowance(midDeployer, user1), 1500);

        vm.prank(midDeployer);
        memeCoin.decreaseAllowance(user1, 200);
        assertEq(memeCoin.allowance(midDeployer, user1), 1300);
    }

    function testFailReinitialize() public {
        memeCoin.initialize(INITIAL_SUPPLY, "NewMemeCoin", "NMEME", midDeployer, deployer, rewardPool);
    }

    function testDelegateVotes() public {
        vm.prank(midDeployer);
        memeCoin.transfer(user1, 1000);
        vm.prank(user1);
        memeCoin.delegate(user2);
        assertEq(memeCoin.getVotes(user1), 0);
        assertEq(memeCoin.getVotes(user2), 1000);
    }

    function testCheckpoints() public {
        vm.prank(midDeployer);
        memeCoin.transfer(user1, 1000);
        vm.prank(user1);
        memeCoin.delegate(user1);

        assertEq(memeCoin.numCheckpoints(user1), 1);
        Checkpoints.Checkpoint208 memory checkpoint = memeCoin.checkpoints(user1, 0);
        assertEq(checkpoint._key, block.number);
        assertEq(checkpoint._value, 1000);
    }
}
