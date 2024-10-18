// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {LpLockDeployer} from "../src/LpLockDeployer.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

contract LpLockDeployerTest is Test {
    LpLockDeployer public lpLockDeployer;
    MockERC20 public mockToken;
    address public owner;
    address public memeOwner;

    function setUp() public {
        lpLockDeployer = new LpLockDeployer();
        mockToken = new MockERC20("Mock Token", "MOCK");

        owner = address(this);
        memeOwner = address(0x1);
    }

    function testCreateLPLocker() public {
        uint256 lockingAmount = 1000;
        uint256 unlockTime = block.timestamp + 1 days;

        mockToken.mint(owner, lockingAmount);

        mockToken.approve(address(lpLockDeployer), lockingAmount);

        address locker = lpLockDeployer.createLPLocker(address(mockToken), unlockTime, "logo", lockingAmount, memeOwner);

        // Check if the lock info is correctly stored
        LpLockDeployer.LockInfo memory lockInfo = lpLockDeployer.getLockInfo(locker);
        assertEq(lockInfo.lockingToken, address(mockToken));
        assertEq(lockInfo.lockerEndTimeStamp, unlockTime);
        assertEq(lockInfo.logo, "logo");
        assertEq(lockInfo.lockingAmount, lockingAmount);
        assertEq(lockInfo.memeOwner, memeOwner);
        assertEq(lockInfo.isUnlocked, false);

        // Check if the locker is added to allLocks
        address[] memory allLocks = lpLockDeployer.getAllLocks();
        assertEq(allLocks.length, 1);
        assertEq(allLocks[0], locker);

        // Check if the LockCreated event is emitted
        assertEq(mockToken.balanceOf(address(lpLockDeployer)), lockingAmount);
    }

    function testUnlock() public {
        uint256 lockingAmount = 1000;
        uint256 unlockTime = block.timestamp + 1 days;

        mockToken.mint(owner, lockingAmount);

        mockToken.approve(address(lpLockDeployer), lockingAmount);

        address locker = lpLockDeployer.createLPLocker(address(mockToken), unlockTime, "logo", lockingAmount, memeOwner);

        vm.prank(memeOwner);
        vm.expectRevert("Lock period not ended");
        lpLockDeployer.unlock(locker);

        vm.warp(unlockTime);

        vm.prank(memeOwner);
        lpLockDeployer.unlock(locker);

        LpLockDeployer.LockInfo memory lockInfo = lpLockDeployer.getLockInfo(locker);
        assertEq(lockInfo.isUnlocked, true);

        assertEq(mockToken.balanceOf(memeOwner), lockingAmount);
    }

    function testGetLockInfo() public {
        uint256 lockingAmount = 1000;
        uint256 unlockTime = block.timestamp + 1 days;
        string memory logo = "test_logo";

        mockToken.mint(owner, lockingAmount);

        mockToken.approve(address(lpLockDeployer), lockingAmount);

        address locker = lpLockDeployer.createLPLocker(address(mockToken), unlockTime, logo, lockingAmount, memeOwner);

        LpLockDeployer.LockInfo memory lockInfo = lpLockDeployer.getLockInfo(locker);

        assertEq(lockInfo.lockingToken, address(mockToken));
        assertEq(lockInfo.lockingAmount, lockingAmount);
        assertEq(lockInfo.lockerEndTimeStamp, unlockTime);
        assertEq(lockInfo.memeOwner, memeOwner);
        assertEq(lockInfo.logo, logo);
        assertEq(lockInfo.isUnlocked, false);
    }
}
