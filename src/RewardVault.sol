// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IRewardsDistributor.sol";

/**
 * @title RewardVault
 * @dev Vault for depositing assets and earning rewards
 */
contract RewardVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable asset;
    IERC20 public immutable rewardsToken;
    IRewardsDistributor public immutable rewardsDistributor;
    uint256 public reserveRatio;
    uint256 public minLiquidity;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event ReserveRatioSet(uint256 oldRatio, uint256 newRatio);
    event MinLiquiditySet(uint256 oldMinLiquidity, uint256 newMinLiquidity);
    event AgentActionExecuted(uint256 actionType, bool success);

    /**
     * @dev Constructor
     * @param _asset Address of the asset token
     * @param _rewardsToken Address of the rewards token
     * @param _rewardsDistributor Address of the rewards distributor
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     */
    constructor(
        address _asset,
        address _rewardsToken,
        address _rewardsDistributor,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_asset != address(0), "RewardVault: zero asset address");
        require(
            _rewardsToken != address(0),
            "RewardVault: zero rewards token address"
        );
        require(
            _rewardsDistributor != address(0),
            "RewardVault: zero distributor address"
        );

        asset = IERC20(_asset);
        rewardsToken = IERC20(_rewardsToken);
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        reserveRatio = 20; // 20% default reserve ratio
        minLiquidity = 1000; // Default minimum liquidity

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);
    }

    /**
     * @dev Deposit assets into the vault
     * @param amount Amount of assets to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "RewardVault: zero amount");
        uint256 oldBalance = balanceOf(msg.sender);

        // Transfer assets to the vault
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Mint shares
        _mint(msg.sender, amount);

        // Update rewards
        rewardsDistributor.updateUserRewards(
            msg.sender,
            oldBalance,
            balanceOf(msg.sender)
        );

        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev Withdraw assets from the vault
     * @param amount Amount of assets to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "RewardVault: zero amount");
        require(
            balanceOf(msg.sender) >= amount,
            "RewardVault: insufficient balance"
        );

        uint256 vaultAssets = asset.balanceOf(address(this));
        uint256 reserveRequired = (vaultAssets * reserveRatio) / 100;
        require(
            vaultAssets - amount >= reserveRequired,
            "RewardVault: insufficient liquidity"
        );
        require(
            vaultAssets - amount >= minLiquidity,
            "RewardVault: below minimum liquidity"
        );

        uint256 oldBalance = balanceOf(msg.sender);

        // Burn shares first to prevent reentrancy
        _burn(msg.sender, amount);

        // Update rewards before transfer to prevent reward manipulation
        rewardsDistributor.updateUserRewards(
            msg.sender,
            oldBalance,
            balanceOf(msg.sender)
        );

        // Transfer assets last
        asset.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Set the reserve ratio
     * @param newRatio New reserve ratio (percentage)
     */
    function setReserveRatio(uint256 newRatio) external onlyRole(ADMIN_ROLE) {
        require(newRatio <= 100, "RewardVault: invalid ratio");
        uint256 oldRatio = reserveRatio;
        reserveRatio = newRatio;
        emit ReserveRatioSet(oldRatio, newRatio);
    }

    /**
     * @dev Set the minimum liquidity
     * @param newMinLiquidity New minimum liquidity
     */
    function setMinLiquidity(
        uint256 newMinLiquidity
    ) external onlyRole(ADMIN_ROLE) {
        uint256 oldMinLiquidity = minLiquidity;
        minLiquidity = newMinLiquidity;
        emit MinLiquiditySet(oldMinLiquidity, newMinLiquidity);
    }

    /**
     * @dev Execute an agent action
     * @param actionType Type of action to execute
     * @param data Additional data for the action
     * @return success Success of the action
     * @return result Result of the action
     */
    function executeAgentAction(
        uint256 actionType,
        bytes memory data
    )
        external
        onlyRole(AGENT_ROLE)
        nonReentrant
        returns (bool success, bytes memory result)
    {
        if (actionType == 1) {
            // Set reserve ratio
            uint256 newRatio = abi.decode(data, (uint256));
            require(newRatio <= 100, "RewardVault: invalid ratio");
            uint256 oldRatio = reserveRatio;
            reserveRatio = newRatio;
            emit ReserveRatioSet(oldRatio, newRatio);
            success = true;
            result = abi.encode(newRatio);
        } else if (actionType == 2) {
            // Set minimum liquidity
            uint256 newMinLiquidity = abi.decode(data, (uint256));
            require(newMinLiquidity > 0, "RewardVault: zero min liquidity");
            uint256 oldMinLiquidity = minLiquidity;
            minLiquidity = newMinLiquidity;
            emit MinLiquiditySet(oldMinLiquidity, newMinLiquidity);
            success = true;
            result = abi.encode(newMinLiquidity);
        } else {
            success = false;
            result = "";
        }

        emit AgentActionExecuted(actionType, success);
        return (success, result);
    }

    /**
     * @dev Claim rewards for a user
     * @param user Address of the user
     * @return Amount of rewards claimed
     */
    function claimRewards(
        address user
    ) external nonReentrant returns (uint256) {
        require(user != address(0), "RewardVault: zero address");
        return rewardsDistributor.claimRewards(user);
    }

    /**
     * @dev Get accrued rewards for a user
     * @param user Address of the user
     * @return Amount of accrued rewards
     */
    function getAccruedRewards(address user) external view returns (uint256) {
        require(user != address(0), "RewardVault: zero address");
        return rewardsDistributor.getAccruedRewards(user);
    }

    /**
     * @dev Get total assets in the vault
     * @return Total amount of assets
     */
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @dev Distribute rewards to the vault
     * @param amount Amount of rewards to distribute
     */
    function distributeRewards(uint256 amount) external nonReentrant {
        require(amount > 0, "RewardVault: zero amount");
        require(totalSupply() > 0, "RewardVault: no shares outstanding");
        require(
            rewardsToken.balanceOf(msg.sender) >= amount,
            "RewardVault: insufficient rewards"
        );
        require(
            rewardsToken.allowance(msg.sender, address(this)) >= amount,
            "RewardVault: insufficient allowance"
        );

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardsToken.forceApprove(address(rewardsDistributor), 0); // Reset approval to 0 first
        rewardsToken.forceApprove(address(rewardsDistributor), amount);
        rewardsToken.safeTransfer(address(rewardsDistributor), amount);
        rewardsDistributor.distributeRewards(amount);
    }

    /**
     * @dev Emergency function to rescue tokens accidentally sent to this contract
     * @param tokenAddress Address of the token to rescue
     * @param to Address to send the tokens to
     * @param amount Amount of tokens to rescue
     * @notice Only admin can call this function
     * @notice Cannot be used to remove asset tokens
     */
    function rescueTokens(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(to != address(0), "RewardVault: zero address");
        require(amount > 0, "RewardVault: zero amount");
        require(
            tokenAddress != address(asset),
            "RewardVault: cannot rescue vault assets"
        );

        IERC20(tokenAddress).safeTransfer(to, amount);
    }
}
