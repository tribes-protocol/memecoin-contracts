// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Interfaces/IERC20.sol";
import "./Interfaces/IMemePool.sol";
import "./Interfaces/IMemeEventTracker.sol";
import "./Interfaces/IMemeStorage.sol";

contract MemeDeployer is Ownable {
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
    event royal(
        address indexed memeContract,
        address indexed tokenAddress,
        address indexed router,
        address baseAddress,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 _time,
        uint256 totalVolume
    );

    address public creationFeeDistributionContract;
    address public memeStorage;
    address public eventTracker;
    address public memePool;
    uint256 public teamFee = 10000000; // value in wei
    uint256 public teamFeePer = 100; // base of 10000 -> 100 equals 1%
    uint256 public ownerFeePer = 1000; // base of 10000 -> 1000 means 10%
    uint256 public listThreshold = 12000; // value in ether -> 12000 means 12000 tokens(any decimal place)
    uint256 public antiSnipePer = 5; // base of 100 -> 5 equals 5%
    uint256 public affiliatePer = 1000; // base of 10000 -> 1000 equals 10%
    uint256 public supplyValue = 1000000000 ether;
    uint256 public initialReserveEth = 1 ether;
    uint256 public routerCount;
    uint256 public baseCount;
    bool public supplyLock = true;
    bool public lpBurn = true;
    mapping(address => bool) public routerValid;
    mapping(address => bool) public routerAdded;
    mapping(uint256 => address) public routerStorage;
    mapping(address => bool) public baseValid;
    mapping(address => bool) public baseAdded;
    mapping(uint256 => address) public baseStorage;
    mapping(address => uint256) public affiliateSpecialPer;
    mapping(address => bool) public affiliateSpecial;

    constructor(address _memePool, address _creationFeeContract, address _memeStorage, address _eventTracker)
        Ownable(msg.sender)
    {
        memePool = _memePool;
        creationFeeDistributionContract = _creationFeeContract;
        memeStorage = _memeStorage;
        eventTracker = _eventTracker;
    }

    function CreateMeme(
        string memory _name,
        string memory _symbol,
        string memory _data,
        uint256 _totalSupply,
        uint256 _liquidityETHAmount,
        address _baseToken,
        address _router,
        bool _antiSnipe,
        uint256 _amountAntiSnipe
    ) public payable returns (address) {
        require(routerValid[_router], "invalid router");
        require(baseValid[_baseToken], "invalid base token");
        if (supplyLock) {
            require(_totalSupply == supplyValue, "invalid supply");
        }

        if (_antiSnipe) {
            require(_amountAntiSnipe > 0, "invalid antisnipe value");
        }

        require(_amountAntiSnipe <= ((initialReserveEth * antiSnipePer) / 100), "over antisnipe restrictions");

        require(msg.value >= (teamFee + _liquidityETHAmount + _amountAntiSnipe), "fee amount error");

        (bool feeSuccess,) = creationFeeDistributionContract.call{value: teamFee}("");
        require(feeSuccess, "creation fee failed");

        address memeToken = IMemePool(memePool).createMeme{value: _liquidityETHAmount}(
            [_name, _symbol], _totalSupply, msg.sender, _baseToken, _router, [listThreshold, initialReserveEth], lpBurn
        );
        IMemeStorageInterface(memeStorage).addMemeContract(
            msg.sender,
            (memeToken),
            memeToken,
            address(_router),
            _name,
            _symbol,
            _data,
            _totalSupply,
            _liquidityETHAmount
        );

        if (_antiSnipe) {
            IMemePool(memePool).buyTokens{value: _amountAntiSnipe}(memeToken, 0, msg.sender);
            IERC20(memeToken).transfer(msg.sender, IERC20(memeToken).balanceOf(address(this)));
        }
        IMemeEventTracker(eventTracker).createMemeEvent(
            msg.sender,
            (memeToken),
            (memeToken),
            _name,
            _symbol,
            _data,
            _totalSupply,
            initialReserveEth + _liquidityETHAmount,
            block.timestamp
        );
        emit memeCreated(
            msg.sender,
            (memeToken),
            (memeToken),
            _name,
            _symbol,
            _data,
            _totalSupply,
            initialReserveEth + _liquidityETHAmount,
            block.timestamp
        );

        return memeToken;
    }

    function updateTeamFee(uint256 _newTeamFeeInWei) public onlyOwner {
        teamFee = _newTeamFeeInWei;
    }

    function updateownerFee(uint256 _newOwnerFeeBaseTenK) public onlyOwner {
        ownerFeePer = _newOwnerFeeBaseTenK;
    }

    function updateSpecialAffiliateData(address _affiliateAddrs, bool _status, uint256 _specialPer) public onlyOwner {
        affiliateSpecial[_affiliateAddrs] = _status;
        affiliateSpecialPer[_affiliateAddrs] = _specialPer;
    }

    function getAffiliatePer(address _affiliateAddrs) public view returns (uint256) {
        if (affiliateSpecial[_affiliateAddrs]) {
            return affiliateSpecialPer[_affiliateAddrs];
        } else {
            return affiliatePer;
        }
    }

    function getOwnerPer() public view returns (uint256) {
        return ownerFeePer;
    }

    function getSpecialAffiliateValidity(address _affiliateAddrs) public view returns (bool) {
        return affiliateSpecial[_affiliateAddrs];
    }

    function updateSupplyValue(uint256 _newSupplyVal) public onlyOwner {
        supplyValue = _newSupplyVal;
    }

    function updateInitResEthVal(uint256 _newVal) public onlyOwner {
        initialReserveEth = _newVal;
    }

    function stateChangeSupplyLock(bool _lockState) public onlyOwner {
        supplyLock = _lockState;
    }

    function addRouter(address _routerAddress) public onlyOwner {
        require(!routerAdded[_routerAddress], "already added");
        routerAdded[_routerAddress] = true;
        routerValid[_routerAddress] = true;
        routerStorage[routerCount] = _routerAddress;
        routerCount++;
    }

    function disableRouter(address _routerAddress) public onlyOwner {
        require(routerAdded[_routerAddress], "not added");
        require(routerValid[_routerAddress], "not valid");
        routerValid[_routerAddress] = false;
    }

    function enableRouter(address _routerAddress) public onlyOwner {
        require(routerAdded[_routerAddress], "not added");
        require(!routerValid[_routerAddress], "already enabled");
        routerValid[_routerAddress] = true;
    }

    function addBaseToken(address _baseTokenAddress) public onlyOwner {
        require(!baseAdded[_baseTokenAddress], "already added");
        baseAdded[_baseTokenAddress] = true;
        baseValid[_baseTokenAddress] = true;
        baseStorage[baseCount] = _baseTokenAddress;
        baseCount++;
    }

    function disableBaseToken(address _baseTokenAddress) public onlyOwner {
        require(baseAdded[_baseTokenAddress], "not added");
        require(baseValid[_baseTokenAddress], "not valid");
        baseValid[_baseTokenAddress] = false;
    }

    function enableBasetoken(address _baseTokenAddress) public onlyOwner {
        require(baseAdded[_baseTokenAddress], "not added");
        require(!baseValid[_baseTokenAddress], "already enabled");
        baseValid[_baseTokenAddress] = true;
    }

    function updateMemeData(uint256 _ownerMemeCount, string memory _newData) public {
        IMemeStorageInterface(memeStorage).updateData(msg.sender, _ownerMemeCount, _newData);
    }

    function updateMemePool(address _newmemePool) public onlyOwner {
        memePool = _newmemePool;
    }

    function updateCreationFeeContract(address _newCreationFeeContract) public onlyOwner {
        creationFeeDistributionContract = _newCreationFeeContract;
    }

    function updateStorageContract(address _newStorageContract) public onlyOwner {
        memeStorage = _newStorageContract;
    }

    function updateEventContract(address _newEventContract) public onlyOwner {
        eventTracker = _newEventContract;
    }

    function updateListThreshold(uint256 _newListThreshold) public onlyOwner {
        listThreshold = _newListThreshold;
    }

    function updateAntiSnipePer(uint256 _newAntiSnipePer) public onlyOwner {
        antiSnipePer = _newAntiSnipePer;
    }

    function stateChangeLPBurn(bool _state) public onlyOwner {
        lpBurn = _state;
    }

    function updateAffiliatePerBaseTenK(uint256 _newAffPer) public onlyOwner {
        affiliatePer = _newAffPer;
    }

    function updateteamFeeper(uint256 _newFeePer) public onlyOwner {
        teamFeePer = _newFeePer;
    }

    function emitRoyal(
        address memeContract,
        address tokenAddress,
        address router,
        address baseAddress,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 _time,
        uint256 totalVolume
    ) public {
        require(msg.sender == memePool, "invalid caller");
        emit royal(memeContract, tokenAddress, router, baseAddress, liquidityAmount, tokenAmount, _time, totalVolume);
    }

    // Emergency withdrawal by owner

    function emergencyWithdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }
}
