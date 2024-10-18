// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IMemeStorage.sol";

contract MemeEventTracker is Ownable {
    address public memeRegistry;
    mapping(address => bool) public memeContractDeployer;
    mapping(address => address) public memeContractCreatedByDeployer;
    mapping(address => uint256) public memeContractIndex;
    uint256 public buyEventCount;
    uint256 public sellEventCount;

    event buyCall(
        address indexed buyer,
        address indexed memeContract,
        uint256 buyAmount,
        uint256 tokenReceived,
        uint256 index,
        uint256 timestamp
    );
    event sellCall(
        address indexed seller,
        address indexed memeContract,
        uint256 sellAmount,
        uint256 nativeReceived,
        uint256 index,
        uint256 timestamp
    );
    event tradeCall(
        address indexed caller,
        address indexed memeContract,
        uint256 outAmount,
        uint256 inAmount,
        uint256 index,
        uint256 timestamp,
        string tradeType
    );
    event memeCreated(
        address indexed creator,
        address indexed memeContract,
        address indexed tokenAddress,
        string name,
        string symbol,
        string data,
        uint256 totalSupply,
        uint256 initialReserve,
        uint256 timestamp
    );

    event listed(
        address indexed user,
        address indexed tokenAddress,
        address indexed router,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 time,
        uint256 totalVolume
    );

    constructor(address _memeStorage) Ownable(msg.sender) {
        memeRegistry = _memeStorage;
    }

    function buyEvent(address _buyer, address _memeContract, uint256 _buyAmount, uint256 _tokenRecieved) public {
        require(memeContractDeployer[msg.sender], "invalid meme contract");
        uint256 memeIndex;
        memeIndex = IMemeStorageInterface(memeRegistry).getMemeContractIndex(_memeContract);
        emit buyCall(_buyer, _memeContract, _buyAmount, _tokenRecieved, memeIndex, block.timestamp);
        emit tradeCall(_buyer, _memeContract, _buyAmount, _tokenRecieved, memeIndex, block.timestamp, "buy");
        buyEventCount++;
    }

    function sellEvent(address _seller, address _memeContract, uint256 _sellAmount, uint256 _nativeRecieved) public {
        require(memeContractDeployer[msg.sender], "invalid meme contract");
        uint256 memeIndex;
        memeIndex = IMemeStorageInterface(memeRegistry).getMemeContractIndex(_memeContract);
        emit sellCall(_seller, _memeContract, _sellAmount, _nativeRecieved, memeIndex, block.timestamp);
        emit tradeCall(_seller, _memeContract, _sellAmount, _nativeRecieved, memeIndex, block.timestamp, "sell");
        sellEventCount++;
    }

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
    ) public {
        require(memeContractDeployer[msg.sender], "invalid deployer");
        memeContractCreatedByDeployer[memeContract] = msg.sender;
        memeContractIndex[memeContract] = IMemeStorageInterface(memeRegistry).getMemeContractIndex(memeContract);
        emit memeCreated(
            creator, memeContract, tokenAddress, name, symbol, data, totalSupply, initialReserve, timestamp
        );
    }

    function listEvent(
        address user,
        address tokenAddress,
        address router,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 _time,
        uint256 totalVolume
    ) public {
        require(memeContractDeployer[msg.sender], "invalid deployer");
        emit listed(user, tokenAddress, router, liquidityAmount, tokenAmount, _time, totalVolume);
    }

    function addDeployer(address _newDeployer) public onlyOwner {
        memeContractDeployer[_newDeployer] = true;
    }

    function removeDeployer(address _deployer) public onlyOwner {
        memeContractDeployer[_deployer] = false;
    }
}
