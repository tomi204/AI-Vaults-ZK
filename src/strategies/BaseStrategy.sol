// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ILending.sol";

/**
 * @title BaseStrategy
 * @dev Abstract base contract for all investment strategies
 */
abstract contract BaseStrategy is
    IStrategy,
    ILending,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    address public immutable vault;

    // Strategy information
    string public name;
    string public description;
    string public version;
    address[] public supportedAssets;

    // Performance tracking
    uint256 public lastRebalanceTimestamp;
    uint256 public historicalReturns;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint8 public riskLevel;

    // ActionId to action name mapping
    mapping(uint256 => string) public actionNames;

    // Action IDs
    uint256[] internal _availableActionIds;

    // Emergency withdrawal recipient
    address public emergencyRecipient;

    // Events
    event StrategyExecuted(uint256 indexed actionId, bool success);
    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event EmergencyWithdrawal(
        address indexed asset,
        uint256 amount,
        address recipient
    );
    event RebalancePerformed(uint256 timestamp);

    /**
     * @dev Modifier to restrict access to the vault
     */
    modifier onlyVault() {
        require(
            hasRole(VAULT_ROLE, msg.sender),
            "BaseStrategy: caller is not the vault"
        );
        _;
    }

    /**
     * @dev Modifier to restrict access to AI agents
     */
    modifier onlyAgent() {
        require(
            hasRole(AGENT_ROLE, msg.sender),
            "BaseStrategy: caller is not an agent"
        );
        _;
    }

    /**
     * @dev Modifier to restrict access to guardians (can pause in emergency)
     */
    modifier onlyGuardian() {
        require(
            hasRole(GUARDIAN_ROLE, msg.sender),
            "BaseStrategy: caller is not a guardian"
        );
        _;
    }

    /**
     * @dev Constructor to set vault address and basic info
     * @param _vault Address of the vault
     * @param _name Name of the strategy
     * @param _description Description of the strategy
     * @param _version Version of the strategy
     * @param _supportedAssets Array of supported asset addresses
     * @param _riskLevel Risk level from 1-5
     */
    constructor(
        address _vault,
        string memory _name,
        string memory _description,
        string memory _version,
        address[] memory _supportedAssets,
        uint8 _riskLevel
    ) {
        require(
            _vault != address(0),
            "BaseStrategy: vault is the zero address"
        );
        require(
            _riskLevel >= 1 && _riskLevel <= 5,
            "BaseStrategy: risk level out of range"
        );

        vault = _vault;
        name = _name;
        description = _description;
        version = _version;
        supportedAssets = _supportedAssets;
        riskLevel = _riskLevel;

        _grantRole(DEFAULT_ADMIN_ROLE, _vault);
        _grantRole(VAULT_ROLE, _vault);

        // Set emergency recipient as the vault initially
        emergencyRecipient = _vault;

        // Initialize rebalance timestamp
        lastRebalanceTimestamp = block.timestamp;
    }

    /**
     * @dev Validate that an asset is supported
     * @param asset The asset address to check
     */
    function _validateAsset(address asset) internal view {
        bool assetSupported = false;
        for (uint i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                assetSupported = true;
                break;
            }
        }
        require(assetSupported, "BaseStrategy: unsupported asset");
    }

    /**
     * @dev Add a supported asset
     * @param asset The asset address to add
     */
    function addSupportedAsset(address asset) external onlyVault {
        require(asset != address(0), "BaseStrategy: asset is the zero address");

        // Check if asset is already supported
        bool assetExists = false;
        for (uint i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                assetExists = true;
                break;
            }
        }

        require(!assetExists, "BaseStrategy: asset already supported");

        supportedAssets.push(asset);
        emit AssetAdded(asset);
    }

    /**
     * @dev Remove a supported asset
     * @param asset The asset address to remove
     */
    function removeSupportedAsset(address asset) external onlyVault {
        require(asset != address(0), "BaseStrategy: asset is the zero address");

        bool assetRemoved = false;
        for (uint i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                // Replace with the last element
                supportedAssets[i] = supportedAssets[
                    supportedAssets.length - 1
                ];
                // Remove the last element
                supportedAssets.pop();
                assetRemoved = true;
                break;
            }
        }

        require(assetRemoved, "BaseStrategy: asset not found");
        emit AssetRemoved(asset);
    }

    /**
     * @dev Execute emergency withdrawal of funds
     * @param asset The asset to withdraw
     */
    function emergencyWithdraw(
        address asset
    ) external onlyGuardian nonReentrant {
        _validateAsset(asset);

        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance > 0, "BaseStrategy: no balance to withdraw");

        IERC20(asset).safeTransfer(emergencyRecipient, balance);

        emit EmergencyWithdrawal(asset, balance, emergencyRecipient);
    }

    /**
     * @dev Set the emergency recipient
     * @param _emergencyRecipient The new emergency recipient
     */
    function setEmergencyRecipient(
        address _emergencyRecipient
    ) external onlyVault {
        require(
            _emergencyRecipient != address(0),
            "BaseStrategy: zero address"
        );
        emergencyRecipient = _emergencyRecipient;
    }

    /**
     * @dev Grant agent role to an address
     * @param agent The address to grant agent role
     */
    function grantAgentRole(address agent) external onlyVault {
        _grantRole(AGENT_ROLE, agent);
    }

    /**
     * @dev Revoke agent role from an address
     * @param agent The address to revoke agent role
     */
    function revokeAgentRole(address agent) external onlyVault {
        _revokeRole(AGENT_ROLE, agent);
    }

    /**
     * @dev Grant guardian role to an address
     * @param guardian The address to grant guardian role
     */
    function grantGuardianRole(address guardian) external onlyVault {
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    /**
     * @dev Revoke guardian role from an address
     * @param guardian The address to revoke guardian role
     */
    function revokeGuardianRole(address guardian) external onlyVault {
        _revokeRole(GUARDIAN_ROLE, guardian);
    }

    /**
     * @dev Pause the strategy
     */
    function pause() external onlyGuardian {
        _pause();
    }

    /**
     * @dev Unpause the strategy
     */
    function unpause() external onlyVault {
        _unpause();
    }

    // IStrategy interface implementations

    /**
     * @dev Execute a strategy operation (must be implemented by derived contracts)
     * @param actionId The identifier of the action to perform
     * @param data Encoded data for the operation
     * @return success Indicates whether the operation was successful
     * @return result Result data from the operation
     */
    function executeStrategy(
        uint256 actionId,
        bytes calldata data
    )
        external
        override
        onlyAgent
        nonReentrant
        whenNotPaused
        returns (bool success, bytes memory result)
    {
        (bool valid, string memory reason) = validateAction(actionId, data);
        require(valid, reason);

        (success, result) = _executeStrategy(actionId, data);

        emit StrategyExecuted(actionId, success);
        return (success, result);
    }

    /**
     * @dev Implementation of strategy execution (to be overridden)
     * @param actionId The identifier of the action to perform
     * @param data Encoded data for the operation
     * @return success Indicates whether the operation was successful
     * @return result Result data from the operation
     */
    function _executeStrategy(
        uint256 actionId,
        bytes calldata data
    ) internal virtual returns (bool success, bytes memory result);

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
        override
        returns (string memory, string memory, string memory, address[] memory)
    {
        return (name, description, version, supportedAssets);
    }

    /**
     * @dev Get available actions (must be implemented by derived contracts)
     * @return actionIds Array of action identifiers
     * @return actionNames Array of action names
     * @return actionDescriptions Array of action descriptions
     */
    function getAvailableActions()
        external
        view
        virtual
        override
        returns (
            uint256[] memory actionIds,
            string[] memory names,
            string[] memory actionDescriptions
        );

    /**
     * @dev Get the current performance metrics of the strategy
     * @return apy The current APY (annual percentage yield) in basis points
     * @return tvl Total value locked in the strategy
     * @return risk Risk score from 1-5 (1 being the safest)
     */
    function getPerformanceMetrics()
        external
        view
        override
        returns (uint256 apy, uint256 tvl, uint8 risk)
    {
        return (_calculateAPY(), _calculateTVL(), riskLevel);
    }

    /**
     * @dev Calculate Annual Percentage Yield (to be overridden by specific strategies)
     * @return APY in basis points
     */
    function _calculateAPY() internal view virtual returns (uint256);

    /**
     * @dev Calculate Total Value Locked
     * @return TVL in asset value
     */
    function _calculateTVL() internal view virtual returns (uint256);

    /**
     * @dev Implementation of ILending.deposit (to be overridden)
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @return The amount deposited
     */
    function deposit(
        address asset,
        uint256 amount
    ) external override onlyVault nonReentrant whenNotPaused returns (uint256) {
        _validateAsset(asset);
        require(amount > 0, "BaseStrategy: deposit amount is zero");

        totalDeposited += amount;
        return _depositInternal(asset, amount);
    }

    /**
     * @dev Internal implementation of deposit (to be overridden)
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @return The amount deposited
     */
    function _depositInternal(
        address asset,
        uint256 amount
    ) internal virtual returns (uint256);

    /**
     * @dev Implementation of ILending.withdraw
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @return The amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override onlyVault nonReentrant returns (uint256) {
        _validateAsset(asset);
        require(amount > 0, "BaseStrategy: withdraw amount is zero");

        uint256 withdrawn = _withdrawInternal(asset, amount);
        totalWithdrawn += withdrawn;
        return withdrawn;
    }

    /**
     * @dev Internal implementation of withdraw (to be overridden)
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     * @return The amount withdrawn
     */
    function _withdrawInternal(
        address asset,
        uint256 amount
    ) internal virtual returns (uint256);

    /**
     * @dev Implementation of ILending.getBalance
     * @param asset The address of the asset
     * @return The balance of the asset
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        _validateAsset(asset);
        return _getBalanceInternal(asset);
    }

    /**
     * @dev Internal implementation of getBalance (to be overridden)
     * @param asset The address of the asset
     * @return The balance of the asset
     */
    function _getBalanceInternal(
        address asset
    ) internal view virtual returns (uint256);

    /**
     * @dev Implementation of ILending.claimRewards
     * @param to The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function claimRewards(
        address to
    ) external override onlyVault nonReentrant returns (uint256) {
        require(to != address(0), "BaseStrategy: to is the zero address");
        return _claimRewardsInternal(to);
    }

    /**
     * @dev Internal implementation of claimRewards (to be overridden)
     * @param to The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function _claimRewardsInternal(
        address to
    ) internal virtual returns (uint256);

    /**
     * @dev Record historical return
     * @param profit The profit made
     */
    function _recordReturn(uint256 profit) internal {
        historicalReturns += profit;
    }
}
