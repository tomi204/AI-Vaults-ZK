// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev A simple ERC20 token for testing
 */
contract MockToken is ERC20 {
    /**
     * @dev Constructor
     * @param name Name of the token
     * @param symbol Symbol of the token
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    /**
     * @dev Mint tokens
     * @param account Account to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
