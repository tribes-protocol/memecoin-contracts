// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMemePool} from "./Interfaces/IMemePool.sol";

contract RewardPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public memePool;

    event MemeTokensPurchased(address indexed memeCoinAddress, uint256 amountSpent, uint256 tokensReceived);
    event RewardsDistributed(address indexed recipient, address indexed memeCoinAddress, uint256 amount);
    event EthWithdrawn(address indexed owner, uint256 amount);
    event MemePoolUpdated(address indexed oldMemePool, address indexed newMemePool);

    constructor(address _memePool) Ownable(msg.sender) {
        memePool = _memePool;
    }

    function buyMemecoinRewards(address _memeCoinAddress, address _affiliate) public payable {
        require(msg.value > 0, "Must send ETH to buy rewards");

        uint256 balanceBefore = IERC20(_memeCoinAddress).balanceOf(address(this));

        IMemePool(memePool).buyTokens{value: msg.value}(_memeCoinAddress, 0, _affiliate, 0);

        uint256 tokensReceived = IERC20(_memeCoinAddress).balanceOf(address(this)) - balanceBefore;

        emit MemeTokensPurchased(_memeCoinAddress, msg.value, tokensReceived);
    }

    function rewardRecipients(address[] memory recipients, address[] memory memecoinAddresses, uint256[] memory amounts)
        external
        onlyOwner
        nonReentrant
    {
        require(
            recipients.length == memecoinAddresses.length && recipients.length == amounts.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            address memecoin = memecoinAddresses[i];
            uint256 amount = amounts[i];

            IERC20(memecoin).safeTransfer(recipient, amount);

            emit RewardsDistributed(recipient, memecoin, amount);
        }
    }

    function withdrawEth() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");

        emit EthWithdrawn(owner(), balance);
    }

    function setMemePool(address _memePool) external onlyOwner {
        require(_memePool != address(0), "Invalid address");
        address oldMemePool = memePool;
        memePool = _memePool;

        emit MemePoolUpdated(oldMemePool, _memePool);
    }

    receive() external payable {}

    fallback() external payable {}
}
