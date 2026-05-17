// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MockAggregator
 * @dev Mock-contract Chainlink AggregatorV3Interface for local tests.
 * Allows you to manually set the price and time of the upgrade in order to test
 * staleness check and other oracle logic without real RPC.
 */
contract MockAggregator {
    int256 private _answer;
    uint256 private _updatedAt;
    uint8 private _decimals;

    constructor(int256 initialAnswer, uint8 decimalsValue) {
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _decimals = decimalsValue;
    }

    /// @dev Update the price (called in tests)
    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
    }

    /// @dev Manually roll back the update time (for testing staleness)
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }
}
