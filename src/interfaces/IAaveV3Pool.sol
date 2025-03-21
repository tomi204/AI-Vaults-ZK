// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Import from the actual DataTypes file
import "../libraries/DataTypes.sol";

/**
 * @title IAaveV3Pool
 * @dev Interface for interaction with Aave V3 lending pools
 */
interface IAaveV3Pool {
    /**
     * @dev Supplies an amount of an asset to the protocol
     * @param asset The address of the asset to supply
     * @param amount The amount to supply
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Referral code for tracking and rewards
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @dev Withdraws an amount of an asset from the protocol
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @param to The address that will receive the withdrawn assets
     * @return The final amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the asset
     * @return The reserve data
     */
    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData memory);

    /**
     * @dev Deposits funds into the lending protocol
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     */
    function deposit(address asset, uint256 amount) external;
}
