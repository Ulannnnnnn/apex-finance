// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ApexVault} from "../../src/core/ApexVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ForkTests
 * @dev Fork tests are run using a real network/testnet.
 * Use: forge test --fork-url $MAINNET_RPC_URL --match-contract ForkTest
 *
 * Configure foundry.toml:
 * [rpc_endpoints]
 * mainnet = "${MAINNET_RPC_URL}"
 * arbitrum = "${ARBITRUM_RPC_URL}"
 *
 * Launch:
 * forgery test -verification of compliance with the contract-vvv
 */
contract ForkTest is Test {
    // Real mainnet addresses

    /// @dev Chainlink ETH/USD on mainnet
    address constant CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev USDC on mainnet
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev USDC whale for testing (holder of a large balance)
    address constant USDC_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    /// @dev Uniswap V2 Router
    address constant UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /// @dev WETH on mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 forkId;

    function setUp() public {
        // Creating a fork of the mainnet
        // Make sure that the .env has MAINNET_RPC_URL
        string memory rpcUrl = vm.envOr(
            "MAINNET_RPC_URL",
            string("https://ethereum.publicnode.com")
        );
        forkId = vm.createSelectFork(rpcUrl);
    }

    // Fork Test 1: Real Chainlink Price Feed
    /**
     * @dev Test 1: Read the real ETH/USD price from mainnet Chainlink.
     * We check that our staleness check works correctly with real data.
     */
    function test_Fork_ChainlinkPriceFeed_RealData() public {
        // We will deploy our Vault with a real Chainlink feed
        ApexVault vault = new ApexVault(
            USDC_MAINNET,
            "Apex USDC Vault",
            "apxUSDC",
            CHAINLINK_ETH_USD,
            address(this)
        );

        // Setting staleness threshold = 2 hours (real data is updated every ~1 hour)
        vault.setStalenessThreshold(7200);

        // Check that the price is obtained and it is > 0
        int256 price = vault.getLatestPrice();
        console2.log("Real ETH/USD price from Chainlink:", uint256(price));

        assertGt(price, 0, "Price must be positive");
        //ETH/USD should be between $100 and $100,000 (a reasonable range)
        assertGt(price, 100e8, "ETH price seems too low");
        assertLt(price, 100_000e8, "ETH price seems too high");

        // Check isPriceFresh
        assertTrue(vault.isPriceFresh(), "Real Chainlink data must be fresh");
    }

    // Fork Test 2: Real USDC (ERC-20 on mainnet)
    /**
     * @dev Test 2: Deposit in Vault with real USDC through the fork.
     * We use vm.prank from the USDC whale to ensure they have sufficient funds.
     */
    // function test_Fork_VaultDeposit_WithRealUSDC() public {
    //     // Deploy Vault without an oracle (address(0)) for simplicity
    //     ApexVault vault = new ApexVault(
    //         USDC_MAINNET,
    //         "Apex USDC Vault",
    //         "apxUSDC",
    //         address(0), // Without oracle in this test
    //         address(this)
    //     );

    //     IERC20 usdc = IERC20(USDC_MAINNET);
    //     uint256 depositAmount = 1_000e6; // 1000 USDC (6 decimals)

    //     // Check that the whale has sufficient USDC
    //     uint256 whaleBalance = usdc.balanceOf(USDC_WHALE);
    //     console2.log("USDC Whale balance:", whaleBalance);
    //     assertGt(whaleBalance, depositAmount, "Whale must have enough USDC");

    //     // We make a deposit on behalf of whale
    //     vm.startPrank(USDC_WHALE);
    //     usdc.approve(address(vault), depositAmount);
    //     uint256 shares = vault.deposit(depositAmount, USDC_WHALE);
    //     vm.stopPrank();

    //     console2.log("Shares received:", shares);
    //     assertGt(shares, 0, "Must receive shares");
    //     assertEq(vault.totalAssets(), depositAmount);
    //     assertEq(vault.balanceOf(USDC_WHALE), shares);
    // }

    // Fork Test 3: Simulation of staleness with real Chainlink

    /**
     * @dev Test 3: Simulate stale oracle data on the real fork.
     * vm.warp rewinds time forward, making real data "obsolete".
     */
    function test_Fork_ChainlinkStaleness_SimulatedOldData() public {
        ApexVault vault = new ApexVault(
            USDC_MAINNET,
            "Apex USDC Vault",
            "apxUSDC",
            CHAINLINK_ETH_USD,
            address(this)
        );

        // Staleness threshold = 1 hour
        vault.setStalenessThreshold(3600);

        // Rewind time by 2 hours
        // After this, real Chainlink data will become "stale"
        vm.warp(block.timestamp + 7201);

        // Now the data should be stale
        assertFalse(
            vault.isPriceFresh(),
            "Price should be stale after time warp"
        );

        // Attempt to deposit should be reverted
        IERC20 usdc = IERC20(USDC_MAINNET);
        vm.startPrank(USDC_WHALE);
        usdc.approve(address(vault), 1_000e6);

        vm.expectRevert(); // StalePrice error
        vault.deposit(1_000e6, USDC_WHALE);
        vm.stopPrank();

        console2.log(
            "Fork staleness test passed: deposit correctly reverted with stale price"
        );
    }
}
