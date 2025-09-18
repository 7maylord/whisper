// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoWMatcher} from "./CoWMatcher.sol";

/**
 * @title SimpleAVSServiceManager
 * @dev Simplified EigenLayer AVS Service Manager for CoW protocol
 * Demonstrates the AVS pattern without complex middleware dependencies
 */
contract SimpleAVSServiceManager {
    // ============== STRUCTS ==============

    struct Task {
        bytes32 poolId;
        bytes32 orderHash;
        bool isBuyOrder;
        uint256 blockNumberTaskCreated;
        uint32 quorumThresholdPercentage;
    }

    struct TaskResponse {
        uint32 referenceTaskIndex;
        bytes32 oppositeOrderHash;
        uint256 matchedPrice;
        uint256 savings;
    }

    // ============== STATE VARIABLES ==============

    CoWMatcher public immutable cowMatcher;

    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => TaskResponse) public allTaskResponses;
    mapping(address => bool) public registeredOperators;

    uint32 public latestTaskNum;
    address public owner;

    // ============== EVENTS ==============

    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event TaskResponded(TaskResponse taskResponse);
    event OperatorRegistered(address indexed operator);
    event CoWMatchCreated(bytes32 indexed taskHash, bytes32 indexed matchId, uint256 savings);

    // ============== MODIFIERS ==============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyRegisteredOperator() {
        require(registeredOperators[msg.sender], "Operator not registered");
        _;
    }

    // ============== CONSTRUCTOR ==============

    constructor(CoWMatcher _cowMatcher) {
        cowMatcher = _cowMatcher;
        owner = msg.sender;
    }

    // ============== EXTERNAL FUNCTIONS ==============

    /**
     * @notice Register as an operator for this AVS
     */
    function registerOperator() external {
        registeredOperators[msg.sender] = true;
        emit OperatorRegistered(msg.sender);
    }

    /**
     * @notice Creates a new CoW matching task for operators to solve
     */
    function createNewTask(
        bytes32 poolId,
        bytes32 orderHash,
        bool isBuyOrder,
        uint32 quorumThresholdPercentage
    ) external onlyOwner {
        Task memory newTask = Task({
            poolId: poolId,
            orderHash: orderHash,
            isBuyOrder: isBuyOrder,
            blockNumberTaskCreated: block.number,
            quorumThresholdPercentage: quorumThresholdPercentage
        });

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNum, newTask);
        latestTaskNum = latestTaskNum + 1;
    }

    /**
     * @notice Operators call this to respond to tasks with CoW matches
     */
    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse
    ) external onlyRegisteredOperator {
        // Verify task hash
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskResponse.referenceTaskIndex],
            "Task hash does not match"
        );

        // Store response
        allTaskResponses[taskResponse.referenceTaskIndex] = taskResponse;

        // Execute CoW match if valid
        if (taskResponse.savings > 0) {
            bytes32 matchId = cowMatcher.createMatch(
                task.orderHash,
                taskResponse.oppositeOrderHash,
                taskResponse.matchedPrice,
                taskResponse.savings
            );

            emit CoWMatchCreated(task.orderHash, matchId, taskResponse.savings);
        }

        emit TaskResponded(taskResponse);
    }

    // ============== VIEW FUNCTIONS ==============

    function totalOperators() external view returns (uint256) {
        return cowMatcher.totalOperators();
    }

    function isOperator(address operator) external view returns (bool) {
        return registeredOperators[operator];
    }

    function getTask(uint32 taskIndex) external view returns (bytes32) {
        return allTaskHashes[taskIndex];
    }

    function getTaskResponse(uint32 taskIndex) external view returns (TaskResponse memory) {
        return allTaskResponses[taskIndex];
    }
}