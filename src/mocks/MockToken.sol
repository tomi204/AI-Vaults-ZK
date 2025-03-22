// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockToken
 * @dev A simple ERC20 token for testing with decimal support and burn functionality
 */
contract MockToken is ERC20, Ownable {
    uint8 private _decimals;

    /**
     * @dev Constructor
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @param decimals_ Decimals of the token (default 18)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_ == 0 ? 18 : decimals_;
        // Mint initial supply to deployer
        _mint(msg.sender, 1000000 * 10 ** _decimals);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mint tokens - only callable by the owner
     * @param account Account to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /**
     * @dev Burn tokens - only callable by the owner
     * @param account Account to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    /**
     * @dev Self-burn tokens - only callable by the token holder
     * @param amount Amount of tokens to burn
     */
    function burnSelf(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
