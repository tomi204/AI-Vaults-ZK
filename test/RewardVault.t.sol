// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "../src/strategies/DefaultStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev Simple ERC20 token with minting capabilities for testing
 */
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title RewardVaultTest
 * @dev Test contract for RewardVault
 */
contract RewardVaultTest is Test {
    MockToken public asset;
    MockToken public rewardsToken;
    RewardVault public vault;
    DefaultStrategy public strategy;
    address public admin;
    address public user1;
    address public user2;
    address public agent;

    // Constant values for tests
    uint256 constant INITIAL_DEPOSIT = 1000 * 10 ** 18;
    uint256 constant ALLOCATION_AMOUNT = 500 * 10 ** 18;

    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        agent = makeAddr("agent");

        vm.startPrank(admin);

        // Deploy mock tokens
        asset = new MockToken("Test Token", "TT");
        rewardsToken = new MockToken("Rewards Token", "RWD");

        // Deploy the vault
        vault = new RewardVault(
            admin,
            IERC20(address(asset)),
            "Reward Vault Token",
            "RVT",
            agent,
            address(rewardsToken)
        );

        // Deploy the default strategy
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(asset);
        strategy = new DefaultStrategy(address(vault), supportedAssets);
        vault.addStrategy(RewardVault.StrategyType.DEFAULT, address(strategy));

        // Transfer tokens to users
        asset.transfer(user1, 10000 * 10 ** 18);
        asset.transfer(user2, 10000 * 10 ** 18);

        // Get the RewardsDistributor address
        address rewardsDistributor = address(vault.rewardsDistributor());

        // Approve the RewardsDistributor to spend rewards tokens
        rewardsToken.approve(rewardsDistributor, 100000 * 10 ** 18);

        // Add rewards to the distributor
        IRewardsDistributor(rewardsDistributor).addRewards(10000 * 10 ** 18);

        vm.stopPrank();
    }

    /**
     * @dev Test deposit and withdraw functions
     */
    function testDepositAndWithdraw() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        // Deposit as user1
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Check vault balance
        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);

        // Withdraw half of the amount
        uint256 withdrawAmount = depositAmount / 2;
        vault.withdraw(withdrawAmount);

        // Check new balances
        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
        vm.stopPrank();
    }

    /**
     * @dev Test rewards accrual and claiming
     */
    function testRewardsAccrual() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        // Deposit as user1
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Move time forward to accrue rewards
        vm.warp(block.timestamp + 7 days);

        // Check accrued rewards
        uint256 accruedRewards = vault.getAccruedRewards(user1);
        console.log("Accrued rewards after 7 days:", accruedRewards);
        assertGt(accruedRewards, 0);

        // Claim rewards
        vm.startPrank(user1);
        uint256 claimedRewards = vault.claimRewards();
        vm.stopPrank();

        // Check that rewards were claimed
        assertEq(claimedRewards, accruedRewards);
        assertEq(rewardsToken.balanceOf(user1), claimedRewards);
        assertEq(vault.getAccruedRewards(user1), 0);
    }

    /**
     * @dev Test multiple users with different deposit amounts
     */
    function testMultipleUsers() public {
        uint256 user1DepositAmount = INITIAL_DEPOSIT;
        uint256 user2DepositAmount = INITIAL_DEPOSIT / 2;

        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), user1DepositAmount);
        vault.deposit(user1DepositAmount);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        asset.approve(address(vault), user2DepositAmount);
        vault.deposit(user2DepositAmount);
        vm.stopPrank();

        // Move time forward to accrue rewards
        vm.warp(block.timestamp + 7 days);

        // Check rewards for both users
        uint256 user1Rewards = vault.getAccruedRewards(user1);
        uint256 user2Rewards = vault.getAccruedRewards(user2);

        console.log("User1 rewards:", user1Rewards);
        console.log("User2 rewards:", user2Rewards);

        // User1 should have approximately twice the rewards of user2
        assertApproxEqRel(user1Rewards, user2Rewards * 2, 0.01e18); // 1% tolerance
    }

    /**
     * @dev Test allocating and withdrawing from strategy
     */
    function testStrategyAllocation() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT);
        vm.stopPrank();

        // Agent allocates funds to strategy
        vm.startPrank(agent);
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            ALLOCATION_AMOUNT
        );
        vm.stopPrank();

        // Check balances
        assertEq(
            asset.balanceOf(address(vault)),
            INITIAL_DEPOSIT - ALLOCATION_AMOUNT
        );
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT);
        assertEq(strategy.getBalance(address(asset)), ALLOCATION_AMOUNT);

        // Agent withdraws from strategy
        vm.startPrank(agent);
        uint256 withdrawn = vault.withdrawFromStrategy(
            RewardVault.StrategyType.DEFAULT,
            ALLOCATION_AMOUNT
        );
        vm.stopPrank();

        // Check balances after withdrawal
        assertEq(withdrawn, ALLOCATION_AMOUNT);
        assertEq(asset.balanceOf(address(vault)), INITIAL_DEPOSIT);
        assertEq(strategy.getBalance(address(asset)), 0);
    }

    /**
     * @dev Test reserve ratio functionality
     */
    function testReserveRatio() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT);
        vm.stopPrank();

        // Set reserve ratio to 30%
        vm.startPrank(admin);
        vault.setReserveRatio(30);
        assertEq(vault.getReserveRatio(), 30);
        vm.stopPrank();

        // Calculate max allocation (70% of deposits)
        uint256 expectedMaxAllocation = (INITIAL_DEPOSIT * 70) / 100;

        // Attempt to allocate more than allowed (should fail)
        vm.startPrank(agent);
        vm.expectRevert("RewardVault: insufficient balance after reserve");
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            (INITIAL_DEPOSIT * 80) / 100
        );
        vm.stopPrank();

        // Allocate allowed amount
        vm.startPrank(agent);
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            expectedMaxAllocation
        );
        vm.stopPrank();

        // Check balances
        assertEq(
            asset.balanceOf(address(vault)),
            INITIAL_DEPOSIT - expectedMaxAllocation
        );
        assertEq(strategy.getBalance(address(asset)), expectedMaxAllocation);
    }

    /**
     * @dev Test auto-withdrawal from strategy when user withdraws
     */
    function testAutoWithdrawalFromStrategy() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT);
        vm.stopPrank();

        // Agent allocates 80% to strategy
        uint256 allocationAmount = (INITIAL_DEPOSIT * 80) / 100;
        vm.startPrank(agent);
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            allocationAmount
        );
        vm.stopPrank();

        // User1 tries to withdraw more than available liquidity (should auto-withdraw from strategy)
        uint256 withdrawAmount = (INITIAL_DEPOSIT * 60) / 100;
        vm.startPrank(user1);
        vault.withdraw(withdrawAmount);
        vm.stopPrank();

        // Check balances (auto-withdrawal should have happened)
        assertEq(vault.balanceOf(user1), INITIAL_DEPOSIT - withdrawAmount);
        assertEq(
            asset.balanceOf(user1),
            10000 * 10 ** 18 - INITIAL_DEPOSIT + withdrawAmount
        );

        // Strategy should have less than the original allocation
        assertLt(strategy.getBalance(address(asset)), allocationAmount);
    }

    /**
     * @dev Test agent executing custom functions via strategy
     */
    function testAgentCustomFunctions() public {
        // User deposits
        vm.startPrank(user1);
        asset.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT);
        vm.stopPrank();

        // Agent allocates to strategy
        vm.startPrank(agent);
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            ALLOCATION_AMOUNT
        );
        vm.stopPrank();

        // Initial reserve ratio is 20%
        assertEq(strategy.reserveRatio(), 20);

        // Agent changes reserve ratio using executeAgentAction
        uint256 newRatio = 30;
        bytes memory data = abi.encode(newRatio);

        vm.startPrank(agent);
        (bool success, bytes memory result) = vault.executeAgentAction(3, data); // 3 is ACTION_SET_RESERVE_RATIO
        vm.stopPrank();

        // Verify execution succeeded
        assertTrue(success);
        assertEq(strategy.reserveRatio(), newRatio);
    }

    /**
     * @dev Test emergency liquidity provision
     */
    function testEmergencyLiquidity() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT);
        vm.stopPrank();

        // Agent allocates most funds to strategy (90%)
        uint256 allocationAmount = (INITIAL_DEPOSIT * 90) / 100;
        vm.startPrank(agent);
        vault.allocateToStrategy(
            RewardVault.StrategyType.DEFAULT,
            allocationAmount
        );
        vm.stopPrank();

        // Set a higher reserve ratio in the strategy to limit normal withdrawals
        vm.startPrank(agent);
        bytes memory setRatioData = abi.encode(40); // 40% reserve ratio
        vault.executeAgentAction(3, setRatioData); // 3 = ACTION_SET_RESERVE_RATIO
        vm.stopPrank();

        // User1 tries to withdraw almost everything - should trigger emergency liquidity
        uint256 withdrawAmount = (INITIAL_DEPOSIT * 85) / 100;
        vm.startPrank(user1);
        vault.withdraw(withdrawAmount);
        vm.stopPrank();

        // Check balances - withdrawal should have succeeded despite reserve ratio limits
        assertEq(vault.balanceOf(user1), INITIAL_DEPOSIT - withdrawAmount);
        assertEq(
            asset.balanceOf(user1),
            10000 * 10 ** 18 - INITIAL_DEPOSIT + withdrawAmount
        );

        // Strategy balance should be reduced significantly
        assertLt(
            strategy.getBalance(address(asset)),
            (allocationAmount * 60) / 100
        );
    }
}
