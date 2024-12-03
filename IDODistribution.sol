// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title IDOTokenDistribution
 * @dev A contract for managing the distribution of tokens during Initial DEX Offerings (IDOs)
 * using vesting schedules. It supports creating vesting rules, allocating tokens to users,
 * and enabling users to claim tokens based on their vesting schedules.
 */
contract IDOTokenDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Struct representing a single vesting rule
    struct VestingRule {
        uint256 totalTokens; // Total tokens allocated for this vesting rule
        uint256 intervalDays; // Number of days between each release
        uint256 startDate; // Timestamp when vesting starts
        uint256 repetitions; // Total number of releases
    }

    // Struct representing a user's token allocation
    struct UserAllocation {
        uint256 percentage; // Percentage of the total project tokens allocated to the user
        uint256 lastClaimed; // Last claimed amount by the user
    }

    // Mapping of project IDs to their vesting rules
    mapping(uint256 => VestingRule[]) public vestingRules;

    // Mapping of project IDs to their distribution pool addresses
    mapping(uint256 => address) public distributionPools;

    // Mapping of project IDs to the total tokens allocated
    mapping(uint256 => uint256) public projectTotalTokens;

    // Merkle root for user allocations
    bytes32 public merkleRoot; 

    // Mapping of project IDs and user addresses to their allocations
    mapping(uint256 => mapping(address => UserAllocation))
        public userAllocations;

    // Mapping of project IDs to the total percentage allocated to users
    mapping(uint256 => uint256) public projectTotalAllocations;

    // The token being distributed
    IERC20 public token;

    // Events for logging critical actions
    event DistributionPoolCreated(
        uint256 indexed projectId,
        address indexed poolAddress
    );
    event TokensDeposited(uint256 indexed projectId, uint256 amount, address indexed sender);
    event VestingRuleCreated(
        uint256 indexed projectId,
        uint256 totalTokens,
        uint256 intervalDays,
        uint256 startDate,
        uint256 repetitions
    );
    event VestingRuleUpdated(
        uint256 indexed projectId,
        uint256 index,
        uint256 totalTokens,
        uint256 intervalDays,
        uint256 startDate,
        uint256 repetitions
    );
    event VestingRuleDeleted(uint256 indexed projectId, uint256 index);
    event UserAllocationSet(
        uint256 indexed projectId,
        address indexed user,
        uint256 percentage
    );
    event TokensClaimed(
        uint256 indexed projectId,
        address indexed user,
        uint256 amount
    );
    event TokensRecovered(address indexed token, uint256 amount, address to);
    event NativeRecovered(address indexed to, uint256 amount);

    // Custom errors for more efficient error handling
    error PoolAlreadyExists(uint256 projectId);
    error InvalidPercentage(uint256 projectId, uint256 percentage);
    error TotalAllocationExceeded(uint256 projectId, uint256 total);
    error InvalidAddress(); // For invalid address checks
    error InvalidProject(); // For invalid project-related checks
    error AllocationExceedsLimit(); // For allocation exceeding 100%
    error InsufficientAllowance(uint256 required, uint256 available); // For insufficient token allowance
    error InvalidMerkleProof(); // For invalid Merkle proof validation
    error ClaimExceedsEntitlement(
        uint256 totalEntitlement,
        uint256 attemptedClaim
    );

    /**
     * @dev Constructor to initialize the contract.
     * @param _token Address of the ERC20 token to be distributed.
     * @param initialOwner Address of the contract's initial owner.
     */
    constructor(address _token, address initialOwner) Ownable(initialOwner) {
        if (_token == address(0)) revert InvalidAddress();
        if (initialOwner == address(0)) revert InvalidAddress();
        token = IERC20(_token);
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Fetches a user's allocation details for a specific project.
     * @param projectId The ID of the project.
     * @param user The address of the user.
     * @return allocationPercentage The percentage of the project tokens allocated to the user.
     * @return lastClaimed The last claimed amount by the user.
     */
    function getUserAllocation(uint256 projectId, address user)
        external
        view
        returns (uint256 allocationPercentage, uint256 lastClaimed)
    {
        UserAllocation storage allocation = userAllocations[projectId][user];
        return (allocation.percentage, allocation.lastClaimed);
    }

    /**
     * @dev Triggers emergency stop.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Lifts emergency stop.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Creates a distribution pool for a given project.
     */
    function createDistributionPool(uint256 projectId, address poolAddress)
        external
        onlyOwner
    {
        if (distributionPools[projectId] != address(0)) {
            revert PoolAlreadyExists(projectId);
        }
        if (poolAddress == address(0)) revert InvalidAddress();
        distributionPools[projectId] = poolAddress;
        emit DistributionPoolCreated(projectId, poolAddress);
    }

    /**
     * @dev Deposits tokens into the contract for a specific project.
     */
    function depositTokens(uint256 projectId, uint256 amount)
        external
        onlyOwner
        whenNotPaused
    {
        if (distributionPools[projectId] == address(0)) revert InvalidProject();
        if (amount == 0) revert AllocationExceedsLimit();

        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(amount, allowance);
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        projectTotalTokens[projectId] += amount;

        // Emit updated event including the sender address
        emit TokensDeposited(projectId, amount, msg.sender);
    }

    /**
     * @dev Creates a vesting rule for a project.
     */
    function createVestingRule(
        uint256 projectId,
        uint256 totalTokens,
        uint256 intervalDays,
        uint256 startDate,
        uint256 repetitions
    ) external onlyOwner {
        vestingRules[projectId].push(
            VestingRule(totalTokens, intervalDays, startDate, repetitions)
        );
        emit VestingRuleCreated(
            projectId,
            totalTokens,
            intervalDays,
            startDate,
            repetitions
        );
    }

    /**
     * @dev Updates an existing vesting rule.
     */
    function updateVestingRule(
        uint256 projectId,
        uint256 index,
        uint256 totalTokens,
        uint256 intervalDays,
        uint256 startDate,
        uint256 repetitions
    ) external onlyOwner {
        if (index >= vestingRules[projectId].length) revert InvalidProject();

        vestingRules[projectId][index] = VestingRule(
            totalTokens,
            intervalDays,
            startDate,
            repetitions
        );
        emit VestingRuleUpdated(
            projectId,
            index,
            totalTokens,
            intervalDays,
            startDate,
            repetitions
        );
    }

    /**
     * @dev Deletes a specific vesting rule for a project.
     */
    function deleteVestingRule(uint256 projectId, uint256 index)
        external
        onlyOwner
    {
        if (index >= vestingRules[projectId].length) revert InvalidProject();

        vestingRules[projectId][index] = vestingRules[projectId][
            vestingRules[projectId].length - 1
        ];
        vestingRules[projectId].pop();
        emit VestingRuleDeleted(projectId, index);
    }

    /**
     * @dev Sets a user's token allocation for a specific project.
     */
    function setUserAllocation(
        uint256 projectId,
        address user,
        uint256 percentage
    ) external onlyOwner whenNotPaused {
        if (user == address(0)) revert InvalidAddress();
        _validatePercentage(percentage);

        uint256 currentAllocation = userAllocations[projectId][user].percentage;
        uint256 currentLastClaimed = userAllocations[projectId][user].lastClaimed;

        // Perform safe arithmetic for allocation changes
        if (projectTotalAllocations[projectId] < currentAllocation) revert InvalidProject();

        uint256 newTotalAllocation = projectTotalAllocations[projectId]
            - currentAllocation + percentage;

        if (newTotalAllocation > 100) revert AllocationExceedsLimit();


        userAllocations[projectId][user] = UserAllocation(percentage, currentLastClaimed);
        projectTotalAllocations[projectId] = newTotalAllocation;

        emit UserAllocationSet(projectId, user, percentage);
    }

    /**
     * @dev Sets multiple users' allocations in a batch.
     */
/**
 * @dev Sets the Merkle root for user allocations. The Merkle root is used to validate user allocations
 * through proofs without directly iterating over user arrays, saving gas.
 * @param _merkleRoot The new Merkle root to set.
 */
function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
    emit MerkleRootUpdated(_merkleRoot);
}

/**
 * @dev Verifies a user's allocation using a Merkle proof and updates their allocation.
 * This replaces the traditional batch allocation logic to reduce gas costs.
 * @param projectId The ID of the project.
 * @param user The address of the user.
 * @param percentage The percentage of allocation for the user.
 * @param proof The Merkle proof validating the allocation.
 */
function verifyAndSetAllocation(
    uint256 projectId,
    address user,
    uint256 percentage,
    bytes32[] calldata proof
) external {
    if (user == address(0)) revert InvalidAddress();
    _validatePercentage(percentage);

    // Compute the leaf node from the user data and validate with the Merkle root
    bytes32 leaf = keccak256(abi.encodePacked(projectId, user, percentage));
    if (!_verifyMerkleProof(leaf, proof)) revert InvalidMerkleProof();


    uint256 currentAllocation = userAllocations[projectId][user].percentage;
    uint256 newTotalAllocation = projectTotalAllocations[projectId] -
        currentAllocation +
        percentage;

    if (newTotalAllocation > 100) revert AllocationExceedsLimit();


    userAllocations[projectId][user] = UserAllocation(percentage, 0);
    projectTotalAllocations[projectId] = newTotalAllocation;

    emit UserAllocationSet(projectId, user, percentage);
}

/**
 * @dev Event emitted when a new Merkle root is set.
 */
    event MerkleRootUpdated(bytes32 indexed newMerkleRoot);

/**
 * @dev Internal helper function to verify a Merkle proof.
 * @param leaf The leaf node (hash of the user's data).
 * @param proof The Merkle proof to validate the leaf against the root.
 * @return True if the proof is valid, false otherwise.
 */
    function _verifyMerkleProof(bytes32 leaf, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash < proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        return computedHash == merkleRoot;
    }


    /**
     * @dev Calculates the vested amount of tokens for a user under a specific vesting rule.
     */
function calculateVestedAmount(
    uint256 projectId,
    address user,
    uint256 ruleIndex
) public view returns (uint256) {
    VestingRule storage rule = vestingRules[projectId][ruleIndex];
    UserAllocation storage allocation = userAllocations[projectId][user];

    if (rule.intervalDays == 0) revert InvalidProject();
    if (rule.repetitions == 0) revert InvalidProject();

    uint256 currentTime = block.timestamp;

    // If vesting has not started, return 0
    if (currentTime < rule.startDate) {
        return 0;
    }

    uint256 elapsedTime = currentTime - rule.startDate;

    // Calculate intervals passed and ensure it does not exceed the total repetitions
    uint256 intervalsPassed = elapsedTime / (rule.intervalDays * 1 days);
    if (intervalsPassed >= rule.repetitions) {
        intervalsPassed = rule.repetitions;
    }

    // Calculate the maximum vested amount based on user's allocation percentage
    uint256 maxVestedTokens = (rule.totalTokens * allocation.percentage) / 100;

    // Calculate the vested amount based on intervals passed
    uint256 vestedAmount = (maxVestedTokens * intervalsPassed) / rule.repetitions;

    // Ensure vested amount does not exceed the maximum allocation
    if (vestedAmount > maxVestedTokens) {
        vestedAmount = maxVestedTokens;
    }

    return vestedAmount;
}

    /**
     * @dev Allows a user to claim their vested tokens for a specific project.
     */
    function claimTokens(uint256 projectId) external nonReentrant whenNotPaused {
        UserAllocation storage allocation = userAllocations[projectId][msg.sender];
        uint256 totalEntitlement = 0;
        uint256 totalClaimableAmount = 0;

        for (uint256 i = 0; i < vestingRules[projectId].length; i++) {
            uint256 vestedAmount = calculateVestedAmount(
                projectId,
                msg.sender,
                i
            );
            totalEntitlement += vestedAmount;
            uint256 claimableAmount = vestedAmount - allocation.lastClaimed;
            totalClaimableAmount += claimableAmount;
        }

        if (totalClaimableAmount == 0) revert AllocationExceedsLimit();
        if (totalEntitlement < allocation.lastClaimed + totalClaimableAmount) {
            revert ClaimExceedsEntitlement(
                totalEntitlement,
                allocation.lastClaimed + totalClaimableAmount
            );
        }

        allocation.lastClaimed += totalClaimableAmount;

        token.safeTransfer(msg.sender, totalClaimableAmount);

        emit TokensClaimed(projectId, msg.sender, totalClaimableAmount);
    }

    /**
     * @dev Recovers ERC20 tokens mistakenly sent to the contract.
     */
    function recoverTokens(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (_isProjectToken(_token)) revert InvalidProject();
        if (_token == token) revert InvalidProject();

        _token.safeTransfer(to, amount);

        emit TokensRecovered(address(_token), amount, to);
    }

    function _isProjectToken(IERC20 _token) internal view returns (bool) {
    for (uint256 projectId = 0; projectId < 2**256 - 1; projectId++) {
        if (distributionPools[projectId] == address(_token)) {
            return true;
        }
    }
    return false;
    }


    /**
     * @dev Recovers native currency (ETH) mistakenly sent to the contract.
     */
    function recoverNative(address to) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();

        // Add validation to ensure native funds are not associated with active projects
        uint256 balance = address(this).balance;
        if (balance == 0) revert AllocationExceedsLimit();

        (bool success, ) = to.call{value: balance}("");
        if (!success) revert InvalidProject(); // Use a relevant custom error for this case

        emit NativeRecovered(to, balance);
    }

    /**
     * @dev Fallback function to handle native currency (ETH) deposits.
     */
    receive() external payable {
        revert("Contract does not accept Ether");
    }

    /**
     * @dev Fallback function to handle unsupported function calls.
     */
    fallback() external payable {
        revert("Unsupported function call or Ether transfer");
    }

    /**
     * @dev Internal function to validate percentage values.
     */
    function _validatePercentage(uint256 percentage) internal pure {
        if (percentage == 0 || percentage > 100) revert InvalidPercentage(0, percentage);
    }
}
