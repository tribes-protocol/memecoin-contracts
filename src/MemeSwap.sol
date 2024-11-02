// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IUniswapRouter02.sol";
import "./Interfaces/IERC20.sol";
import {IMemePool} from "./Interfaces/IMemePool.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MemeSwap is Ownable, ReentrancyGuard {
    event EthWithdrawn(address indexed owner, uint256 amount);
    event ERC20Withdrawal(address indexed recipient, address indexed memeCoinAddress, uint256 amount);
    event MemeSwapEvent(
        address indexed user,
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    UniswapRouter02 public uniswapRouter;
    IMemePool public memePool;

    uint256 public constant BASIS_POINTS = 10000;
    uint16 public uniswapFeePer = 175; // 1.75%

    constructor(address _uniswapRouter, address _memePool) Ownable(msg.sender) {
        uniswapRouter = UniswapRouter02(_uniswapRouter);
        memePool = IMemePool(_memePool);
    }

    function swap(address fromToken, address toToken, uint256 amountIn, uint256 minAmountOut, address _affiliate)
        public
    {
        require(amountIn > 0, "Invalid input amount");

        address feeContract = memePool.feeContract();
        require(feeContract != address(0), "Fee contract not set");
        require(fromToken != toToken, "Cannot swap to the same token");
        require(fromToken != address(0) && toToken != address(0), "Cannot be zero address");

        bool fromMemePool = memePool.getMemeTokenPool(fromToken).pool.tradeActive;
        bool toMemePool = memePool.getMemeTokenPool(toToken).pool.tradeActive;
        uint256 tokensReceived;

        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);

        // From MemePool to MemePool
        if (fromMemePool && toMemePool) {
            IERC20(fromToken).approve(address(memePool), amountIn);

            (bool success, uint256 amountOutETH) = memePool.sellTokens(fromToken, amountIn, 0, _affiliate);
            require(success, "Sell failed");

            memePool.buyTokens{value: amountOutETH}(toToken, minAmountOut, _affiliate, 0);

            tokensReceived = IERC20(toToken).balanceOf(address(this));
            IERC20(toToken).transfer(msg.sender, tokensReceived);
        }
        // From MemePool to Uniswap
        else if (fromMemePool) {
            IERC20(fromToken).approve(address(memePool), amountIn);

            (bool success, uint256 amountOutReceived) = memePool.sellTokens(fromToken, amountIn, 0, _affiliate);
            require(success, "Sell failed");

            uint256 uniswapFee = (amountOutReceived * uniswapFeePer) / BASIS_POINTS;

            (bool successFee,) = feeContract.call{value: uniswapFee}(""); // paying plat fee
            require(successFee, "fee ETH transfer failed");

            uint256 amountToSwap = amountOutReceived - uniswapFee;

            address[] memory path = new address[](2);
            path[0] = uniswapRouter.WETH();
            path[1] = toToken;

            uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{value: amountToSwap}(
                minAmountOut, path, msg.sender, block.timestamp + 300
            );
            tokensReceived = amounts[amounts.length - 1];
        }
        // From Uniswap to MemePool
        else if (toMemePool) {
            IERC20(fromToken).approve(address(uniswapRouter), amountIn);

            address[] memory path = new address[](2);
            path[0] = fromToken;
            path[1] = uniswapRouter.WETH();

            uint256[] memory amounts =
                uniswapRouter.swapExactTokensForETH(amountIn, 0, path, address(this), block.timestamp + 300);
            uint256 ethReceived = amounts[amounts.length - 1];

            uint256 uniswapFee = (ethReceived * uniswapFeePer) / BASIS_POINTS;

            (bool successFee,) = feeContract.call{value: uniswapFee}(""); // paying plat fee
            require(successFee, "fee ETH transfer failed");

            uint256 amountToSend = ethReceived - uniswapFee;

            memePool.buyTokens{value: amountToSend}(toToken, minAmountOut, _affiliate, 0);

            tokensReceived = IERC20(toToken).balanceOf(address(this));
            IERC20(toToken).transfer(msg.sender, tokensReceived);
        }
        // From Uniswap to Uniswap
        else {
            IERC20(fromToken).approve(address(uniswapRouter), amountIn);

            address[] memory pathToEth = new address[](2);
            pathToEth[0] = fromToken;
            pathToEth[1] = uniswapRouter.WETH();

            uint256[] memory amountsEth =
                uniswapRouter.swapExactTokensForETH(amountIn, 0, pathToEth, address(this), block.timestamp + 300);
            uint256 ethReceived = amountsEth[amountsEth.length - 1];

            uint256 uniswapFee = (ethReceived * uniswapFeePer) / BASIS_POINTS;
            (bool successFee,) = feeContract.call{value: uniswapFee}("");
            require(successFee, "fee ETH transfer failed");

            uint256 amountToSend = ethReceived - uniswapFee;
            address[] memory pathFromEth = new address[](2);
            pathFromEth[0] = uniswapRouter.WETH();
            pathFromEth[1] = toToken;

            uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{value: amountToSend}(
                minAmountOut, pathFromEth, msg.sender, block.timestamp + 300
            );
            tokensReceived = amounts[amounts.length - 1];
        }

        emit MemeSwapEvent(msg.sender, fromToken, toToken, amountIn, tokensReceived, block.timestamp);
    }

    function estimateSwap(address fromToken, address toToken, uint256 amountIn)
        public
        view
        returns (uint256 estimatedAmountOut)
    {
        require(amountIn > 0, "Invalid input amount");
        require(fromToken != toToken, "Cannot swap to the same token");
        require(fromToken != address(0) && toToken != address(0), "Cannot be zero address");

        bool fromMemePool = memePool.getMemeTokenPool(fromToken).pool.tradeActive;
        bool toMemePool = memePool.getMemeTokenPool(toToken).pool.tradeActive;

        // From MemePool to MemePool
        if (fromMemePool && toMemePool) {
            uint256 estimatedEthReceived = memePool.getAmountOutETH(fromToken, amountIn);
            uint256 fee = (estimatedEthReceived * memePool.feePer()) / BASIS_POINTS;
            estimatedAmountOut = memePool.getAmountOutTokens(toToken, estimatedEthReceived - (fee * 2));
        }
        // From MemePool to Uniswap
        else if (fromMemePool) {
            uint256 estimatedEthReceived = memePool.getAmountOutETH(fromToken, amountIn);
            uint256 fee = (estimatedEthReceived * memePool.feePer()) / BASIS_POINTS;
            uint256 uniswapFee = ((estimatedEthReceived - fee) * uniswapFeePer) / BASIS_POINTS;

            address[] memory path = new address[](2);
            path[0] = uniswapRouter.WETH();
            path[1] = toToken;

            uint256[] memory amounts = uniswapRouter.getAmountsOut(estimatedEthReceived - uniswapFee - fee, path);
            estimatedAmountOut = amounts[amounts.length - 1];
        }
        // From Uniswap to MemePool
        else if (toMemePool) {
            address[] memory path = new address[](2);
            path[0] = fromToken;
            path[1] = uniswapRouter.WETH();

            uint256[] memory amounts = uniswapRouter.getAmountsOut(amountIn, path);
            uint256 estimatedEthReceived = amounts[amounts.length - 1];
            uint256 uniswapFee = (estimatedEthReceived * uniswapFeePer) / BASIS_POINTS;
            uint256 fee = ((estimatedEthReceived - uniswapFee) * memePool.feePer()) / BASIS_POINTS;
            estimatedAmountOut = memePool.getAmountOutTokens(toToken, estimatedEthReceived - uniswapFee - fee);
        }
        // From Uniswap to Uniswap
        else {
            address[] memory path = new address[](2);
            path[0] = fromToken;
            path[1] = uniswapRouter.WETH();

            uint256[] memory amounts = uniswapRouter.getAmountsOut(amountIn, path);
            uint256 estimatedEthReceived = amounts[amounts.length - 1];
            uint256 uniswapFee = (estimatedEthReceived * uniswapFeePer) / BASIS_POINTS;

            path = new address[](2);
            path[0] = uniswapRouter.WETH();
            path[1] = toToken;

            amounts = uniswapRouter.getAmountsOut(estimatedEthReceived - uniswapFee, path);
            estimatedAmountOut = amounts[amounts.length - 1];
        }

        return estimatedAmountOut;
    }

    function updateUniswapRouter(address _uniswapRouter) public onlyOwner {
        require(_uniswapRouter != address(0), "Cannot be zero address");
        uniswapRouter = UniswapRouter02(_uniswapRouter);
    }

    function updateMemePool(address _memePool) public onlyOwner {
        require(_memePool != address(0), "Cannot be zero address");
        memePool = IMemePool(_memePool);
    }

    // Function to receive ETH
    receive() external payable {}

    function withdrawEth() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");

        emit EthWithdrawn(owner(), balance);
    }

    function withdrawERC20s(address[] memory recipients, address[] memory memecoinAddresses, uint256[] memory amounts)
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

            IERC20(memecoin).transfer(recipient, amount);

            emit ERC20Withdrawal(recipient, memecoin, amount);
        }
    }

    function updateUniswapFeePer(uint16 _uniswapFeePer) public onlyOwner {
        uniswapFeePer = _uniswapFeePer;
    }
}
