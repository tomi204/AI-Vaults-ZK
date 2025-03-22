// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "./mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RewardVaultTest
 * @dev Comprehensive test contract for RewardVault
 */
contract RewardVaultTest is Test {
    RewardVault public vault;
    MockERC20 public asset;
    MockERC20 public rewardsToken;
    RewardsDistributor public rewardsDistributor;
    address public admin;
    address public user1;
    address public user2;
    address public attacker;
    address public agent;

    // Constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    uint256 public constant LARGE_AMOUNT = 1000000 * 10 ** 18;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event ReserveRatioSet(uint256 oldRatio, uint256 newRatio);
    event MinLiquiditySet(uint256 oldMinLiquidity, uint256 newMinLiquidity);

    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        attacker = address(0x3);
        agent = address(0x4);

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

        // Grant agent role
        vault.grantRole(AGENT_ROLE, agent);

        // Transfer tokens to users
        asset.transfer(user1, 10000 * 10 ** 18);
        asset.transfer(user2, 10000 * 10 ** 18);
        asset.transfer(attacker, 10000 * 10 ** 18);

        // Transfer rewards tokens to this contract for distribution
        rewardsToken.transfer(address(this), 10000 * 10 ** 18);
    }

    /**
     * @dev Test constructor with invalid parameters
     */
    function testConstructorZeroAddresses() public {
        vm.expectRevert("RewardVault: zero asset address");
        new RewardVault(
            address(0),
            address(rewardsToken),
            address(rewardsDistributor),
            "Vault Token",
            "vTKN"
        );

        vm.expectRevert("RewardVault: zero rewards token address");
        new RewardVault(
            address(asset),
            address(0),
            address(rewardsDistributor),
            "Vault Token",
            "vTKN"
        );

        vm.expectRevert("RewardVault: zero distributor address");
        new RewardVault(
            address(asset),
            address(rewardsToken),
            address(0),
            "Vault Token",
            "vTKN"
        );
    }

    /**
     * @dev Test deposit function
     */
    function testDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Check event emission
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, depositAmount);
        vault.deposit(depositAmount);

        vm.stopPrank();

        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);

        // Test zero amount
        vm.startPrank(user1);
        vm.expectRevert("RewardVault: zero amount");
        vault.deposit(0);
        vm.stopPrank();
    }

    /**
     * @dev Test deposit with insufficient approval
     */
    function testDepositInsufficientApproval() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount - 1);

        // Simplemente capturamos cualquier revert, ya que el mensaje exacto puede variar
        vm.expectRevert();
        vault.deposit(depositAmount);

        vm.stopPrank();
    }

    /**
     * @dev Test deposit with insufficient balance
     */
    function testDepositInsufficientBalance() public {
        uint256 depositAmount = 20000 * 10 ** 18; // More than user has

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Simplemente capturamos cualquier revert, ya que el mensaje exacto puede variar
        vm.expectRevert();
        vault.deposit(depositAmount);

        vm.stopPrank();
    }

    /**
     * @dev Test withdraw function
     */
    function testWithdraw() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 500 * 10 ** 18;

        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Then withdraw
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user1, withdrawAmount);
        vault.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - withdrawAmount
        );
        assertEq(
            asset.balanceOf(user1),
            10000 * 10 ** 18 - depositAmount + withdrawAmount
        );
    }

    /**
     * @dev Test withdraw with zero amount
     */
    function testWithdrawZeroAmount() public {
        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);

        // Try to withdraw zero
        vm.expectRevert("RewardVault: zero amount");
        vault.withdraw(0);
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw with insufficient balance
     */
    function testWithdrawInsufficientBalance() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Try to withdraw more than deposited
        vm.expectRevert("RewardVault: insufficient balance");
        vault.withdraw(depositAmount + 1);
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw with insufficient liquidity due to reserve ratio
     */
    function testWithdrawInsufficientLiquidity() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Set reserve ratio to 90%
        vault.setReserveRatio(90);

        // Try to withdraw too much (exceeds available liquidity)
        vm.startPrank(user1);
        vm.expectRevert("RewardVault: insufficient liquidity");
        vault.withdraw(900 * 10 ** 18); // Trying to withdraw 90% when reserve ratio is 90%
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw with insufficient liquidity due to minLiquidity
     */
    function testWithdrawBelowMinLiquidity() public {
        uint256 depositAmount = 1500 * 10 ** 18;

        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Set minLiquidity to 1000
        vault.setMinLiquidity(1000 * 10 ** 18);

        // Try to withdraw too much (would go below minLiquidity)
        vm.startPrank(user1);
        vm.expectRevert("RewardVault: below minimum liquidity");
        vault.withdraw(600 * 10 ** 18); // This would leave 900 tokens, below minLiquidity
        vm.stopPrank();
    }

    /**
     * @dev Test setReserveRatio function
     */
    function testSetReserveRatio() public {
        uint256 newRatio = 30;
        uint256 oldRatio = vault.reserveRatio();

        vm.expectEmit(false, false, false, true);
        emit ReserveRatioSet(oldRatio, newRatio);
        vault.setReserveRatio(newRatio);

        assertEq(vault.reserveRatio(), newRatio);

        // Test invalid ratio
        vm.expectRevert("RewardVault: invalid ratio");
        vault.setReserveRatio(101); // Over 100%
    }

    /**
     * @dev Test setMinLiquidity function
     */
    function testSetMinLiquidity() public {
        uint256 newMinLiquidity = 2000;
        uint256 oldMinLiquidity = vault.minLiquidity();

        vm.expectEmit(false, false, false, true);
        emit MinLiquiditySet(oldMinLiquidity, newMinLiquidity);
        vault.setMinLiquidity(newMinLiquidity);

        assertEq(vault.minLiquidity(), newMinLiquidity);
    }

    /**
     * @dev Test agent actions
     */
    function testAgentActions() public {
        vm.startPrank(agent);

        // Test setting reserve ratio through agent
        bytes memory data = abi.encode(30); // 30%
        vm.expectEmit(false, false, false, true);
        emit ReserveRatioSet(20, 30);
        (bool success, bytes memory result) = vault.executeAgentAction(1, data);
        assertTrue(success);
        assertEq(vault.reserveRatio(), 30);
        assertEq(abi.decode(result, (uint256)), 30);

        // Test setting minimum liquidity through agent
        data = abi.encode(2000);
        vm.expectEmit(false, false, false, true);
        emit MinLiquiditySet(1000, 2000);
        (success, result) = vault.executeAgentAction(2, data);
        assertTrue(success);
        assertEq(vault.minLiquidity(), 2000);
        assertEq(abi.decode(result, (uint256)), 2000);

        // Test invalid action
        (success, ) = vault.executeAgentAction(3, data);
        assertFalse(success);

        vm.stopPrank();
    }

    /**
     * @dev Test agent actions without permission
     */
    function testAgentActionsWithoutPermission() public {
        vm.startPrank(attacker);

        bytes memory data = abi.encode(30);
        // Simplemente capturamos cualquier revert, ya que el mensaje exacto puede variar
        vm.expectRevert();
        vault.executeAgentAction(1, data);

        vm.stopPrank();
    }

    /**
     * @dev Test distributeRewards function
     */
    function testDistributeRewards() public {
        // Set up deposits for two users
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), 500 * 10 ** 18);
        vault.deposit(500 * 10 ** 18);
        vm.stopPrank();

        // Distribute rewards
        rewardsToken.approve(address(vault), 1500 * 10 ** 18);
        vault.distributeRewards(1500 * 10 ** 18);

        // Check rewards - should be proportional to deposits
        uint256 user1Rewards = vault.getAccruedRewards(user1);
        uint256 user2Rewards = vault.getAccruedRewards(user2);

        assertEq(user1Rewards, 1000 * 10 ** 18);
        assertEq(user2Rewards, 500 * 10 ** 18);
    }

    /**
     * @dev Test distributeRewards with validation issues
     */
    function testDistributeRewardsValidation() public {
        // Deposit first to have shares outstanding
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Test zero amount
        vm.expectRevert("RewardVault: zero amount");
        vault.distributeRewards(0);

        // Test insufficient allowance
        rewardsToken.approve(address(vault), 500 * 10 ** 18);
        // Simplemente capturamos cualquier revert, ya que el mensaje exacto puede variar
        vm.expectRevert();
        vault.distributeRewards(1000 * 10 ** 18);

        // Test insufficient balance (actual balance == INITIAL_SUPPLY)
        uint256 tooMuch = rewardsToken.balanceOf(address(this)) + 1; // One more than our balance
        rewardsToken.approve(address(vault), tooMuch);
        // Simplemente capturamos cualquier revert, ya que el mensaje exacto puede variar
        vm.expectRevert();
        vault.distributeRewards(tooMuch);
    }

    /**
     * @dev Test claimRewards function
     */
    function testClaimRewards() public {
        // Set up deposits for two users
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), 500 * 10 ** 18);
        vault.deposit(500 * 10 ** 18);
        vm.stopPrank();

        // Distribute rewards
        rewardsToken.approve(address(vault), 1500 * 10 ** 18);
        vault.distributeRewards(1500 * 10 ** 18);

        // Claim rewards
        vm.prank(user1);
        uint256 claimedRewards = vault.claimRewards(user1);
        assertEq(claimedRewards, 1000 * 10 ** 18);
        assertEq(rewardsToken.balanceOf(user1), claimedRewards);

        // Check rewards are reset
        assertEq(vault.getAccruedRewards(user1), 0);

        // Second user claims
        vm.prank(user2);
        claimedRewards = vault.claimRewards(user2);
        assertEq(claimedRewards, 500 * 10 ** 18);
        assertEq(rewardsToken.balanceOf(user2), claimedRewards);
    }

    /**
     * @dev Test reward accrual after additional deposits and withdrawals
     */
    function testRewardAccrualWithDepositsAndWithdrawals() public {
        // Initial deposits
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // Distribute initial rewards (1000 tokens)
        rewardsToken.approve(address(vault), 1000 * 10 ** 18);
        vault.distributeRewards(1000 * 10 ** 18);

        // User1 has all the shares, so gets all rewards
        assertEq(vault.getAccruedRewards(user1), 1000 * 10 ** 18);

        // User2 deposits after rewards distributed
        vm.startPrank(user2);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        // User2 should have 0 rewards at this point
        assertEq(vault.getAccruedRewards(user2), 0);

        // Distribute more rewards (2000 tokens)
        rewardsToken.approve(address(vault), 2000 * 10 ** 18);
        vault.distributeRewards(2000 * 10 ** 18);

        // Rewards should be split 50/50 between the two users for the second distribution
        assertEq(
            vault.getAccruedRewards(user1),
            1000 * 10 ** 18 + 1000 * 10 ** 18
        );
        assertEq(vault.getAccruedRewards(user2), 1000 * 10 ** 18);

        // User1 withdraws half their deposit
        vm.startPrank(user1);
        vault.withdraw(500 * 10 ** 18);
        vm.stopPrank();

        // Distribute more rewards (1500 tokens)
        rewardsToken.approve(address(vault), 1500 * 10 ** 18);
        vault.distributeRewards(1500 * 10 ** 18);

        // User1 now has 1/3 of the shares, User2 has 2/3
        uint256 user1ExpectedRewards = 1000 *
            10 ** 18 +
            1000 *
            10 ** 18 +
            500 *
            10 ** 18;
        uint256 user2ExpectedRewards = 1000 * 10 ** 18 + 1000 * 10 ** 18;

        assertApproxEqAbs(
            vault.getAccruedRewards(user1),
            user1ExpectedRewards,
            1e17
        ); // Allow small rounding error
        assertApproxEqAbs(
            vault.getAccruedRewards(user2),
            user2ExpectedRewards,
            1e17
        ); // Allow small rounding error
    }

    /**
     * @dev Test totalAssets function
     */
    function testTotalAssets() public {
        // Initial state
        assertEq(vault.totalAssets(), 0);

        // After deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1000 * 10 ** 18);

        // After withdraw
        vm.startPrank(user1);
        vault.withdraw(300 * 10 ** 18);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 700 * 10 ** 18);
    }
}
