// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title IDOTokenDistribution
 * @dev A contract for managing the distribution of tokens during Initial DEX Offerings (IDOs) 
 * using vesting schedules. It supports creating vesting rules, allocating tokens to users,
 * and enabling users to claim tokens based on their vesting schedules.
 */
contract IDOTokenDistribution is Ownable, ReentrancyGuard {
    // Struct representing a single vesting rule
    struct VestingRule {
        uint256 totalTokens;    // Total tokens allocated for this vesting rule
        uint256 intervalDays;   // Number of days between each release
        uint256 startDate;      // Timestamp when vesting starts
        uint256 repetitions;    // Total number of releases
    }

    // Struct representing a user's token allocation
    struct UserAllocation {
        uint256 percentage;     // Percentage of the total project tokens allocated to the user
        uint256 lastClaimed;    // Last claimed amount by the user
    }

    // Mapping of project IDs to their vesting rules
    mapping(uint256 => VestingRule[]) public vestingRules;

    // Mapping of project IDs to their distribution pool addresses
    mapping(uint256 => address) public distributionPools;

    // Mapping of project IDs to the total tokens allocated
    mapping(uint256 => uint256) public projectTotalTokens;

    // Mapping of project IDs and user addresses to their allocations
    mapping(uint256 => mapping(address => UserAllocation)) public userAllocations;

    // Mapping of project IDs to the total percentage allocated to users
    mapping(uint256 => uint256) public projectTotalAllocations;

    // The token being distributed
    IERC20 public token;

    // Events for logging critical actions
    event DistributionPoolCreated(uint256 indexed projectId, address indexed poolAddress);
    event TokensDeposited(uint256 indexed projectId, uint256 amount);
    event VestingRuleCreated(uint256 indexed projectId, uint256 totalTokens, uint256 intervalDays, uint256 startDate, uint256 repetitions);
    event VestingRuleUpdated(uint256 indexed projectId, uint256 index, uint256 totalTokens, uint256 intervalDays, uint256 startDate, uint256 repetitions);
    event VestingRuleDeleted(uint256 indexed projectId, uint256 index);
    event UserAllocationSet(uint256 indexed projectId, address indexed user, uint256 percentage);
    event TokensClaimed(uint256 indexed projectId, address indexed user, uint256 amount);
    event TokensRecovered(address indexed token, uint256 amount, address to);
    event NativeRecovered(address indexed to, uint256 amount);

    // Custom errors for more efficient error handling
    error PoolAlreadyExists(uint256 projectId);
    error InvalidPercentage(uint256 projectId, uint256 percentage);
    error TotalAllocationExceeded(uint256 projectId, uint256 total);
    error InsufficientAllowance(uint256 required, uint256 available);
    error ClaimExceedsEntitlement(uint256 totalEntitlement, uint256 attemptedClaim);

    /**
     * @dev Constructor to initialize the contract.
     * @param _token Address of the ERC20 token to be distributed.
     * @param initialOwner Address of the contract's initial owner.
     */
    constructor(address _token, address initialOwner) Ownable(initialOwner) {
        require(_token != address(0), "Token address cannot be zero");
        require(initialOwner != address(0), "Owner address cannot be zero");
        token = IERC20(_token);
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Creates a distribution pool for a given project.
     * @param projectId The ID of the project.
     * @param poolAddress The address of the distribution pool.
     */
    function createDistributionPool(uint256 projectId, address poolAddress) external onlyOwner {
        if (distributionPools[projectId] != address(0)) {
            revert PoolAlreadyExists(projectId);
        }
        require(poolAddress != address(0), "Invalid pool address");
        distributionPools[projectId] = poolAddress;
        emit DistributionPoolCreated(projectId, poolAddress);
    }

    /**
     * @dev Deposits tokens into the contract for a specific project.
     * @param projectId The ID of the project.
     * @param amount The number of tokens to deposit.
     */
    function depositTokens(uint256 projectId, uint256 amount) external onlyOwner {
        require(distributionPools[projectId] != address(0), "Distribution pool doesn't exist");
        require(amount > 0, "Amount must be greater than zero");

        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(amount, allowance);
        }

        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");

        projectTotalTokens[projectId] += amount;
        emit TokensDeposited(projectId, amount);
    }

    /**
     * @dev Sets a user's token allocation for a specific project.
     * @param projectId The ID of the project.
     * @param user The address of the user.
     * @param percentage The percentage of the project's tokens allocated to the user.
     */
    function setUserAllocation(uint256 projectId, address user, uint256 percentage) external onlyOwner {
        require(user != address(0), "Invalid user address");
        _validatePercentage(percentage);

        uint256 currentAllocation = userAllocations[projectId][user].percentage;
        require(projectTotalAllocations[projectId] >= currentAllocation, "Underflow in allocation");
        uint256 newTotalAllocation = projectTotalAllocations[projectId] - currentAllocation + percentage;

        if (newTotalAllocation > 100) {
            revert TotalAllocationExceeded(projectId, newTotalAllocation);
        }

        userAllocations[projectId][user] = UserAllocation(percentage, 0);
        projectTotalAllocations[projectId] = newTotalAllocation;

        emit UserAllocationSet(projectId, user, percentage);
    }

    /**
     * @dev Sets multiple users' allocations in a batch.
     * @param projectId The ID of the project.
     * @param users Array of user addresses.
     * @param percentages Array of allocation percentages corresponding to each user.
     */
    function batchSetUserAllocation(uint256 projectId, address[] calldata users, uint256[] calldata percentages) external onlyOwner {
        require(users.length == percentages.length, "Users and percentages length mismatch");

        uint256 totalAllocationChange = 0;

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid user address");
            _validatePercentage(percentages[i]);

            uint256 currentAllocation = userAllocations[projectId][users[i]].percentage;
            require(projectTotalAllocations[projectId] >= currentAllocation, "Underflow in allocation");
            totalAllocationChange += percentages[i] - currentAllocation;
        }

        if (projectTotalAllocations[projectId] + totalAllocationChange > 100) {
            revert TotalAllocationExceeded(projectId, projectTotalAllocations[projectId] + totalAllocationChange);
        }

        for (uint256 i = 0; i < users.length; i++) {
            userAllocations[projectId][users[i]] = UserAllocation(percentages[i], 0);
            emit UserAllocationSet(projectId, users[i], percentages[i]);
        }

        projectTotalAllocations[projectId] += totalAllocationChange;
    }

    /**
     * @dev Calculates the vested amount of tokens for a user under a specific vesting rule.
     * @param projectId The ID of the project.
     * @param user The address of the user.
     * @param ruleIndex The index of the vesting rule.
     * @return The amount of tokens vested for the user.
     */
    function calculateVestedAmount(uint256 projectId, address user, uint256 ruleIndex) public view returns (uint256) {
        VestingRule storage rule = vestingRules[projectId][ruleIndex];
        UserAllocation storage allocation = userAllocations[projectId][user];

        require(rule.intervalDays > 0, "Interval days must be greater than zero");
        require(rule.repetitions > 0, "Repetitions must be greater than zero");

        uint256 currentTime = block.timestamp;

        if (currentTime < rule.startDate) {
            return 0;
        }

        uint256 elapsedTime = currentTime - rule.startDate;
        uint256 intervalsPassed = elapsedTime / (rule.intervalDays * 1 days);

        if (intervalsPassed > rule.repetitions) {
            intervalsPassed = rule.repetitions;
        }

        uint256 totalUserTokens = (rule.totalTokens * allocation.percentage) / 100;
        uint256 vestedAmount = (totalUserTokens * intervalsPassed) / rule.repetitions;

        return vestedAmount;
    }

    /**
     * @dev Allows a user to claim their vested tokens for a specific project.
     * @param projectId The ID of the project.
     */
    function claimTokens(uint256 projectId) external nonReentrant {
        UserAllocation storage allocation = userAllocations[projectId][msg.sender];
        uint256 totalEntitlement = 0;
        uint256 totalClaimableAmount = 0;

        for (uint256 i = 0; i < vestingRules[projectId].length; i++) {
            uint256 vestedAmount = calculateVestedAmount(projectId, msg.sender, i);
            totalEntitlement += vestedAmount;
            uint256 claimableAmount = vestedAmount - allocation.lastClaimed;
            totalClaimableAmount += claimableAmount;
        }

        require(totalClaimableAmount > 0, "No tokens claimable at this time");
        if (totalEntitlement < allocation.lastClaimed + totalClaimableAmount) {
            revert ClaimExceedsEntitlement(totalEntitlement, allocation.lastClaimed + totalClaimableAmount);
        }

        allocation.lastClaimed += totalClaimableAmount;
        token.transfer(msg.sender, totalClaimableAmount);

        emit TokensClaimed(projectId, msg.sender, totalClaimableAmount);
    }

    /**
     * @dev Recovers ERC20 tokens mistakenly sent to the contract.
     * @param _token The address of the ERC20 token to recover.
     * @param amount The number of tokens to recover.
     * @param to The address to send the recovered tokens to.
     */
    function recoverTokens(IERC20 _token, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(_token != token, "Cannot recover main distribution token");

        bool success = _token.transfer(to, amount);
        require(success, "Token recovery failed");

        emit TokensRecovered(address(_token), amount, to);
    }

    /**
     * @dev Recovers native currency (ETH) mistakenly sent to the contract.
     * @param to The address to send the recovered ETH to.
     */
    function recoverNative(address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No native funds to recover");

        (bool success, ) = to.call{value: balance}("");
        require(success, "Native recovery failed");

        emit NativeRecovered(to, balance);
    }

    /**
     * @dev Fallback function to handle native currency (ETH) deposits.
     */
    receive() external payable {
        require(msg.value > 0, "Cannot send zero ETH");
        emit NativeRecovered(msg.sender, msg.value);
    }

    /**
     * @dev Fallback function to handle unsupported function calls.
     */
    fallback() external payable {
        revert("Unsupported function call");
    }

    /**
     * @dev Internal function to validate percentage values.
     * @param percentage The percentage to validate.
     */
    function _validatePercentage(uint256 percentage) internal pure {
        require(percentage > 0 && percentage <= 100, "Invalid percentage");
    }
}
