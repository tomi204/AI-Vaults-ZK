// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IRewardsDistributor.sol";

/**
 * @title RewardsDistributor
 * @dev Distributes rewards to users based on their share of the vault
 */
contract RewardsDistributor is
    IRewardsDistributor,
    AccessControl,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant REWARDS_PRECISION = 1e18;

    // State variables
    IERC20 public immutable rewardsToken;
    address public vault;
    uint256 public rewardsPerShareStored;
    mapping(address => uint256) public userRewardsPerSharePaid;
    mapping(address => uint256) public rewards;

    // Events
    event RewardsDistributed(uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event VaultSet(address vault);

    // Modifiers
    modifier onlyVault() {
        require(msg.sender == vault, "RewardsDistributor: caller is not vault");
        _;
    }

    /**
     * @dev Constructor
     * @param _rewardsToken Address of the rewards token
     * @param _admin Address of the admin
     */
    constructor(address _rewardsToken, address _admin) {
        require(
            _rewardsToken != address(0),
            "RewardsDistributor: zero rewards token"
        );
        require(_admin != address(0), "RewardsDistributor: zero admin");

        rewardsToken = IERC20(_rewardsToken);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @dev Set the vault address
     * @param _vault Address of the vault
     */
    function setVault(
        address _vault
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vault != address(0), "RewardsDistributor: zero vault");
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @dev Distribute rewards to users based on their share of the total supply
     * @param amount Amount of rewards to distribute
     */
    function distributeRewards(
        uint256 amount
    ) external override onlyVault nonReentrant {
        require(amount > 0, "RewardsDistributor: zero amount");

        uint256 totalSupply = IERC20(vault).totalSupply();
        require(totalSupply > 0, "RewardsDistributor: no shares");

        // Ensure we have enough balance before distributing
        require(
            rewardsToken.balanceOf(address(this)) >= amount,
            "RewardsDistributor: insufficient rewards"
        );

        // Update rewards per share
        rewardsPerShareStored += (amount * REWARDS_PRECISION) / totalSupply;
        emit RewardsDistributed(amount);
    }

    /**
     * @dev Update user rewards
     * @param user Address of the user
     * @param oldBalance Old balance of the user
     * @param newBalance New balance of the user
     */
    function updateUserRewards(
        address user,
        uint256 oldBalance,
        uint256 newBalance
    ) external override onlyVault nonReentrant {
        require(user != address(0), "RewardsDistributor: zero user");

        // Calculate and update rewards
        uint256 accruedRewards = (oldBalance *
            (rewardsPerShareStored - userRewardsPerSharePaid[user])) /
            REWARDS_PRECISION;
        rewards[user] += accruedRewards;
        userRewardsPerSharePaid[user] = rewardsPerShareStored;
    }

    /**
     * @dev Get accrued rewards for a user
     * @param user Address of the user
     * @return Amount of accrued rewards
     */
    function getAccruedRewards(
        address user
    ) external view override returns (uint256) {
        if (user == address(0)) return 0;

        uint256 currentBalance = IERC20(vault).balanceOf(user);
        uint256 accruedRewards = (currentBalance *
            (rewardsPerShareStored - userRewardsPerSharePaid[user])) /
            REWARDS_PRECISION;
        return rewards[user] + accruedRewards;
    }

    /**
     * @dev Claim rewards for a user
     * @param user Address of the user
     * @return Amount of rewards claimed
     */
    function claimRewards(
        address user
    ) external override onlyVault nonReentrant returns (uint256) {
        require(user != address(0), "RewardsDistributor: zero user");

        // Update rewards
        uint256 currentBalance = IERC20(vault).balanceOf(user);
        uint256 accruedRewards = (currentBalance *
            (rewardsPerShareStored - userRewardsPerSharePaid[user])) /
            REWARDS_PRECISION;
        uint256 totalRewards = rewards[user] + accruedRewards;

        // Reset rewards
        rewards[user] = 0;
        userRewardsPerSharePaid[user] = rewardsPerShareStored;

        // Transfer rewards - check for non-zero to save gas
        if (totalRewards > 0) {
            // Verify we have enough balance before transfer
            require(
                rewardsToken.balanceOf(address(this)) >= totalRewards,
                "RewardsDistributor: insufficient rewards balance"
            );

            rewardsToken.safeTransfer(user, totalRewards);
            emit RewardsClaimed(user, totalRewards);
        }

        return totalRewards;
    }

    /**
     * @dev Emergency function to recover tokens accidentally sent to this contract
     * @param tokenAddress Address of the token to recover
     * @param to Address to send the tokens to
     * @param amount Amount of tokens to recover
     */
    function recoverTokens(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(to != address(0), "RewardsDistributor: zero recipient");
        require(amount > 0, "RewardsDistributor: zero amount");

        // If recovering rewards token, ensure there's enough balance accounting for pending rewards
        if (tokenAddress == address(rewardsToken)) {
            require(
                amount <= rewardsToken.balanceOf(address(this)),
                "RewardsDistributor: insufficient balance"
            );
        }

        IERC20(tokenAddress).safeTransfer(to, amount);
    }
}
