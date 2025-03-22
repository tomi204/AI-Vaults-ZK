// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/strategies/DefaultStrategy.sol";
import "./mocks/MockERC20.sol";

/**
 * @title DefaultStrategyTest
 * @dev Comprehensive test for DefaultStrategy contract
 */
contract DefaultStrategyTest is Test {
    DefaultStrategy public strategy;
    MockERC20 public asset;
    address public vault;
    address public admin;
    address public agent;
    address public guardian;
    address public attacker;

    // Constants
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // Action IDs
    uint256 private constant ACTION_DEPOSIT = 1;
    uint256 private constant ACTION_WITHDRAW = 2;
    uint256 private constant ACTION_SET_RESERVE_RATIO = 3;
    uint256 private constant ACTION_CUSTOM_FUNCTION = 4;
    uint256 private constant ACTION_SET_MIN_LIQUIDITY = 5;

    // Events
    event ReserveRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event MinLiquidityUpdated(uint256 oldValue, uint256 newValue);
    event AssetDeposited(address indexed asset, uint256 amount);
    event AssetWithdrawn(address indexed asset, uint256 amount);
    event CustomFunctionExecuted(bytes data, bool success);
    event EmergencyWithdrawal(
        address indexed asset,
        uint256 amount,
        address recipient
    );
    event StrategyExecuted(uint256 indexed actionId, bool success);

    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        admin = address(this);
        vault = address(0xBB);
        agent = address(0xCC);
        guardian = address(0xDD);
        attacker = address(0xEE);

        // Deploy mock token
        asset = new MockERC20("Test Asset", "ASSET");

        // Create array of supported assets
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(asset);

        // Deploy strategy
        vm.startPrank(vault);
        strategy = new DefaultStrategy(vault, supportedAssets);

        // Set up roles
        strategy.grantAgentRole(agent);
        strategy.grantGuardianRole(guardian);
        vm.stopPrank();

        // Transfer assets to vault for deposits
        asset.transfer(vault, 100000 * 10 ** 18);
    }

    /**
     * @dev Test constructor and initial setup
     */
    function testConstructor() public {
        assertEq(strategy.vault(), vault);
        assertTrue(strategy.hasRole(VAULT_ROLE, vault));
        assertEq(strategy.riskLevel(), 1); // Default risk level is 1
        assertEq(strategy.supportedAssets(0), address(asset));
        assertEq(strategy.reserveRatio(), 20); // Default is 20%
        assertEq(strategy.minLiquidity(), 100 * 10 ** 18); // Default is 100 tokens
    }

    /**
     * @dev Test constructor with zero vault address
     */
    function testConstructorZeroVault() public {
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(asset);

        vm.expectRevert("BaseStrategy: vault is the zero address");
        new DefaultStrategy(address(0), supportedAssets);
    }

    /**
     * @dev Test deposit function
     */
    function testDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Transfer tokens to the strategy
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), depositAmount);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + depositAmount);

        // Deposit assets
        vm.expectEmit(true, false, false, true);
        emit AssetDeposited(address(asset), depositAmount);
        uint256 result = strategy.deposit(address(asset), depositAmount);
        vm.stopPrank();

        assertEq(result, depositAmount);
        assertEq(strategy.getBalance(address(asset)), depositAmount);
    }

    /**
     * @dev Test deposit with unauthorized caller
     */
    function testDepositUnauthorized() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Try to deposit as non-vault
        vm.startPrank(attacker);
        vm.expectRevert("BaseStrategy: caller is not the vault");
        strategy.deposit(address(asset), depositAmount);
        vm.stopPrank();
    }

    /**
     * @dev Test deposit with zero amount
     */
    function testDepositZeroAmount() public {
        // Try to deposit zero
        vm.startPrank(vault);
        vm.expectRevert("BaseStrategy: deposit amount is zero");
        strategy.deposit(address(asset), 0);
        vm.stopPrank();
    }

    /**
     * @dev Test deposit with unsupported asset
     */
    function testDepositUnsupportedAsset() public {
        // Deploy a new token not supported by the strategy
        MockERC20 unsupportedAsset = new MockERC20("Unsupported", "UNS");

        // Try to deposit unsupported asset
        vm.startPrank(vault);
        vm.expectRevert("BaseStrategy: unsupported asset");
        strategy.deposit(address(unsupportedAsset), 1000 * 10 ** 18);
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw function
     */
    function testWithdraw() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 500 * 10 ** 18;

        // First deposit - transfer tokens and verify transfer
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), depositAmount);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + depositAmount);

        // Now deposit
        strategy.deposit(address(asset), depositAmount);

        // Then withdraw
        vm.expectEmit(true, false, false, true);
        emit AssetWithdrawn(address(asset), withdrawAmount);
        uint256 result = strategy.withdraw(address(asset), withdrawAmount);
        vm.stopPrank();

        assertEq(result, withdrawAmount);
        assertEq(
            strategy.getBalance(address(asset)),
            depositAmount - withdrawAmount
        );
        assertEq(
            asset.balanceOf(vault),
            100000 * 10 ** 18 - depositAmount + withdrawAmount
        );
    }

    /**
     * @dev Test withdraw with insufficient balance
     */
    function testWithdrawInsufficientBalance() public {
        // Deposit a small amount
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 500 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 500 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 500 * 10 ** 18);

        // Try to withdraw more than deposited
        vm.expectRevert("DefaultStrategy: insufficient balance");
        strategy.withdraw(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw respecting reserve ratio
     */
    function testWithdrawRespectingReserveRatio() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Deposit - transfer tokens and verify transfer
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), depositAmount);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + depositAmount);

        // Now deposit
        strategy.deposit(address(asset), depositAmount);

        // Set reserve ratio to 50%
        bytes memory data = abi.encode(50);
        strategy.grantRole(AGENT_ROLE, vault); // Give vault agent role temporarily
        strategy.executeStrategy(ACTION_SET_RESERVE_RATIO, data);

        // Try to withdraw more than allowed by reserve ratio
        // 50% of 1000 = 500 must be kept as reserve, so can only withdraw up to 500
        uint256 result = strategy.withdraw(address(asset), 700 * 10 ** 18);
        vm.stopPrank();

        // Should only have withdrawn 500 (the max available given reserve ratio)
        assertEq(result, 500 * 10 ** 18);
        assertEq(strategy.getBalance(address(asset)), 500 * 10 ** 18);
    }

    /**
     * @dev Test withdraw respecting min liquidity
     */
    function testWithdrawRespectingMinLiquidity() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Deposit - transfer tokens and verify transfer
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), depositAmount);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + depositAmount);

        // Now deposit
        strategy.deposit(address(asset), depositAmount);

        // Set min liquidity to 800
        bytes memory data = abi.encode(800 * 10 ** 18);
        strategy.grantRole(AGENT_ROLE, vault); // Give vault agent role temporarily
        strategy.executeStrategy(ACTION_SET_MIN_LIQUIDITY, data);

        // Try to withdraw more than allowed by min liquidity
        // Min liquidity is 800, so can only withdraw up to 200
        uint256 result = strategy.withdraw(address(asset), 300 * 10 ** 18);
        vm.stopPrank();

        // Should only have withdrawn 200 (the max available given min liquidity)
        assertEq(result, 200 * 10 ** 18);
        assertEq(strategy.getBalance(address(asset)), 800 * 10 ** 18);
    }

    /**
     * @dev Test executeStrategy deposit action
     */
    function testExecuteStrategyDeposit() public {
        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer assets directly to the strategy
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        vm.startPrank(agent);

        // Prepare data for deposit action
        bytes memory depositData = abi.encode(address(asset), 1000 * 10 ** 18);

        // Execute deposit via strategy execution
        vm.expectEmit(true, false, false, true);
        emit StrategyExecuted(ACTION_DEPOSIT, true);
        (bool success, ) = strategy.executeStrategy(
            ACTION_DEPOSIT,
            depositData
        );

        vm.stopPrank();

        assertTrue(success);
        assertEq(strategy.getBalance(address(asset)), 1000 * 10 ** 18);
    }

    /**
     * @dev Test executeStrategy withdraw action
     */
    function testExecuteStrategyWithdraw() public {
        // First deposit tokens
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();

        // Check balance after deposit
        assertEq(strategy.getBalance(address(asset)), 1000 * 10 ** 18);

        // Execute withdraw via strategy execution
        vm.startPrank(agent);
        bytes memory withdrawData = abi.encode(address(asset), 500 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit StrategyExecuted(ACTION_WITHDRAW, true);
        (bool success, ) = strategy.executeStrategy(
            ACTION_WITHDRAW,
            withdrawData
        );

        vm.stopPrank();

        assertTrue(success);
        assertEq(strategy.getBalance(address(asset)), 500 * 10 ** 18);
    }

    /**
     * @dev Test executeStrategy set reserve ratio action
     */
    function testExecuteStrategySetReserveRatio() public {
        uint256 newRatio = 30;
        bytes memory data = abi.encode(newRatio);

        vm.startPrank(agent);
        vm.expectEmit(false, false, false, true);
        emit ReserveRatioUpdated(20, newRatio);
        vm.expectEmit(true, false, false, true);
        emit StrategyExecuted(ACTION_SET_RESERVE_RATIO, true);
        (bool success, bytes memory result) = strategy.executeStrategy(
            ACTION_SET_RESERVE_RATIO,
            data
        );
        vm.stopPrank();

        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), newRatio);
        assertEq(strategy.reserveRatio(), newRatio);
    }

    /**
     * @dev Test executeStrategy set min liquidity action
     */
    function testExecuteStrategySetMinLiquidity() public {
        uint256 newMinLiquidity = 200 * 10 ** 18;
        bytes memory data = abi.encode(newMinLiquidity);

        vm.startPrank(agent);
        vm.expectEmit(false, false, false, true);
        emit MinLiquidityUpdated(100 * 10 ** 18, newMinLiquidity);
        vm.expectEmit(true, false, false, true);
        emit StrategyExecuted(ACTION_SET_MIN_LIQUIDITY, true);
        (bool success, bytes memory result) = strategy.executeStrategy(
            ACTION_SET_MIN_LIQUIDITY,
            data
        );
        vm.stopPrank();

        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), newMinLiquidity);
        assertEq(strategy.minLiquidity(), newMinLiquidity);
    }

    /**
     * @dev Test executeStrategy with invalid action
     */
    function testExecuteStrategyInvalidAction() public {
        bytes memory data = abi.encode(30);

        vm.startPrank(agent);
        vm.expectRevert("DefaultStrategy: invalid action ID");
        strategy.executeStrategy(999, data); // Invalid action ID
        vm.stopPrank();
    }

    /**
     * @dev Test executeStrategy with unauthorized caller
     */
    function testExecuteStrategyUnauthorized() public {
        bytes memory data = abi.encode(30);

        vm.startPrank(attacker);
        vm.expectRevert("BaseStrategy: caller is not an agent");
        strategy.executeStrategy(ACTION_SET_RESERVE_RATIO, data);
        vm.stopPrank();
    }

    /**
     * @dev Test pause and unpause functionality
     */
    function testPauseUnpause() public {
        // Pause the strategy
        vm.startPrank(guardian);
        strategy.pause();
        vm.stopPrank();

        // Verify paused state
        bool paused = strategy.paused();
        assertTrue(paused);

        // Try to execute an action when paused
        vm.startPrank(agent);
        vm.expectRevert();
        strategy.executeStrategy(ACTION_SET_RESERVE_RATIO, abi.encode(30));
        vm.stopPrank();

        // Unpause the strategy - this should be done by the vault, not guardian
        vm.startPrank(vault);
        strategy.unpause();
        vm.stopPrank();

        // Verify unpaused state
        paused = strategy.paused();
        assertFalse(paused);

        // Execute an action after unpausing
        vm.startPrank(agent);
        (bool success, ) = strategy.executeStrategy(
            ACTION_SET_RESERVE_RATIO,
            abi.encode(30)
        );
        vm.stopPrank();
        assertTrue(success);
        assertEq(strategy.reserveRatio(), 30);
    }

    /**
     * @dev Test emergency withdrawal
     */
    function testEmergencyWithdrawal() public {
        // First deposit tokens
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();

        // Check initial balance
        assertEq(strategy.getBalance(address(asset)), 1000 * 10 ** 18);

        // Execute emergency withdrawal as guardian
        vm.startPrank(guardian);

        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawal(address(asset), 1000 * 10 ** 18, vault);
        strategy.emergencyWithdraw(address(asset));

        vm.stopPrank();

        // Check all tokens were withdrawn to vault
        assertEq(strategy.getBalance(address(asset)), 0);
        // Initial vault balance (100000) - initial deposit (1000) + emergency withdrawn (1000)
        assertEq(asset.balanceOf(vault), 100000 * 10 ** 18);
    }

    /**
     * @dev Test emergency withdrawal with unauthorized caller
     */
    function testEmergencyWithdrawalUnauthorized() public {
        // First deposit tokens
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();

        // Try to execute emergency withdrawal as attacker
        vm.startPrank(attacker);

        vm.expectRevert("BaseStrategy: caller is not a guardian");
        strategy.emergencyWithdraw(address(asset));

        vm.stopPrank();

        // Check tokens are still in the strategy
        assertEq(strategy.getBalance(address(asset)), 1000 * 10 ** 18);
    }

    /**
     * @dev Test setEmergencyRecipient function
     */
    function testSetEmergencyRecipient() public {
        address newRecipient = address(0xFF);

        vm.startPrank(vault);
        strategy.setEmergencyRecipient(newRecipient);
        vm.stopPrank();

        assertEq(strategy.emergencyRecipient(), newRecipient);

        // Test with zero address
        vm.startPrank(vault);
        vm.expectRevert("BaseStrategy: zero address");
        strategy.setEmergencyRecipient(address(0));
        vm.stopPrank();
    }

    /**
     * @dev Test getWithdrawableAmount function
     */
    function testGetWithdrawableAmount() public {
        // Deposit tokens
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();

        // Default: reserve ratio = 20%, min liquidity = 100 tokens
        // Withdrawable = 1000 - max(20% of 1000, 100) = 1000 - max(200, 100) = 1000 - 200 = 800
        assertEq(
            strategy.getWithdrawableAmount(address(asset)),
            800 * 10 ** 18
        );

        // Change reserve ratio to 50%
        vm.startPrank(agent);
        bytes memory data = abi.encode(50);
        strategy.executeStrategy(ACTION_SET_RESERVE_RATIO, data);
        vm.stopPrank();

        // Now: reserve ratio = 50%, min liquidity = 100 tokens
        // Withdrawable = 1000 - max(50% of 1000, 100) = 1000 - max(500, 100) = 1000 - 500 = 500
        assertEq(
            strategy.getWithdrawableAmount(address(asset)),
            500 * 10 ** 18
        );

        // Change min liquidity to 600
        vm.startPrank(agent);
        data = abi.encode(600 * 10 ** 18);
        strategy.executeStrategy(ACTION_SET_MIN_LIQUIDITY, data);
        vm.stopPrank();

        // Now: reserve ratio = 50%, min liquidity = 600 tokens
        // Withdrawable = 1000 - max(50% of 1000, 600) = 1000 - max(500, 600) = 1000 - 600 = 400
        assertEq(
            strategy.getWithdrawableAmount(address(asset)),
            400 * 10 ** 18
        );
    }

    /**
     * @dev Test calculateAPY and calculateTVL
     */
    function testPerformanceMetrics() public {
        // Get initial metrics
        (uint256 apy, uint256 tvl, uint8 risk) = strategy
            .getPerformanceMetrics();

        assertEq(apy, 0); // Default strategy has 0 APY
        assertEq(tvl, 0); // No deposits yet
        assertEq(risk, 1); // Risk level 1 (low)

        // Deposit tokens and check TVL changes
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);
        vm.stopPrank();

        (apy, tvl, risk) = strategy.getPerformanceMetrics();

        assertEq(apy, 0); // Still 0 APY
        assertEq(tvl, 1000 * 10 ** 18); // TVL should match deposit
        assertEq(risk, 1); // Risk level should remain the same
    }

    /**
     * @dev Test adding and removing supported assets
     */
    function testSupportedAssets() public {
        // Deploy a new token
        MockERC20 newAsset = new MockERC20("New Asset", "NEW");

        // Add as supported asset
        vm.startPrank(vault);
        strategy.addSupportedAsset(address(newAsset));
        vm.stopPrank();

        // Check it was added
        assertEq(strategy.supportedAssets(1), address(newAsset));

        // Try to add again - should fail
        vm.startPrank(vault);
        vm.expectRevert("BaseStrategy: asset already supported");
        strategy.addSupportedAsset(address(newAsset));
        vm.stopPrank();

        // Remove asset
        vm.startPrank(vault);
        strategy.removeSupportedAsset(address(newAsset));
        vm.stopPrank();

        // Check it's gone - the array shifts elements
        assertEq(strategy.supportedAssets(0), address(asset)); // Original asset still there
        vm.expectRevert(); // Trying to access index 1 should revert as array is smaller now
        strategy.supportedAssets(1);
    }

    /**
     * @dev Test validateAction function
     */
    function testValidateAction() public {
        // Valid action - set reserve ratio to 30
        bytes memory data = abi.encode(30);
        (bool valid, ) = strategy.validateAction(
            ACTION_SET_RESERVE_RATIO,
            data
        );
        assertTrue(valid);

        // Invalid action - set reserve ratio too high
        data = abi.encode(51);
        (valid, ) = strategy.validateAction(ACTION_SET_RESERVE_RATIO, data);
        assertFalse(valid);

        // Valid action - deposit
        data = abi.encode(address(asset), 1000);
        (valid, ) = strategy.validateAction(ACTION_DEPOSIT, data);
        assertTrue(valid);

        // Invalid action - deposit zero amount
        data = abi.encode(address(asset), 0);
        (valid, ) = strategy.validateAction(ACTION_DEPOSIT, data);
        assertFalse(valid);

        // Invalid action - unknown action ID
        data = abi.encode(30);
        (valid, ) = strategy.validateAction(999, data);
        assertFalse(valid);
    }

    /**
     * @dev Test providing emergency liquidity
     */
    function testProvideEmergencyLiquidity() public {
        // Deposit tokens
        vm.startPrank(vault);

        // Get balance before transfer
        uint256 strategyBalanceBefore = asset.balanceOf(address(strategy));

        // Transfer the tokens
        asset.transfer(address(strategy), 1000 * 10 ** 18);

        // Verify the transfer occurred
        uint256 strategyBalanceAfter = asset.balanceOf(address(strategy));
        assertEq(strategyBalanceAfter, strategyBalanceBefore + 1000 * 10 ** 18);

        // Now deposit
        strategy.deposit(address(asset), 1000 * 10 ** 18);

        // Provide emergency liquidity
        uint256 provided = strategy.provideEmergencyLiquidity(
            address(asset),
            400 * 10 ** 18
        );
        vm.stopPrank();

        assertEq(provided, 400 * 10 ** 18);
        assertEq(strategy.getBalance(address(asset)), 600 * 10 ** 18);

        // Initial balance (100000) - deposit (1000) + provided (400)
        assertEq(asset.balanceOf(vault), 99400 * 10 ** 18);
    }

    /**
     * @dev Test role-based access control
     */
    function testRoleManagement() public {
        address newAgent = address(0x123);
        address newGuardian = address(0x456);

        // Grant roles
        vm.startPrank(vault);
        strategy.grantAgentRole(newAgent);
        strategy.grantGuardianRole(newGuardian);
        vm.stopPrank();

        assertTrue(strategy.hasRole(AGENT_ROLE, newAgent));
        assertTrue(strategy.hasRole(GUARDIAN_ROLE, newGuardian));

        // Revoke roles
        vm.startPrank(vault);
        strategy.revokeAgentRole(newAgent);
        strategy.revokeGuardianRole(newGuardian);
        vm.stopPrank();

        assertFalse(strategy.hasRole(AGENT_ROLE, newAgent));
        assertFalse(strategy.hasRole(GUARDIAN_ROLE, newGuardian));
    }
}
