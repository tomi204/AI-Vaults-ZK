// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "./mocks/MockERC20.sol";

/**
 * @title RewardsDistributorTest
 * @dev Comprehensive test for RewardsDistributor contract
 */
contract RewardsDistributorTest is Test {
    RewardsDistributor public rewardsDistributor;
    RewardVault public vault;
    MockERC20 public asset;
    MockERC20 public rewardsToken;
    address public admin;
    address public user1;
    address public user2;
    address public attacker;

    // Constants
    uint256 private constant REWARDS_PRECISION = 1e18;

    // Events
    event RewardsDistributed(uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event VaultSet(address vault);

    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        attacker = address(0x3);

        // Deploy mock tokens
        asset = new MockERC20("Test Asset", "ASSET");
        rewardsToken = new MockERC20("Test Rewards", "REWARD");

        // Deploy rewards distributor
        rewardsDistributor = new RewardsDistributor(
            address(rewardsToken),
            admin
        );

        // Deploy vault
        vault = new RewardVault(
            address(asset),
            address(rewardsToken),
            address(rewardsDistributor),
            "Vault Token",
            "vTKN"
        );

        // Set vault in rewards distributor
        rewardsDistributor.setVault(address(vault));

        // Transfer tokens to users
        asset.transfer(user1, 10000 * 10 ** 18);
        asset.transfer(user2, 10000 * 10 ** 18);

        // Transfer rewards tokens for distribution
        rewardsToken.transfer(address(vault), 10000 * 10 ** 18);
    }

    /**
     * @dev Test constructor with invalid parameters
     */
    function testConstructorZeroAddresses() public {
        vm.expectRevert("RewardsDistributor: zero rewards token");
        new RewardsDistributor(address(0), admin);

        vm.expectRevert("RewardsDistributor: zero admin");
        new RewardsDistributor(address(rewardsToken), address(0));
    }

    /**
     * @dev Test setVault function
     */
    function testSetVault() public {
        // Deploy a new distributor
        RewardsDistributor newDistributor = new RewardsDistributor(
            address(rewardsToken),
            admin
        );

        // Try to set zero address as vault
        vm.expectRevert("RewardsDistributor: zero vault");
        newDistributor.setVault(address(0));

        // Set a valid vault
        vm.expectEmit(false, false, false, true);
        emit VaultSet(address(vault));
        newDistributor.setVault(address(vault));

        assertEq(newDistributor.vault(), address(vault));
    }

    /**
     * @dev Test setVault with non-admin caller
     */
    function testSetVaultNonAdmin() public {
        // Deploy a new distributor
        RewardsDistributor newDistributor = new RewardsDistributor(
            address(rewardsToken),
            admin
        );

        // Try to set vault as non-admin
        vm.startPrank(attacker);
        vm.expectRevert();
        newDistributor.setVault(address(vault));
        vm.stopPrank();
    }

    /**
     * @dev Test distributeRewards function
     */
    function testDistributeRewards() public {
        // Setup - User deposits to create shares
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Transfer rewards to vault (normally this would be done via distributeRewards in the vault)
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);

        // Distribute rewards from the vault (pretend to be the vault)
        vm.startPrank(address(vault));
        vm.expectEmit(false, false, false, true);
        emit RewardsDistributed(1000 * 10 ** 18);
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);
        vm.stopPrank();

        // Check that user can claim rewards
        uint256 userRewards = rewardsDistributor.getAccruedRewards(user1);
        assertEq(userRewards, 1000 * 10 ** 18);
    }

    /**
     * @dev Test distributeRewards with invalid parameters
     */
    function testDistributeRewardsInvalid() public {
        // Setup - User deposits to create shares
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Transfer rewards to vault
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);

        // Try to distribute with zero amount
        vm.startPrank(address(vault));
        vm.expectRevert("RewardsDistributor: zero amount");
        rewardsDistributor.distributeRewards(0);
        vm.stopPrank();

        // Try to distribute from non-vault
        vm.startPrank(attacker);
        vm.expectRevert("RewardsDistributor: caller is not vault");
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);
        vm.stopPrank();
    }

    /**
     * @dev Test distributeRewards with no shares
     */
    function testDistributeRewardsNoShares() public {
        // No deposits/shares have been made yet
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);

        // Try to distribute rewards when no shares exist
        vm.startPrank(address(vault));
        vm.expectRevert("RewardsDistributor: no shares");
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);
        vm.stopPrank();
    }

    /**
     * @dev Test updateUserRewards function
     */
    function testUpdateUserRewards() public {
        // Setup - User deposits to create shares
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute initial rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.startPrank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // Update user rewards (this happens during deposit/withdraw)
        rewardsDistributor.updateUserRewards(
            user1,
            1000 * 10 ** 18,
            2000 * 10 ** 18
        );
        vm.stopPrank();

        // User should have accrued the rewards based on old balance
        uint256 userRewards = rewardsDistributor.getAccruedRewards(user1);
        assertEq(userRewards, 1000 * 10 ** 18);
    }

    /**
     * @dev Test updateUserRewards with invalid parameters
     */
    function testUpdateUserRewardsInvalid() public {
        // Try to update rewards from non-vault
        vm.startPrank(attacker);
        vm.expectRevert("RewardsDistributor: caller is not vault");
        rewardsDistributor.updateUserRewards(user1, 0, 0);
        vm.stopPrank();

        // Try to update rewards for zero address
        vm.startPrank(address(vault));
        vm.expectRevert("RewardsDistributor: zero user");
        rewardsDistributor.updateUserRewards(address(0), 0, 0);
        vm.stopPrank();
    }

    /**
     * @dev Test getAccruedRewards function
     */
    function testGetAccruedRewards() public {
        // Setup - User deposits to create shares
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Initial accrued rewards should be zero
        uint256 initialRewards = rewardsDistributor.getAccruedRewards(user1);
        assertEq(initialRewards, 0);

        // Distribute rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // Check accrued rewards
        uint256 accrued = rewardsDistributor.getAccruedRewards(user1);
        assertEq(accrued, 1000 * 10 ** 18);
    }

    /**
     * @dev Test claimRewards function
     */
    function testClaimRewards() public {
        // Setup - User deposits to create shares
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // Claim rewards
        vm.startPrank(address(vault));
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(user1, 1000 * 10 ** 18);
        uint256 claimed = rewardsDistributor.claimRewards(user1);
        vm.stopPrank();

        assertEq(claimed, 1000 * 10 ** 18);
        assertEq(rewardsToken.balanceOf(user1), 1000 * 10 ** 18);

        // Rewards should be reset
        uint256 remaining = rewardsDistributor.getAccruedRewards(user1);
        assertEq(remaining, 0);
    }

    /**
     * @dev Test claimRewards with invalid parameters
     */
    function testClaimRewardsInvalid() public {
        // Try to claim from non-vault
        vm.startPrank(attacker);
        vm.expectRevert("RewardsDistributor: caller is not vault");
        rewardsDistributor.claimRewards(user1);
        vm.stopPrank();

        // Try to claim for zero address
        vm.startPrank(address(vault));
        vm.expectRevert("RewardsDistributor: zero user");
        rewardsDistributor.claimRewards(address(0));
        vm.stopPrank();
    }

    /**
     * @dev Test rewards calculation with multiple users
     */
    function testRewardsCalculationMultipleUsers() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute initial rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // User2 deposits
        vm.startPrank(user2);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute more rewards
        rewardsToken.transfer(address(rewardsDistributor), 2000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(2000 * 10 ** 18);

        // Check rewards
        uint256 user1Rewards = rewardsDistributor.getAccruedRewards(user1);
        uint256 user2Rewards = rewardsDistributor.getAccruedRewards(user2);

        assertEq(user1Rewards, 1000 * 10 ** 18 + 1000 * 10 ** 18); // 1000 from first distribution + 1000 from second (50%)
        assertEq(user2Rewards, 1000 * 10 ** 18); // Only got rewards from second distribution (50%)

        // User1 claims
        vm.prank(address(vault));
        rewardsDistributor.claimRewards(user1);

        // Distribute more rewards
        rewardsToken.transfer(address(rewardsDistributor), 2000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(2000 * 10 ** 18);

        // Check rewards again
        user1Rewards = rewardsDistributor.getAccruedRewards(user1);
        user2Rewards = rewardsDistributor.getAccruedRewards(user2);

        assertEq(user1Rewards, 1000 * 10 ** 18); // Half of 2000 from third distribution
        assertEq(user2Rewards, 1000 * 10 ** 18 + 1000 * 10 ** 18); // 1000 from second + 1000 from third (50% each time)
    }

    /**
     * @dev Test rewards with state changes
     */
    function testRewardsWithStateChanges() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute initial rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // User1 should have 1000 * 10^18 rewards
        assertEq(rewardsDistributor.getAccruedRewards(user1), 1000 * 10 ** 18);

        // User1 deposits more
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute more rewards
        rewardsToken.transfer(address(rewardsDistributor), 2000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(2000 * 10 ** 18);

        // User1 should have 1000 + 2000 = 3000 * 10^18 rewards
        assertEq(rewardsDistributor.getAccruedRewards(user1), 3000 * 10 ** 18);

        // User1 withdraws half
        vm.startPrank(user1);
        vault.withdraw(1000 * 10 ** 18);
        vm.stopPrank();

        // User1 should still have 3000 * 10^18 rewards (accrued before withdrawal)
        assertEq(rewardsDistributor.getAccruedRewards(user1), 3000 * 10 ** 18);

        // Distribute more rewards
        rewardsToken.transfer(address(rewardsDistributor), 1000 * 10 ** 18);
        vm.prank(address(vault));
        rewardsDistributor.distributeRewards(1000 * 10 ** 18);

        // User1 should have 3000 + 1000 = 4000 * 10^18 rewards
        assertEq(rewardsDistributor.getAccruedRewards(user1), 4000 * 10 ** 18);
    }
}
