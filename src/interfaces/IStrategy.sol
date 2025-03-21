// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IStrategy
 * @dev Interface for AI agent interaction with strategy contracts
 */
interface IStrategy {
    /**
     * @dev Execute a custom strategy operation with arbitrary parameters
     * @param actionId The identifier of the action to perform
     * @param data Encoded data for the operation
     * @return success Indicates whether the operation was successful
     * @return result Result data from the operation
     */
    function executeStrategy(
        uint256 actionId,
        bytes calldata data
    ) external returns (bool success, bytes memory result);

    /**
     * @dev Get strategy metadata
     * @return name The name of the strategy
     * @return description The description of the strategy
     * @return version The version of the strategy
     * @return supportedAssets Array of supported asset addresses
     */
    function getStrategyInfo()
        external
        view
        returns (
            string memory name,
            string memory description,
            string memory version,
            address[] memory supportedAssets
        );

    /**
     * @dev Get available actions that can be performed by this strategy
     * @return actionIds Array of action identifiers
     * @return actionNames Array of action names
     * @return actionDescriptions Array of action descriptions
     */
    function getAvailableActions()
        external
        view
        returns (
            uint256[] memory actionIds,
            string[] memory actionNames,
            string[] memory actionDescriptions
        );

    /**
     * @dev Get the current performance metrics of the strategy
     * @return apy The current APY (annual percentage yield) in basis points (1% = 100)
     * @return tvl Total value locked in the strategy
     * @return risk Risk score from 1-5 (1 being the safest)
     */
    function getPerformanceMetrics()
        external
        view
        returns (uint256 apy, uint256 tvl, uint8 risk);

    /**
     * @dev Check if an action is valid for execution
     * @param actionId The identifier of the action
     * @param data Encoded data for the operation
     * @return isValid Whether the action can be executed with the given parameters
     * @return reason Reason if the action is invalid
     */
    function validateAction(
        uint256 actionId,
        bytes calldata data
    ) external view returns (bool isValid, string memory reason);
}
