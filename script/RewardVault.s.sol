// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "../src/mocks/MockToken.sol";

/**
 * @title RewardVaultScript
 * @dev Script for deploying the RewardVault contract
 */
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        MockToken asset = new MockToken("USDC", "USDC");
        MockToken rewardsToken = new MockToken("Rewards Token", "RWD");

        // Deploy Rewards Distributor
        RewardsDistributor rewardsDistributor = new RewardsDistributor(
            address(rewardsToken),
            msg.sender
        );

        // Deploy the vault
        RewardVault vault = new RewardVault(
            address(asset),
            address(rewardsToken),
            address(rewardsDistributor),
            "USDC Vault",
            "vUSDC"
        );

        // Set the vault in the rewards distributor
        rewardsDistributor.setVault(address(vault));

        // Create an initial supply for testing
        // asset.mint(msg.sender, 1000000 * 10 ** 18);
        // rewardsToken.mint(msg.sender, 1000000 * 10 ** 18);

        vm.stopBroadcast();
    }
}
