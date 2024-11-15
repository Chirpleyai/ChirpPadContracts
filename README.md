# ChirpPad Smart Contracts README.md

## Overview

This repository contains two Solidity smart contracts designed for different use cases:
1. **IDODistribution.sol**: A contract for managing token distributions through vesting schedules.
2. **ProjectInvestment.sol**: A contract system for managing investment rounds in various projects.

### 1. IDODistribution.sol

The `IDODistribution` contract allows an owner to create and manage vesting schedules for different projects. It supports:
- Defining vesting rules for token distribution.
- Allocating tokens to users based on percentages.
- Claiming tokens periodically according to the defined vesting schedule.

#### Key Features
- Flexible vesting rule definitions per project.
- Support for batch user allocation settings.
- ERC20 token compatibility checks.
- Event logging for critical operations.
- Recovery mechanisms for mistakenly sent native tokens.

#### Deployment Instructions
1. Ensure you have a deployed ERC20 token contract.
2. Deploy `IDODistribution.sol` by specifying the address of the ERC20 token and the initial owner.
3. Use the following methods to manage the contract:
   - `createDistributionPool`: Create a distribution pool for a specific project.
   - `setUserAllocation`: Set allocation percentages for individual users.
   - `claimTokens`: Allow users to claim their vested tokens.
   - `recoverTokens` and `recoverNative`: Recover mistakenly sent tokens or native currency.

#### Example Deployment Code
```solidity
constructor(address tokenAddress, address initialOwner)
```

### 2. ProjectInvestment.sol

The `ProjectInvestment` contract facilitates managing investment rounds in projects. It allows:
- Managing two investment rounds with configurable targets and allocations.
- User investments with checks on their allocation and maximum limits.
- Manual activation of the second round by the owner.
- Withdrawal of invested tokens by the owner.

#### Key Features
- Supports setting maximum allocations for users in each round.
- Protects against reentrancy attacks with `ReentrancyGuard`.
- Includes event logging for auditing.
- Native token recovery function.

#### Deployment Instructions
1. Deploy `ProjectInvestmentManager` to create and manage individual `ProjectInvestment` contracts.
2. Use `createProject` to deploy a new `ProjectInvestment` contract with:
   - A unique project ID.
   - An ERC20 token address.
   - A target for the first round.
   - An option to enable a second round.

#### Example Deployment Code
```solidity
constructor(address tokenAddress, uint256 round1Target, bool enableRound2, address owner)
```

## How to Deploy

### Prerequisites
- A compatible Solidity development environment (e.g., Remix, Hardhat, or Truffle).
- Access to an Ethereum wallet like MetaMask for deploying and managing the contract.
- Ensure sufficient ETH for gas fees and tokens for distribution/investment.

### Deployment Steps
1. Compile the contracts using Solidity version `0.8.27`.
2. Deploy the `ProjectInvestmentManager` contract to manage investment projects.
3. Deploy the `IDODistribution` contract with an ERC20 token address.
4. Use the provided functions to configure vesting schedules or investment rounds.

### Notes for Auditors
- **Reentrancy Protection**: `nonReentrant` is applied to all critical functions.
- **Custom Errors**: Custom error messages replace `require` for gas efficiency.
- **Compatibility Checks**: ERC20 compatibility is ensured using `totalSupply()`.
- **Events**: All major state changes emit events for tracking.

### Contact Information
For any questions or concerns regarding these contracts, please contact the repository owner.

