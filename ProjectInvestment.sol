// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Import the ERC20 interface for interacting with tokens.
import "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable for access control.
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Import ReentrancyGuard to protect against reentrancy attacks.
import "@openzeppelin/contracts/security/Pausable.sol"; // Import Pausable to enable to pause investments.

/**
 * @title ProjectInvestmentManager
 * @dev A contract for managing multiple investment projects and deploying individual investment contracts.
 */
contract ProjectInvestmentManager is Ownable(address(0)) {
    // Event emitted when a new project investment contract is deployed.
    event ProjectDeployed(
        address indexed projectAddress,
        uint256 indexed projectId
    );

    /**
     * @dev Creates a new project investment contract.
     * @param projectId The unique ID of the project.
     * @param tokenAddress The address of the ERC20 token used for investments.
     * @param round1Target The target amount to be raised in Round 1.
     * @param enableRound2 A boolean indicating whether Round 2 is enabled.
     */
    function createProject(
        uint256 projectId,
        address tokenAddress,
        uint256 round1Target,
        bool enableRound2
    ) external onlyOwner {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(IERC20(tokenAddress).totalSupply() > 0, "Invalid ERC20 token"); // Check compatibility with the ERC20 token.

        // Deploy a new ProjectInvestment contract.
        ProjectInvestment newProject = new ProjectInvestment(
            tokenAddress,
            round1Target,
            enableRound2,
            msg.sender
        );
        emit ProjectDeployed(address(newProject), projectId); // Emit event for tracking deployment.
    }
}

/**
 * @title ProjectInvestment
 * @dev A contract for managing investment rounds for a specific project.
 */
contract ProjectInvestment is Ownable, Pausable, ReentrancyGuard {
    // Structure to store details of an investment round.
    struct InvestmentRound {
        uint256 totalAllocation; // Total allocation allowed for the round.
        uint256 totalInvestment; // Total amount invested in the round.
        uint256 maxAllocationPerUser; // Maximum allocation allowed per user in the round.
        mapping(address => uint256) investments; // Mapping of user addresses to their investments.
        mapping(address => uint256) maxAllocations; // Mapping of user addresses to their maximum allocations.
    }

    IERC20 public token; // The ERC20 token used for investments.
    uint256 public round1Target; // The target amount for Round 1.
    bool public round2Enabled; // Indicates whether Round 2 is enabled.
    bool public round1Complete; // Indicates whether Round 1 is complete.

    InvestmentRound public round1; // Data structure for Round 1.
    InvestmentRound public round2; // Data structure for Round 2.

    // Events for tracking significant actions.
    event InvestmentMade(address indexed user, uint256 amount, uint8 round); // Emitted when a user invests in a round.
    event RoundComplete(uint8 round); // Emitted when a round is marked as complete.
    event Withdrawal(address indexed to, uint256 amount); // Emitted when funds are withdrawn.
    event NativeRecovered(address indexed to, uint256 amount); // Emitted when native funds are recovered.

    /**
     * @dev Constructor to initialize the project investment contract.
     * @param tokenAddress The address of the ERC20 token used for investments.
     * @param _round1Target The target amount for Round 1.
     * @param enableRound2 A boolean indicating whether Round 2 is enabled.
     * @param owner The address of the owner of the contract.
     */
    constructor(
        address tokenAddress,
        uint256 _round1Target,
        bool enableRound2,
        address owner
    ) Ownable(owner) {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(owner != address(0), "Owner address cannot be zero");
        require(IERC20(tokenAddress).totalSupply() > 0, "Invalid ERC20 token"); // Check compatibility with the ERC20 token.

        token = IERC20(tokenAddress);
        round1Target = _round1Target;
        round2Enabled = enableRound2;
    }

     /**
     * @dev Pauses the contract, preventing certain functions from being executed.
     * Can only be called by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing certain functions to be executed again.
     * Can only be called by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Activates Round 2.
     * Can only be called by the owner.
     */
    function activateRound2() external onlyOwner {
        require(!round1Complete, "Round 1 is complete");
        require(round2Enabled, "Round 2 is not enabled");

        round1Complete = true; // Mark Round 1 as complete.
        emit RoundComplete(1); // Emit event indicating Round 1 completion.
    }

    /**
     * @dev Updates the investment project parameters.
     * Can only be called by the owner.
     * @param tokenAddress The new token address.
     * @param _round1Target The new target amount for Round 1.
     * @param enableRound2 The new status of Round 2 enablement.
     */
    function UpdateProjectInvestment(
        address tokenAddress,
        uint256 _round1Target,
        bool enableRound2
    ) external onlyOwner {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(IERC20(tokenAddress).totalSupply() > 0, "Invalid ERC20 token");
        require(_round1Target > 0, "Round 1 target must be greater than zero");

        token = IERC20(tokenAddress);
        round1Target = _round1Target;
        round2Enabled = enableRound2;
    }

    /**
     * @dev Enables or disables Round 2.
     * Can only be called by the owner.
     * @param value A boolean indicating whether Round 2 should be enabled or disabled.
     */
    function UpdateRound2Enabling(bool value) external onlyOwner {
        round2Enabled = value;
    }

    /**
     * @dev Allows a user to invest in Round 1.
     * @param amount The amount of tokens the user wishes to invest.
     */
    function investRound1(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(!round1Complete, "Round 1 is complete");
        require(
            round1.totalInvestment + amount <= round1Target,
            "Exceeds round 1 target"
        );

        uint256 userAllocation = round1.maxAllocations[msg.sender];
        require(userAllocation > 0, "User has no allocation");
        require(
            round1.investments[msg.sender] + amount <= userAllocation,
            "Exceeds max allocation"
        );

        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        // Update state before making external calls
        round1.investments[msg.sender] += amount;
        round1.totalInvestment += amount;

        // External interaction with return value check
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        emit InvestmentMade(msg.sender, amount, 1);
    }

    /**
     * @dev Allows a user to invest in Round 2.
     * @param amount The amount of tokens the user wishes to invest.
     */
    function investRound2(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(round1Complete, "Round 1 is not complete");
        require(round2Enabled, "Round 2 is disabled");

        uint256 remaining = round1Target > round1.totalInvestment
            ? round1Target - round1.totalInvestment
            : 0;
        require(remaining > 0, "No remaining allocation for Round 2");
        require(amount <= remaining, "Amount exceeds remaining allocation");

        uint256 userAllocation = round2.maxAllocationPerUser;
        require(userAllocation > 0, "Round 2 allocation not set");
        require(
            round2.investments[msg.sender] + amount <= userAllocation,
            "Exceeds max allocation for Round 2"
        );

        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        // Update state before making external calls
        round2.investments[msg.sender] += amount;
        round2.totalInvestment += amount;

        // External interaction with return value check
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        emit InvestmentMade(msg.sender, amount, 2);
    }

    /**
     * @dev Allows the owner to withdraw tokens from the contract.
     * @param amount The amount to withdraw.
     * @param to The recipient address.
     */
    function withdraw(
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(to != address(0), "Recipient address cannot be zero");
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        // External interaction with return value check
        require(token.transfer(to, amount), "Token transfer failed");

        emit Withdrawal(to, amount);
    }

    /**
     * @dev Allows the owner to recover native funds mistakenly sent to the contract.
     * @param to The recipient address.
     */
    function recoverNative(address to) external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No native funds to recover");
        require(to != address(0), "Recipient address cannot be zero");

        // External interaction after state validation
        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");

        emit NativeRecovered(to, balance);
    }

    /**
     * @dev Batch sets the maximum allocation for users in Round 1.
     * @param users The array of user addresses.
     * @param allocations The array of allocations corresponding to the users.
     */
    function batchSetRound1Allocation(
        address[] calldata users,
        uint256[] calldata allocations
    ) external onlyOwner {
        require(
            users.length == allocations.length,
            "Users and allocations length mismatch"
        );
        require(users.length > 0, "No users provided");

        uint256 newTotalAllocation = 0;

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "User address cannot be zero");
            require(allocations[i] > 0, "Allocation must be greater than 0");

            newTotalAllocation += allocations[i];
            require(
                newTotalAllocation <= round1Target,
                "Total allocation exceeds round1Target"
            );

            round1.maxAllocations[users[i]] = allocations[i];
        }

        round1.totalAllocation = newTotalAllocation;
    }

    /**
     * @dev Sets the maximum allocation per user for Round 2.
     * @param maxAllocation The maximum allocation.
     */
    function setRound2MaxAllocation(uint256 maxAllocation) external onlyOwner {
        require(maxAllocation > 0, "Max allocation must be greater than 0");

        uint256 remainingAllocation = round1Target > round1.totalInvestment
            ? round1Target - round1.totalInvestment
            : 0;

        require(
            maxAllocation <= remainingAllocation,
            "Max allocation exceeds remaining allocation from Round 1"
        );

        round2.maxAllocationPerUser = maxAllocation;
    }

    /**
     * @dev Returns the investment history of a user across all rounds.
     * @param user The address of the user whose investment history is being queried.
     * @return round1Investment The total investment made by the user in Round 1.
     * @return round2Investment The total investment made by the user in Round 2 (if applicable).
     */
    function getUserInvestmentHistory(
        address user
    )
        external
        view
        returns (uint256 round1Investment, uint256 round2Investment)
    {
        require(user != address(0), "User address cannot be zero");
        round1Investment = round1.investments[user];
        round2Investment = round2.investments[user];
    }
}
