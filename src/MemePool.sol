// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Interfaces/IERC20.sol";
import "./Interfaces/IMemeDeployer.sol";
import "./Interfaces/IMemeEventTracker.sol";
import "./Interfaces/IMemeCoin.sol";
import "./Interfaces/IMemePool.sol";
import {UniswapRouter02} from "./Interfaces/IUniswapRouter02.sol";

interface UniswapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface LPToken {
    function sync() external;
}

interface ILpLockDeployerInterface {
    function createLPLocker(
        address _lockingToken,
        uint256 _lockerEndTimeStamp,
        string memory _logo,
        uint256 _lockingAmount,
        address _memeOwner
    ) external payable returns (address);
}

contract MemePool is IMemePool, Ownable, ReentrancyGuard {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant HUNDRED = 100;
    uint256 public constant BASIS_POINTS = 10000;

    // deployer allowed to create meme tokens
    mapping(address => bool) public allowedDeployers;
    // user => array of meme tokens
    mapping(address => address[]) public userMemeTokens;
    // meme token => meme token details
    mapping(address => IMemePool.MemeTokenPool) public tokenPools;

    address public implementation;
    address public feeContract;
    address public stableAddress;
    address public lpLockDeployer;
    address public eventTracker;
    address public rewardPool;
    address public memeswap;
    uint16 public feePer;

    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount);
    event sold(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 _time,
        uint256 reserveEth,
        uint256 reserveTokens,
        uint256 totalVolume
    );
    event bought(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 _time,
        uint256 reserveEth,
        uint256 reserveTokens,
        uint256 totalVolume
    );
    event memeTradeCall(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 _time,
        uint256 reserveEth,
        uint256 reserveTokens,
        string tradeType,
        uint256 totalVolume
    );
    event listed(
        address indexed user,
        address indexed tokenAddress,
        address indexed router,
        uint256 liquidityAmount,
        uint256 tokenAmount,
        uint256 _time,
        uint256 totalVolume
    );

    constructor(
        address _implementation,
        address _feeContract,
        address _lpLockDeployer,
        address _stableAddress,
        address _eventTracker,
        uint16 _feePer
    ) payable Ownable(msg.sender) {
        implementation = _implementation;
        feeContract = _feeContract;
        lpLockDeployer = _lpLockDeployer;
        stableAddress = _stableAddress;
        eventTracker = _eventTracker;
        feePer = _feePer;
    }

    function createMeme(
        string[2] memory _name_symbol,
        uint256 _totalSupply,
        address _creator,
        address _baseToken,
        address _router,
        uint256[2] memory listThreshold_initReserveEth,
        bool lpBurn
    ) public payable returns (address) {
        require(allowedDeployers[msg.sender], "not deployer");

        address memeToken = Clones.clone(implementation);
        IMemeCoin(memeToken).initialize(_totalSupply, _name_symbol[0], _name_symbol[1], address(this), msg.sender);

        // add tokens to the tokens user list
        userMemeTokens[_creator].push(memeToken);

        // create the pool data
        MemeTokenPool memory pool;

        pool.creator = _creator;
        pool.token = memeToken;
        pool.baseToken = _baseToken;
        pool.router = _router;
        pool.deployer = msg.sender;

        if (_baseToken == UniswapRouter02(_router).WETH()) {
            pool.pool.nativePer = 100;
        } else {
            pool.pool.nativePer = 50;
        }
        pool.pool.tradeActive = true;
        pool.pool.lpBurn = lpBurn;
        pool.pool.reserveTokens += _totalSupply;
        pool.pool.reserveETH += (listThreshold_initReserveEth[1] + msg.value);
        pool.pool.listThreshold = listThreshold_initReserveEth[0];
        pool.pool.initialReserveEth = listThreshold_initReserveEth[1];

        // add the meme data for the meme token
        tokenPools[memeToken] = pool;

        emit LiquidityAdded(address(this), _totalSupply, msg.value);

        return address(memeToken); // return meme token address
    }

    // Calculate amount of output tokens or ETH to give out
    function getAmountOutTokens(address memeToken, uint256 amountIn) public view returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid input amount");
        MemeTokenPool storage token = tokenPools[memeToken];
        require(token.pool.reserveTokens > 0 && token.pool.reserveETH > 0, "Invalid reserves");
        uint256 numerator = amountIn * token.pool.reserveTokens;
        uint256 denominator = (token.pool.reserveETH) + amountIn;
        amountOut = numerator / denominator;
    }

    function getAmountOutETH(address memeToken, uint256 amountIn) public view returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid input amount");
        MemeTokenPool storage token = tokenPools[memeToken];
        require(token.pool.reserveTokens > 0 && token.pool.reserveETH > 0, "Invalid reserves");
        uint256 numerator = amountIn * token.pool.reserveETH;
        uint256 denominator = (token.pool.reserveTokens) + amountIn;
        amountOut = numerator / denominator;
    }

    function getBaseToken(address memeToken) public view returns (address) {
        MemeTokenPool storage token = tokenPools[memeToken];
        return address(token.baseToken);
    }

    function getWrapAddr(address memeToken) public view returns (address) {
        return UniswapRouter02(tokenPools[memeToken].router).WETH();
    }

    function getAmountsMinToken(address memeToken, address _tokenAddress, uint256 _ethIN)
        public
        view
        returns (uint256)
    {
        // generate the pair path of token -> weth
        uint256[] memory amountMinArr;
        address[] memory path = new address[](2);
        path[0] = getWrapAddr(memeToken);
        path[1] = address(_tokenAddress);
        amountMinArr = UniswapRouter02(tokenPools[memeToken].router).getAmountsOut(_ethIN, path);
        return uint256(amountMinArr[1]);
    }

    function getCurrentCap(address memeToken) public view returns (uint256) {
        MemeTokenPool storage token = tokenPools[memeToken];
        return (getAmountsMinToken(memeToken, stableAddress, token.pool.reserveETH) * IERC20(memeToken).totalSupply())
            / token.pool.reserveTokens;
    }

    function getMemeTokenPool(address memeToken) public view returns (MemeTokenPool memory) {
        return tokenPools[memeToken];
    }

    function getMemeTokenPools(address[] memory memeTokens) public view returns (MemeTokenPool[] memory) {
        uint256 length = memeTokens.length;
        MemeTokenPool[] memory pools = new MemeTokenPool[](length);
        for (uint256 i = 0; i < length;) {
            pools[i] = tokenPools[memeTokens[i]];
            unchecked {
                i++;
            }
        }
        return pools;
    }

    function getUserMemeTokens(address user) public view returns (address[] memory) {
        return userMemeTokens[user];
    }

    function sellTokens(address memeToken, uint256 tokenAmount, uint256 minEth, address _affiliate)
        public
        nonReentrant
        returns (bool, uint256)
    {
        MemeTokenPool storage token = tokenPools[memeToken];
        require(token.pool.tradeActive, "Trading not active");

        uint256 tokenToSell = tokenAmount;
        uint256 ethAmount = getAmountOutETH(memeToken, tokenToSell);
        uint256 ethAmountFee = (ethAmount * feePer) / BASIS_POINTS;
        uint256 ethAmountCreatorFee =
            (ethAmountFee * (IMemeDeployerInterface(token.deployer).getCreatorPer())) / BASIS_POINTS;
        uint256 affiliateFee =
            (ethAmountFee * (IMemeDeployerInterface(token.deployer).getAffiliatePer(_affiliate))) / BASIS_POINTS;
        require(ethAmount > 0 && ethAmount >= minEth, "Slippage too high");

        token.pool.reserveTokens += tokenAmount;
        token.pool.reserveETH -= ethAmount;
        token.pool.volume += ethAmount;

        IERC20(memeToken).transferFrom(msg.sender, address(this), tokenToSell);
        (bool success,) = feeContract.call{value: ethAmountFee - ethAmountCreatorFee - affiliateFee}(""); // paying plat fee
        require(success, "fee ETH transfer failed");

        (success,) = _affiliate.call{value: affiliateFee}(""); // paying affiliate fee which is same amount as plat fee %
        require(success, "aff ETH transfer failed");

        (success,) = payable(token.creator).call{value: ethAmountCreatorFee}(""); // paying owner fee per tx
        require(success, "creator ETH transfer failed");

        uint256 amountToSend = ethAmount - ethAmountFee;

        (success,) = msg.sender.call{value: amountToSend}("");
        require(success, "seller ETH transfer failed");

        emit sold(
            msg.sender,
            tokenAmount,
            ethAmount,
            block.timestamp,
            token.pool.reserveETH,
            token.pool.reserveTokens,
            token.pool.volume
        );
        emit memeTradeCall(
            msg.sender,
            tokenAmount,
            ethAmount,
            block.timestamp,
            token.pool.reserveETH,
            token.pool.reserveTokens,
            "sell",
            token.pool.volume
        );
        IMemeEventTracker(eventTracker).sellEvent(msg.sender, memeToken, tokenToSell, ethAmount);

        return (true, amountToSend);
    }

    function buyTokens(address memeToken, uint256 minTokens, address _affiliate, uint256 _lockedDeadlineDays)
        public
        payable
        nonReentrant
    {
        require(msg.value > 0, "Invalid buy value");
        _buyTokens(memeToken, minTokens, msg.value, _affiliate, _lockedDeadlineDays);
    }

    function buyManyTokens(
        address[] calldata memeTokens,
        uint256[] calldata minTokensAmounts,
        uint256[] calldata ethAmounts,
        address _affiliate,
        uint256 _lockedDeadlineDays
    ) public payable nonReentrant {
        require(
            memeTokens.length == minTokensAmounts.length && memeTokens.length == ethAmounts.length,
            "Array lengths mismatch"
        );

        uint256 totalEthAmount = 0;
        for (uint256 i = 0; i < ethAmounts.length; i++) {
            totalEthAmount += ethAmounts[i];
        }
        require(msg.value == totalEthAmount, "Invalid total buy value");

        for (uint256 i = 0; i < memeTokens.length; i++) {
            _buyTokens(memeTokens[i], minTokensAmounts[i], ethAmounts[i], _affiliate, _lockedDeadlineDays);
        }
    }

    function _buyTokens(
        address memeToken,
        uint256 minTokens,
        uint256 ethAmount,
        address _affiliate,
        uint256 _lockedDeadlineDays
    ) internal {
        MemeTokenPool storage token = tokenPools[memeToken];
        require(token.pool.tradeActive, "Trading not active");

        uint256 ethAmountFee = (ethAmount * feePer) / BASIS_POINTS;
        uint256 ethAmountCreatorFee =
            (ethAmountFee * (IMemeDeployerInterface(token.deployer).getCreatorPer())) / BASIS_POINTS;
        uint256 affiliateFee =
            (ethAmountFee * (IMemeDeployerInterface(token.deployer).getAffiliatePer(_affiliate))) / BASIS_POINTS;

        uint256 tokenAmount = getAmountOutTokens(memeToken, ethAmount - ethAmountFee);
        require(tokenAmount >= minTokens, "Slippage too high");

        token.pool.reserveETH += (ethAmount - ethAmountFee);
        token.pool.reserveTokens -= tokenAmount;
        token.pool.volume += ethAmount;

        (bool success,) = feeContract.call{value: ethAmountFee - ethAmountCreatorFee - affiliateFee}("");
        require(success, "fee ETH transfer failed");

        (success,) = _affiliate.call{value: affiliateFee}("");
        require(success, "affiliate fee ETH transfer failed");

        (success,) = payable(token.creator).call{value: ethAmountCreatorFee}("");
        require(success, "creator fee ETH transfer failed");

        IERC20(memeToken).transfer(msg.sender, tokenAmount);

        if (_lockedDeadlineDays > 0) {
            lockTokens(msg.sender, memeToken, _lockedDeadlineDays);
        }

        emit bought(
            msg.sender,
            ethAmount,
            tokenAmount,
            block.timestamp,
            token.pool.reserveETH,
            token.pool.reserveTokens,
            token.pool.volume
        );
        emit memeTradeCall(
            msg.sender,
            ethAmount,
            tokenAmount,
            block.timestamp,
            token.pool.reserveETH,
            token.pool.reserveTokens,
            "buy",
            token.pool.volume
        );
        IMemeEventTracker(eventTracker).buyEvent(msg.sender, memeToken, ethAmount, tokenAmount);

        _checkAndProcessListing(memeToken);
    }

    function _checkAndProcessListing(address memeToken) internal {
        MemeTokenPool storage token = tokenPools[memeToken];
        uint256 currentMarketCap = getCurrentCap(memeToken);
        uint256 listThresholdCap = token.pool.listThreshold * 10 ** IERC20(stableAddress).decimals();

        if (currentMarketCap >= (listThresholdCap / 2) && !token.pool.royalemitted) {
            IMemeDeployerInterface(token.deployer).emitRoyal(
                memeToken,
                memeToken,
                token.router,
                token.baseToken,
                token.pool.reserveETH,
                token.pool.reserveTokens,
                block.timestamp,
                token.pool.volume
            );
            token.pool.royalemitted = true;
        }

        if (currentMarketCap >= listThresholdCap) {
            token.pool.tradeActive = false;
            IMemeCoin(memeToken).initiateDex();
            token.pool.reserveETH -= token.pool.initialReserveEth;
            if (token.pool.nativePer > 0) {
                _addLiquidityETH(
                    memeToken,
                    (IERC20(memeToken).balanceOf(address(this)) * token.pool.nativePer) / HUNDRED,
                    (token.pool.reserveETH * token.pool.nativePer) / HUNDRED,
                    token.pool.lpBurn
                );
                token.pool.reserveETH -= (token.pool.reserveETH * token.pool.nativePer) / HUNDRED;
            }
            if (token.pool.nativePer < HUNDRED) {
                _swapEthToBase(memeToken, token.baseToken, token.pool.reserveETH);
                _addLiquidity(
                    memeToken,
                    IERC20(memeToken).balanceOf(address(this)),
                    IERC20(token.baseToken).balanceOf(address(this)),
                    token.pool.lpBurn
                );
            }
        }
    }

    function changeNativePer(address memeToken, uint8 _newNativePer) public {
        require(_isMemeToken(memeToken), "Unauthorized");
        MemeTokenPool storage token = tokenPools[memeToken];
        require(token.baseToken != getWrapAddr(memeToken), "no custom base selected");
        require(_newNativePer >= 0 && _newNativePer <= 100, "invalid per");
        token.pool.nativePer = _newNativePer;
    }

    function _addLiquidityETH(address memeToken, uint256 amountTokenDesired, uint256 nativeForDex, bool lpBurn)
        internal
    {
        uint256 amountETH = nativeForDex;
        uint256 amountETHMin = (amountETH * 90) / HUNDRED;
        uint256 amountTokenToAddLiq = amountTokenDesired;
        uint256 amountTokenMin = (amountTokenToAddLiq * 90) / HUNDRED;
        uint256 LP_WBNB_exp_balance;
        uint256 LP_token_balance;
        uint256 tokenToSend = 0;

        MemeTokenPool storage token = tokenPools[memeToken];

        address wrapperAddress = getWrapAddr(memeToken);
        token.storedLPAddress = _getpair(memeToken, memeToken, wrapperAddress);
        address storedLPAddress = token.storedLPAddress;
        LP_WBNB_exp_balance = IERC20(wrapperAddress).balanceOf(storedLPAddress);
        LP_token_balance = IERC20(memeToken).balanceOf(storedLPAddress);

        if (storedLPAddress != address(0x0) && (LP_WBNB_exp_balance > 0 && LP_token_balance <= 0)) {
            tokenToSend = (amountTokenToAddLiq * LP_WBNB_exp_balance) / amountETH;

            IERC20(memeToken).transfer(storedLPAddress, tokenToSend);

            LPToken(storedLPAddress).sync();
            // sync after adding token
        }
        _approve(memeToken, false);

        if (lpBurn) {
            UniswapRouter02(token.router).addLiquidityETH{value: amountETH - LP_WBNB_exp_balance}(
                memeToken,
                amountTokenToAddLiq - tokenToSend,
                amountTokenMin,
                amountETHMin,
                DEAD,
                block.timestamp + (300)
            );
        } else {
            UniswapRouter02(token.router).addLiquidityETH{value: amountETH - LP_WBNB_exp_balance}(
                memeToken,
                amountTokenToAddLiq - tokenToSend,
                amountTokenMin,
                amountETHMin,
                address(this),
                block.timestamp + (300)
            );
            _approveLock(storedLPAddress, lpLockDeployer);
            token.lockerAddress = ILpLockDeployerInterface(lpLockDeployer).createLPLocker(
                storedLPAddress, 32503698000, "logo", IERC20(storedLPAddress).balanceOf(address(this)), token.creator
            );
        }
        IMemeEventTracker(eventTracker).listEvent(
            msg.sender,
            memeToken,
            token.router,
            amountETH - LP_WBNB_exp_balance,
            amountTokenToAddLiq - tokenToSend,
            block.timestamp,
            token.pool.volume
        );
        emit listed(
            msg.sender,
            memeToken,
            token.router,
            amountETH - LP_WBNB_exp_balance,
            amountTokenToAddLiq - tokenToSend,
            block.timestamp,
            token.pool.volume
        );
    }

    function _addLiquidity(address memeToken, uint256 amountTokenDesired, uint256 baseForDex, bool lpBurn) internal {
        uint256 amountBase = baseForDex;
        uint256 amountBaseMin = (amountBase * 90) / HUNDRED;
        uint256 amountTokenToAddLiq = amountTokenDesired;
        uint256 amountTokenMin = (amountTokenToAddLiq * 90) / HUNDRED;
        uint256 LP_WBNB_exp_balance;
        uint256 LP_token_balance;
        uint256 tokenToSend = 0;

        MemeTokenPool storage token = tokenPools[memeToken];

        token.storedLPAddress = _getpair(memeToken, memeToken, token.baseToken);
        address storedLPAddress = token.storedLPAddress;

        LP_WBNB_exp_balance = IERC20(token.baseToken).balanceOf(storedLPAddress);
        LP_token_balance = IERC20(memeToken).balanceOf(storedLPAddress);

        if (storedLPAddress != address(0x0) && (LP_WBNB_exp_balance > 0 && LP_token_balance <= 0)) {
            tokenToSend = (amountTokenToAddLiq * LP_WBNB_exp_balance) / amountBase;

            IERC20(memeToken).transfer(storedLPAddress, tokenToSend);

            LPToken(storedLPAddress).sync();
            // sync after adding token
        }
        _approve(memeToken, false);
        _approve(memeToken, true);
        if (lpBurn) {
            UniswapRouter02(token.router).addLiquidity(
                memeToken,
                token.baseToken,
                amountTokenToAddLiq - tokenToSend,
                amountBase - LP_WBNB_exp_balance,
                amountTokenMin,
                amountBaseMin,
                DEAD,
                block.timestamp + (300)
            );
        } else {
            UniswapRouter02(token.router).addLiquidity(
                memeToken,
                token.baseToken,
                amountTokenToAddLiq - tokenToSend,
                amountBase - LP_WBNB_exp_balance,
                amountTokenMin,
                amountBaseMin,
                address(this),
                block.timestamp + (300)
            );
            _approveLock(storedLPAddress, lpLockDeployer);
            token.lockerAddress = ILpLockDeployerInterface(lpLockDeployer).createLPLocker(
                storedLPAddress, 32503698000, "logo", IERC20(storedLPAddress).balanceOf(address(this)), owner()
            );
        }
        IMemeEventTracker(eventTracker).listEvent(
            msg.sender,
            memeToken,
            token.router,
            amountBase - LP_WBNB_exp_balance,
            amountTokenToAddLiq - tokenToSend,
            block.timestamp,
            token.pool.volume
        );
        emit listed(
            msg.sender,
            memeToken,
            token.router,
            amountBase - LP_WBNB_exp_balance,
            amountTokenToAddLiq - tokenToSend,
            block.timestamp,
            token.pool.volume
        );
    }

    function _swapEthToBase(address memeToken, address _baseAddress, uint256 _ethIN) internal returns (uint256) {
        _approve(memeToken, true);
        // generate the pair path of token -> weth
        uint256[] memory amountMinArr;
        address[] memory path = new address[](2);
        path[0] = getWrapAddr(memeToken);
        path[1] = _baseAddress;
        uint256 minBase = (getAmountsMinToken(memeToken, _baseAddress, _ethIN) * 90) / HUNDRED;

        amountMinArr = UniswapRouter02(tokenPools[memeToken].router).swapExactETHForTokens{value: _ethIN}(
            minBase, path, address(this), block.timestamp + 300
        );
        return amountMinArr[1];
    }

    function _approve(address memeToken, bool isBaseToken) internal returns (bool) {
        MemeTokenPool storage token = tokenPools[memeToken];
        IERC20 token_ = IERC20(memeToken);
        if (isBaseToken) {
            token_ = IERC20(token.baseToken);
        }

        if (token_.allowance(address(this), token.router) == 0) {
            token_.approve(token.router, type(uint256).max);
        }
        return true;
    }

    function _approveLock(address _lp, address _lockDeployer) internal returns (bool) {
        IERC20 lp_ = IERC20(_lp);
        if (lp_.allowance(address(this), _lockDeployer) == 0) {
            lp_.approve(_lockDeployer, type(uint256).max);
        }
        return true;
    }

    function _getpair(address memeToken, address _token1, address _token2) internal returns (address) {
        address router = tokenPools[memeToken].router;
        address factory = UniswapRouter02(router).factory();
        address pair = UniswapFactory(factory).getPair(_token1, _token2);
        if (pair != address(0)) {
            return pair;
        } else {
            return UniswapFactory(factory).createPair(_token1, _token2);
        }
    }

    function _isMemeToken(address memeToken) internal view returns (bool) {
        for (uint256 i = 0; i < userMemeTokens[msg.sender].length;) {
            if (memeToken == userMemeTokens[msg.sender][i]) {
                return true;
            }
            unchecked {
                i++;
            }
        }
        return false;
    }

    function lockTokens(address _user, address _memeContract, uint256 _newLockedDeadlineDays) public {
        require(msg.sender == _user || allowedDeployers[msg.sender], "unauthorized account");
        IMemeCoin(_memeContract).lockTokens(_user, _newLockedDeadlineDays);
        IMemeEventTracker(eventTracker).lockedDeadlineUpdatedEvent(_user, _memeContract, _newLockedDeadlineDays);
    }

    function addDeployer(address _deployer) public onlyOwner {
        allowedDeployers[_deployer] = true;
    }

    function removeDeployer(address _deployer) public onlyOwner {
        allowedDeployers[_deployer] = false;
    }

    function updateMemeSwap(address _newMemeSwap) public onlyOwner {
        require(_newMemeSwap != address(0), "Cannot be zero address");
        memeswap = _newMemeSwap;
    }

    function updateImplementation(address _implementation) public onlyOwner {
        require(_implementation != address(0));
        implementation = _implementation;
    }

    function updateFeeContract(address _newFeeContract) public onlyOwner {
        require(_newFeeContract != address(0), "Cannot be zero address");
        feeContract = _newFeeContract;
    }

    function updateLpLockDeployer(address _newLpLockDeployer) public onlyOwner {
        require(_newLpLockDeployer != address(0), "Cannot be zero address");
        lpLockDeployer = _newLpLockDeployer;
    }

    function updateEventTracker(address _newEventTracker) public onlyOwner {
        require(_newEventTracker != address(0), "Cannot be zero address");
        eventTracker = _newEventTracker;
    }

    function updateStableAddress(address _newStableAddress) public onlyOwner {
        require(_newStableAddress != address(0), "Cannot be zero address");
        stableAddress = _newStableAddress;
    }

    function updateTeamFeePer(uint16 _newFeePer) public onlyOwner {
        require(_newFeePer != 0, "Cannot be zero");
        feePer = _newFeePer;
    }

    function updateRewardPool(address _newRewardPool) public onlyOwner {
        require(_newRewardPool != address(0), "Cannot be zero address");
        rewardPool = _newRewardPool;
    }
}
