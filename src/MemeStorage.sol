// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MemeStorage is Ownable {
    constructor() Ownable(msg.sender) {}

    struct MemeDetails {
        address memeAddress;
        address tokenAddress;
        address memeOwner;
        address router;
        string name;
        string symbol;
        string data;
        uint256 totalSupply;
        uint256 initialLiquidity;
        uint256 createdOn;
    }

    MemeDetails[] public memeContracts;
    mapping(address => bool) public deployer;
    mapping(address => uint256) public memeContractToIndex;
    mapping(address => uint256) public tokenContractToIndex;
    mapping(address => uint256) public ownerToMemeCount;
    mapping(address => mapping(uint256 => uint256)) public ownerIndexToStorageIndex;
    mapping(address => address) public memeContractToOwner;
    mapping(address => uint256) public memeContractToOwnerCount;
    uint256 public memeCount;

    modifier onlyDeployer() {
        require(deployer[msg.sender], "not deployer");
        _;
    }

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
    ) external onlyDeployer {
        MemeDetails memory newMeme = MemeDetails({
            memeAddress: _memeAddress,
            tokenAddress: _tokenAddress,
            memeOwner: _memeOwner,
            router: _routerAddress,
            name: _name,
            symbol: _symbol,
            data: _data,
            totalSupply: _totalSupply,
            initialLiquidity: _initialLiquidity,
            createdOn: block.timestamp
        });
        memeContracts.push(newMeme);
        memeContractToIndex[_memeAddress] = memeContracts.length - 1;
        tokenContractToIndex[_tokenAddress] = memeContracts.length - 1;
        memeContractToOwner[_memeAddress] = _memeOwner;
        memeContractToOwnerCount[_memeAddress] = ownerToMemeCount[_memeOwner];
        ownerIndexToStorageIndex[_memeOwner][ownerToMemeCount[_memeOwner]] = memeCount;
        ownerToMemeCount[_memeOwner]++;
        memeCount++;
    }

    function updateData(address _memeOwner, uint256 _ownerMemeIndex, string memory _data) external onlyDeployer {
        require(_ownerMemeIndex < ownerToMemeCount[_memeOwner], "invalid owner meme count");
        require(
            memeContracts[ownerIndexToStorageIndex[_memeOwner][_ownerMemeIndex]].memeOwner == _memeOwner,
            "invalid caller"
        );
        memeContracts[ownerIndexToStorageIndex[_memeOwner][_ownerMemeIndex]].data = _data;
    }

    function getMemeContract(uint256 index) public view returns (MemeDetails memory) {
        return memeContracts[index];
    }

    function getMemeContractIndex(address _memeContract) public view returns (uint256) {
        return memeContractToIndex[_memeContract];
    }

    function getTotalContracts() public view returns (uint256) {
        return memeContracts.length;
    }

    function getMemeContractOwner(address _memeContract) public view returns (address) {
        return memeContractToOwner[_memeContract];
    }

    function addDeployer(address _deployer) public onlyOwner {
        require(!deployer[_deployer], "already added");
        deployer[_deployer] = true;
    }

    function removeDeployer(address _deployer) public onlyOwner {
        require(deployer[_deployer], "not deployer");
        deployer[_deployer] = false;
    }
    // Emergency withdrawal by owner

    function emergencyWithdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }
}
