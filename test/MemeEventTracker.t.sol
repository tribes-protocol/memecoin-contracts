// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeEventTracker.sol";

interface IMemeStorage {
    function getMemeContractIndex(address _memeContract) external view returns (uint256);
}

contract MockMemeStorage is IMemeStorage {
    function getMemeContractIndex(address _memeContract) external pure returns (uint256) {
        // Suppress unused variable warning by using it in a no-op operation
        if (_memeContract == address(0)) {
            return 0;
        }
        return 1;
    }
}

contract MemeEventTrackerTest is Test {
    MemeEventTracker public tracker;
    MockMemeStorage public mockStorage;
    address public owner;
    address public deployer;
    address public user;

    function setUp() public {
        owner = address(this);
        deployer = address(0x1);
        user = address(0x2);

        mockStorage = new MockMemeStorage();
        tracker = new MemeEventTracker(address(mockStorage));

        tracker.addDeployer(deployer);
    }

    function testAddAndRemoveDeployer() public {
        address newDeployer = address(0x3);

        assertFalse(tracker.memeContractDeployer(newDeployer));

        tracker.addDeployer(newDeployer);
        assertTrue(tracker.memeContractDeployer(newDeployer));

        tracker.removeDeployer(newDeployer);
        assertFalse(tracker.memeContractDeployer(newDeployer));
    }

    function testBuyEvent() public {
        address memeContract = address(0x4);
        uint256 buyAmount = 1 ether;
        uint256 tokenReceived = 100;

        vm.prank(deployer);
        tracker.buyEvent(user, memeContract, buyAmount, tokenReceived);

        assertEq(tracker.buyEventCount(), 1);
    }

    function testSellEvent() public {
        address memeContract = address(0x4);
        uint256 sellAmount = 100;
        uint256 nativeReceived = 1 ether;

        vm.prank(deployer);
        tracker.sellEvent(user, memeContract, sellAmount, nativeReceived);

        assertEq(tracker.sellEventCount(), 1);
    }

    function testCreateMemeEvent() public {
        address memeContract = address(0x4);
        address tokenAddress = address(0x5);
        string memory name = "TestMeme";
        string memory symbol = "TM";
        string memory data = "Test data";
        uint256 totalSupply = 1000000;
        uint256 initialReserve = 100000;

        vm.prank(deployer);
        tracker.createMemeEvent(
            user, memeContract, tokenAddress, name, symbol, data, totalSupply, initialReserve, block.timestamp
        );

        assertEq(tracker.memeContractCreatedByDeployer(memeContract), deployer);
        assertEq(tracker.memeContractIndex(memeContract), 1);
    }

    function testListEvent() public {
        address tokenAddress = address(0x5);
        address router = address(0x6);
        uint256 liquidityAmount = 1 ether;
        uint256 tokenAmount = 1000;
        uint256 totalVolume = 10000;

        vm.prank(deployer);
        tracker.listEvent(user, tokenAddress, router, liquidityAmount, tokenAmount, block.timestamp, totalVolume);
    }

    function testUnauthorizedDeployer() public {
        address unauthorizedDeployer = address(0x7);
        address memeContract = address(0x4);

        vm.expectRevert("invalid meme contract");
        vm.prank(unauthorizedDeployer);
        tracker.buyEvent(user, memeContract, 1 ether, 100);

        vm.expectRevert("invalid meme contract");
        vm.prank(unauthorizedDeployer);
        tracker.sellEvent(user, memeContract, 100, 1 ether);

        vm.expectRevert("invalid deployer");
        vm.prank(unauthorizedDeployer);
        tracker.createMemeEvent(
            user, memeContract, address(0x5), "TestMeme", "TM", "Test data", 1000000, 100000, block.timestamp
        );

        vm.expectRevert("invalid deployer");
        vm.prank(unauthorizedDeployer);
        tracker.listEvent(user, address(0x5), address(0x6), 1 ether, 1000, block.timestamp, 10000);
    }

    function testOnlyOwnerFunctions() public {
        address newDeployer = address(0x8);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        tracker.addDeployer(newDeployer);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        tracker.removeDeployer(deployer);
    }
}
