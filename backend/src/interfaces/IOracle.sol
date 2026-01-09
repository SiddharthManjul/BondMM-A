// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @notice Interface for BondMM-A rate oracle
 * @dev Provides anchor rate (r*) for the AMM
 */
interface IOracle {
    /**
     * @notice Get the current anchor rate
     * @return rate The anchor rate r* (scaled by 1e18)
     */
    function getRate() external view returns (uint256 rate);

    /**
     * @notice Check if oracle data is stale
     * @return True if data is stale (> 1 hour old)
     */
    function isStale() external view returns (bool);

    /**
     * @notice Update the rate (only authorized)
     * @param newRate New anchor rate to set
     */
    function updateRate(uint256 newRate) external;
}
