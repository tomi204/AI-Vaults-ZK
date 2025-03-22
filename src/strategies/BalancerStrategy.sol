// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IBalancerV2.sol";
import "./BaseStrategy.sol";

/**
 * @title BalancerStrategy
 * @dev Strategy for interacting with Balancer V2 pools with enhanced AI agent support
 */
contract BalancerStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Balancer specific variables
    IBalancerV2Vault public immutable balancerVault;

    // Tracking active pool positions
    mapping(bytes32 => bool) public activePools;
    bytes32[] public poolIds;

    // Action IDs for executeStrategy
    uint256 private constant ACTION_ADD_LIQUIDITY = 1;
    uint256 private constant ACTION_REMOVE_LIQUIDITY = 2;
    uint256 private constant ACTION_CLAIM_BAL_REWARDS = 3;
    uint256 private constant ACTION_REBALANCE_POOLS = 4;
    uint256 private constant ACTION_SET_POOL_WEIGHTS = 5;

    // Action descriptions
    mapping(uint256 => string) private actionDescriptions;

    // Pool performance metrics
    mapping(bytes32 => uint256) public poolEntryTimestamps;
    mapping(bytes32 => uint256) public poolEntryValues;

    // Events
    event LiquidityAdded(bytes32 indexed poolId, uint256[] amountsIn);
    event LiquidityRemoved(bytes32 indexed poolId, uint256[] amountsOut);
    event PoolAdded(bytes32 indexed poolId);
    event PoolRemoved(bytes32 indexed poolId);
    event BalRewardsClaimed(uint256 amount, address recipient);
    event PoolRebalanced(bytes32 indexed poolId, uint256 timestamp);

    /**
     * @dev Constructor to set vault and balancer vault addresses
     * @param _vault Address of the owner vault
     * @param _balancerVault Address of the Balancer V2 vault
     * @param _supportedAssets Array of supported assets for this strategy
     */
    constructor(
        address _vault,
        address _balancerVault,
        address[] memory _supportedAssets
    )
        BaseStrategy(
            _vault,
            "Balancer LP Strategy",
            "Strategy for providing liquidity to Balancer V2 pools",
            "1.0.0",
            _supportedAssets,
            3 // Risk level medium (3 out of 5)
        )
    {
        require(
            _balancerVault != address(0),
            "BalancerStrategy: zero balancer vault"
        );

        balancerVault = IBalancerV2Vault(_balancerVault);

        // Initialize available actions
        _availableActionIds = [
            ACTION_ADD_LIQUIDITY,
            ACTION_REMOVE_LIQUIDITY,
            ACTION_CLAIM_BAL_REWARDS,
            ACTION_REBALANCE_POOLS,
            ACTION_SET_POOL_WEIGHTS
        ];

        // Set action names
        actionNames[ACTION_ADD_LIQUIDITY] = "Add Liquidity";
        actionNames[ACTION_REMOVE_LIQUIDITY] = "Remove Liquidity";
        actionNames[ACTION_CLAIM_BAL_REWARDS] = "Claim BAL Rewards";
        actionNames[ACTION_REBALANCE_POOLS] = "Rebalance Pools";
        actionNames[ACTION_SET_POOL_WEIGHTS] = "Set Pool Weights";

        // Set action descriptions
        actionDescriptions[
            ACTION_ADD_LIQUIDITY
        ] = "Add liquidity to a Balancer V2 pool";
        actionDescriptions[
            ACTION_REMOVE_LIQUIDITY
        ] = "Remove liquidity from a Balancer V2 pool";
        actionDescriptions[
            ACTION_CLAIM_BAL_REWARDS
        ] = "Claim BAL governance token rewards";
        actionDescriptions[
            ACTION_REBALANCE_POOLS
        ] = "Rebalance pool positions for optimal yield";
        actionDescriptions[
            ACTION_SET_POOL_WEIGHTS
        ] = "Adjust pool allocation weights";
    }

    /**
     * @dev Add a pool to the active pools list
     * @param poolId The Balancer pool ID to add
     */
    function addPool(bytes32 poolId) external onlyVault {
        require(poolId != bytes32(0), "BalancerStrategy: zero pool ID");
        require(!activePools[poolId], "BalancerStrategy: pool already active");

        activePools[poolId] = true;
        poolIds.push(poolId);
        poolEntryTimestamps[poolId] = block.timestamp;

        emit PoolAdded(poolId);
    }

    /**
     * @dev Remove a pool from the active pools list
     * @param poolId The Balancer pool ID to remove
     */
    function removePool(bytes32 poolId) external onlyVault {
        require(activePools[poolId], "BalancerStrategy: pool not active");

        activePools[poolId] = false;

        // Remove from poolIds array
        for (uint i = 0; i < poolIds.length; i++) {
            if (poolIds[i] == poolId) {
                poolIds[i] = poolIds[poolIds.length - 1];
                poolIds.pop();
                break;
            }
        }

        emit PoolRemoved(poolId);
    }

    /**
     * @dev Add liquidity to a Balancer pool through the strategy interface
     * @param poolId The ID of the Balancer pool
     * @param assets Array of assets to provide as liquidity
     * @param maxAmountsIn Maximum amounts to provide for each asset
     * @param userData Additional data for the operation
     * @return amountsIn Actual amounts provided
     */
    function addLiquidity(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external onlyVault whenNotPaused nonReentrant returns (uint256[] memory) {
        require(activePools[poolId], "BalancerStrategy: pool not active");
        require(
            assets.length == maxAmountsIn.length,
            "BalancerStrategy: length mismatch"
        );

        uint256 totalValueBefore = _calculatePoolValue(poolId);

        // Approve assets for the Balancer vault
        for (uint256 i = 0; i < assets.length; i++) {
            address token = address(assets[i]);
            if (token != address(0)) {
                IERC20(token).forceApprove(address(balancerVault), 0);
                IERC20(token).forceApprove(
                    address(balancerVault),
                    maxAmountsIn[i]
                );
            }
        }

        // Join the pool
        IBalancerV2Vault.JoinPoolRequest memory request = IBalancerV2Vault
            .JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            });

        uint256[] memory amountsIn = balancerVault.joinPool(
            poolId,
            address(this),
            vault,
            request
        );

        // Update pool entry value for APY calculation
        uint256 totalValueAfter = _calculatePoolValue(poolId);
        if (poolEntryValues[poolId] == 0) {
            poolEntryValues[poolId] = totalValueAfter;
        } else {
            poolEntryValues[poolId] = totalValueAfter;
        }

        emit LiquidityAdded(poolId, amountsIn);
        return amountsIn;
    }

    /**
     * @dev Remove liquidity from a Balancer pool through the strategy interface
     * @param poolId The ID of the Balancer pool
     * @param assets Array of assets to receive from liquidity removal
     * @param minAmountsOut Minimum amounts expected for each asset
     * @param userData Additional data for the operation
     * @return amountsOut Actual amounts received
     */
    function removeLiquidity(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external onlyVault nonReentrant returns (uint256[] memory) {
        require(activePools[poolId], "BalancerStrategy: pool not active");
        require(
            assets.length == minAmountsOut.length,
            "BalancerStrategy: length mismatch"
        );

        // Calculate current pool value for profit tracking
        uint256 totalValueBefore = _calculatePoolValue(poolId);

        // Create exit request
        IBalancerV2Vault.ExitPoolRequest memory request = IBalancerV2Vault
            .ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: userData,
                toInternalBalance: false
            });

        uint256[] memory amountsOut = balancerVault.exitPool(
            poolId,
            address(this),
            vault,
            request
        );

        // Calculate profit if any
        if (poolEntryValues[poolId] > 0) {
            uint256 totalValueAfter = _calculatePoolValue(poolId);
            if (totalValueAfter < poolEntryValues[poolId]) {
                // Record profit
                uint256 profit = totalValueAfter - totalValueBefore;
                _recordReturn(profit);
            }
        }

        emit LiquidityRemoved(poolId, amountsOut);
        return amountsOut;
    }

    /**
     * @dev Get the list of active pool IDs
     * @return Array of active pool IDs
     */
    function getActivePools() external view returns (bytes32[] memory) {
        // Filter out inactive pools
        bytes32[] memory activePoolsList = new bytes32[](poolIds.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < poolIds.length; i++) {
            if (activePools[poolIds[i]]) {
                activePoolsList[activeCount] = poolIds[i];
                activeCount++;
            }
        }

        // Resize the array
        bytes32[] memory result = new bytes32[](activeCount);
        for (uint i = 0; i < activeCount; i++) {
            result[i] = activePoolsList[i];
        }

        return result;
    }

    // IStrategy interface implementations

    /**
     * @dev Get available actions for this strategy
     * @return actionIds Array of action identifiers
     * @return names Array of action names
     * @return descriptions Array of action descriptions
     */
    function getAvailableActions()
        external
        view
        override
        returns (
            uint256[] memory actionIds,
            string[] memory names,
            string[] memory descriptions
        )
    {
        actionIds = _availableActionIds;
        names = new string[](_availableActionIds.length);
        descriptions = new string[](_availableActionIds.length);

        for (uint i = 0; i < _availableActionIds.length; i++) {
            names[i] = actionNames[_availableActionIds[i]];
            descriptions[i] = actionDescriptions[_availableActionIds[i]];
        }

        return (actionIds, names, descriptions);
    }

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
    ) public view override returns (bool isValid, string memory reason) {
        // Check if actionId is valid
        bool validAction = false;
        for (uint i = 0; i < _availableActionIds.length; i++) {
            if (_availableActionIds[i] == actionId) {
                validAction = true;
                break;
            }
        }

        if (!validAction) {
            return (false, "BalancerStrategy: invalid action ID");
        }

        // Add custom validation for each action
        if (actionId == ACTION_ADD_LIQUIDITY) {
            // Validate add liquidity parameters
            (bytes32 poolId, , uint256[] memory maxAmountsIn, ) = abi.decode(
                data,
                (bytes32, IAsset[], uint256[], bytes)
            );

            if (!activePools[poolId]) {
                return (false, "BalancerStrategy: pool not active");
            }

            if (maxAmountsIn.length == 0) {
                return (false, "BalancerStrategy: empty amounts array");
            }

            return (true, "");
        } else if (actionId == ACTION_REMOVE_LIQUIDITY) {
            // Validate remove liquidity parameters
            (bytes32 poolId, , , ) = abi.decode(
                data,
                (bytes32, IAsset[], uint256[], bytes)
            );

            if (!activePools[poolId]) {
                return (false, "BalancerStrategy: pool not active");
            }

            return (true, "");
        } else if (actionId == ACTION_CLAIM_BAL_REWARDS) {
            // Any address can claim rewards
            address recipient = abi.decode(data, (address));

            if (recipient == address(0)) {
                return (false, "BalancerStrategy: zero recipient address");
            }

            return (true, "");
        } else if (actionId == ACTION_REBALANCE_POOLS) {
            // Check if there are any active pools
            if (poolIds.length == 0) {
                return (false, "BalancerStrategy: no active pools");
            }

            return (true, "");
        } else if (actionId == ACTION_SET_POOL_WEIGHTS) {
            // Validate pool weights parameters
            (bytes32[] memory _poolIds, uint256[] memory weights) = abi.decode(
                data,
                (bytes32[], uint256[])
            );

            if (_poolIds.length != weights.length) {
                return (false, "BalancerStrategy: length mismatch");
            }

            if (_poolIds.length == 0) {
                return (false, "BalancerStrategy: empty pools array");
            }

            // Check if all pools are active
            for (uint i = 0; i < _poolIds.length; i++) {
                if (!activePools[_poolIds[i]]) {
                    return (
                        false,
                        "BalancerStrategy: inactive pool in weights"
                    );
                }
            }

            // Check if weights sum up to 100%
            uint256 totalWeight = 0;
            for (uint i = 0; i < weights.length; i++) {
                totalWeight += weights[i];
            }

            if (totalWeight != 10000) {
                // 100% in basis points
                return (false, "BalancerStrategy: weights must sum to 10000");
            }

            return (true, "");
        }

        return (false, "BalancerStrategy: unknown action");
    }

    /**
     * @dev Implementation of strategy execution
     * @param actionId The identifier of the action to perform
     * @param data Encoded data for the operation
     * @return success Indicates whether the operation was successful
     * @return result Result data from the operation
     */
    function _executeStrategy(
        uint256 actionId,
        bytes calldata data
    ) internal override returns (bool success, bytes memory result) {
        if (actionId == ACTION_ADD_LIQUIDITY) {
            (
                bytes32 poolId,
                IAsset[] memory assets,
                uint256[] memory maxAmountsIn,
                bytes memory userData
            ) = abi.decode(data, (bytes32, IAsset[], uint256[], bytes));

            uint256[] memory amountsIn = this.addLiquidity(
                poolId,
                assets,
                maxAmountsIn,
                userData
            );
            return (true, abi.encode(amountsIn));
        } else if (actionId == ACTION_REMOVE_LIQUIDITY) {
            (
                bytes32 poolId,
                IAsset[] memory assets,
                uint256[] memory minAmountsOut,
                bytes memory userData
            ) = abi.decode(data, (bytes32, IAsset[], uint256[], bytes));

            uint256[] memory amountsOut = this.removeLiquidity(
                poolId,
                assets,
                minAmountsOut,
                userData
            );
            return (true, abi.encode(amountsOut));
        } else if (actionId == ACTION_CLAIM_BAL_REWARDS) {
            address recipient = abi.decode(data, (address));

            // Simplified rewards claiming (implementation would vary by balancer reward contract)
            uint256 claimedAmount = _claimBalRewards(recipient);
            return (true, abi.encode(claimedAmount));
        } else if (actionId == ACTION_REBALANCE_POOLS) {
            bool rebalanceSuccess = _rebalancePools();
            return (rebalanceSuccess, abi.encode(rebalanceSuccess));
        } else if (actionId == ACTION_SET_POOL_WEIGHTS) {
            (bytes32[] memory _poolIds, uint256[] memory weights) = abi.decode(
                data,
                (bytes32[], uint256[])
            );

            _setPoolWeights(_poolIds, weights);
            return (true, abi.encode(true));
        }

        return (false, abi.encode("Unknown action"));
    }

    /**
     * @dev Claim BAL token rewards (implementation would connect to actual Balancer rewards)
     * @param recipient Address to receive the rewards
     * @return Amount of rewards claimed
     */
    function _claimBalRewards(address recipient) internal returns (uint256) {
        // This is a placeholder. In a real implementation, this would interact with
        // the Balancer rewards contract to claim BAL tokens.

        // For this example, we'll simulate claiming rewards
        uint256 claimedAmount = 0;

        emit BalRewardsClaimed(claimedAmount, recipient);
        return claimedAmount;
    }

    /**
     * @dev Rebalance pool positions for optimal yield
     * @return Whether the rebalance was successful
     */
    function _rebalancePools() internal returns (bool) {
        // In a real implementation, this would involve complex rebalancing logic
        // based on market conditions and yield opportunities

        // For this example, we'll just update the rebalance timestamp
        lastRebalanceTimestamp = block.timestamp;

        // Emit events for each pool
        for (uint i = 0; i < poolIds.length; i++) {
            if (activePools[poolIds[i]]) {
                emit PoolRebalanced(poolIds[i], block.timestamp);
            }
        }

        emit RebalancePerformed(block.timestamp);
        return true;
    }

    /**
     * @dev Set allocation weights for pools
     * @param _poolIds Pool IDs to set weights for
     * @param weights Weights for each pool (in basis points, should sum to 10000)
     */
    function _setPoolWeights(
        bytes32[] memory _poolIds,
        uint256[] memory weights
    ) internal {
        // In a real implementation, this would adjust the target allocation for each pool
        // and potentially trigger rebalancing
        // This is a placeholder function
    }

    /**
     * @dev Calculate the value of a pool position (placeholder)
     * @param poolId The pool ID to value
     * @return The value of the position
     */
    function _calculatePoolValue(
        bytes32 poolId
    ) internal view returns (uint256) {
        // This is a placeholder. In a real implementation, this would query
        // the Balancer pool to get the current value of the position.
        return 0;
    }

    /**
     * @dev Calculate APY for all active pool positions
     * @return APY in basis points
     */
    function _calculateAPY() internal view override returns (uint256) {
        // Calculate weighted average APY across all pools
        if (poolIds.length == 0) {
            return 0;
        }

        uint256 totalValue = 0;
        uint256 weightedAPY = 0;

        for (uint i = 0; i < poolIds.length; i++) {
            bytes32 poolId = poolIds[i];
            if (activePools[poolId]) {
                uint256 poolValue = _calculatePoolValue(poolId);
                totalValue += poolValue;

                // Calculate individual pool APY
                if (
                    poolEntryTimestamps[poolId] > 0 &&
                    poolEntryValues[poolId] > 0 &&
                    poolValue > poolEntryValues[poolId]
                ) {
                    uint256 timeElapsed = block.timestamp -
                        poolEntryTimestamps[poolId];
                    if (timeElapsed > 0) {
                        // Calculate annualized return
                        uint256 profit = poolValue - poolEntryValues[poolId];
                        uint256 annualizedReturn = (profit * 365 days * 10000) /
                            (poolEntryValues[poolId] * timeElapsed);
                        weightedAPY +=
                            (annualizedReturn * poolValue) /
                            totalValue;
                    }
                }
            }
        }

        return weightedAPY;
    }

    /**
     * @dev Calculate total value locked in the strategy
     * @return Total value in underlying asset terms
     */
    function _calculateTVL() internal view override returns (uint256) {
        uint256 totalValue = 0;

        // Sum up values across all pools
        for (uint i = 0; i < poolIds.length; i++) {
            if (activePools[poolIds[i]]) {
                totalValue += _calculatePoolValue(poolIds[i]);
            }
        }

        // Add any tokens held directly
        for (uint i = 0; i < supportedAssets.length; i++) {
            totalValue += IERC20(supportedAssets[i]).balanceOf(address(this));
        }

        return totalValue;
    }

    /**
     * @dev Implementation of deposit for Balancer strategy
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @return The amount deposited
     */
    function _depositInternal(
        address asset,
        uint256 amount
    ) internal override returns (uint256) {
        // In a real implementation, this would deposit into a Balancer pool
        // For now, we just hold the token in the contract
        return amount;
    }

    /**
     * @dev Implementation of withdraw for Balancer strategy
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @return The amount withdrawn
     */
    function _withdrawInternal(
        address asset,
        uint256 amount
    ) internal override returns (uint256) {
        // In a real implementation, this would withdraw from Balancer pools
        // For now, we just transfer the token from the contract
        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 withdrawAmount = amount < balance ? amount : balance;

        if (withdrawAmount > 0) {
            IERC20(asset).safeTransfer(vault, withdrawAmount);
        }

        return withdrawAmount;
    }

    /**
     * @dev Implementation of getBalance for Balancer strategy
     * @param asset The address of the asset
     * @return The balance of the asset
     */
    function _getBalanceInternal(
        address asset
    ) internal view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @dev Implementation of claimRewards for Balancer strategy
     * @param to The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function _claimRewardsInternal(
        address to
    ) internal override returns (uint256) {
        return _claimBalRewards(to);
    }
}
