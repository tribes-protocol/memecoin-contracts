// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeStorage.sol";

contract MemeStorageTest is Test {
    MemeStorage memeStorage;
    address owner = address(1);
    address deployer = address(2);
    address memeOwner = address(3);
    address memeAddress = address(4);
    address tokenAddress = address(5);
    address routerAddress = address(6);

    function setUp() public {
        vm.prank(owner);
        memeStorage = new MemeStorage();
        vm.prank(owner);
        memeStorage.addDeployer(deployer);
    }

    function testAddMemeContract() public {
        vm.prank(deployer);
        memeStorage.addMemeContract(
            memeOwner, memeAddress, tokenAddress, routerAddress, "TestMeme", "TM", "Some data", 1000, 500
        );
        assertEq(memeStorage.getTotalContracts(), 1);
    }

    function testAddMemeContractUnauthorized() public {
        vm.prank(address(7)); // Non-deployer
        vm.expectRevert("not deployer");
        memeStorage.addMemeContract(
            memeOwner, memeAddress, tokenAddress, routerAddress, "TestMeme", "TM", "Some data", 1000, 500
        );
    }

    function testUpdateData() public {
        vm.prank(deployer);
        memeStorage.addMemeContract(
            memeOwner, memeAddress, tokenAddress, routerAddress, "TestMeme", "TM", "Initial data", 1000, 500
        );
        vm.prank(deployer);
        memeStorage.updateData(memeOwner, 0, "Updated data");
        MemeStorage.MemeDetails memory meme = memeStorage.getMemeContract(0);

        assertEq(meme.memeAddress, memeAddress);
        assertEq(meme.tokenAddress, tokenAddress);
        assertEq(meme.memeOwner, memeOwner);
        assertEq(meme.router, routerAddress);
        assertEq(meme.name, "TestMeme");
        assertEq(meme.symbol, "TM");
        assertEq(meme.data, "Updated data");
        assertEq(meme.totalSupply, 1000);
        assertEq(meme.initialLiquidity, 500);
    }

    function testUpdateDataInvalidIndex() public {
        vm.prank(deployer);
        memeStorage.addMemeContract(
            memeOwner, memeAddress, tokenAddress, routerAddress, "TestMeme", "TM", "Initial data", 1000, 500
        );
        vm.prank(deployer);
        vm.expectRevert("invalid owner meme count");
        memeStorage.updateData(memeOwner, 1, "Updated data");
    }

    function testEmergencyWithdraw() public {
        vm.deal(address(memeStorage), 10 ether);

        uint256 initialContractBalance = address(memeStorage).balance;
        uint256 initialOwnerBalance = owner.balance;

        vm.prank(owner);
        memeStorage.emergencyWithdraw();

        uint256 finalContractBalance = address(memeStorage).balance;
        uint256 finalOwnerBalance = owner.balance;

        assertEq(finalContractBalance, 0, "Contract balance should be 0 after withdrawal");
        assertEq(
            finalOwnerBalance, initialOwnerBalance + initialContractBalance, "Owner should receive the contract balance"
        );
    }

    function testAddAndRemoveDeployer() public {
        vm.prank(owner);
        memeStorage.addDeployer(address(8));
        assertTrue(memeStorage.deployer(address(8)));

        vm.prank(owner);
        memeStorage.removeDeployer(address(8));
        assertFalse(memeStorage.deployer(address(8)));
    }
}
