// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {FHE, euint32, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

interface ICoWMatcher {
    function findMatch(
        bytes32 poolId,
        bool isBuyOrder,
        euint32 encryptedAmount,
        euint32 encryptedMaxPrice,
        uint256 chainId
    ) external returns (bytes32 matchId);

    function getMatch(bytes32 matchId) external view returns (
        bool exists,
        uint256 matchedAmount,
        uint256 matchedPrice,
        uint256 savings
    );
}

contract Whisper is BaseHook {
    using PoolIdLibrary for PoolKey;

    uint256 public constant ORDER_THRESHOLD = 10 ether;
    uint256 public constant MATCH_WINDOW = 2 minutes;

    // FHE constants
    euint32 private ENCRYPTED_ZERO;
    euint32 private ENCRYPTED_ONE;

    enum OrderState {
        None,
        Pending,    // Waiting for CoW match
        Matched,    // CoW match found
        Executed    // CoW match executed
    }

    struct Order {
        address trader;
        bool isBuyOrder;
        euint32 encryptedAmount;
        euint32 encryptedMaxPrice;
        uint256 deadline;
        OrderState state;
        bytes32 matchId;
    }

    // Simple state management
    mapping(bytes32 => Order) public orders;
    mapping(address => bytes32) public traderOrders;

    ICoWMatcher public immutable COW_MATCHER;

    event OrderCreated(bytes32 indexed orderId, address trader, bool isBuyOrder, uint256 amount);
    event CoWMatchFound(bytes32 indexed orderId, bytes32 indexed matchId, uint256 savings);
    event CoWMatchExecuted(bytes32 indexed orderId, uint256 matchedAmount, uint256 matchedPrice);

    constructor(IPoolManager _poolManager, address _cowMatcher) BaseHook(_poolManager) {
        COW_MATCHER = ICoWMatcher(_cowMatcher);

        // Initialize FHE constants
        ENCRYPTED_ZERO = FHE.asEuint32(0);
        ENCRYPTED_ONE = FHE.asEuint32(1);

        // Grant contract access
        FHE.allowThis(ENCRYPTED_ZERO);
        FHE.allowThis(ENCRYPTED_ONE);
    }

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(
        address trader,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 inputAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        // Only process large orders for CoW matching
        if (inputAmount <= ORDER_THRESHOLD) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        bytes32 poolId = PoolId.unwrap(key.toId());
        bytes32 orderId = keccak256(abi.encodePacked(poolId, trader, block.timestamp, block.number));

        // Encrypt order details
        euint32 encryptedAmount = FHE.asEuint32(uint32(inputAmount / 1e14));
        uint256 maxPrice = _calculateMaxPrice(inputAmount);
        euint32 encryptedMaxPrice = FHE.asEuint32(uint32(maxPrice / 1e12));

        // Grant access for CoW matcher
        FHE.allowThis(encryptedAmount);
        FHE.allowThis(encryptedMaxPrice);
        FHE.allowSender(encryptedAmount);
        FHE.allowSender(encryptedMaxPrice);

        // Create order
        orders[orderId] = Order({
            trader: trader,
            isBuyOrder: !params.zeroForOne,
            encryptedAmount: encryptedAmount,
            encryptedMaxPrice: encryptedMaxPrice,
            deadline: block.timestamp + MATCH_WINDOW,
            state: OrderState.Pending,
            matchId: bytes32(0)
        });

        traderOrders[trader] = orderId;

        // Request CoW match
        bytes32 matchId = COW_MATCHER.findMatch(
            poolId,
            !params.zeroForOne,
            encryptedAmount,
            encryptedMaxPrice,
            block.chainid
        );

        orders[orderId].matchId = matchId;

        emit OrderCreated(orderId, trader, !params.zeroForOne, inputAmount);

        // Pause swap for CoW matching
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address trader,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        bytes32 orderId = traderOrders[trader];
        
        if (orderId == 0) {
            return (this.afterSwap.selector, 0);
        }

        Order storage order = orders[orderId];

        // Check if match found
        if (order.state == OrderState.Pending) {
            (bool exists, uint256 matchedAmount, uint256 matchedPrice, uint256 savings) = 
                COW_MATCHER.getMatch(order.matchId);

            if (exists) {
                order.state = OrderState.Matched;
                emit CoWMatchFound(orderId, order.matchId, savings);
            } else if (block.timestamp > order.deadline) {
                // Order expired, let it fall through to normal AMM execution
                _cleanupOrder(orderId);
            }
        } else if (order.state == OrderState.Matched) {
            // Execute the CoW match
            order.state = OrderState.Executed;
            (, uint256 matchedAmount, uint256 matchedPrice,) = COW_MATCHER.getMatch(order.matchId);
            emit CoWMatchExecuted(orderId, matchedAmount, matchedPrice);
            _cleanupOrder(orderId);
        }

        return (this.afterSwap.selector, 0);
    }

    function _cleanupOrder(bytes32 orderId) internal {
        Order storage order = orders[orderId];
        delete traderOrders[order.trader];
        delete orders[orderId];
    }

    function _calculateMaxPrice(uint256 inputAmount) internal pure returns (uint256) {
        // Simple price calculation - in production would query actual pool price
        return inputAmount * 101 / 100; // 1% tolerance
    }

    // Simple view functions
    function getOrderState(bytes32 orderId) external view returns (OrderState) {
        return orders[orderId].state;
    }

    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getTraderOrder(address trader) external view returns (bytes32) {
        return traderOrders[trader];
    }
}
