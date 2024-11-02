// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IMemePool} from "./Interfaces/IMemePool.sol";

contract MemeCoin is IERC20, IERC20Permit, EIP712, Nonces, Votes {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     * @dev Permit deadline has expired.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Mismatched signature.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    struct LockInfo {
        uint256 startTime; // Initial lock timestamp
        uint256 durationDays; // Lock duration in days
    }

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint8 public constant version = 2;

    address public memePool;
    address public deployer;
    bool public isInitialized;
    bool public dexInitiated;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => LockInfo) private _locks;

    constructor() EIP712("memeCoin.new", "1") {}

    function initialize(
        uint256 initialSupply,
        string memory _name,
        string memory _symbol,
        address _memePool,
        address _deployer
    ) external {
        require(!isInitialized);
        require(_memePool != address(0), "MemePool address cannot be zero");
        require(_deployer != address(0), "Deployer address cannot be zero");
        _mint(_memePool, initialSupply);
        memePool = _memePool;
        deployer = _deployer;
        name = _name;
        symbol = _symbol;
        isInitialized = true;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(_validateTransfer(msg.sender), "not dex listed");
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(_validateTransfer(msg.sender), "not dex listed");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function Burn(uint256 amount) public returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "invalid transfer amount");

        require(dexInitiated || block.timestamp > lockedDeadlineOf(sender), "Balance is locked");

        require(_balances[sender] >= amount, "Insufficient balance");

        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);

        // Update voting rights
        _update(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _update(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _validateTransfer(address _from) internal view returns (bool) {
        if (dexInitiated) {
            return true;
        }

        address rewardPool = IMemePool(memePool).rewardPool();
        address memeswap = IMemePool(memePool).memeswap();

        require(rewardPool != address(0), "Reward pool not set");
        require(memeswap != address(0), "MemeSwap not set");

        if (_from == memePool || _from == deployer || _from == rewardPool || _from == memeswap) {
            return true;
        }
        return false;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(spender != address(0));

        _allowances[msg.sender][spender] = (_allowances[msg.sender][spender] + addedValue);
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(spender != address(0));

        _allowances[msg.sender][spender] = (_allowances[msg.sender][spender] - subtractedValue);
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param account The account whose tokens will be burnt.
     * @param amount The amount that will be burnt.
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0));
        require(amount <= _balances[account]);

        _totalSupply = _totalSupply - amount;
        _balances[account] = _balances[account] - amount;
        emit Transfer(account, address(0), amount);

        _update(account, address(0), amount);
    }

    function initiateDex() public {
        require(msg.sender == memePool, "only deployer allowed");
        dexInitiated = true;
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }

        _approve(owner, spender, value);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(address owner) public view virtual override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Total supply cap has been exceeded, introducing a risk of votes overflowing.
     */
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    /**
     * @dev Maximum token supply. Defaults to `type(uint208).max` (2^208^ - 1).
     *
     * This maximum is enforced in {_update}. It limits the total supply of the token, which is otherwise a uint256,
     * so that checkpoints can be stored in the Trace208 structure used by {{Votes}}. Increasing this value will not
     * remove the underlying limitation, and will cause {_update} to fail because of a math overflow in
     * {_transferVotingUnits}. An override could be used to further restrict the total supply (to a lower value) if
     * additional logic requires it. When resolving override conflicts on this function, the minimum should be
     * returned.
     */
    function _maxSupply() internal view virtual returns (uint256) {
        return type(uint208).max;
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }

    /**
     * @dev Returns the voting units of an `account`.
     *
     * WARNING: Overriding this function may compromise the internal vote accounting.
     * `ERC20Votes` assumes tokens map to voting units 1:1 and this is not easy to change.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }

    function lockTokens(address account, uint256 deadlineDays) external {
        require(!dexInitiated, "Cannot lock tokens after dex initiated");
        require(msg.sender == memePool || msg.sender == deployer, "Only deployer or memepool can lock tokens");
        require(deadlineDays > 0 && deadlineDays <= 365, "Deadline must be between 1 and 365 days");
        require(_balances[account] > 0, "Cannot lock zero balance");

        LockInfo storage lockInfo = _locks[account];

        uint256 lockDeadline = lockedDeadlineOf(account);
        if (lockDeadline > block.timestamp) {
            require(lockInfo.durationDays <= deadlineDays, "New duration must be greater than current duration");
        }
        lockInfo.durationDays = deadlineDays;
        lockInfo.startTime = block.timestamp;
    }

    function lockedDeadlineOf(address account) public view returns (uint256) {
        LockInfo storage lockInfo = _locks[account];
        if (lockInfo.startTime == 0) return 0;
        return lockInfo.startTime + (lockInfo.durationDays * 1 days);
    }

    // Helper function to get all lock information at once
    function getLockInfo(address account) public view returns (LockInfo memory) {
        return _locks[account];
    }
}
