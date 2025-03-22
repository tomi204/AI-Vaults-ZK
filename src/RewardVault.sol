// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IRewardsDistributor.sol";

contract RewardVault is ERC20, AccessControl {
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
    function deposit(uint256 amount) external {
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
    function withdraw(uint256 amount) external {
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
        _burn(msg.sender, amount);
        asset.safeTransfer(msg.sender, amount);

        // Update rewards
        rewardsDistributor.updateUserRewards(
            msg.sender,
            oldBalance,
            balanceOf(msg.sender)
        );

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
        returns (bool success, bytes memory result)
    {
        if (actionType == 1) {
            // Set reserve ratio
            uint256 newRatio = abi.decode(data, (uint256));
            uint256 oldRatio = reserveRatio;
            reserveRatio = newRatio;
            emit ReserveRatioSet(oldRatio, newRatio);
            return (true, abi.encode(newRatio));
        } else if (actionType == 2) {
            // Set minimum liquidity
            uint256 newMinLiquidity = abi.decode(data, (uint256));
            uint256 oldMinLiquidity = minLiquidity;
            minLiquidity = newMinLiquidity;
            emit MinLiquiditySet(oldMinLiquidity, newMinLiquidity);
            return (true, abi.encode(newMinLiquidity));
        }
        return (false, "");
    }

    /**
     * @dev Claim rewards for a user
     * @param user Address of the user
     * @return Amount of rewards claimed
     */
    function claimRewards(address user) external returns (uint256) {
        return rewardsDistributor.claimRewards(user);
    }

    /**
     * @dev Get accrued rewards for a user
     * @param user Address of the user
     * @return Amount of accrued rewards
     */
    function getAccruedRewards(address user) external view returns (uint256) {
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
    function distributeRewards(uint256 amount) external {
        require(amount > 0, "RewardVault: zero amount");
        require(
            rewardsToken.balanceOf(msg.sender) >= amount,
            "RewardVault: insufficient rewards"
        );
        require(
            rewardsToken.allowance(msg.sender, address(this)) >= amount,
            "RewardVault: insufficient allowance"
        );

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardsToken.safeTransfer(address(rewardsDistributor), amount);
        rewardsDistributor.distributeRewards(amount);
    }
}
