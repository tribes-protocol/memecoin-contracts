// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMemeEventTracker {
    event LockedDeadlineUpdated(address indexed user, address indexed memecontract, uint256 numDays);

    function buyEvent(address _caller, address _memeContract, uint256 _buyAmount, uint256 _tokenRecieved) external;
    function sellEvent(address _caller, address _memeContract, uint256 _sellAmount, uint256 _nativeRecieved) external;
    function createMemeEvent(
        address creator,
        address memeContract,
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory data,
        uint256 totalSupply,
        uint256 initialReserve,
        uint256 timestamp
    ) external;
    function listEvent(
        address user,
        address tokenAddress,
        address router,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 _time,
        uint256 totalVolume
    ) external;
    function addDeployer(address) external;
    function lockedDeadlineUpdatedEvent(address _user, address _memeContract, uint256 _newLockedDeadlineDays)
        external;
}
