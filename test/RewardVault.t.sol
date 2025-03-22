// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "./mocks/MockERC20.sol";

/**
 * @title RewardVaultTest
 * @dev Test contract for RewardVault
 */
contract RewardVaultTest is Test {
    RewardVault public vault;
    MockERC20 public asset;
    MockERC20 public rewardsToken;
    RewardsDistributor public rewardsDistributor;
    address public admin;
    address public user1;
    address public user2;

    // Constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

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

        // Transfer rewards tokens to this contract for distribution
        rewardsToken.transfer(address(this), 10000 * 10 ** 18);
    }

    /**
     * @dev Test deposit
     */
    function testDeposit() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 1000 * 10 ** 18);
        assertEq(asset.balanceOf(address(vault)), 1000 * 10 ** 18);
    }

    /**
     * @dev Test withdraw
     */
    function testWithdraw() public {
        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10 ** 18);
        vault.deposit(1000 * 10 ** 18);

        // User1 withdraws
        vault.withdraw(500 * 10 ** 18);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 500 * 10 ** 18);
        assertEq(asset.balanceOf(address(vault)), 500 * 10 ** 18);
        assertEq(asset.balanceOf(user1), 9500 * 10 ** 18);
    }

    /**
     * @dev Test agent actions
     */
    function testAgentActions() public {
        // Set reserve ratio through agent
        bytes memory data = abi.encode(30); // 30%

        (bool success, ) = vault.executeAgentAction(1, data);
        assertTrue(success);
        assertEq(vault.reserveRatio(), 30);

        // Set minimum liquidity through agent
        data = abi.encode(2000);

        (success, ) = vault.executeAgentAction(2, data);
        assertTrue(success);
        assertEq(vault.minLiquidity(), 2000);
    }

    /**
     * @dev Test reward distribution
     */
    function testRewardDistribution() public {
        // Deposit assets
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

        // Check rewards
        uint256 user1Rewards = vault.getAccruedRewards(user1);
        uint256 user2Rewards = vault.getAccruedRewards(user2);

        assertEq(user1Rewards, 1000 * 10 ** 18);
        assertEq(user2Rewards, 500 * 10 ** 18);

        // Claim rewards
        vm.prank(user1);
        uint256 claimedRewards = vault.claimRewards(user1);
        assertEq(claimedRewards, user1Rewards);
        assertEq(rewardsToken.balanceOf(user1), claimedRewards);
    }
}
