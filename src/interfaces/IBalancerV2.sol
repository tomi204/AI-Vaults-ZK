// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IAsset
 * @dev Interface for representing tokens in Balancer pools
 */
interface IAsset {
    // Interface to represent multiple tokens for Balancer asset operation
}

/**
 * @title IBalancerV2Vault
 * @dev Interface for interaction with Balancer V2 vault
 */
interface IBalancerV2Vault {
    /**
     * @dev Joins a pool, adding liquidity
     * @param poolId The ID of the pool to join
     * @param sender The address of the sender of the assets
     * @param recipient The address of the recipient of the BPT
     * @param request Join request parameters containing assets, amounts, and user data
     * @return The amounts of BPT minted
     */
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable returns (uint256[] memory);

    /**
     * @dev Exits a pool, removing liquidity
     * @param poolId The ID of the pool to exit
     * @param sender The address of the sender of the BPT
     * @param recipient The address of the recipient of the returned tokens
     * @param request Exit request parameters containing assets, amounts, and user data
     * @return The amounts of tokens withdrawn
     */
    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external returns (uint256[] memory);

    // Struct to define join pool parameters
    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    // Struct to define exit pool parameters
    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }
}
