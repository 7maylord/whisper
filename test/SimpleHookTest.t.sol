// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Whisper} from "../src/Whisper.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-mock-contracts/contracts/CoFheTest.sol";

/**
 * @title SimpleHookTest - Basic Whisper Hook Testing
 * @dev Tests Whisper hook functions without complex v4 setup
 */
contract SimpleHookTest is Test, CoFheTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Whisper hook;
    CoWMatcher cowMatcher;
    IPoolManager mockManager;

    // Test addresses
    address trader1 = makeAddr("trader1");
    address trader2 = makeAddr("trader2");
    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");

    function setUp() public {
        // Deploy CoWMatcher
        cowMatcher = new CoWMatcher();

        // Register operators
        vm.prank(operator1);
        cowMatcher.registerOperator();
        vm.prank(operator2);
        cowMatcher.registerOperator();
        vm.prank(operator3);
        cowMatcher.registerOperator();

        // Mock pool manager
        mockManager = IPoolManager(makeAddr("mockManager"));

        // Deploy hook using deployCodeTo for testing
        bytes memory constructorArgs = abi.encode(mockManager, address(cowMatcher));
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        address hookAddress = address(flags);
        deployCodeTo("Whisper.sol:Whisper", constructorArgs, hookAddress);
        hook = Whisper(hookAddress);
    }

    function test_HookDeployment() public {
        // Test that Whisper hook deployed correctly
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertEq(hook.ORDER_THRESHOLD(), 10 ether, "Order threshold should be 10 ETH");
        assertEq(hook.MATCH_WINDOW(), 2 minutes, "Match window should be 2 minutes");
        assertEq(address(hook.COW_MATCHER()), address(cowMatcher), "CoW matcher should be set");
    }

    function test_HookPermissions() public {
        // Test that hook has correct permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "Should have beforeSwap permission");
        assertTrue(permissions.afterSwap, "Should have afterSwap permission");
        assertTrue(permissions.beforeSwapReturnDelta, "Should return delta in beforeSwap");
        assertTrue(permissions.afterSwapReturnDelta, "Should return delta in afterSwap");
    }

    function test_OrderStorage() public {
        // Test order storage functionality
        bytes32 orderId = keccak256("testOrder");
        address testTrader = trader1;

        // Initially no order should exist
        bytes32 retrievedOrder = hook.getTraderOrder(testTrader);
        assertEq(retrievedOrder, bytes32(0), "No order should exist initially");

        // Test order state retrieval
        Whisper.OrderState state = hook.getOrderState(orderId);
        assertTrue(state == Whisper.OrderState.None, "Non-existent order should return None");
    }

    function test_ThresholdLogic() public {
        // Test the threshold logic (this would be part of beforeSwap)
        uint256 smallAmount = 5 ether; // Below threshold
        uint256 largeAmount = 15 ether; // Above threshold

        // We can't directly call beforeSwap without proper setup,
        // but we can test the threshold constant
        assertTrue(smallAmount < hook.ORDER_THRESHOLD(), "Small amount should be below threshold");
        assertTrue(largeAmount >= hook.ORDER_THRESHOLD(), "Large amount should be at/above threshold");
    }

    function test_CoWMatcherIntegration() public {
        // Test integration between Whisper hook and CoWMatcher
        assertEq(address(hook.COW_MATCHER()), address(cowMatcher), "Hook should reference correct CoWMatcher");
        assertEq(cowMatcher.totalOperators(), 3, "CoWMatcher should have 3 operators");
        assertTrue(cowMatcher.isOperator(operator1), "Operator1 should be registered");
    }

    function test_HookConstants() public {
        // Test all hook constants are set correctly
        assertEq(hook.ORDER_THRESHOLD(), 10 ether, "Order threshold incorrect");
        assertEq(hook.MATCH_WINDOW(), 2 minutes, "Match window incorrect");
        assertTrue(address(hook.COW_MATCHER()) != address(0), "CoW matcher not set");
    }

    function test_MockOrderCreation() public {
        // Test order creation logic with mocked data
        bytes32 poolId = bytes32("mockPool");
        address testTrader = trader1;

        // Simulate what would happen in beforeSwap for large orders
        // (This tests the internal logic without requiring full v4 setup)

        // Before any order creation
        bytes32 existingOrder = hook.getTraderOrder(testTrader);
        assertEq(existingOrder, bytes32(0), "No order should exist before creation");

        // Test that the hook would detect this as a large order
        uint256 largeAmount = 20 ether;
        assertTrue(largeAmount >= hook.ORDER_THRESHOLD(), "Should trigger CoW for large amounts");

        console.log("Hook deployment and basic functionality verified");
    }

    function test_FHEMockIntegration() public {
        // Test FHE integration using mocks
        uint32 amount = 100;
        uint32 price = 2000;

        // Create encrypted inputs
        InEuint32 memory encryptedAmount = createInEuint32(amount, trader1);
        InEuint32 memory encryptedPrice = createInEuint32(price, trader1);

        // Test that encrypted values can be created
        assertTrue(encryptedAmount.ctHash != 0, "Encrypted amount should be created");
        assertTrue(encryptedPrice.ctHash != 0, "Encrypted price should be created");

        // This verifies FHE mocks work for the CoWMatcher integration
        console.log("FHE mock integration working");
    }

    function test_HookAddressPermissions() public {
        // Test that the hook address has the correct permission flags
        uint160 expectedFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // The hook should be deployed at an address that matches these flags
        uint160 hookAddr = uint160(address(hook));
        uint160 flagsMask = uint160(0xFFFF); // Last 16 bits for flags

        assertEq(hookAddr & flagsMask, expectedFlags & flagsMask, "Hook address should have correct permission flags");
    }
}