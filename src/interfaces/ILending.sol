// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title ILending
 * @dev Generic interface for interacting with lending protocols
 */
interface ILending {
    /**
     * @dev Deposits assets into a lending protocol
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @return The amount of tokens received in return (if any)
     */
    function deposit(address asset, uint256 amount) external returns (uint256);

    /**
     * @dev Withdraws assets from a lending protocol
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @return The amount of tokens actually withdrawn
     */
    function withdraw(address asset, uint256 amount) external returns (uint256);

    /**
     * @dev Returns the balance of an asset in the lending protocol
     * @param asset The address of the asset
     * @return The balance of the asset
     */
    function getBalance(address asset) external view returns (uint256);

    /**
     * @dev Claims rewards from the lending protocol
     * @param to The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function claimRewards(address to) external returns (uint256);
}
