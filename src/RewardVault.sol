// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/ILending.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./RewardsDistributor.sol";

/**
 * @title RewardVault
 * @dev A vault contract that manages deposits with rewards distribution for users
 * This contract implements ERC4626 standard for tokenized vaults
 * Compatible with zkSync Era
 */
contract RewardVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== STATE VARIABLES ========== */

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // Core data structures
    struct VaultInfo {
        address admin;
        address asset;
        address agent;
        uint256 totalAllocatedFunds;
        uint256 reserveRatio; // Percentage of assets to keep in reserve (e.g., 20%)
    }

    VaultInfo private vaultInfo;

    // Strategy mappings
    enum StrategyType {
        DEFAULT
    }

    mapping(StrategyType => address) public strategies;

    // Rewards distributor
    IRewardsDistributor public rewardsDistributor;

    /* ========== EVENTS ========== */

    event StrategyDeployed(
        StrategyType indexed strategyType,
        address strategyAddress
    );
    event FundsAllocated(StrategyType indexed strategyType, uint256 amount);
    event FundsWithdrawn(StrategyType indexed strategyType, uint256 amount);
    event ReserveRatioSet(uint256 oldRatio, uint256 newRatio);
    event RewardsDistributorSet(address rewardsDistributor);
    event RewardsClaimed(address indexed user, uint256 amount);

    /* ========== MODIFIERS ========== */

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "RewardVault: admin only");
        _;
    }

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "RewardVault: agent only");
        _;
    }

    modifier updateRewards(address user) {
        if (address(rewardsDistributor) != address(0)) {
            uint256 oldBalance = balanceOf(user);
            _;
            uint256 newBalance = balanceOf(user);

            if (oldBalance != newBalance) {
                rewardsDistributor.updateUserRewards(
                    user,
                    oldBalance,
                    newBalance
                );
            }
        } else {
            _;
        }
    }

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Constructor initializes the vault with initial configurations
     * @param _admin Address of the admin
     * @param _asset Address of the underlying asset
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     * @param _agent Address of the agent
     * @param _rewardsToken Address of the rewards token
     */
    constructor(
        address _admin,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _agent,
        address _rewardsToken
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        require(
            _admin != address(0),
            "RewardVault: admin cannot be zero address"
        );
        require(
            _agent != address(0),
            "RewardVault: agent cannot be zero address"
        );

        vaultInfo.admin = _admin;
        vaultInfo.asset = address(_asset);
        vaultInfo.agent = _agent;
        vaultInfo.reserveRatio = 20; // Default 20% reserve ratio

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(AGENT_ROLE, _agent);

        // Deploy rewards distributor if rewards token is provided
        if (_rewardsToken != address(0)) {
            RewardsDistributor distributor = new RewardsDistributor(
                _rewardsToken,
                _admin
            );
            rewardsDistributor = distributor;
            distributor.setVault(address(this));
            emit RewardsDistributorSet(address(distributor));
        }
    }

    /* ========== USER OPERATIONS ========== */

    /**
     * @dev Deposit assets into the vault and mint shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive the minted shares
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        updateRewards(receiver)
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /**
     * @dev Mint shares in the vault by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive the minted shares
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        updateRewards(receiver)
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /**
     * @dev Withdraw assets from the vault by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive the assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        updateRewards(owner)
        returns (uint256)
    {
        // Ensure we have enough liquid assets for the withdrawal
        uint256 currentLiquidity = IERC20(asset()).balanceOf(address(this));

        // If we don't have enough liquidity, try to withdraw from strategy
        if (
            currentLiquidity < assets &&
            strategies[StrategyType.DEFAULT] != address(0)
        ) {
            uint256 shortfall = assets - currentLiquidity;

            // Try standard withdrawal first
            uint256 withdrawn = withdrawFromStrategy(
                StrategyType.DEFAULT,
                shortfall
            );

            // If we still need more, try emergency withdrawal
            if (withdrawn < shortfall) {
                uint256 remaining = shortfall - withdrawn;
                (bool success, bytes memory data) = strategies[
                    StrategyType.DEFAULT
                ].call(
                        abi.encodeWithSignature(
                            "provideEmergencyLiquidity(address,uint256)",
                            asset(),
                            remaining
                        )
                    );

                if (success) {
                    uint256 emergencyAmount = abi.decode(data, (uint256));
                    if (emergencyAmount > 0) {
                        vaultInfo.totalAllocatedFunds = emergencyAmount >
                            vaultInfo.totalAllocatedFunds
                            ? 0
                            : vaultInfo.totalAllocatedFunds - emergencyAmount;
                    }
                }
            }
        }

        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev Redeem shares from the vault for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive the assets
     * @param owner Address that owns the shares
     * @return assets Amount of assets returned
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        updateRewards(owner)
        returns (uint256)
    {
        // Estimate the assets amount
        uint256 assets = previewRedeem(shares);

        // Ensure we have enough liquid assets for the withdrawal
        uint256 currentLiquidity = IERC20(asset()).balanceOf(address(this));

        // If we don't have enough liquidity, try to withdraw from strategy
        if (
            currentLiquidity < assets &&
            strategies[StrategyType.DEFAULT] != address(0)
        ) {
            uint256 shortfall = assets - currentLiquidity;

            // Try standard withdrawal first
            uint256 withdrawn = withdrawFromStrategy(
                StrategyType.DEFAULT,
                shortfall
            );

            // If we still need more, try emergency withdrawal
            if (withdrawn < shortfall) {
                uint256 remaining = shortfall - withdrawn;
                (bool success, bytes memory data) = strategies[
                    StrategyType.DEFAULT
                ].call(
                        abi.encodeWithSignature(
                            "provideEmergencyLiquidity(address,uint256)",
                            asset(),
                            remaining
                        )
                    );

                if (success) {
                    uint256 emergencyAmount = abi.decode(data, (uint256));
                    if (emergencyAmount > 0) {
                        vaultInfo.totalAllocatedFunds = emergencyAmount >
                            vaultInfo.totalAllocatedFunds
                            ? 0
                            : vaultInfo.totalAllocatedFunds - emergencyAmount;
                    }
                }
            }
        }

        return super.redeem(shares, receiver, owner);
    }

    /**
     * @dev Simplified deposit function
     * @param amount Amount of assets to deposit
     */
    function deposit(uint256 amount) external {
        deposit(amount, msg.sender);
    }

    /**
     * @dev Simplified withdraw function
     * @param shares Amount of shares to withdraw
     */
    function withdraw(uint256 shares) external {
        redeem(shares, msg.sender, msg.sender);
    }

    /* ========== REWARDS FUNCTIONS ========== */

    /**
     * @dev Claims rewards for the caller
     * @return Amount of rewards claimed
     */
    function claimRewards() external nonReentrant returns (uint256) {
        require(
            address(rewardsDistributor) != address(0),
            "RewardVault: no rewards distributor"
        );

        uint256 rewards = rewardsDistributor.distributeRewards(msg.sender);
        emit RewardsClaimed(msg.sender, rewards);
        return rewards;
    }

    /**
     * @dev Returns the accrued rewards for a user
     * @param user Address of the user
     * @return Amount of rewards accrued
     */
    function getAccruedRewards(address user) external view returns (uint256) {
        if (address(rewardsDistributor) == address(0)) {
            return 0;
        }

        return rewardsDistributor.getAccruedRewards(user);
    }

    /**
     * @dev Sets a new rewards distributor
     * @param _rewardsDistributor Address of the new rewards distributor
     */
    function setRewardsDistributor(
        address _rewardsDistributor
    ) external onlyAdmin {
        require(_rewardsDistributor != address(0), "RewardVault: zero address");

        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        emit RewardsDistributorSet(_rewardsDistributor);
    }

    /* ========== STRATEGY FUNCTIONS ========== */

    /**
     * @dev Adds a strategy to the vault
     * @param strategyType Type of the strategy
     * @param strategyAddress Address of the strategy
     */
    function addStrategy(
        StrategyType strategyType,
        address strategyAddress
    ) external onlyAdmin {
        require(strategyAddress != address(0), "RewardVault: zero address");
        require(
            strategies[strategyType] == address(0),
            "RewardVault: strategy already exists"
        );

        strategies[strategyType] = strategyAddress;
        emit StrategyDeployed(strategyType, strategyAddress);
    }

    /**
     * @dev Allocates funds to a specific strategy
     * @param strategyType Type of strategy to allocate funds to
     * @param amount Amount of funds to allocate
     */
    function allocateToStrategy(
        StrategyType strategyType,
        uint256 amount
    ) external onlyAgent nonReentrant {
        require(amount > 0, "RewardVault: zero amount");
        require(
            strategies[strategyType] != address(0),
            "RewardVault: strategy not found"
        );

        // Calculate max allocation based on reserve ratio
        uint256 totalBalance = IERC20(asset()).balanceOf(address(this));
        uint256 reserveAmount = (totalAssets() * vaultInfo.reserveRatio) / 100;
        uint256 maxAllocation = totalBalance > reserveAmount
            ? totalBalance - reserveAmount
            : 0;

        require(
            amount <= maxAllocation,
            "RewardVault: insufficient balance after reserve"
        );

        IERC20(asset()).forceApprove(strategies[strategyType], amount);
        ILending(strategies[strategyType]).deposit(asset(), amount);
        vaultInfo.totalAllocatedFunds += amount;

        emit FundsAllocated(strategyType, amount);
    }

    /**
     * @dev Withdraws funds from a specific strategy
     * @param strategyType Type of strategy to withdraw funds from
     * @param amount Amount of funds to withdraw
     */
    function withdrawFromStrategy(
        StrategyType strategyType,
        uint256 amount
    ) public onlyAgent nonReentrant returns (uint256) {
        require(amount > 0, "RewardVault: zero amount");
        require(
            strategies[strategyType] != address(0),
            "RewardVault: strategy not found"
        );

        uint256 withdrawn = ILending(strategies[strategyType]).withdraw(
            asset(),
            amount
        );
        vaultInfo.totalAllocatedFunds = withdrawn >
            vaultInfo.totalAllocatedFunds
            ? 0
            : vaultInfo.totalAllocatedFunds - withdrawn;

        emit FundsWithdrawn(strategyType, withdrawn);
        return withdrawn;
    }

    /**
     * @dev Sets the reserve ratio
     * @param _reserveRatio New reserve ratio percentage (1-50)
     */
    function setReserveRatio(uint256 _reserveRatio) external onlyAdmin {
        require(
            _reserveRatio > 0 && _reserveRatio <= 50,
            "RewardVault: invalid reserve ratio"
        );

        uint256 oldRatio = vaultInfo.reserveRatio;
        vaultInfo.reserveRatio = _reserveRatio;

        emit ReserveRatioSet(oldRatio, _reserveRatio);
    }

    /**
     * @dev Execute agent action on the default strategy
     * @param actionId The identifier of the action to perform
     * @param data Encoded data for the operation
     * @return success Indicates whether the operation was successful
     * @return result Result data from the operation
     */
    function executeAgentAction(
        uint256 actionId,
        bytes calldata data
    ) external onlyAgent returns (bool success, bytes memory result) {
        require(
            strategies[StrategyType.DEFAULT] != address(0),
            "RewardVault: default strategy not found"
        );

        address strategyAddr = strategies[StrategyType.DEFAULT];

        // Call the strategy's executeStrategy function
        (success, result) = strategyAddr.call(
            abi.encodeWithSignature(
                "executeStrategy(uint256,bytes)",
                actionId,
                data
            )
        );

        require(success, "RewardVault: strategy execution failed");
        return (success, result);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @dev Returns the total assets managed by the vault
     * @return Total assets including vault balance and allocated funds
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 strategiesBalance = vaultInfo.totalAllocatedFunds;
        return vaultBalance + strategiesBalance;
    }

    /**
     * @dev Returns the available liquidity in the vault that can be withdrawn immediately
     * @return Available liquidity
     */
    function availableLiquidity() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @dev Returns the address of a strategy
     * @param strategyType Type of the strategy
     * @return Address of the strategy
     */
    function getStrategyAddress(
        StrategyType strategyType
    ) external view returns (address) {
        return strategies[strategyType];
    }

    /**
     * @dev Get the current reserve ratio
     * @return The reserve ratio percentage
     */
    function getReserveRatio() external view returns (uint256) {
        return vaultInfo.reserveRatio;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @dev Sets the agent address
     * @param _agent New agent address
     */
    function setAgent(address _agent) external onlyAdmin {
        require(_agent != address(0), "RewardVault: zero address");
        vaultInfo.agent = _agent;
        _grantRole(AGENT_ROLE, _agent);
    }

    /**
     * @dev Sets the admin address
     * @param _admin New admin address
     */
    function setAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "RewardVault: zero address");
        vaultInfo.admin = _admin;
        _grantRole(ADMIN_ROLE, _admin);
    }
}
