// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IERC20.sol";

contract FeeDistribution is Ownable {
    event ERC20Withdrawn(address recipient, address tokenAddress, uint256 amount);
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

    function withdrawERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        bool success = token.transfer(owner(), amount);
        require(success, "ERC20 transfer failed");

        emit ERC20Withdrawn(owner(), tokenAddress, amount);
    }
}
