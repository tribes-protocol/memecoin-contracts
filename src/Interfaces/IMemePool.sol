// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMemePool {
    struct MemeTokenPoolData {
        uint256 reserveTokens;
        uint256 reserveETH;
        uint256 volume;
        uint256 listThreshold;
        uint256 initialReserveEth;
        uint8 nativePer;
        bool tradeActive;
        bool lpBurn;
        bool royalemitted;
    }

    struct MemeTokenPool {
        address creator;
        address token;
        address baseToken;
        address router;
        address lockerAddress;
        address storedLPAddress;
        address deployer;
        MemeTokenPoolData pool;
    }

    function createMeme(
        string[2] memory _name_symbol,
        uint256 _totalSupply,
        address _creator,
        address _baseToken,
        address _router,
        uint256[2] memory listThreshold_initReserveEth,
        bool lpBurn
    ) external payable returns (address);

    function buyTokens(address memeCoin, uint256 minTokens, address _affiliate, uint256 _lockedDeadlineDays)
        external
        payable;

    function sellTokens(address memeToken, uint256 tokenAmount, uint256 minEth, address _affiliate)
        external
        returns (bool, uint256);

    function rewardPool() external view returns (address);

    function memeswap() external view returns (address);

    function feeContract() external view returns (address);

    function feePer() external view returns (uint16);

    function getMemeTokenPool(address memeToken) external view returns (MemeTokenPool memory);

    function getAmountOutTokens(address memeToken, uint256 amountIn) external view returns (uint256 amountOut);

    function getAmountOutETH(address memeToken, uint256 amountIn) external view returns (uint256 amountOut);

    function lockTokens(address _user, address _memeContract, uint256 _newLockedDeadlineDays) external;
}
