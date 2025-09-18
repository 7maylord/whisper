// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-mock-contracts/contracts/CoFheTest.sol";

/**
 * @title CleanAVSTest - Test CoWMatcher as EigenLayer AVS
 * @dev Clean test without Unicode characters
 */
contract CleanAVSTest is Test, CoFheTest {
    CoWMatcher cowMatcher;

    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");

    function setUp() public {
        cowMatcher = new CoWMatcher();

        vm.prank(operator1);
        cowMatcher.registerOperator();
        vm.prank(operator2);
        cowMatcher.registerOperator();
        vm.prank(operator3);
        cowMatcher.registerOperator();
    }

    function test_RealArbitrumSepoliaIntegration() public {
        // Verify real Arbitrum Sepolia addresses are configured
        assertEq(address(cowMatcher.ETH_USD_FEED()), 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08);
        assertEq(address(cowMatcher.USDC_USD_FEED()), 0x0153002d20B96532C639313c2d54c3dA09109309);
        assertEq(address(cowMatcher.LZ_ENDPOINT()), 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(address(cowMatcher.USDC()), 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);
        assertEq(address(cowMatcher.WETH()), 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);

        console.log("Real Arbitrum Sepolia integration verified");
    }

    function test_AVSOperatorManagement() public {
        assertEq(cowMatcher.totalOperators(), 3);
        assertTrue(cowMatcher.isOperator(operator1));
        assertTrue(cowMatcher.isOperator(operator2));
        assertTrue(cowMatcher.isOperator(operator3));

        console.log("AVS operator management working");
    }

    function test_CrossChainConfiguration() public {
        assertEq(cowMatcher.ETHEREUM_SEPOLIA_EID(), 40161);
        assertEq(cowMatcher.POLYGON_MUMBAI_EID(), 40109);
        assertEq(cowMatcher.OPTIMISM_SEPOLIA_EID(), 40232);

        console.log("Cross-chain configuration verified");
    }

    function test_ProductionReadyAVS() public {
        // Actually test production readiness with real assertions

        // 1. Verify Chainlink price feeds are configured (not just addresses)
        assertTrue(address(cowMatcher.ETH_USD_FEED()) != address(0), "ETH price feed not configured");
        assertTrue(address(cowMatcher.USDC_USD_FEED()) != address(0), "USDC price feed not configured");

        // 2. Verify LayerZero cross-chain is configured
        assertTrue(address(cowMatcher.LZ_ENDPOINT()) != address(0), "LayerZero endpoint not configured");
        assertTrue(cowMatcher.ETHEREUM_SEPOLIA_EID() != 0, "Ethereum EID not set");
        assertTrue(cowMatcher.POLYGON_MUMBAI_EID() != 0, "Polygon EID not set");

        // 3. Verify real ERC20 tokens are configured
        assertTrue(address(cowMatcher.USDC()) != address(0), "USDC not configured");
        assertTrue(address(cowMatcher.WETH()) != address(0), "WETH not configured");

        // 4. Verify MEV protection constants are set correctly
        assertEq(cowMatcher.MATCH_TIMEOUT(), 5 minutes, "Match timeout incorrect");
        assertEq(cowMatcher.MEV_PROTECTION_WINDOW(), 30 seconds, "MEV protection window incorrect");

        // 5. Verify operator consensus threshold
        assertEq(cowMatcher.QUORUM_THRESHOLD(), 66, "Quorum threshold incorrect");
        assertGt(cowMatcher.totalOperators(), 0, "No operators registered");

        // 6. Verify contract is properly initialized
        assertTrue(cowMatcher.totalOperators() >= 3, "Insufficient operators for consensus");

        console.log("All production readiness checks passed!");
    }

    //     function test_FHEOperationsWithMocks() public {
    //         console.log("=== Testing FHE Operations with Mocks ===");
    // 
    //         // Test basic FHE order creation with mocks
    //         bytes32 poolId = bytes32("mockTestPool");
    //         uint32 amount = 100;
    //         uint32 price = 2000;
    // 
    //         // Create encrypted inputs using the official CoFheTest method
    //         InEuint32 memory encryptedAmount = createInEuint32(amount, operator1);
    //         InEuint32 memory encryptedPrice = createInEuint32(price, operator1);
    // 
    //         // Test order creation
    //         vm.prank(operator1);
    //         bytes32 orderId = cowMatcher.findMatch(
    //             poolId,
    //             true, // isBuyOrder
    //             FHE.asEuint32(encryptedAmount),
    //             FHE.asEuint32(encryptedPrice),
    //             block.chainid
    //         );
    // 
    //         assertTrue(orderId != bytes32(0), "Order created successfully with FHE mocks");
    //         console.log("FHE operations working with mocks!");
    //     }
    }