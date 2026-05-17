// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ApexPair
 * @dev Custom AMM 
 *
 * Implements:
* - Constant product formula: x * y = k
* - Fixed LP commission: 0.3% (997/1000)
* - Slippage protection via minAmountOut
 * - LP tokens
* - Critical sqrt() function optimized for Yul
* - ReentrancyGuard for all recording functions
* - Checks-Effects-Interactions pattern
*
* Patterns: Factory, Checks-Effects-Interactions, Reentrancy Guard
 */
contract ApexPair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    /// @dev Commission numerator: 997/1000 = 0.3% LP commission
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    /// @dev Minimum liquidity, burned forever on first deposit (protection against attacks on empty pool)
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    /// @dev Address of the "zero" wallet to which MINIMUM_LIQUIDITY is burned
    address public constant DEAD_ADDRESS = address(0xdEaD);

    // Storage
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    /// @dev Current reserves of the pool (synchronized at the end of each transaction)
    uint112 private _reserve0;
    uint112 private _reserve1;

    /// @dev Chainlink Price Feed for token0/token1 
    address public priceFeed;
  
    // Events
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // Constructor
    constructor(address _token0, address _token1, address _factory)
        ERC20("Apex LP Token", "APEX-LP")
    {
        require(_token0 != _token1, "ApexPair: IDENTICAL_TOKENS");
        require(_token0 != address(0) && _token1 != address(0), "ApexPair: ZERO_ADDRESS");
        token0 = _token0;
        token1 = _token1;
        factory = _factory;
    }

    // View functions
    /// @dev Returns the current reserves of the pool
    function getReserves() public view returns (uint112 reserve0, uint112 reserve1) {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    // Yul-optimized sqrt
    /**
     * @dev Calculates the square root using the Babylonian method (iterative).
     */
    function sqrt(uint256 y) public pure returns (uint256 z) {
        assembly {
            // If y > 3, we run iterations of the Babylonian method.
            if gt(y, 3) {
                // Initial approximation: z = y
                z := y
                // x = y / 2 + 1
                let x := add(div(y, 2), 1)
                // Loop: while x < z, update z = x, x = (y/x + x) / 2
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, x), x), 2)
                }
            }
            // If y == 1, 2 or 3 — z = 1
            if and(gt(y, 0), lt(y, 4)) { z := 1 }
            // If y == 0 — z remains 0 (default)
        }
    }

    /**
     * @dev 
     */
    function sqrtPureSolidity(uint256 y) public pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // AMM Core: getAmountOut
    /**
     * @dev Calculates the amount of output token for a given input amount.
     * Implements the AMM formula with a 0.3% fee:
     *   amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "ApexPair: INSUFFICIENT_INPUT");
        require(reserveIn > 0 && reserveOut > 0, "ApexPair: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // Liquidity: addLiquidity
    /**
     * @dev Adds liquidity to the pool.
     * Pattern: Checks-Effects-Interactions
     *
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param to Recipient of LP tokens
     * @return liquidity Quantity of issued LP tokens
     */
    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        // CHECKS
        require(amount0Desired > 0 && amount1Desired > 0, "ApexPair: INSUFFICIENT_INPUT_AMOUNTS");
        require(to != address(0), "ApexPair: ZERO_ADDRESS");

        uint256 totalSupply_ = totalSupply();
        uint256 amount0 = amount0Desired;
        uint256 amount1 = amount1Desired;

        // EFFECTS — calculating how many lps to release
        if (totalSupply_ == 0) {
            // First deposit: we issue sqrt(amount0 * amount1) LP tokens
            // Minus MINIMUM_LIQUIDITY, which are burned forever
            uint256 liquidityRaw = sqrt(amount0 * amount1);
            require(liquidityRaw > MINIMUM_LIQUIDITY, "ApexPair: INSUFFICIENT_INITIAL_LIQUIDITY");
            liquidity = liquidityRaw - MINIMUM_LIQUIDITY;
            // Burning MINIMUM_LIQUIDITY on DEAD_ADDRESS (protection against manipulation)
            _mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        } else {
            // Subsequent deposits: proportional to current reserves
            uint256 liquidity0 = (amount0 * totalSupply_) / _reserve0;
            uint256 liquidity1 = (amount1 * totalSupply_) / _reserve1;
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }

        require(liquidity > 0, "ApexPair: INSUFFICIENT_LIQUIDITY_MINTED");

        // Updating reserves BEFORE external calls
        _reserve0 += uint112(amount0);
        _reserve1 += uint112(amount1);

        // Minting LP tokens to the recipient
        _mint(to, liquidity);

        // INTERACTIONS — transferring tokens from the user to the pool
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        emit Mint(msg.sender, amount0, amount1);
        emit Sync(_reserve0, _reserve1);
    }

    // Liquidity: removeLiquidity
    /**
     * @dev Removes liquidity from the pool.
     * Pattern: Checks-Effects-Interactions
     *
     * @param liquidity Quantity of LP tokens to burn
     * @param minAmount0 Minimum amount of token0 (slippage protection)
     * @param minAmount1 Minimum amount of token1 (slippage protection)
     * @param to Recipient of tokens
     */
    function removeLiquidity(uint256 liquidity, uint256 minAmount0, uint256 minAmount1, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        // CHECKS
        require(liquidity > 0, "ApexPair: INSUFFICIENT_LIQUIDITY");
        require(to != address(0), "ApexPair: ZERO_ADDRESS");
        require(balanceOf(msg.sender) >= liquidity, "ApexPair: INSUFFICIENT_LP_BALANCE");

        uint256 totalSupply_ = totalSupply();

        // EFFECTS — calculating amounts to return
        amount0 = (liquidity * _reserve0) / totalSupply_;
        amount1 = (liquidity * _reserve1) / totalSupply_;

        // Slippage protection
        require(amount0 >= minAmount0, "ApexPair: INSUFFICIENT_TOKEN0_AMOUNT");
        require(amount1 >= minAmount1, "ApexPair: INSUFFICIENT_TOKEN1_AMOUNT");

        // Burning LP tokens and updating reserves
        _burn(msg.sender, liquidity);
        _reserve0 -= uint112(amount0);
        _reserve1 -= uint112(amount1);

        // INTERACTIONS — sending tokens to the user
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        emit Burn(msg.sender, amount0, amount1, to);
        emit Sync(_reserve0, _reserve1);
    }

    // Swap
    /**
     * @dev Swaps token0 for token1 (or vice versa).
     * Pattern: Checks-Effects-Interactions, ReentrancyGuard
     *
     * @param tokenIn Address of the input token (must be token0 or token1)
     * @param amountIn Quantity of the input token
     * @param minAmountOut Minimum expected output (slippage protection)
     * @param to Recipient of the output token
     * @return amountOut Actual quantity of the output token
     */
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        // CHECKS
        require(tokenIn == token0 || tokenIn == token1, "ApexPair: INVALID_TOKEN");
        require(amountIn > 0, "ApexPair: INSUFFICIENT_INPUT");
        require(to != address(0), "ApexPair: ZERO_ADDRESS");
        require(_reserve0 > 0 && _reserve1 > 0, "ApexPair: NO_LIQUIDITY");

        bool isToken0In = tokenIn == token0;
        (uint256 reserveIn, uint256 reserveOut) = isToken0In
            ? (uint256(_reserve0), uint256(_reserve1))
            : (uint256(_reserve1), uint256(_reserve0));

        address tokenOut = isToken0In ? token1 : token0;

        // Calculate output amount considering the 0.3% fee
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        // Slippage protection
        require(amountOut >= minAmountOut, "ApexPair: SLIPPAGE_EXCEEDED");
        require(amountOut < reserveOut, "ApexPair: INSUFFICIENT_LIQUIDITY");

        // EFFECTS — update reserves BEFORE external calls
        if (isToken0In) {
            _reserve0 += uint112(amountIn);
            _reserve1 -= uint112(amountOut);
        } else {
            _reserve1 += uint112(amountIn);
            _reserve0 -= uint112(amountOut);
        }

        // INTERACTIONS — transferring tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(to, amountOut);

        emit Swap(
            msg.sender,
            isToken0In ? amountIn : 0,
            isToken0In ? 0 : amountIn,
            isToken0In ? 0 : amountOut,
            isToken0In ? amountOut : 0,
            to
        );
        emit Sync(_reserve0, _reserve1);
    }

    // Sync (forced synchronization of reserves with the real balance)
    /// @dev Forces synchronization of reserves with the actual contract balance.
    /// Used when tokens are sent directly to the contract (not through swap).
    function sync() external nonReentrant {
        _reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        emit Sync(_reserve0, _reserve1);
    }
}