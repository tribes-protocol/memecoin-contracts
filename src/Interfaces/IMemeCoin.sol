// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMemeCoin {
    function initialize(
        uint256 initialSupply,
        string memory _name,
        string memory _symbol,
        address _midDeployer,
        address _deployer
    ) external;

    function initiateDex() external;

    function lockTokens(address user, uint256 deadlineDays) external;

    function dexInitiated() external view returns (bool);

    function lockedDeadlineOf(address user) external view returns (uint256);
}
