// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IERC20.sol";

contract LpLockDeployer is Ownable, ReentrancyGuard {
    struct LockInfo {
        address lockingToken;
        uint256 lockerEndTimeStamp;
        string logo;
        uint256 lockingAmount;
        address memeOwner;
        bool isUnlocked;
    }

    mapping(address => LockInfo) public locks;
    address[] public allLocks;

    event LockCreated(address indexed locker, address indexed token, uint256 amount, uint256 unlockTime);
    event LockUnlocked(address indexed locker, address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function createLPLocker(
        address _lockingToken,
        uint256 _lockerEndTimeStamp,
        string memory _logo,
        uint256 _lockingAmount,
        address _memeOwner
    ) external payable nonReentrant returns (address) {
        require(_lockingToken != address(0), "Invalid token address");
        require(_lockerEndTimeStamp > block.timestamp, "End time must be in the future");
        require(_lockingAmount > 0, "Locking amount must be greater than 0");
        require(_memeOwner != address(0), "Invalid meme owner address");

        IERC20 token = IERC20(_lockingToken);
        require(token.transferFrom(msg.sender, address(this), _lockingAmount), "Transfer failed");

        address locker = address(this);

        locks[locker] = LockInfo({
            lockingToken: _lockingToken,
            lockerEndTimeStamp: _lockerEndTimeStamp,
            logo: _logo,
            lockingAmount: _lockingAmount,
            memeOwner: _memeOwner,
            isUnlocked: false
        });

        allLocks.push(locker);

        emit LockCreated(locker, _lockingToken, _lockingAmount, _lockerEndTimeStamp);

        return locker;
    }

    function unlock(address _locker) external nonReentrant {
        LockInfo storage lockInfo = locks[_locker];
        require(msg.sender == lockInfo.memeOwner, "Only meme owner can unlock");
        require(!lockInfo.isUnlocked, "Already unlocked");
        require(block.timestamp >= lockInfo.lockerEndTimeStamp, "Lock period not ended");

        lockInfo.isUnlocked = true;
        IERC20 token = IERC20(lockInfo.lockingToken);
        require(token.transfer(lockInfo.memeOwner, lockInfo.lockingAmount), "Transfer failed");

        emit LockUnlocked(_locker, lockInfo.lockingToken, lockInfo.lockingAmount);
    }

    function getLockInfo(address _locker) external view returns (LockInfo memory) {
        return locks[_locker];
    }

    function getAllLocks() external view returns (address[] memory) {
        return allLocks;
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}
