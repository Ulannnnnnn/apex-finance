// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

contract ApexVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 3600;

    AggregatorV3Interface public priceFeed;

    uint256 public stalenessThreshold;

    bool public depositsPaused;

    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event DepositsPaused(bool paused);
    event PriceChecked(int256 price, uint256 updatedAt);

    error StalePrice(uint256 updatedAt, uint256 threshold);
    error NegativePrice(int256 price);
    error DepositsPausedError();
    error ZeroAddress();

    constructor(
        address asset_,
        string memory name_,
        string memory symbol_,
        address _priceFeed,
        address initialOwner
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) Ownable(initialOwner) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        stalenessThreshold = DEFAULT_STALENESS_THRESHOLD;
    }

    function getLatestPrice() public view returns (int256 price) {
        require(address(priceFeed) != address(0), "ApexVault: No price feed configured");

        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();

        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice(updatedAt, stalenessThreshold);
        }

        // Negative price protection (theoretically it shouldn't come, but we are defending ourselves)
        if (answer <= 0) {
            revert NegativePrice(answer);
        }

        return answer;
    }

    /**
     * @dev Checks the freshness of the price without retrieving the value.
     * Used by the frontend before making a deposit.
     */
    function isPriceFresh() external view returns (bool) {
        if (address(priceFeed) == address(0)) return false;
        (, , , uint256 updatedAt,) = priceFeed.latestRoundData();
        return (block.timestamp - updatedAt) <= stalenessThreshold;
    }

    // ERC-4626 Overrides (protection against share-inflation attack)
    /**
     * @dev Overrides _decimalsOffset for protection against share-inflation attack.
     * Offset of 0 - the base implementation of OZ already protects against this through
     * virtual assets (1 wei of the underlying asset = 1 share when the vault is empty).
     *
     * OZ ERC4626 already contains protection: 1 is added to totalAssets(),
     * and 10**_decimalsOffset() = 1 is added to totalSupply(   ).
     * This makes an attack through a "donation" economically unprofitable.
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }

    // Deposit/Withdraw с дополнительными проверками
    /**
     * @dev Redefining deposit with Circuit Breaker and Chainlink check
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Circuit Breaker pattern 
        if (depositsPaused) revert DepositsPausedError();

        // If the oracle is set up, we check the freshness of the price.
        if (address(priceFeed) != address(0)) {
            getLatestPrice(); // Reverts if stale
        }

        return super.deposit(assets, receiver);
    }

    /**
     * @dev Redefining mint with the same checks
     */
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (depositsPaused) revert DepositsPausedError();

        if (address(priceFeed) != address(0)) {
            getLatestPrice();
        }

        return super.mint(shares, receiver);
    }

    // Admin functions (controlled in the future via the DAO Timelock)
    /**
     * @dev Update the Chainlink Price Feed address
     */
    function setPriceFeed(address newFeed) external onlyOwner {
        address old = address(priceFeed);
        priceFeed = AggregatorV3Interface(newFeed);
        emit PriceFeedUpdated(old, newFeed);
    }

    /**
     * @dev Update the staleness threshold for the price feed
     */
    function setStalenessThreshold(uint256 newThreshold) external onlyOwner {
        uint256 old = stalenessThreshold;
        stalenessThreshold = newThreshold;
        emit StalenessThresholdUpdated(old, newThreshold);
    }

    /**
     * @dev Circuit Breaker: pause/unpause deposits in case of emergency (e.g., oracle failure, exploit, etc.)
     */
    function setDepositsPaused(bool paused) external onlyOwner {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }
}
