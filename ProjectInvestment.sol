// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Import the ERC20 interface for interacting with tokens.
import "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable for access control.
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Import ReentrancyGuard to protect against reentrancy attacks.
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title ProjectInvestmentManager
 * @dev A contract for managing multiple investment projects and deploying individual investment contracts.
 */
contract ProjectInvestmentManager is Ownable(address(0)) {
    // Event emitted when a new project investment contract is deployed.
    event ProjectDeployed(address indexed projectAddress, uint256 indexed projectId);

    /**
     * @dev Creates a new project investment contract.
     * @param projectId The unique ID of the project.
     * @param tokenAddress The address of the ERC20 token used for investments.
     * @param round1Target The target amount to be raised in Round 1.
     * @param enableRound2 A boolean indicating whether Round 2 is enabled.
     */
    function createProject(uint256 projectId, address tokenAddress, uint256 round1Target, bool enableRound2) external onlyOwner {
        require(tokenAddress != address(0), "Constructor: Token address cannot be the zero address");
        require(IERC20(tokenAddress).totalSupply() > 0, "updateProjectInvestment: Token address is invalid, total supply is zero");

        // Deploy a new ProjectInvestment contract.
        ProjectInvestment newProject = new ProjectInvestment(tokenAddress, round1Target, enableRound2, msg.sender);
        emit ProjectDeployed(address(newProject), projectId); // Emit event for tracking deployment.
    }
}

/**
 * @title ProjectInvestment
 * @dev A contract for managing investment rounds for a specific project.
 */
contract ProjectInvestment is Ownable, ReentrancyGuard, Pausable {
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
    constructor(address tokenAddress, uint256 _round1Target, bool enableRound2, address owner) Ownable(owner) {
        require(tokenAddress != address(0), "createProject: Token address cannot be the zero address");
        require(owner != address(0), "Constructor: Owner address cannot be the zero address");
        require(IERC20(tokenAddress).totalSupply() > 0, "createProject: Token address is invalid, total supply is zero");

        token = IERC20(tokenAddress);
        round1Target = _round1Target;
        round2Enabled = enableRound2;
    }

    /**
     * @dev Activates Round 2.
     * Can only be called by the owner.
     */
    function startRound2() external onlyOwner {
        require(!round1Complete, "startRound2: Cannot start Round 2 because Round 1 is already complete");
        require(round2Enabled, "startRound2: Round 2 is not enabled for this project");

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
    function updateProjectInvestment (address tokenAddress, uint256 _round1Target, bool enableRound2) external onlyOwner {
        require(tokenAddress != address(0), "updateProjectInvestment: Token address cannot be the zero address");
        require(IERC20(tokenAddress).totalSupply() > 0, "Constructor: Token address is invalid, total supply is zero");

        token = IERC20(tokenAddress);
        round1Target = _round1Target;
        round2Enabled = enableRound2;
    }

    /**
     * @dev Enables or disables Round 2.
     * Can only be called by the owner.
     * @param value A boolean indicating whether Round 2 should be enabled or disabled.
     */
    function setRound2Enabled (bool value) external onlyOwner {
        round2Enabled = value;
    }

    /**
     * @dev Allows a user to invest in Round 1.
     * @param amount The amount of tokens the user wishes to invest.
     */
    function investInRound1(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "investInRound1: Investment amount must be greater than zero");
        require(!round1Complete, "investInRound1: Cannot invest because Round 1 is already complete");
        require(round1.totalInvestment + amount <= round1Target, "investInRound1: Investment exceeds the Round 1 target");

        uint256 userAllocation = round1.maxAllocations[msg.sender];
        require(userAllocation > 0, "investInRound1: User does not have an allocation for Round 1");
        require(round1.investments[msg.sender] + amount <= userAllocation, "investInRound1: Investment exceeds user's maximum allocation");

        round1.investments[msg.sender] += amount;
        round1.totalInvestment += amount;

        require(token.transferFrom(msg.sender, address(this), amount), "Token transferFrom failed");

        emit InvestmentMade(msg.sender, amount, 1);
    }



    /**
     * @dev Allows a user to invest in Round 2.
     * @param amount The amount of tokens the user wishes to invest.
     */
    function investInRound2(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "investInRound2: Investment amount must be greater than zero");
        require(round1Complete, "investInRound2: Cannot invest because Round 1 is not complete");
        require(round2Enabled, "investInRound2: Round 2 is not enabled for this project");

        uint256 remaining = round1Target > round1.totalInvestment ? round1Target - round1.totalInvestment : 0;
        require(remaining > 0, "investInRound2: No remaining allocation available for Round 2");
        require(amount <= remaining, "investInRound2: Investment exceeds the remaining allocation for Round 2");

        uint256 userAllocation = round2.maxAllocationPerUser;
        require(userAllocation > 0, "investInRound2: User does not have an allocation for Round 2");
        require(round2.investments[msg.sender] + amount <= userAllocation, "investInRound2: Investment exceeds user's maximum allocation for Round 2");

        round2.investments[msg.sender] += amount;
        round2.totalInvestment += amount;

        require(token.transferFrom(msg.sender, address(this), amount), "Token transferFrom failed");

        emit InvestmentMade(msg.sender, amount, 2);
    }




    /**
     * @dev Allows the owner to withdraw tokens from the contract.
     * @param amount The amount to withdraw.
     * @param to The recipient address.
     */
    function withdraw(uint256 amount, address to) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(to != address(0), "Recipient address cannot be zero"); // Check for zero address
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance");

        require(token.transfer(to, amount), "Token transfer failed");
        emit Withdrawal(to, amount);
    }

    // Fallback function to prevent accidental Ether transfers
    fallback() external payable {
        revert("Contract does not accept Ether");
    }

    // Receive function to handle plain Ether transfers (if needed, can also revert)
    receive() external payable {
        revert("Contract does not accept Ether");
    }


    /**
     * @dev Allows the owner to recover native funds mistakenly sent to the contract.
     * @param to The recipient address.
     */
    function recoverEther(address to) external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No native funds to recover");
        require(to != address(0), "Recipient address cannot be zero"); // Check for zero address

        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");
        emit NativeRecovered(to, balance);
    }

    function safeTransfer(IERC20 _token, address _to, uint256 _amount) internal {
        require(_token.transfer(_to, _amount), "Token transfer failed");
    }

    function safeTransferFrom(IERC20 _token, address _from, address _to, uint256 _amount) internal {
        require(_token.transferFrom(_from, _to, _amount), "Token transferFrom failed");
    }



    /**
     * @dev Batch sets the maximum allocation for users in Round 1.
     * @param users The array of user addresses.
     * @param allocations The array of allocations corresponding to the users.
     */
    function setRound1Allocations(address[] calldata users, uint256[] calldata allocations) external onlyOwner {
        require(users.length == allocations.length, "setRound1Allocations: Length of users and allocations arrays must match");

        uint256 newTotalAllocation = 0; // Start with 0 to calculate the new total allocation.

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "setRound1Allocations: User address cannot be the zero address");
            require(allocations[i] > 0, "setRound1Allocations: Allocation must be greater than zero");
            require(allocations[i] <= round1Target, "setRound1Allocations: Individual allocation exceeds the Round 1 target");

            uint256 currentUserAllocation = round1.maxAllocations[users[i]];
            newTotalAllocation = newTotalAllocation - currentUserAllocation + allocations[i];

            require(newTotalAllocation <= round1Target, "setRound1Allocations: Total allocation exceeds the Round 1 target");

            round1.maxAllocations[users[i]] = allocations[i];
        }

        round1.totalAllocation = newTotalAllocation; // Update the total allocation after successful iteration.
    }

    /**
     * @dev Sets the maximum allocation per user for Round 2.
     * @param maxAllocation The maximum allocation.
     */
    function setRound2Allocations(uint256 maxAllocation, address[] calldata users, uint256[] calldata allocations) external onlyOwner {
        require(maxAllocation > 0, "setRound2Allocations: Maximum allocation must be greater than zero");
        require(users.length == allocations.length, "setRound2Allocations: Length of users and allocations arrays must match");

        uint256 remainingAllocation = round1Target > round1.totalInvestment
            ? round1Target - round1.totalInvestment
            : 0;

        require(maxAllocation <= remainingAllocation, "setRound2Allocations: Maximum allocation exceeds remaining allocation from Round 1");


        uint256 newTotalAllocation = 0; // Start with 0 to track new total allocation.

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "setRound2Allocations: User address cannot be the zero address");
            require(allocations[i] > 0, "setRound2Allocations: Allocation must be greater than zero");
            require(allocations[i] <= maxAllocation, "setRound2Allocations: Individual allocation exceeds the maximum allocation");

            uint256 currentUserAllocation = round2.maxAllocations[users[i]];
            newTotalAllocation = newTotalAllocation - currentUserAllocation + allocations[i];

            require(newTotalAllocation <= remainingAllocation, "setRound2Allocations: Total allocation exceeds remaining allocation for Round 2");

            round2.maxAllocations[users[i]] = allocations[i]; // Update allocation for each user.
        }

        round2.totalAllocation = newTotalAllocation; // Update total allocation after successful validation.
        round2.maxAllocationPerUser = maxAllocation; // Update max allocation per user.
    }

    /**
    * @dev Removes a user's allocation and investment data from the mapping.
    * Can only be called by the owner.
    * @param user The address of the user to remove.
    * @param round The round from which to remove the user (1 or 2).
    */
    function removeUserData(address user, uint8 round) external onlyOwner {
        require(user != address(0), "User address cannot be zero");

        if (round == 1) {
            round1.totalAllocation -= round1.maxAllocations[user];
            round1.totalInvestment -= round1.investments[user];

            delete round1.maxAllocations[user];
            delete round1.investments[user];
        } else if (round == 2) {
            round2.totalAllocation -= round2.maxAllocations[user];
            round2.totalInvestment -= round2.investments[user];

            delete round2.maxAllocations[user];
            delete round2.investments[user];
        } else {
            revert("Invalid round number");
        }
    }

    /**
    * @dev Removes multiple users' allocation and investment data from the mapping.
    * Can only be called by the owner.
    * @param users The array of user addresses to remove.
    * @param round The round from which to remove the users (1 or 2).
    */
    function removeBatchUserData(address[] calldata users, uint8 round) external onlyOwner {
        require(users.length > 0, "Users array cannot be empty");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            require(user != address(0), "User address cannot be zero");

            if (round == 1) {
                round1.totalAllocation -= round1.maxAllocations[user];
                round1.totalInvestment -= round1.investments[user];

                delete round1.maxAllocations[user];
                delete round1.investments[user];
            } else if (round == 2) {
                round2.totalAllocation -= round2.maxAllocations[user];
                round2.totalInvestment -= round2.investments[user];

                delete round2.maxAllocations[user];
                delete round2.investments[user];
            } else {
                revert("Invalid round number");
            }
        }
    }

    /**
    * @dev Retrieves the investment details of a specific user across both rounds.
    * @param user The address of the user to query.
    * @return round1Investment The amount invested by the user in Round 1.
    * @return round2Investment The amount invested by the user in Round 2.
    */
    function getInvestmentDetails(address user) external view returns (uint256 round1Investment, uint256 round2Investment) {
        require(user != address(0), "getInvestmentDetails: User address cannot be the zero address");
        return (round1.investments[user], round2.investments[user]);
    }

    /**
    * @dev Pauses the contract, preventing investments.
    * Can only be called by the owner.
    */
    function pause() external onlyOwner {
        _pause();
    }

    /**
    * @dev Unpauses the contract, allowing investments.
    * Can only be called by the owner.
    */
    function unpause() external onlyOwner {
        _unpause();
    }

}
