// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CreationFeeContract is Ownable {
    event FeesWithdrawn(address recipient, uint256 amount);

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");

        emit FeesWithdrawn(owner(), balance);
    }
}
