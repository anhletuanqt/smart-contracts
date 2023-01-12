// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract StableTokensPoolUpgradeable is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public multiSig;
    IERC20Upgradeable public tokenA;
    IERC20Upgradeable public tokenB;

    /// @dev 1 token A = 24000 token B
    uint256 public exchangeRate;
    uint256 public txFee; // 0.08 = 8
    uint256 public totalTokenAFee;
    uint256 public totalTokenBFee;
    uint256 public txIndex;

    // *** EVENTS *** //
    event TokenSwapped(
        address user,
        address fromToken,
        uint256 fromAmount,
        address recipient,
        address toToken,
        uint256 toAmount,
        uint256 txIndex,
        uint256 exchangeRate,
        uint256 txFee,
        uint256 feeAmount
    );

    event LiquidityAdded(address user, address tokenIn, uint256 amountIn);

    event LiquidityRemoved(
        address user,
        address to,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    );

    modifier onlyMultiSig() {
        require(isMultiSig(msg.sender), "Caller is not multi-sig wallet");
        _;
    }

    modifier ensureExchangeRate(uint256 _exchangeRate) {
        require(
            _exchangeRate == exchangeRate,
            "StableTokensPool: EXCHANGE_RATE_CHANGED"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function isMultiSig(address _account) public view returns (bool) {
        return multiSig == _account;
    }

    function initialize(
        address _tokenA,
        address _tokenB,
        address _multiSig
    ) public initializer {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        tokenA = IERC20Upgradeable(_tokenA);
        tokenB = IERC20Upgradeable(_tokenB);
        multiSig = _multiSig;

        exchangeRate = 24000;
        txFee = 8;
        txIndex = 1;
    }

    function addLiquidity(address tokenIn, uint256 amountIn)
        external
        whenNotPaused
    {
        IERC20Upgradeable erc20TokenIn = IERC20Upgradeable(tokenIn);

        require(amountIn > 0, "StableTokensPool: INVALID_AMOUNT");
        require(
            erc20TokenIn == tokenA || erc20TokenIn == tokenB,
            "StableTokensPool: INVALID_TOKEN"
        );
        // check allowance
        require(
            erc20TokenIn.allowance(msg.sender, address(this)) >= amountIn,
            "StableTokensPool: NOT_ALLOWANCE"
        );

        erc20TokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        emit LiquidityAdded(msg.sender, tokenIn, amountIn);
    }

    function removeLiquidity(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external onlyMultiSig whenNotPaused {
        require(amountA > 0 || amountB > 0, "StableTokensPool: INVALID_AMOUNT");
        require(
            tokenA.balanceOf(address(this)) >= amountA,
            "StableTokensPool: INSUFFICIENT_AMOUNT_A"
        );
        require(
            tokenB.balanceOf(address(this)) >= amountB,
            "StableTokensPool: INSUFFICIENT_AMOUNT_B"
        );

        // transfer tokens to user's wallet
        tokenA.safeTransfer(to, amountA);
        tokenB.safeTransfer(to, amountB);

        emit LiquidityRemoved(
            msg.sender,
            to,
            address(tokenA),
            amountA,
            address(tokenB),
            amountB
        );
    }

    function swap(
        uint256 amountIn,
        address tokenIn,
        address to,
        uint256 currentExchangeRate
    )
        external
        ensureExchangeRate(currentExchangeRate)
        whenNotPaused
        returns (uint256 amountOut, address tokenOut)
    {
        (amountOut, tokenOut, ) = _swap(
            amountIn,
            tokenIn,
            to,
            currentExchangeRate
        );
    }

    function swapWithPermit(
        uint256 amountIn,
        address tokenIn,
        address to,
        uint256 currentExchangeRate,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused returns (uint256 amountOut, address tokenOut) {
        IERC20PermitUpgradeable(tokenIn).permit(
            msg.sender,
            address(this),
            amountIn,
            deadline,
            v,
            r,
            s
        );

        (amountOut, tokenOut, ) = _swap(
            amountIn,
            tokenIn,
            to,
            currentExchangeRate
        );
    }

    function setExchangeRate(uint256 _exchangeRate) external onlyOwner {
        exchangeRate = _exchangeRate;
    }

    function setTxFee(uint256 _txFee) external onlyOwner {
        txFee = _txFee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawFee(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external onlyOwner {
        require(amountA > 0 || amountB > 0, "StableTokensPool: INVALID_AMOUNT");
        require(
            totalTokenAFee >= amountA && totalTokenBFee >= amountB,
            "StableTokensPool: INVALID_AMOUNT_FEE"
        );

        if (amountA > 0) {
            tokenA.safeTransfer(to, amountA);
        }
        if (amountB > 0) {
            tokenB.safeTransfer(to, amountB);
        }
    }

    function reserves()
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        amountA = tokenA.balanceOf(address(this));
        amountB = tokenB.balanceOf(address(this));
    }

    function getAmountOut(uint256 amountIn, address tokenIn)
        external
        view
        returns (
            uint256 amountOut,
            address tokenOut,
            uint256 totalFee
        )
    {
        return _getAmountOut(amountIn, tokenIn);
    }

    // *** PRIVATE FUNCTIONS *** //

    function _swap(
        uint256 amountIn,
        address tokenIn,
        address to,
        uint256 currentExchangeRate
    )
        private
        ensureExchangeRate(currentExchangeRate)
        returns (
            uint256 amountOut,
            address tokenOut,
            uint256 totalFee
        )
    {
        (amountOut, tokenOut, totalFee) = _getAmountOut(amountIn, tokenIn);

        IERC20Upgradeable(tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            amountIn
        );
        IERC20Upgradeable(tokenOut).safeTransfer(to, amountOut);

        if (tokenIn == address(tokenA)) {
            totalTokenAFee += totalFee;
        } else {
            totalTokenBFee += totalFee;
        }
        txIndex += 1;

        emit TokenSwapped(
            msg.sender,
            tokenIn,
            amountIn,
            to,
            tokenOut,
            amountOut,
            txIndex,
            exchangeRate,
            txFee,
            totalFee
        );
    }

    function _getAmountOut(uint256 amountIn, address tokenIn)
        private
        view
        returns (
            uint256 amountOut,
            address tokenOut,
            uint256 totalFee
        )
    {
        IERC20Upgradeable erc20TokenIn = IERC20Upgradeable(tokenIn);

        require(amountIn > 0, "StableTokensPool: INSUFFICIENT_AMOUNT_IN");
        require(
            erc20TokenIn == tokenA || erc20TokenIn == tokenB,
            "StableTokensPool: INVALID_TOKEN"
        );

        require(amountIn > 0, "StableTokensPool: INVALID_AMOUNT");
        totalFee = (amountIn * txFee) / 10000;
        uint256 amountInWithFee = amountIn - totalFee;

        if (erc20TokenIn == tokenA) {
            amountOut = amountInWithFee * exchangeRate;
            tokenOut = address(tokenB);
        } else {
            amountOut = amountInWithFee / exchangeRate;
            tokenOut = address(tokenA);
        }

        require(
            IERC20Upgradeable(tokenOut).balanceOf(address(this)) >= amountOut,
            "StableTokensPool: INSUFFICIENT_AMOUNT_OUT"
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
