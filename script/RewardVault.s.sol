// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "../src/strategies/DefaultStrategy.sol";
import "../src/mocks/MockToken.sol";

/**
 * @title DeployScript
 * @dev Script for deploying the RewardVault, RewardsDistributor, and DefaultStrategy
 */
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying contracts with deployer:", deployer);

        // Deploy mock tokens
        MockToken asset = new MockToken("USDC", "USDC", 6);
        MockToken rewardsToken = new MockToken("Rewards Token", "RWD", 18);

        console.log("Deployed asset token at:", address(asset));
        console.log("Deployed rewards token at:", address(rewardsToken));

        // Deploy Rewards Distributor
        RewardsDistributor rewardsDistributor = new RewardsDistributor(
            address(rewardsToken),
            deployer
        );
        console.log(
            "Deployed RewardsDistributor at:",
            address(rewardsDistributor)
        );

        // Deploy the vault
        RewardVault vault = new RewardVault(
            address(asset),
            address(rewardsToken),
            address(rewardsDistributor),
            "USDC Vault",
            "vUSDC"
        );
        console.log("Deployed RewardVault at:", address(vault));

        // Set the vault in the rewards distributor
        rewardsDistributor.setVault(address(vault));
        console.log("Set vault in RewardsDistributor");

        // Deploy the strategy
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(asset);

        DefaultStrategy defaultStrategy = new DefaultStrategy(
            address(vault),
            supportedAssets
        );
        console.log("Deployed DefaultStrategy at:", address(defaultStrategy));

        // Setup roles using the new initialSetup function
        address agent = deployer;
        address guardian = deployer;

        // Call initialSetup to grant agent and guardian roles
        defaultStrategy.initialSetup(agent, guardian);
        console.log("Initial setup complete with agent and guardian roles");

        // Create an initial supply for testing
        asset.mint(deployer, 1000000 * 10 ** 6);
        rewardsToken.mint(deployer, 1000000 * 10 ** 18);
        console.log("Minted initial tokens to deployer");

        // Now we can set up the strategy parameters as agent
        vm.startPrank(agent);
        // Set reserve ratio to 25%
        (bool success, ) = defaultStrategy.executeStrategy(
            3, // ACTION_SET_RESERVE_RATIO
            abi.encode(25)
        );
        require(success, "Failed to set reserve ratio");

        // Set min liquidity to 200 tokens
        (success, ) = defaultStrategy.executeStrategy(
            5, // ACTION_SET_MIN_LIQUIDITY
            abi.encode(200 * 10 ** 6)
        );
        require(success, "Failed to set min liquidity");
        vm.stopPrank();
        console.log("Initialized strategy parameters");

        // Approve and deposit some initial liquidity to the vault
        asset.approve(address(vault), 10000 * 10 ** 6);
        vault.deposit(10000 * 10 ** 6);
        console.log("Initial deposit to vault complete");

        // Distribute some initial rewards
        rewardsToken.approve(address(vault), 1000 * 10 ** 18);
        vault.distributeRewards(1000 * 10 ** 18);
        console.log("Initial rewards distribution complete");

        vm.stopBroadcast();

        console.log("Deployment complete!");
        console.log("-------------------");
        console.log("Vault:", address(vault));
        console.log("RewardsDistributor:", address(rewardsDistributor));
        console.log("DefaultStrategy:", address(defaultStrategy));
        console.log("Asset:", address(asset));
        console.log("Rewards Token:", address(rewardsToken));
        console.log("-------------------");
    }
}
