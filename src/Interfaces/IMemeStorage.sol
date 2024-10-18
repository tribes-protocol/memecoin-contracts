// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMemeStorageInterface {
    function addMemeContract(
        address _memeOwner,
        address _memeAddress,
        address _tokenAddress,
        address _routerAddress,
        string memory _name,
        string memory _symbol,
        string memory _data,
        uint256 _totalSupply,
        uint256 _initialLiquidity
    ) external;
    function getMemeContractOwner(address _memeContract) external view returns (address);
    function updateData(address _memeOwner, uint256 _ownerMemeNumber, string memory _data) external;
    function addDeployer(address) external;
    function owner() external view;
    function getMemeContractIndex(address _memeContract) external returns (uint256);
}
