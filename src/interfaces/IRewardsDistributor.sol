// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRewardsDistributor
 * @dev Interface for distributing rewards to vault depositors
 */
interface IRewardsDistributor {
    /**
     * @dev Updates the rewards for a user
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
     * @dev Distributes rewards to users
     * @param amount The amount of rewards to distribute
     */
    function distributeRewards(uint256 amount) external;

    /**
     * @dev Gets the accrued rewards for a user
     * @param user The address of the user
     * @return The amount of accrued rewards
     */
    function getAccruedRewards(address user) external view returns (uint256);

    /**
     * @dev Sets the vault associated with the distributor
     * @param _vault The address of the vault
     */
    function setVault(address _vault) external;

    /**
     * @dev Claims rewards for a user
     * @param user The address of the user to claim rewards for
     * @return The amount of rewards claimed
     */
    function claimRewards(address user) external returns (uint256);
}
