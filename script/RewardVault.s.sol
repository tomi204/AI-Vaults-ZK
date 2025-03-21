// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/RewardVault.sol";
import "../src/RewardsDistributor.sol";
import "../src/strategies/DefaultStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev Simple ERC20 token for deployment script
 */
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

/**
 * @title RewardVaultScript
 * @dev Script for deploying the RewardVault contract
 */
contract RewardVaultScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a mock ERC20 token to use as the asset
        MockToken asset = new MockToken("Mock Token", "MTK");

        // Mock rewards token (in production this would be a real token)
        MockToken rewardsToken = new MockToken("Rewards Token", "RWD");

        // Deploy the RewardVault
        RewardVault vault = new RewardVault(
            msg.sender, // admin
            IERC20(address(asset)),
            "Reward Vault Token",
            "RVT",
            msg.sender, // agent (same as admin for simplicity)
            address(rewardsToken)
        );

        // Set up a default strategy
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(asset);

        DefaultStrategy strategy = new DefaultStrategy(
            address(vault),
            supportedAssets
        );

        // Add strategy to vault
        vault.addStrategy(RewardVault.StrategyType.DEFAULT, address(strategy));

        // Mint some tokens to the deployer to play with
        asset.transfer(msg.sender, 100000 * 10 ** 18);

        // Add some initial rewards to the distributor
        address distributor = address(vault.rewardsDistributor());
        rewardsToken.transfer(distributor, 10000 * 10 ** 18);
        RewardsDistributor(distributor).addRewards(10000 * 10 ** 18);

        console.log("RewardVault deployed at:", address(vault));
        console.log("DefaultStrategy deployed at:", address(strategy));
        console.log("Underlying Asset:", address(asset));
        console.log("Rewards Token:", address(rewardsToken));

        vm.stopBroadcast();
    }
}
