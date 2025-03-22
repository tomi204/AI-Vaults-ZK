// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./BaseStrategy.sol";

/**
 * @title DefaultStrategy
 * @dev Default strategy that can be called via the agent with simplified functionality
 * It stores funds and implements the basic ILending interface without any external protocol integrations
 */
contract DefaultStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Reserve ratio - Percentage of assets that must be kept in reserve for withdrawals (e.g., 20%)
    uint256 public reserveRatio = 20;
    uint256 public constant MAX_RESERVE_RATIO = 50;

    // Minimum liquidity - Extra buffer to maintain in addition to reserve ratio
    uint256 public minLiquidity = 100 * 10 ** 18;

    // Action IDs for executeStrategy
    uint256 private constant ACTION_DEPOSIT = 1;
    uint256 private constant ACTION_WITHDRAW = 2;
    uint256 private constant ACTION_SET_RESERVE_RATIO = 3;
    uint256 private constant ACTION_CUSTOM_FUNCTION = 4;
    uint256 private constant ACTION_SET_MIN_LIQUIDITY = 5;

    // Maps describing action details
    mapping(uint256 => string) private actionDescriptions;

    // Assets balances tracking
    mapping(address => uint256) private assetBalances;

    // Events
    event ReserveRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event MinLiquidityUpdated(uint256 oldValue, uint256 newValue);
    event AssetDeposited(address indexed asset, uint256 amount);
    event AssetWithdrawn(address indexed asset, uint256 amount);
    event CustomFunctionExecuted(bytes data, bool success);
    event EmergencyLiquidityProvided(address indexed asset, uint256 amount);
    event AssetEmergencyWithdrawal(
        address indexed asset,
        uint256 amount,
        address indexed recipient
    );

    /**
     * @dev Constructor to set vault address and basic info
     * @param _vault Address of the owner vault
     * @param _supportedAssets Array of supported assets for this strategy
     */
    constructor(
        address _vault,
        address[] memory _supportedAssets
    )
        BaseStrategy(
            _vault,
            "Default Strategy",
            "Basic strategy for storing assets with agent-callable functions",
            "1.0.0",
            _supportedAssets,
            1 // Risk level low (1 out of 5)
        )
    {
        // Validate supported assets
        for (uint256 i = 0; i < _supportedAssets.length; i++) {
            require(
                _supportedAssets[i] != address(0),
                "DefaultStrategy: zero asset address"
            );
        }

        // Initialize available actions
        _availableActionIds = [
            ACTION_DEPOSIT,
            ACTION_WITHDRAW,
            ACTION_SET_RESERVE_RATIO,
            ACTION_CUSTOM_FUNCTION,
            ACTION_SET_MIN_LIQUIDITY
        ];

        // Set action names
        actionNames[ACTION_DEPOSIT] = "Deposit";
        actionNames[ACTION_WITHDRAW] = "Withdraw";
        actionNames[ACTION_SET_RESERVE_RATIO] = "Set Reserve Ratio";
        actionNames[ACTION_CUSTOM_FUNCTION] = "Custom Function";
        actionNames[ACTION_SET_MIN_LIQUIDITY] = "Set Minimum Liquidity";

        // Set action descriptions
        actionDescriptions[ACTION_DEPOSIT] = "Deposit assets into the strategy";
        actionDescriptions[
            ACTION_WITHDRAW
        ] = "Withdraw assets from the strategy";
        actionDescriptions[
            ACTION_SET_RESERVE_RATIO
        ] = "Set the reserve ratio for withdrawals";
        actionDescriptions[
            ACTION_CUSTOM_FUNCTION
        ] = "Execute a custom function call";
        actionDescriptions[
            ACTION_SET_MIN_LIQUIDITY
        ] = "Set the minimum liquidity buffer";
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
        if (actionId == ACTION_DEPOSIT) {
            (address asset, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            require(asset != address(0), "DefaultStrategy: zero asset address");
            require(amount > 0, "DefaultStrategy: zero deposit amount");

            uint256 deposited = _depositInternal(asset, amount);
            return (true, abi.encode(deposited));
        } else if (actionId == ACTION_WITHDRAW) {
            (address asset, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            require(asset != address(0), "DefaultStrategy: zero asset address");
            require(amount > 0, "DefaultStrategy: zero withdraw amount");

            uint256 withdrawn = _withdrawInternal(asset, amount);
            return (true, abi.encode(withdrawn));
        } else if (actionId == ACTION_SET_RESERVE_RATIO) {
            uint256 newRatio = abi.decode(data, (uint256));
            return _setReserveRatio(newRatio);
        } else if (actionId == ACTION_SET_MIN_LIQUIDITY) {
            uint256 newMinLiquidity = abi.decode(data, (uint256));
            return _setMinLiquidity(newMinLiquidity);
        } else if (actionId == ACTION_CUSTOM_FUNCTION) {
            // This allows any custom function to be executed by the agent
            // We need to be careful with this functionality as it's potentially dangerous
            require(
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                    hasRole(AGENT_ROLE, msg.sender),
                "DefaultStrategy: not authorized for custom function"
            );

            (bool callSuccess, bytes memory callResult) = address(this).call(
                data
            );
            emit CustomFunctionExecuted(data, callSuccess);
            return (callSuccess, callResult);
        }

        return (false, bytes("DefaultStrategy: unknown action"));
    }

    /**
     * @dev Get available actions
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
        names = new string[](actionIds.length);
        descriptions = new string[](actionIds.length);

        for (uint256 i = 0; i < actionIds.length; i++) {
            names[i] = actionNames[actionIds[i]];
            descriptions[i] = actionDescriptions[actionIds[i]];
        }

        return (actionIds, names, descriptions);
    }

    /**
     * @dev Sets the reserve ratio
     * @param newRatio New reserve ratio percentage (0-50)
     * @return success Whether the operation was successful
     * @return result Encoded result data
     */
    function _setReserveRatio(
        uint256 newRatio
    ) internal returns (bool success, bytes memory result) {
        require(
            newRatio <= MAX_RESERVE_RATIO,
            "DefaultStrategy: ratio too high"
        );

        uint256 oldRatio = reserveRatio;
        reserveRatio = newRatio;

        emit ReserveRatioUpdated(oldRatio, newRatio);

        return (true, abi.encode(newRatio));
    }

    /**
     * @dev Sets the minimum liquidity buffer
     * @param newMinLiquidity New minimum liquidity amount
     * @return success Whether the operation was successful
     * @return result Encoded result data
     */
    function _setMinLiquidity(
        uint256 newMinLiquidity
    ) internal returns (bool success, bytes memory result) {
        require(newMinLiquidity > 0, "DefaultStrategy: zero min liquidity");

        uint256 oldValue = minLiquidity;
        minLiquidity = newMinLiquidity;

        emit MinLiquidityUpdated(oldValue, newMinLiquidity);

        return (true, abi.encode(newMinLiquidity));
    }

    /**
     * @dev Calculate Annual Percentage Yield
     * @return APY in basis points (0% for this default strategy)
     */
    function _calculateAPY() internal pure override returns (uint256) {
        // Default strategy has no yield
        return 0;
    }

    /**
     * @dev Calculate Total Value Locked
     * @return TVL in asset values across all supported assets
     */
    function _calculateTVL() internal view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            total += assetBalances[asset];
        }
        return total;
    }

    /**
     * @dev Implementation of deposit
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @return The amount deposited
     */
    function _depositInternal(
        address asset,
        uint256 amount
    ) internal override returns (uint256) {
        _validateAsset(asset);
        require(amount > 0, "DefaultStrategy: zero amount");

        // Incrementamos directamente el saldo sin verificar si los tokens se recibieron
        // ya que asumimos que los tokens ya están en el contrato
        assetBalances[asset] += amount;
        emit AssetDeposited(asset, amount);

        return amount;
    }

    /**
     * @dev Implementation of withdraw
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @return The amount withdrawn
     */
    function _withdrawInternal(
        address asset,
        uint256 amount
    ) internal override returns (uint256) {
        _validateAsset(asset);
        require(amount > 0, "DefaultStrategy: zero amount");

        // Ensure we have enough balance to withdraw - this check is still needed
        require(
            assetBalances[asset] >= amount,
            "DefaultStrategy: insufficient balance"
        );

        // Calculate the maximum amount that can be withdrawn based on all constraints
        uint256 withdrawableAmount = getWithdrawableAmount(asset);

        // Use the minimum of requested amount and withdrawable amount
        uint256 actualWithdraw = amount < withdrawableAmount
            ? amount
            : withdrawableAmount;

        if (actualWithdraw > 0) {
            // Update balances before transfer to prevent reentrancy
            assetBalances[asset] -= actualWithdraw;

            // Transfer tokens to vault
            IERC20(asset).safeTransfer(vault, actualWithdraw);
            emit AssetWithdrawn(asset, actualWithdraw);
        }

        return actualWithdraw;
    }

    /**
     * @dev Emergency function to provide liquidity immediately
     * @param asset The address of the asset to provide
     * @param amount The amount to provide
     * @return The amount provided
     */
    function provideEmergencyLiquidity(
        address asset,
        uint256 amount
    ) external onlyVault returns (uint256) {
        _validateAsset(asset);
        require(amount > 0, "DefaultStrategy: zero amount");

        uint256 availableAmount = assetBalances[asset];
        uint256 amountToTransfer = amount < availableAmount
            ? amount
            : availableAmount;

        if (amountToTransfer > 0) {
            // Update balances before transfer to prevent reentrancy
            assetBalances[asset] -= amountToTransfer;

            // Transfer tokens to vault
            IERC20(asset).safeTransfer(vault, amountToTransfer);
            emit EmergencyLiquidityProvided(asset, amountToTransfer);
        }

        return amountToTransfer;
    }

    /**
     * @dev Implementation of getBalance
     * @param asset The address of the asset
     * @return The balance of the asset
     */
    function _getBalanceInternal(
        address asset
    ) internal view override returns (uint256) {
        return assetBalances[asset];
    }

    /**
     * @dev Implementation of claimRewards
     * @param to The address to receive the rewards
     * @return The amount of rewards claimed (0 for this default strategy)
     */
    function _claimRewardsInternal(
        address to
    ) internal override returns (uint256) {
        // No rewards for this default strategy
        return 0;
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
        // Check if the action ID is valid
        bool validAction = false;
        for (uint256 i = 0; i < _availableActionIds.length; i++) {
            if (_availableActionIds[i] == actionId) {
                validAction = true;
                break;
            }
        }

        if (!validAction) {
            return (false, "DefaultStrategy: invalid action ID");
        }

        if (actionId == ACTION_DEPOSIT || actionId == ACTION_WITHDRAW) {
            (address asset, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            if (asset == address(0)) {
                return (false, "DefaultStrategy: zero asset address");
            }
            if (amount == 0) {
                return (false, "DefaultStrategy: zero amount");
            }

            // Check if asset is supported
            bool assetSupported = false;
            for (uint256 i = 0; i < supportedAssets.length; i++) {
                if (supportedAssets[i] == asset) {
                    assetSupported = true;
                    break;
                }
            }

            if (!assetSupported) {
                return (false, "DefaultStrategy: unsupported asset");
            }

            // For withdrawal, also check if we have enough balance
            if (actionId == ACTION_WITHDRAW && assetBalances[asset] < amount) {
                return (false, "DefaultStrategy: insufficient balance");
            }

            return (true, "");
        } else if (actionId == ACTION_SET_RESERVE_RATIO) {
            uint256 ratio = abi.decode(data, (uint256));
            if (ratio > MAX_RESERVE_RATIO) {
                return (false, "DefaultStrategy: ratio too high");
            }
            return (true, "");
        } else if (actionId == ACTION_SET_MIN_LIQUIDITY) {
            uint256 minLiq = abi.decode(data, (uint256));
            if (minLiq == 0) {
                return (false, "DefaultStrategy: zero min liquidity");
            }
            return (true, "");
        } else if (actionId == ACTION_CUSTOM_FUNCTION) {
            // We don't validate custom function data, as it could be anything.
            // The action itself will be restricted to admin or agents.
            return (true, "");
        }

        return (true, "");
    }

    /**
     * @dev Returns the available amount that can be withdrawn from the strategy
     * @param asset The asset to check
     * @return The withdrawable amount
     */
    function getWithdrawableAmount(
        address asset
    ) public view returns (uint256) {
        _validateAsset(asset);

        uint256 reserveAmount = (assetBalances[asset] * reserveRatio) / 100;
        uint256 maxWithdrawal = assetBalances[asset];

        if (assetBalances[asset] > minLiquidity) {
            uint256 maxFromMin = assetBalances[asset] - minLiquidity;
            if (maxFromMin < maxWithdrawal) {
                maxWithdrawal = maxFromMin;
            }
        } else {
            maxWithdrawal = 0;
        }

        if (assetBalances[asset] > reserveAmount) {
            uint256 maxFromReserve = assetBalances[asset] - reserveAmount;
            if (maxFromReserve < maxWithdrawal) {
                maxWithdrawal = maxFromReserve;
            }
        } else {
            maxWithdrawal = 0;
        }

        return maxWithdrawal;
    }

    /**
     * @dev Override the emergencyWithdraw method to reset asset balances before performing the withdraw
     */
    function emergencyWithdraw(
        address asset
    ) external override onlyGuardian nonReentrant {
        _validateAsset(asset);

        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance > 0, "BaseStrategy: no balance to withdraw");

        // Reset the tracked asset balance to 0
        assetBalances[asset] = 0;

        // Transfer the tokens to the emergency recipient
        IERC20(asset).safeTransfer(emergencyRecipient, balance);

        // Emit the event from BaseStrategy
        emit EmergencyWithdrawal(asset, balance, emergencyRecipient);
    }
}
