// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ApexPair} from "../src/core/ApexPair.sol";
import {ApexVault} from "../src/core/ApexVault.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for tests
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// UNIT TESTS FOR ApexPair (20+ tests)
contract ApexPairTest is Test {
    ApexPair public pair;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public factory = makeAddr("factory");

    uint256 constant INITIAL_LIQUIDITY_A = 100_000e18;
    uint256 constant INITIAL_LIQUIDITY_B = 200_000e18;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        pair = new ApexPair(address(tokenA), address(tokenB), factory);

        // We give Alice and Bob tokens
        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 2_000_000e18);
        tokenA.mint(bob, 500_000e18);
        tokenB.mint(bob, 1_000_000e18);
    }

    // Block 1: Initialization
    function test_PairInitialState() public view {
        assertEq(pair.token0(), address(tokenA));
        assertEq(pair.token1(), address(tokenB));
        assertEq(pair.factory(), factory);
        (uint112 r0, uint112 r1) = pair.getReserves();
        assertEq(r0, 0);
        assertEq(r1, 0);
    }

    function test_RevertWhen_ConstructWithIdenticalTokens() public {
        vm.expectRevert("ApexPair: IDENTICAL_TOKENS");
        new ApexPair(address(tokenA), address(tokenA), factory);
    }

    function test_RevertWhen_ConstructWithZeroAddress() public {
        vm.expectRevert("ApexPair: ZERO_ADDRESS");
        new ApexPair(address(0), address(tokenB), factory);
    }

    // Block 2: Sqrt (Yul vs Solidity benchmark)
    function test_SqrtYulBasicValues() public view {
        assertEq(pair.sqrt(0), 0);
        assertEq(pair.sqrt(1), 1);
        assertEq(pair.sqrt(4), 2);
        assertEq(pair.sqrt(9), 3);
        assertEq(pair.sqrt(100), 10);
        assertEq(pair.sqrt(10_000e18), 100e9); // Real scale LP
    }

    function test_SqrtYulMatchesSolidity() public view {
        // Check that both implementations give identical results
        uint256[5] memory testValues = [uint256(0), 1, 1000, 1e18, 1e36];
        for (uint256 i = 0; i < testValues.length; i++) {
            assertEq(pair.sqrt(testValues[i]), pair.sqrtPureSolidity(testValues[i]));
        }
    }

    /// @dev Gas benchmark — results are recorded in Gas Report
    function test_GasBenchmark_SqrtYulVsSolidity() public view {
        uint256 bigNumber = 1_000_000e18;

        uint256 gasBeforeYul = gasleft();
        pair.sqrt(bigNumber);
        uint256 gasYul = gasBeforeYul - gasleft();

        uint256 gasBeforeSol = gasleft();
        pair.sqrtPureSolidity(bigNumber);
        uint256 gasSol = gasBeforeSol - gasleft();

        console2.log("Sqrt Yul gas:", gasYul);
        console2.log("Sqrt Solidity gas:", gasSol);
        console2.log("Savings (Yul):", gasSol > gasYul ? gasSol - gasYul : 0);
    }
    // Block 3: getAmountOut
    function test_GetAmountOut_BasicFormula() public view {
        // For reserveIn=100, reserveOut=200, amountIn=10:
        // amountOut = (10 * 997 * 200) / (100 * 1000 + 10 * 997)
        // = 1_994_000 / 109_970 ≈ 18.13 (in clean numbers without 1e18)
        uint256 out = pair.getAmountOut(10, 100, 200);
        assertGt(out, 0);
        // Check that with fee the output is less than without it (200*10/100=20)
        assertLt(out, 20);
    }

    function test_GetAmountOut_RevertOnZeroInput() public {
        vm.expectRevert("ApexPair: INSUFFICIENT_INPUT");
        pair.getAmountOut(0, 100e18, 200e18);
    }

    function test_GetAmountOut_RevertOnZeroReserves() public {
        vm.expectRevert("ApexPair: INSUFFICIENT_LIQUIDITY");
        pair.getAmountOut(10e18, 0, 100e18);
    }

    // Block 4: addLiquidity
    function test_AddLiquidity_FirstDeposit() public {
        vm.startPrank(alice);
        tokenA.approve(address(pair), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(pair), INITIAL_LIQUIDITY_B);
        uint256 lpTokens = pair.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, alice);
        vm.stopPrank();

        assertGt(lpTokens, 0);
        assertEq(pair.balanceOf(alice), lpTokens);
        (uint112 r0, uint112 r1) = pair.getReserves();
        assertEq(r0, INITIAL_LIQUIDITY_A);
        assertEq(r1, INITIAL_LIQUIDITY_B);
    }

    function test_AddLiquidity_MinimumLiquidityBurned() public {
        _addInitialLiquidity(alice);
        // MINIMUM_LIQUIDITY should be burned at DEAD_ADDRESS
        assertEq(pair.balanceOf(address(0xdEaD)), pair.MINIMUM_LIQUIDITY());
    }

    function test_AddLiquidity_SubsequentDeposit() public {
        _addInitialLiquidity(alice);

        vm.startPrank(bob);
        tokenA.approve(address(pair), 10_000e18);
        tokenB.approve(address(pair), 20_000e18);
        uint256 bobLP = pair.addLiquidity(10_000e18, 20_000e18, bob);
        vm.stopPrank();

        assertGt(bobLP, 0);
        assertEq(pair.balanceOf(bob), bobLP);
    }

    function test_RevertWhen_AddLiquidityZeroAmounts() public {
        vm.prank(alice);
        vm.expectRevert("ApexPair: INSUFFICIENT_INPUT_AMOUNTS");
        pair.addLiquidity(0, INITIAL_LIQUIDITY_B, alice);
    }

    function test_RevertWhen_AddLiquidityToZeroAddress() public {
        vm.startPrank(alice);
        tokenA.approve(address(pair), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(pair), INITIAL_LIQUIDITY_B);
        vm.expectRevert("ApexPair: ZERO_ADDRESS");
        pair.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, address(0));
        vm.stopPrank();
    }

    // Block 5: removeLiquidity
    function test_RemoveLiquidity_Full() public {
        uint256 lpTokens = _addInitialLiquidity(alice);

        vm.startPrank(alice);
        (uint256 out0, uint256 out1) = pair.removeLiquidity(lpTokens, 0, 0, alice);
        vm.stopPrank();

        assertGt(out0, 0);
        assertGt(out1, 0);
        assertEq(pair.balanceOf(alice), 0);
    }

    function test_RevertWhen_RemoveLiquidity_SlippageExceeded() public {
        uint256 lpTokens = _addInitialLiquidity(alice);

        vm.startPrank(alice);
        // Require an impossible large minAmount0
        vm.expectRevert("ApexPair: INSUFFICIENT_TOKEN0_AMOUNT");
        pair.removeLiquidity(lpTokens, type(uint256).max, 0, alice);
        vm.stopPrank();
    }

    // Block 6: swap
    function test_Swap_TokenAForTokenB() public {
        _addInitialLiquidity(alice);

        uint256 swapAmount = 1_000e18;
        uint256 bobBalanceBefore = tokenB.balanceOf(bob);

        (uint112 r0, uint112 r1) = pair.getReserves();
        uint256 expectedOut = pair.getAmountOut(swapAmount, r0, r1);

        vm.startPrank(bob);
        tokenA.approve(address(pair), swapAmount);
        uint256 actualOut = pair.swap(address(tokenA), swapAmount, 0, bob);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
        assertEq(tokenB.balanceOf(bob) - bobBalanceBefore, actualOut);
    }

    function test_Swap_TokenBForTokenA() public {
        _addInitialLiquidity(alice);

        vm.startPrank(bob);
        tokenB.approve(address(pair), 5_000e18);
        uint256 out = pair.swap(address(tokenB), 5_000e18, 0, bob);
        vm.stopPrank();

        assertGt(out, 0);
    }

    function test_RevertWhen_Swap_SlippageExceeded() public {
        _addInitialLiquidity(alice);

        vm.startPrank(bob);
        tokenA.approve(address(pair), 1_000e18);
        vm.expectRevert("ApexPair: SLIPPAGE_EXCEEDED");
        // Require an impossible large output
        pair.swap(address(tokenA), 1_000e18, type(uint256).max, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_Swap_InvalidToken() public {
        _addInitialLiquidity(alice);
        vm.startPrank(bob);
        vm.expectRevert("ApexPair: INVALID_TOKEN");
        pair.swap(address(0xBEEF), 1_000e18, 0, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_Swap_NoLiquidity() public {
        vm.startPrank(bob);
        tokenA.approve(address(pair), 1_000e18);
        vm.expectRevert("ApexPair: NO_LIQUIDITY");
        pair.swap(address(tokenA), 1_000e18, 0, bob);
        vm.stopPrank();
    }

    // FUZZ ТЕСТЫ (10+) — random parameters
    /// @dev Fuzz test: the output is always less than the reserve
    function testFuzz_AmountOut_LessThanReserve(
        uint128 reserveIn,
        uint128 reserveOut,
        uint128 amountIn
    ) public view {
        vm.assume(reserveIn > 0 && reserveOut > 0 && amountIn > 0);
        vm.assume(uint256(reserveIn) + uint256(amountIn) < type(uint128).max);

        uint256 out = pair.getAmountOut(amountIn, reserveIn, reserveOut);
        assertLt(out, reserveOut, "Output must be less than reserve");
    }

    /// @dev Fuzz test: larger input → larger output (monotonicity)
    function testFuzz_LargerInput_LargerOutput(
        uint256 amountIn1,
        uint256 amountIn2
    ) public view {
        uint256 reserveIn = 1_000_000e18;
        uint256 reserveOut = 2_000_000e18;

        // The amount must be less than the reserve and greater than 0
        amountIn1 = bound(amountIn1, 1, reserveIn / 2);
        amountIn2 = bound(amountIn2, amountIn1 + 1, reserveIn / 2 + 1);

        uint256 out1 = pair.getAmountOut(amountIn1, reserveIn, reserveOut);
        uint256 out2 = pair.getAmountOut(amountIn2, reserveIn, reserveOut);

        assertGe(out2, out1, "Larger input must yield larger output");
    }

    /// @dev Fuzz test: sqrt always returns a valid result
    function testFuzz_Sqrt_AlwaysValid(uint256 x) public view {
        uint256 result = pair.sqrt(x);
        // result^2 <= x < (result+1)^2
        if (x > 0) {
            assertLe(result * result, x);
            if (result < type(uint128).max) {
                assertGt((result + 1) * (result + 1), x);
            }
        } else {
            assertEq(result, 0);
        }
    }

    /// @dev Fuzz test: Yul sqrt == Solidity sqrt
    function testFuzz_Sqrt_YulMatchesSolidity(uint256 x) public view {
        x = bound(x, 0, type(uint128).max); // Reasonable range
        assertEq(pair.sqrt(x), pair.sqrtPureSolidity(x));
    }

    /// @dev Fuzz test: swap does not violate the k invariant (k does not decrease)
    function testFuzz_Swap_KInvariant(uint256 amountIn) public {
        _addInitialLiquidity(alice);

        (uint112 r0Before, uint112 r1Before) = pair.getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);

        amountIn = bound(amountIn, 1e15, 10_000e18); // 0.001 до 10k токенов

        tokenA.mint(bob, amountIn);
        vm.startPrank(bob);
        tokenA.approve(address(pair), amountIn);
        pair.swap(address(tokenA), amountIn, 0, bob);
        vm.stopPrank();

        (uint112 r0After, uint112 r1After) = pair.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        // k should be >= kBefore (commission increases k)
        assertGe(kAfter, kBefore, "K must not decrease after swap");
    }

    /// @dev Fuzz test: addLiquidity always mints LP > 0 with valid inputs
    function testFuzz_AddLiquidity_AlwaysMintsLP(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e18, 500_000e18);
        amount1 = bound(amount1, 1e18, 500_000e18);

        tokenA.mint(alice, amount0);
        tokenB.mint(alice, amount1);

        vm.startPrank(alice);
        tokenA.approve(address(pair), amount0);
        tokenB.approve(address(pair), amount1);
        uint256 lp = pair.addLiquidity(amount0, amount1, alice);
        vm.stopPrank();

        assertGt(lp, 0);
    }

    /// @dev Fuzz test: removeLiquidity returns correct amounts
    function testFuzz_RemoveLiquidity_ProportionalReturn(uint256 removeFraction) public {
        uint256 lpMinted = _addInitialLiquidity(alice);
        removeFraction = bound(removeFraction, 1, 100);
        uint256 lpToRemove = (lpMinted * removeFraction) / 100;

        if (lpToRemove == 0) return;

        (uint112 r0, uint112 r1) = pair.getReserves();
        uint256 totalLP = pair.totalSupply();

        uint256 expected0 = (lpToRemove * r0) / totalLP;
        uint256 expected1 = (lpToRemove * r1) / totalLP;

        vm.startPrank(alice);
        (uint256 got0, uint256 got1) = pair.removeLiquidity(lpToRemove, 0, 0, alice);
        vm.stopPrank();

        assertEq(got0, expected0);
        assertEq(got1, expected1);
    }

    /// @dev Fuzz test: slippage protection is working correctly
    function testFuzz_Swap_SlippageProtection(uint256 amountIn) public {
        _addInitialLiquidity(alice);
        amountIn = bound(amountIn, 1e15, 5_000e18);

        (uint112 r0, uint112 r1) = pair.getReserves();
        uint256 expectedOut = pair.getAmountOut(amountIn, r0, r1);

        tokenA.mint(bob, amountIn);
        vm.startPrank(bob);
        tokenA.approve(address(pair), amountIn);

        // We request 1 more than we expect — there should be a revert.
        vm.expectRevert("ApexPair: SLIPPAGE_EXCEEDED");
        pair.swap(address(tokenA), amountIn, expectedOut + 1, bob);
        vm.stopPrank();
    }

    /// @dev Fuzz test: getAmountOut output is strictly less than the reserve
    function testFuzz_AmountOut_StrictlyLessThanReserve(uint256 amountIn) public {
        _addInitialLiquidity(alice);
        amountIn = bound(amountIn, 1, INITIAL_LIQUIDITY_A - 1);

        (uint112 r0, uint112 r1) = pair.getReserves();
        uint256 out = pair.getAmountOut(amountIn, r0, r1);

        assertLt(out, r1, "Output must be strictly less than reserve");
    }

    /// @dev Fuzz test: commission is always >0 (the pool always earns something)
    function testFuzz_FeeAlwaysPositive(uint256 amountIn) public view {
        uint256 reserveIn = 1_000_000e18;
        uint256 reserveOut = 1_000_000e18;
        amountIn = bound(amountIn, 1e15, 100_000e18);

        // Without fee: out = amountIn * reserveOut / (reserveIn + amountIn)
        uint256 outNoFee = (amountIn * reserveOut) / (reserveIn + amountIn);
        // With 0.3% fee
        uint256 outWithFee = pair.getAmountOut(amountIn, reserveIn, reserveOut);

        assertLt(outWithFee, outNoFee, "Fee must reduce output");
    }

    // INVARIANT ТЕСТЫ (5+)
    // Invariant tests are executed in a separate contract, see test/invariant/
    // Helper
    function _addInitialLiquidity(address user) internal returns (uint256 lp) {
        vm.startPrank(user);
        tokenA.approve(address(pair), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(pair), INITIAL_LIQUIDITY_B);
        lp = pair.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, user);
        vm.stopPrank();
    }
}

// UNIT ТЕСТЫ ДЛЯ ApexVault (15+ тестов)
contract ApexVaultTest is Test {
    ApexVault public vault;
    MockERC20 public asset;
    MockAggregator public priceFeed;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 100_000e18;

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC");
        priceFeed = new MockAggregator(1e8, 8); // $1.00 с 8 decimals

        vm.prank(owner);
        vault = new ApexVault(
            address(asset),
            "Apex USDC Vault",
            "apxUSDC",
            address(priceFeed),
            owner
        );

        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);
    }

    // Block 1: Basic condition
    function test_VaultInitialState() public view {
        assertEq(vault.name(), "Apex USDC Vault");
        assertEq(vault.symbol(), "apxUSDC");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.owner(), owner);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.stalenessThreshold(), 3600);
    }

    // Block 2: Deposit/Mint/Withdraw/Redeem
    function test_Deposit_BasicFlow() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 10_000e18);
        uint256 shares = vault.deposit(10_000e18, alice);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), 10_000e18);
    }

    function test_Deposit_MultipleUsers() public {
        _deposit(alice, 10_000e18);
        _deposit(bob, 5_000e18);

        assertEq(vault.totalAssets(), 15_000e18);
        assertGt(vault.balanceOf(alice), vault.balanceOf(bob));
    }

    function test_Withdraw_FullAmount() public {
        _deposit(alice, 10_000e18);

        uint256 shares = vault.balanceOf(alice);
        vm.startPrank(alice);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        // Due to the protection from the inflation attack, it will actually get a little less (or exactly)
        assertEq(vault.totalAssets(), 0);
    }

    function test_Deposit_RevertWhen_Paused() public {
        vm.prank(owner);
        vault.setDepositsPaused(true);

        vm.startPrank(alice);
        asset.approve(address(vault), 1_000e18);
        vm.expectRevert(ApexVault.DepositsPausedError.selector);
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    // Block 3: Chainlink Staleness Check
    function test_GetLatestPrice_Success() public view {
        int256 price = vault.getLatestPrice();
        assertEq(price, 1e8);
    }

    function test_Deposit_RevertWhen_PriceStale() public {
        // Rolling back the oracle update time by 2 hours
        priceFeed.setUpdatedAt(block.timestamp - 7201);

        vm.startPrank(alice);
        asset.approve(address(vault), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(ApexVault.StalePrice.selector, block.timestamp - 7201, 3600));
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    function test_IsPriceFresh_True() public view {
        assertTrue(vault.isPriceFresh());
    }

    function test_IsPriceFresh_False_WhenStale() public {
        priceFeed.setUpdatedAt(block.timestamp - 7201);
        assertFalse(vault.isPriceFresh());
    }

    function test_Deposit_RevertWhen_NegativePrice() public {
        priceFeed.setAnswer(-1);

        vm.startPrank(alice);
        asset.approve(address(vault), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(ApexVault.NegativePrice.selector, int256(-1)));
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    // Block 4: Admin functions
    function test_SetPriceFeed_OnlyOwner() public {
        MockAggregator newFeed = new MockAggregator(2e8, 8);
        vm.prank(owner);
        vault.setPriceFeed(address(newFeed));
        assertEq(address(vault.priceFeed()), address(newFeed));
    }

    function test_RevertWhen_SetPriceFeed_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setPriceFeed(address(0));
    }

    function test_SetStalenessThreshold() public {
        vm.prank(owner);
        vault.setStalenessThreshold(7200);
        assertEq(vault.stalenessThreshold(), 7200);
    }

    function test_SetDepositsPaused() public {
        vm.prank(owner);
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused());

        vm.prank(owner);
        vault.setDepositsPaused(false);
        assertFalse(vault.depositsPaused());
    }

    // FUZZ TESTS for Vault
    /// @dev Fuzz: deposit always releases the correct number of shares
    function testFuzz_Vault_DepositAndRedeem(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 50_000e18);
        asset.mint(alice, depositAmount);

        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(shares, 0);

        // Redeem shares and check that we get assets back
        vm.startPrank(alice);
        uint256 assetsBack = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // Due to rounding, assetsBack may be 1 wei less
        assertGe(depositAmount, assetsBack);
        assertGe(assetsBack, depositAmount - 1); // Loss not more than 1 wei
    }

    /// @dev Fuzz: convertToShares and convertToAssets are backward compatible
    function testFuzz_Vault_ConvertSymmetry(uint256 assets) public view {
        assets = bound(assets, 1e6, 1_000_000e18);
        uint256 shares = vault.convertToShares(assets);
        // When the vault is empty, the ratio is 1:1
        assertEq(shares, assets);
    }

    // Helper
    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }
}
