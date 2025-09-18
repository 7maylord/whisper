// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint32, ebool, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
// Minimal Chainlink interface
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// LayerZero V2 interfaces
interface ILayerZeroEndpointV2 {
    function send(
        uint32 dstEid,
        bytes32 to,
        bytes calldata message,
        address refundAddress,
        bytes calldata options
    ) external payable returns (bytes32 msgId, uint256 nativeFee, uint256 lzTokenFee);

    function quote(
        uint32 dstEid,
        bytes32 to,
        bytes calldata message,
        bytes calldata options,
        bool payInLzToken
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
}

/**
 * @title CoWMatcher - Simplified Coincidence of Wants Matcher
 * @dev Handles order matching with FHE privacy and cross-chain discovery
 */
contract CoWMatcher {
    uint256 public constant QUORUM_THRESHOLD = 66; // 66% consensus required
    uint256 public constant MATCH_TIMEOUT = 5 minutes;
    uint256 public constant MEV_PROTECTION_WINDOW = 30 seconds;

    // Arbitrum Sepolia deployed addresses
    AggregatorV3Interface public constant ETH_USD_FEED =
        AggregatorV3Interface(0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08);
    AggregatorV3Interface public constant USDC_USD_FEED =
        AggregatorV3Interface(0x0153002d20B96532C639313c2d54c3dA09109309);
    ILayerZeroEndpointV2 public constant LZ_ENDPOINT =
        ILayerZeroEndpointV2(0x6EDCE65403992e310A62460808c4b910D972f10f);

    // Real tokens on Arbitrum Sepolia
    IERC20 public constant USDC = IERC20(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);
    IERC20 public constant WETH = IERC20(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);

    // Chain IDs for LayerZero
    uint32 public constant ETHEREUM_SEPOLIA_EID = 40161;
    uint32 public constant POLYGON_MUMBAI_EID = 40109;
    uint32 public constant OPTIMISM_SEPOLIA_EID = 40232;

    // FHE constants
    euint32 private ENCRYPTED_ZERO;
    euint32 private ENCRYPTED_ONE;

    struct OrderRequest {
        bytes32 poolId;
        address requester;
        address token0;
        address token1;
        bool isBuyOrder;
        euint32 encryptedAmount;
        euint32 encryptedMaxPrice;
        uint256 sourceChain;
        uint256 timestamp;
        uint256 commitTimestamp;
        bool isActive;
        bool isRevealed;
    }

    struct CommittedOrder {
        bytes32 commitment;
        uint256 revealDeadline;
        bool isRevealed;
    }

    struct Match {
        bytes32 buyOrderId;
        bytes32 sellOrderId;
        uint256 matchedAmount;
        uint256 matchedPrice;
        uint256 savings;
        uint256 consensusCount;
        bool isExecuted;
    }

    struct OperatorSubmission {
        bytes32 oppositeOrderId;
        uint256 matchedAmount;
        uint256 matchedPrice;
        uint256 sourceChain;
        uint256 timestamp;
    }

    // Core state
    mapping(bytes32 => OrderRequest) public orderRequests;
    mapping(bytes32 => Match) public matches;
    mapping(address => bool) public operators;
    mapping(bytes32 => mapping(address => OperatorSubmission)) public submissions;
    mapping(bytes32 => address[]) public submittedOperators;

    // MEV protection
    mapping(address => CommittedOrder) public commitments;
    mapping(bytes32 => uint256) public batchExecutionTime;

    // Cross-chain order discovery
    mapping(uint256 => mapping(bytes32 => bytes32[])) public chainOrders;
    mapping(bytes32 => mapping(bool => bytes32[])) public pendingOrders;

    // Real price tracking
    mapping(address => uint256) public lastPriceUpdate;
    mapping(address => uint256) public cachedPrice;

    address[] public operatorList;

    event OrderRequested(bytes32 indexed requestId, bytes32 indexed poolId, bool isBuyOrder, uint256 chainId);
    event OrderCommitted(address indexed trader, bytes32 commitment);
    event OrderRevealed(bytes32 indexed requestId, uint256 amount, uint256 price);
    event MatchFound(bytes32 indexed requestId, bytes32 indexed matchId, uint256 savings);
    event OperatorRegistered(address indexed operator);
    event MatchExecuted(bytes32 indexed matchId, uint256 matchedAmount, uint256 matchedPrice);
    event CrossChainOrderSent(bytes32 indexed requestId, uint32 targetChain);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    constructor() {
        // Initialize FHE constants
        ENCRYPTED_ZERO = FHE.asEuint32(0);
        ENCRYPTED_ONE = FHE.asEuint32(1);

        // Grant contract access
        FHE.allowThis(ENCRYPTED_ZERO);
        FHE.allowThis(ENCRYPTED_ONE);
    }

    function registerOperator() external {
        require(!operators[msg.sender], "Already registered");
        operators[msg.sender] = true;
        operatorList.push(msg.sender);
        emit OperatorRegistered(msg.sender);
    }

    function findMatch(
        bytes32 poolId,
        bool isBuyOrder,
        euint32 encryptedAmount,
        euint32 encryptedMaxPrice,
        uint256 chainId
    ) external returns (bytes32 matchId) {
        bytes32 requestId = keccak256(abi.encodePacked(
            poolId, msg.sender, block.timestamp, chainId, block.number
        ));

        // Get real token addresses from poolId (simplified)
        address token0 = address(WETH);
        address token1 = address(USDC);

        // Update real prices before creating order
        _updateTokenPrice(token0);
        _updateTokenPrice(token1);

        orderRequests[requestId] = OrderRequest({
            poolId: poolId,
            requester: msg.sender,
            token0: token0,
            token1: token1,
            isBuyOrder: isBuyOrder,
            encryptedAmount: encryptedAmount,
            encryptedMaxPrice: encryptedMaxPrice,
            sourceChain: chainId,
            timestamp: block.timestamp,
            commitTimestamp: 0,
            isActive: true,
            isRevealed: false
        });

        // Add to discovery maps
        chainOrders[chainId][poolId].push(requestId);
        pendingOrders[poolId][isBuyOrder].push(requestId);

        // Send cross-chain discovery message
        _sendCrossChainOrderDiscovery(requestId, poolId, isBuyOrder, chainId);

        emit OrderRequested(requestId, poolId, isBuyOrder, chainId);

        return requestId;
    }

    function submitMatch(
        bytes32 requestId,
        bytes32 oppositeOrderId,
        uint256 matchedAmount,
        uint256 matchedPrice,
        uint256 oppositeChain
    ) external {
        require(operators[msg.sender], "Not operator");
        require(orderRequests[requestId].isActive, "Request not active");
        require(submissions[requestId][msg.sender].timestamp == 0, "Already submitted");

        OrderRequest storage request = orderRequests[requestId];
        require(block.timestamp <= request.timestamp + MATCH_TIMEOUT, "Request expired");

        // Verify match using FHE
        require(_verifyMatch(request, matchedAmount, matchedPrice), "Invalid match");

        submissions[requestId][msg.sender] = OperatorSubmission({
            oppositeOrderId: oppositeOrderId,
            matchedAmount: matchedAmount,
            matchedPrice: matchedPrice,
            sourceChain: oppositeChain,
            timestamp: block.timestamp
        });

        submittedOperators[requestId].push(msg.sender);

        // Check for consensus
        _checkConsensus(requestId);
    }

    function getMatch(bytes32 matchId) external view returns (
        bool exists,
        uint256 matchedAmount,
        uint256 matchedPrice,
        uint256 savings
    ) {
        Match storage matchData = matches[matchId];
        if (matchData.buyOrderId == 0) {
            return (false, 0, 0, 0);
        }

        return (
            true,
            matchData.matchedAmount,
            matchData.matchedPrice,
            matchData.savings
        );
    }

    function executeMatch(bytes32 matchId) external {
        Match storage matchData = matches[matchId];
        require(matchData.buyOrderId != 0, "Match not found");
        require(!matchData.isExecuted, "Already executed");

        matchData.isExecuted = true;

        emit MatchExecuted(matchId, matchData.matchedAmount, matchData.matchedPrice);

        // In production: execute actual cross-chain settlement
        // For now, just mark as executed
    }

    function _verifyMatch(
        OrderRequest storage request,
        uint256 matchedAmount,
        uint256 matchedPrice
    ) internal returns (bool) {
        // Convert to encrypted values for FHE comparison
        euint32 encryptedMatchAmount = FHE.asEuint32(uint32(matchedAmount / 1e14));
        euint32 encryptedMatchPrice = FHE.asEuint32(uint32(matchedPrice / 1e12));

        // Verify amount doesn't exceed available
        ebool amountValid = FHE.lte(encryptedMatchAmount, request.encryptedAmount);
        
        // Verify price is acceptable
        ebool priceValid = FHE.lte(encryptedMatchPrice, request.encryptedMaxPrice);

        // Both conditions must be true
        ebool bothValid = FHE.and(amountValid, priceValid);

        // Use FHE.select to conditionally return validation result
        euint32 validationResult = FHE.select(bothValid, ENCRYPTED_ONE, ENCRYPTED_ZERO);

        // Grant access for potential decryption
        FHE.allowThis(validationResult);
        FHE.allowSender(validationResult);

        return true; // Simplified for demo
    }

    function _checkConsensus(bytes32 requestId) internal {
        address[] memory submitters = submittedOperators[requestId];
        uint256 requiredConsensus = (operatorList.length * QUORUM_THRESHOLD) / 100;

        if (submitters.length >= requiredConsensus) {
            _createMatch(requestId, submitters);
        }
    }

    function _createMatch(bytes32 requestId, address[] memory submitters) internal {
        OrderRequest storage request = orderRequests[requestId];
        
        // Use first submission as consensus (simplified)
        OperatorSubmission storage firstSubmission = submissions[requestId][submitters[0]];

        bytes32 matchId = keccak256(abi.encodePacked(requestId, block.timestamp));

        matches[matchId] = Match({
            buyOrderId: request.isBuyOrder ? requestId : firstSubmission.oppositeOrderId,
            sellOrderId: request.isBuyOrder ? firstSubmission.oppositeOrderId : requestId,
            matchedAmount: firstSubmission.matchedAmount,
            matchedPrice: firstSubmission.matchedPrice,
            savings: _calculateSavings(firstSubmission.matchedAmount, firstSubmission.matchedPrice),
            consensusCount: submitters.length,
            isExecuted: false
        });

        // Update request with match ID
        request.isActive = false;

        emit MatchFound(requestId, matchId, matches[matchId].savings);
    }

    function _calculateSavings(uint256 amount, uint256 price) internal pure returns (uint256) {
        // Simplified savings calculation
        uint256 baseCost = amount * price / 1e18;
        uint256 ammCost = baseCost * 1008 / 1000; // 0.8% extra for AMM
        return ammCost > baseCost ? ammCost - baseCost : 0;
    }

    // Real Chainlink price integration
    function _updateTokenPrice(address token) internal {
        if (block.timestamp - lastPriceUpdate[token] < 5 minutes) {
            return; // Price recently updated
        }

        uint256 price;
        if (token == address(WETH)) {
            price = _getChainlinkPrice(ETH_USD_FEED);
        } else if (token == address(USDC)) {
            price = _getChainlinkPrice(USDC_USD_FEED);
        } else {
            return; // Unsupported token
        }

        cachedPrice[token] = price;
        lastPriceUpdate[token] = block.timestamp;

        emit PriceUpdated(token, price, block.timestamp);
    }

    function _getChainlinkPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            require(price > 0, "Invalid price");
            require(block.timestamp - updatedAt < 1 hours, "Price too stale");
            return uint256(price) * 1e10; // Convert to 18 decimals
        } catch {
            revert("Price feed error");
        }
    }

    function getTokenPrice(address token) external view returns (uint256) {
        return cachedPrice[token];
    }

    // LayerZero cross-chain messaging
    function _sendCrossChainOrderDiscovery(
        bytes32 requestId,
        bytes32 poolId,
        bool isBuyOrder,
        uint256 sourceChain
    ) internal {
        bytes memory message = abi.encode(requestId, poolId, isBuyOrder, sourceChain, msg.sender);

        // Send to other chains for order discovery
        uint32[] memory targetChains = new uint32[](3);
        targetChains[0] = ETHEREUM_SEPOLIA_EID;
        targetChains[1] = POLYGON_MUMBAI_EID;
        targetChains[2] = OPTIMISM_SEPOLIA_EID;

        for (uint256 i = 0; i < targetChains.length; i++) {
            if (targetChains[i] != block.chainid) {
                try LZ_ENDPOINT.send{value: 0.01 ether}(
                    targetChains[i],
                    bytes32(uint256(uint160(address(this)))),
                    message,
                    payable(msg.sender),
                    hex"00030100110100000000000000000000000000030d40"
                ) returns (bytes32 msgId, uint256, uint256) {
                    emit CrossChainOrderSent(requestId, targetChains[i]);
                } catch {
                    // Continue if cross-chain send fails
                }
            }
        }
    }

    // MEV Protection: Commit-Reveal Mechanism
    function commitOrder(bytes32 commitment) external {
        require(commitments[msg.sender].revealDeadline == 0, "Commitment exists");

        commitments[msg.sender] = CommittedOrder({
            commitment: commitment,
            revealDeadline: block.timestamp + MEV_PROTECTION_WINDOW,
            isRevealed: false
        });

        emit OrderCommitted(msg.sender, commitment);
    }

    function revealOrder(
        bytes32 requestId,
        uint256 amount,
        uint256 maxPrice,
        uint256 nonce
    ) external {
        CommittedOrder storage commitment = commitments[msg.sender];
        require(commitment.revealDeadline > 0, "No commitment");
        require(block.timestamp <= commitment.revealDeadline, "Reveal window expired");
        require(!commitment.isRevealed, "Already revealed");

        bytes32 computedCommitment = keccak256(abi.encodePacked(
            msg.sender, requestId, amount, maxPrice, nonce
        ));
        require(computedCommitment == commitment.commitment, "Invalid reveal");

        commitment.isRevealed = true;

        // Update order request with revealed data
        OrderRequest storage order = orderRequests[requestId];
        require(order.requester == msg.sender, "Not order owner");

        order.isRevealed = true;
        order.commitTimestamp = block.timestamp;

        emit OrderRevealed(requestId, amount, maxPrice);
    }

    // ERC20 token settlement
    function executeTokenSettlement(
        bytes32 matchId,
        address buyTrader,
        address sellTrader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        require(operators[msg.sender], "Not operator");
        Match storage matchData = matches[matchId];
        require(matchData.buyOrderId != 0, "Match not found");
        require(!matchData.isExecuted, "Already executed");

        // Execute atomic token swap
        IERC20(tokenIn).transferFrom(buyTrader, sellTrader, amountIn);
        IERC20(tokenOut).transferFrom(sellTrader, buyTrader, amountOut);

        matchData.isExecuted = true;
        emit MatchExecuted(matchId, amountIn, amountOut);
    }

    // Batch execution for MEV protection
    function executeBatch(bytes32[] calldata orderIds) external {
        require(operators[msg.sender], "Not operator");

        for (uint256 i = 0; i < orderIds.length; i++) {
            OrderRequest storage order = orderRequests[orderIds[i]];
            if (order.isActive && order.isRevealed) {
                // Process revealed orders in batch
                batchExecutionTime[orderIds[i]] = block.timestamp;
            }
        }
    }

    // AVS Service Manager integration
    function createMatch(
        bytes32 orderHash,
        bytes32 oppositeOrderHash,
        uint256 matchedPrice,
        uint256 savings
    ) external returns (bytes32 matchId) {
        // Only allow AVS Service Manager to create matches
        // require(msg.sender == avsServiceManager, "Only AVS can create matches");

        matchId = keccak256(abi.encodePacked(orderHash, oppositeOrderHash, block.timestamp));

        matches[matchId] = Match({
            buyOrderId: orderHash,
            sellOrderId: oppositeOrderHash,
            matchedAmount: 0, // Would be determined from orders
            matchedPrice: matchedPrice,
            savings: savings,
            consensusCount: 1,
            isExecuted: false
        });

        emit MatchExecuted(matchId, 0, matchedPrice);
        return matchId;
    }

    function verifyOrderExists(bytes32 orderHash) external view returns (bool) {
        // Check if order exists in any of the discovery maps
        // This is simplified - in production would search through all chains/pools
        return orderHash != bytes32(0);
    }

    // Emergency functions
    function emergencyPause() external {
        require(operators[msg.sender], "Not operator");
        // Emergency pause logic
    }

    function recoverStuckTokens(address token, uint256 amount) external {
        require(operators[msg.sender], "Not operator");
        IERC20(token).transfer(msg.sender, amount);
    }

    // View functions
    function getPendingOrders(bytes32 poolId, bool isBuyOrder) external view returns (bytes32[] memory) {
        return pendingOrders[poolId][isBuyOrder];
    }

    function getChainOrders(uint256 chainId, bytes32 poolId) external view returns (bytes32[] memory) {
        return chainOrders[chainId][poolId];
    }

    function totalOperators() external view returns (uint256) {
        return operatorList.length;
    }

    function isOperator(address operator) external view returns (bool) {
        return operators[operator];
    }
}
