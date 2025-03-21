// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IRewardsDistributor.sol";

/**
 * @title RewardsDistributor
 * @dev Contract for distributing rewards to vault users
 */
contract RewardsDistributor is IRewardsDistributor, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    // State variables
    IERC20 public immutable rewardsToken;
    address public vault;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;
    uint256 public rewardsDuration = 7 days;
    uint256 public totalSupply;

    // User data mapping
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances;

    // Events
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event UserBalanceUpdated(address indexed user, uint256 newBalance);

    /**
     * @dev Modifier to update rewards for a user
     * @param user The address of the user
     */
    modifier updateReward(address user) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (user != address(0)) {
            rewards[user] = earned(user);
            userRewardPerTokenPaid[user] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @dev Modifier to restrict access to the vault
     */
    modifier onlyVault() {
        require(
            hasRole(VAULT_ROLE, msg.sender),
            "RewardsDistributor: caller is not the vault"
        );
        _;
    }

    /**
     * @dev Modifier to restrict access to the admin
     */
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "RewardsDistributor: caller is not an admin"
        );
        _;
    }

    /**
     * @dev Constructor to set initial values
     * @param _rewardsToken Address of the rewards token
     * @param _admin Address of the admin
     */
    constructor(address _rewardsToken, address _admin) {
        require(
            _rewardsToken != address(0),
            "RewardsDistributor: rewards token cannot be zero address"
        );
        require(
            _admin != address(0),
            "RewardsDistributor: admin cannot be zero address"
        );

        rewardsToken = IERC20(_rewardsToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Returns the last time rewards were applicable (either now or periodFinish)
     * @return The last applicable timestamp
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /**
     * @dev Calculates the reward per token
     * @return The reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / totalSupply);
    }

    /**
     * @dev Calculates the earned rewards for a user
     * @param user The address of the user
     * @return The earned rewards
     */
    function earned(address user) public view returns (uint256) {
        return
            ((balances[user] *
                (rewardPerToken() - userRewardPerTokenPaid[user])) / 1e18) +
            rewards[user];
    }

    /**
     * @dev Sets the vault address
     * @param _vault The address of the vault
     */
    function setVault(address _vault) external onlyAdmin {
        require(
            _vault != address(0),
            "RewardsDistributor: vault cannot be zero address"
        );
        vault = _vault;
        _grantRole(VAULT_ROLE, _vault);
    }

    /**
     * @dev Updates user rewards when balance changes
     * @param user The address of the user
     * @param oldBalance The old balance of the user
     * @param newBalance The new balance of the user
     */
    function updateUserRewards(
        address user,
        uint256 oldBalance,
        uint256 newBalance
    ) external override onlyVault updateReward(user) {
        totalSupply = totalSupply - oldBalance + newBalance;
        balances[user] = newBalance;

        emit UserBalanceUpdated(user, newBalance);
    }

    /**
     * @dev Distributes rewards to a user
     * @param user The address of the user
     * @return The amount of rewards distributed
     */
    function distributeRewards(
        address user
    ) external override updateReward(user) returns (uint256) {
        uint256 reward = rewards[user];
        if (reward > 0) {
            rewards[user] = 0;
            rewardsToken.safeTransfer(user, reward);
            emit RewardPaid(user, reward);
        }
        return reward;
    }

    /**
     * @dev Returns the amount of rewards accrued by a user
     * @param user The address of the user
     * @return The amount of rewards accrued
     */
    function getAccruedRewards(
        address user
    ) external view override returns (uint256) {
        return earned(user);
    }

    /**
     * @dev Sets the rewards rate
     * @param newRate The new rewards rate
     */
    function setRewardsRate(uint256 newRate) external override onlyAdmin {
        rewardRate = newRate;
    }

    /**
     * @dev Adds rewards to the distribution pool
     * @param amount The amount of rewards to add
     */
    function addRewards(
        uint256 amount
    ) external override onlyAdmin updateReward(address(0)) {
        require(
            amount > 0,
            "RewardsDistributor: amount must be greater than zero"
        );

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);

        if (block.timestamp >= periodFinish) {
            rewardRate = amount / rewardsDuration;
        } else {
            uint256 remainingTime = periodFinish - block.timestamp;
            uint256 leftoverReward = remainingTime * rewardRate;
            rewardRate = (amount + leftoverReward) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance / rewardsDuration,
            "RewardsDistributor: reward rate too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(amount);
    }

    /**
     * @dev Updates the duration of the rewards period
     * @param _rewardsDuration The new duration of the rewards period
     */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyAdmin {
        require(
            block.timestamp > periodFinish,
            "RewardsDistributor: previous rewards period must be complete"
        );
        require(
            _rewardsDuration > 0,
            "RewardsDistributor: reward duration must be non-zero"
        );

        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    /**
     * @dev Allows admin to recover tokens sent to the contract by mistake
     * @param tokenAddress The address of the token to recover
     * @param tokenAmount The amount of tokens to recover
     */
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyAdmin {
        require(
            tokenAddress != address(rewardsToken),
            "RewardsDistributor: cannot withdraw reward token"
        );

        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
