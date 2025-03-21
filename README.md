# Reward Vault System

A vault system built with Foundry and compatible with zkSync Era that allows users to deposit assets and earn rewards. The system implements ERC4626 standard for tokenized vaults.

## Features

- ERC4626-compliant vault for seamless integration with other DeFi protocols
- Rewards distribution system for depositors
- Multiple strategies for yield generation
- Admin and agent roles for secure management
- zkSync Era compatibility

## Contracts

### Core Contracts

- **RewardVault**: The main vault contract that implements ERC4626 standard with rewards.
- **RewardsDistributor**: Manages the distribution of rewards to vault depositors.

### Strategies

- **BalancerStrategy**: Strategy for interacting with Balancer V2 pools.

### Interfaces

- **ILending**: Generic interface for interacting with lending protocols.
- **IAaveV3Pool**: Interface for interaction with Aave V3 lending pools.
- **IBalancerV2**: Interface for interaction with Balancer V2 vault.
- **IRewardsDistributor**: Interface for rewards distribution.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [zkSync Era toolkit](https://docs.zksync.io/api/tools/zksync-cli/)

### Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd hello_foundry
```

2. Install dependencies:

```bash
forge install
```

3. Build the project:

```bash
forge build
```

### Testing

Run the tests with:

```bash
forge test
```

### Deployment

1. Set up environment variables:

```bash
export PRIVATE_KEY=your_private_key
```

2. Deploy to zkSync Era testnet:

```bash
forge script script/RewardVault.s.sol:RewardVaultScript --broadcast --rpc-url https://testnet.era.zksync.dev
```

## Usage

### Depositing into the Vault

Users can deposit assets into the vault and start earning rewards:

```solidity
// Approve the vault to spend tokens
IERC20(assetAddress).approve(vaultAddress, amount);

// Deposit into the vault
RewardVault(vaultAddress).deposit(amount);
```

### Withdrawing from the Vault

Users can withdraw their assets from the vault:

```solidity
// Withdraw assets
RewardVault(vaultAddress).withdraw(sharesAmount);
```

### Claiming Rewards

Users can claim their accrued rewards:

```solidity
// Claim rewards
RewardVault(vaultAddress).claimRewards();
```

## Architecture

The vault system follows a modular architecture:

1. **Vault**: The core contract that manages user deposits and shares.
2. **Rewards**: A separate system that tracks and distributes rewards based on user deposits.
3. **Strategies**: Pluggable contracts that implement different yield generation strategies.
4. **Pools**: Integration with external lending pools.

## Security Considerations

- The contracts use OpenZeppelin's libraries for standard functionality.
- Access control is implemented using OpenZeppelin's AccessControl.
- Reentrancy protection is added to all external functions that handle assets.
- SafeERC20 is used for safe token transfers.

## License

This project is licensed under the MIT License.
