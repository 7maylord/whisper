// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-mock-contracts/contracts/CoFheTest.sol";

/**
 * @title SimpleWhisperTest - Basic CoWMatcher Testing
 * @dev Tests CoWMatcher functionality without complex Uniswap integration
 */
contract SimpleWhisperTest is Test, CoFheTest {
    CoWMatcher cowMatcher;

    // Test addresses
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
    }

    function test_CoWMatcherDeployment() public {
        // Test that CoWMatcher deployed correctly
        assertTrue(address(cowMatcher) != address(0));
        assertEq(cowMatcher.totalOperators(), 3);
        assertTrue(cowMatcher.isOperator(operator1));
        assertTrue(cowMatcher.isOperator(operator2));
        assertTrue(cowMatcher.isOperator(operator3));
    }

    function test_RealArbitrumSepoliaAddresses() public {
        // Test all the real Arbitrum Sepolia integrations we added
        assertEq(address(cowMatcher.ETH_USD_FEED()), 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08);
        assertEq(address(cowMatcher.USDC_USD_FEED()), 0x0153002d20B96532C639313c2d54c3dA09109309);
        assertEq(address(cowMatcher.LZ_ENDPOINT()), 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(address(cowMatcher.USDC()), 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);
        assertEq(address(cowMatcher.WETH()), 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);
    }

    function test_LayerZeroConfiguration() public {
        // Test LayerZero chain IDs
        assertEq(cowMatcher.ETHEREUM_SEPOLIA_EID(), 40161);
        assertEq(cowMatcher.POLYGON_MUMBAI_EID(), 40109);
        assertEq(cowMatcher.OPTIMISM_SEPOLIA_EID(), 40232);
    }

    function test_MEVProtectionConstants() public {
        // Test MEV protection parameters
        assertEq(cowMatcher.MEV_PROTECTION_WINDOW(), 30 seconds);
        assertEq(cowMatcher.QUORUM_THRESHOLD(), 66);
        assertEq(cowMatcher.MATCH_TIMEOUT(), 5 minutes);
    }

    function test_OperatorRegistration() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(newOperator);
        cowMatcher.registerOperator();

        assertTrue(cowMatcher.isOperator(newOperator));
        assertEq(cowMatcher.totalOperators(), 4); // 3 from setUp + 1 new
    }

    function test_CommitRevealMechanism() public {
        address trader = makeAddr("trader");
        uint256 amount = 15 ether;
        uint256 maxPrice = 2000 ether;
        uint256 nonce = 12345;

        // First create an order request
        bytes32 poolId = bytes32("testPool");
        vm.prank(trader);
        bytes32 requestId = cowMatcher.findMatch(
            poolId,
            true, // isBuyOrder
            FHE.asEuint32(uint32(amount / 1e14)),
            FHE.asEuint32(uint32(maxPrice / 1e12)),
            block.chainid
        );

        // Test commit
        bytes32 commitment = keccak256(abi.encodePacked(
            trader, requestId, amount, maxPrice, nonce
        ));

        vm.prank(trader);
        cowMatcher.commitOrder(commitment);

        // Verify commitment stored
        (bytes32 storedCommitment, uint256 deadline, bool isRevealed) =
            cowMatcher.commitments(trader);
        assertEq(storedCommitment, commitment);
        assertGt(deadline, block.timestamp);
        assertFalse(isRevealed);

        // Test reveal
        vm.prank(trader);
        cowMatcher.revealOrder(requestId, amount, maxPrice, nonce);

        // Verify reveal worked
        (, , bool revealed) = cowMatcher.commitments(trader);
        assertTrue(revealed);
    }

    function test_OrderCreation() public {
        bytes32 poolId = bytes32("testPool");

        // Create order
        vm.prank(operator1);
        bytes32 orderId = cowMatcher.findMatch(
            poolId,
            true, // isBuyOrder
            FHE.asEuint32(100), // amount
            FHE.asEuint32(2000), // maxPrice
            block.chainid
        );

        // Verify order was created
        assertNotEq(orderId, bytes32(0));

        // Check that order was added to discovery maps
        bytes32[] memory chainOrders = cowMatcher.getChainOrders(block.chainid, poolId);
        assertEq(chainOrders.length, 1);
        assertEq(chainOrders[0], orderId);

        bytes32[] memory pendingOrders = cowMatcher.getPendingOrders(poolId, true);
        assertEq(pendingOrders.length, 1);
        assertEq(pendingOrders[0], orderId);
    }

    function test_OperatorConsensus() public {
        bytes32 requestId = keccak256("testRequest");
        uint256 amount = 15 ether;
        uint256 price = 1000 ether;

        // Create a mock order first
        bytes32 poolId = bytes32("testPool");
        vm.prank(operator1);
        cowMatcher.findMatch(
            poolId,
            true,
            FHE.asEuint32(100),
            FHE.asEuint32(2000),
            block.chainid
        );

        // Operators submit matches (need 66% consensus = 2 out of 3)
        vm.prank(operator1);
        cowMatcher.submitMatch(
            requestId,
            bytes32("oppositeOrderId"),
            amount,
            price,
            1 // oppositeChain
        );

        vm.prank(operator2);
        cowMatcher.submitMatch(
            requestId,
            bytes32("oppositeOrderId"),
            amount,
            price,
            1
        );

        // Check that consensus was reached and match created
        (bool exists, uint256 matchedAmount, uint256 matchedPrice, uint256 savings) =
            cowMatcher.getMatch(requestId);

        assertTrue(exists);
        assertEq(matchedAmount, amount);
        assertEq(matchedPrice, price);
        assertGt(savings, 0);
    }

    function test_GasEfficiency() public {
        bytes32 poolId = bytes32("testPool");

        // Test gas efficiency of order creation
        uint256 gasStart = gasleft();

        vm.prank(operator1);
        cowMatcher.findMatch(
            poolId,
            true,
            FHE.asEuint32(100),
            FHE.asEuint32(2000),
            block.chainid
        );

        uint256 gasUsed = gasStart - gasleft();

        // Should be under 300k gas for order creation with real integrations
        assertLt(gasUsed, 300_000);
        console.log("Gas used for order creation:", gasUsed);
    }
}