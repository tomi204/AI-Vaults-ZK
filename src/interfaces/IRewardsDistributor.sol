// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IRewardsDistributor
 * @dev Interface for distributing rewards to vault depositors
 */
interface IRewardsDistributor {
    /**
     * @dev Adds rewards to the distribution pool
     * @param amount The amount of rewards to add
     */
    function addRewards(uint256 amount) external;

    /**
     * @dev Updates user's reward accrual when their balance changes
     * @param user The address of the user
     * @param oldBalance The old balance of the user
     * @param newBalance The new balance of the user
     */
    function updateUserRewards(
        address user,
        uint256 oldBalance,
        uint256 newBalance
    ) external;

    /**
     * @dev Distributes rewards to a user
     * @param user The address of the user to distribute rewards to
     * @return The amount of rewards distributed
     */
    function distributeRewards(address user) external returns (uint256);

    /**
     * @dev Returns the amount of rewards accrued by a user
     * @param user The address of the user
     * @return The amount of rewards accrued
     */
    function getAccruedRewards(address user) external view returns (uint256);

    /**
     * @dev Sets the rewards rate (rewards per token per second)
     * @param newRate The new rewards rate
     */
    function setRewardsRate(uint256 newRate) external;
}
