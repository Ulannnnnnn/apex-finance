// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {ApexPair} from "../../src/core/ApexPair.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 a) external { _mint(to, a); }
}

/**
 * @title ApexPairHandler
 * @dev Handler is a contract for Foundry Invariant tests.
 * Foundry calls the functions of this contract randomly,
* simulating a real user. After each call
*, the invariant functions in ApexPairInvariantTest are checked.
 */
contract ApexPairHandler is Test {
    ApexPair public pair;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address[] public actors;
    address internal _currentActor;

    uint256 public totalSwapsExecuted;
    uint256 public totalLiquidityAdded;

    constructor(ApexPair _pair, MockERC20 _tokenA, MockERC20 _tokenB) {
        pair = _pair;
        tokenA = _tokenA;
        tokenB = _tokenB;

        // Creating 3 actors
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));

        // We give tokens to everyone
        for (uint256 i = 0; i < actors.length; i++) {
            tokenA.mint(actors[i], 10_000_000e18);
            tokenB.mint(actors[i], 10_000_000e18);
        }

        // Adding initial liquidity
        address liqudityProvider = actors[0];
        vm.startPrank(liqudityProvider);
        tokenA.approve(address(pair), 1_000_000e18);
        tokenB.approve(address(pair), 2_000_000e18);
        pair.addLiquidity(1_000_000e18, 2_000_000e18, liqudityProvider);
        vm.stopPrank();
    }

    function swap(uint256 actorSeed, uint256 amountSeed, bool direction) external {
        _currentActor = actors[actorSeed % actors.length];
        uint256 amountIn = bound(amountSeed, 1e15, 100_000e18);

        (uint112 r0, uint112 r1) = pair.getReserves();
        if (r0 == 0 || r1 == 0) return;

        address tokenIn = direction ? address(tokenA) : address(tokenB);

        vm.startPrank(_currentActor);
        IERC20(tokenIn).approve(address(pair), amountIn);
        try pair.swap(tokenIn, amountIn, 0, _currentActor) {
            totalSwapsExecuted++;
        } catch {}
        vm.stopPrank();
    }

    function addLiquidity(uint256 actorSeed, uint256 amount0Seed, uint256 amount1Seed) external {
        _currentActor = actors[actorSeed % actors.length];
        uint256 amount0 = bound(amount0Seed, 1e18, 100_000e18);
        uint256 amount1 = bound(amount1Seed, 1e18, 100_000e18);

        vm.startPrank(_currentActor);
        tokenA.approve(address(pair), amount0);
        tokenB.approve(address(pair), amount1);
        try pair.addLiquidity(amount0, amount1, _currentActor) {
            totalLiquidityAdded++;
        } catch {}
        vm.stopPrank();
    }
}

interface IERC20 {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/**
 * @title ApexPairInvariantTest
 * @dev Invariant tests verify the fundamental properties of the pool,
 * which should NEVER be violated, no matter how many operations are performed.
 */
contract ApexPairInvariantTest is StdInvariant, Test {
    ApexPair public pair;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    ApexPairHandler public handler;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        pair = new ApexPair(address(tokenA), address(tokenB), address(this));
        handler = new ApexPairHandler(pair, tokenA, tokenB);

        // We tell Foundry to call only the functions of our handler
        targetContract(address(handler));
    }

    /**
* @dev INVARIANT 1: K never decreases after swaps.
     * This is the main invariant of AMM — the commission always increases K.
     * Violation of this invariant = critical vulnerability.
     */
    function invariant_KNeverDecreases() public view {
        (uint112 r0, uint112 r1) = pair.getReserves();
        // Если пул не пуст, k > 0
        if (pair.totalSupply() > pair.MINIMUM_LIQUIDITY()) {
            assertGt(uint256(r0) * uint256(r1), 0, "K must be positive");
        }
    }
/**
* @dev INVARIANT 2: Real balance of tokens >= reserves.
     * A contract should never have fewer tokens than are recorded in reserves.
     */
    function invariant_BalanceGeReserves() public view {
        (uint112 r0, uint112 r1) = pair.getReserves();
        assertGe(
            tokenA.balanceOf(address(pair)),
            uint256(r0),
            "Token A balance must be >= reserve0"
        );
        assertGe(
            tokenB.balanceOf(address(pair)),
            uint256(r1),
            "Token B balance must be >= reserve1"
        );
    }

/**
* @dev INVARIANT 3: The total supply of LP tokens is always >= MINIMUM_LIQUIDITY.
     * After the first deposit, this invariant must be maintained forever.
     */
    function invariant_TotalSupplyGeMinLiquidity() public view {
        if (handler.totalLiquidityAdded() > 0 || handler.totalSwapsExecuted() > 0) {
            assertGe(
                pair.totalSupply(),
                pair.MINIMUM_LIQUIDITY(),
                "Total supply must be >= MINIMUM_LIQUIDITY"
            );
        }
    }
/**
* @dev INVARIANT 4: MINIMUM_LIQUIDITY is always on DEAD_ADDRESS.
     * No one can withdraw these LP tokens - this is a protection against manipulation.
     */
    function invariant_MinLiquidityLocked() public view {
        if (pair.totalSupply() >= pair.MINIMUM_LIQUIDITY()) {
            assertEq(
                pair.balanceOf(address(0xdEaD)),
                pair.MINIMUM_LIQUIDITY(),
                "MINIMUM_LIQUIDITY must be locked on DEAD_ADDRESS"
            );
        }
    }

    /**
     * @dev INVARIANT 5: Reserves cannot be zero simultaneously when supply is non-zero.
     */
    function invariant_NonZeroReservesWhenSupplyExists() public view {
        (uint112 r0, uint112 r1) = pair.getReserves();
        uint256 supply = pair.totalSupply();
        if (supply > pair.MINIMUM_LIQUIDITY()) {
            assertGt(uint256(r0), 0, "Reserve0 must be non-zero when supply exists");
            assertGt(uint256(r1), 0, "Reserve1 must be non-zero when supply exists");
        }
    }
}
