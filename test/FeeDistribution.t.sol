// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FeeDistribution.sol";

contract FeeDistributionTest is Test {
    FeeDistribution public feeContract;
    address owner = address(0x1);
    address nonOwner = address(0x2);

    function setUp() public {
        vm.prank(owner);
        feeContract = new FeeDistribution();
        vm.deal(address(feeContract), 1 ether);
    }

    function testWithdrawFeesAsOwner() public {
        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        feeContract.withdrawFees();

        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether, "Owner should receive the correct amount of fees");
    }

    function testWithdrawFeesAsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        feeContract.withdrawFees();
    }

    function testWithdrawFeesWhenNoFees() public {
        FeeDistribution emptyFeeContract = new FeeDistribution();
        vm.expectRevert(bytes("No fees to withdraw"));
        emptyFeeContract.withdrawFees();
    }

    function testReceive() public {
        payable(address(feeContract)).transfer(1 ether);
        assertEq(address(feeContract).balance, 2 ether, "Contract should receive Ether");
    }
}
