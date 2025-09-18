// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Whisper} from "../src/Whisper.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-mock-contracts/contracts/CoFheTest.sol";

/**
 * @title WhisperTest - Proper Uniswap v4 Hook Testing
 * @dev Tests Whisper CoW hook using standard Uniswap v4 testing patterns
 */
contract WhisperTest is Test, Deployers, CoFheTest {
    Whisper hook;
    CoWMatcher cowMatcher;

    // Test addresses
    address trader1 = makeAddr("trader1");
    address trader2 = makeAddr("trader2");
    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");

    function setUp() public {
        // 1. Deploy Uniswap infrastructure first (required for proper setup)
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // 2. Deploy CoWMatcher
        cowMatcher = new CoWMatcher();

        // 3. Deploy hook using proper HookMiner pattern
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(manager, address(cowMatcher));

        // Mine the correct address for local testing
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this), // deployer for tests
            flags,
            type(Whisper).creationCode,
            constructorArgs
        );

        // Deploy using deployCodeTo for local testing
        deployCodeTo("Whisper.sol:Whisper", constructorArgs, hookAddress);
        hook = Whisper(hookAddress);

        // 4. Register operators
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

    function test_HookDeployment() public {
        // Test that Whisper hook deployed correctly
        assertTrue(address(hook) != address(0));
        assertEq(hook.ORDER_THRESHOLD(), 10 ether);
        assertEq(hook.MATCH_WINDOW(), 2 minutes);
        assertEq(address(hook.COW_MATCHER()), address(cowMatcher));
    }

    function test_HookPermissions() public {
        // Test that hook has correct permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();

        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertTrue(permissions.beforeSwapReturnDelta);
        assertTrue(permissions.afterSwapReturnDelta);
    }

    function test_OperatorRegistration() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(newOperator);
        cowMatcher.registerOperator();

        assertTrue(cowMatcher.isOperator(newOperator));
        assertEq(cowMatcher.totalOperators(), 4); // 3 from setUp + 1 new
    }

    function test_PriceOracleIntegration() public {
        // Test price oracle addresses are set correctly
        assertEq(address(cowMatcher.ETH_USD_FEED()), 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08);
        assertEq(address(cowMatcher.USDC_USD_FEED()), 0x0153002d20B96532C639313c2d54c3dA09109309);
        assertEq(address(cowMatcher.LZ_ENDPOINT()), 0x6EDCE65403992e310A62460808c4b910D972f10f);
    }

    function test_RealTokenAddresses() public {
        // Test real token addresses are set
        assertEq(address(cowMatcher.USDC()), 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);
        assertEq(address(cowMatcher.WETH()), 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);
    }

    function test_CrossChainConfiguration() public {
        // Test LayerZero chain IDs are configured
        assertEq(cowMatcher.ETHEREUM_SEPOLIA_EID(), 40161);
        assertEq(cowMatcher.POLYGON_MUMBAI_EID(), 40109);
        assertEq(cowMatcher.OPTIMISM_SEPOLIA_EID(), 40232);
    }

    function test_MEVProtectionConfiguration() public {
        // Test MEV protection window
        assertEq(cowMatcher.MEV_PROTECTION_WINDOW(), 30 seconds);
        assertEq(cowMatcher.QUORUM_THRESHOLD(), 66);
        assertEq(cowMatcher.MATCH_TIMEOUT(), 5 minutes);
    }

    //     function test_CommitRevealMechanism() public {
    //         address trader = trader1;
    //         uint256 amount = 15 ether;
    //         uint256 maxPrice = 2000 ether;
    //         uint256 nonce = 12345;
    // 
    //         // First create an order request
    //         bytes32 poolId = bytes32("testPool");
    //         vm.prank(trader);
    //         bytes32 requestId = cowMatcher.findMatch(
    //             poolId,
    //             true, // isBuyOrder
    //             FHE.asEuint32(uint32(amount / 1e14)),
    //             FHE.asEuint32(uint32(maxPrice / 1e12)),
    //             block.chainid
    //         );
    // 
    //         // Test commit
    //         bytes32 commitment = keccak256(abi.encodePacked(
    //             trader, requestId, amount, maxPrice, nonce
    //         ));
    // 
    //         vm.prank(trader);
    //         cowMatcher.commitOrder(commitment);
    // 
    //         // Verify commitment stored
    //         (bytes32 storedCommitment, uint256 deadline, bool isRevealed) =
    //             cowMatcher.commitments(trader);
    //         assertEq(storedCommitment, commitment);
    //         assertGt(deadline, block.timestamp);
    //         assertFalse(isRevealed);
    // 
    //         // Test reveal
    //         vm.prank(trader);
    //         cowMatcher.revealOrder(requestId, amount, maxPrice, nonce);
    // 
    //         // Verify reveal worked
    //         (, , bool revealed) = cowMatcher.commitments(trader);
    //         assertTrue(revealed);
    //     }
    // 
    //     function test_OperatorConsensus() public {
    //         bytes32 requestId = keccak256("testRequest");
    //         uint256 amount = 15 ether;
    //         uint256 price = 1000 ether;
    // 
    //         // Create a mock order first
    //         vm.prank(operator1);
    //         cowMatcher.findMatch(
    //             bytes32("poolId"),
    //             true, // isBuyOrder
    //             FHE.asEuint32(0), // Mock encrypted amount
    //             FHE.asEuint32(0), // Mock encrypted price
    //             block.chainid
    //         );
    // 
    //         // Operators submit matches (need 66% consensus = 2 out of 3)
    //         vm.prank(operator1);
    //         cowMatcher.submitMatch(
    //             requestId,
    //             bytes32("oppositeOrderId"),
    //             amount,
    //             price,
    //             1 // oppositeChain
    //         );
    // 
    //         vm.prank(operator2);
    //         cowMatcher.submitMatch(
    //             requestId,
    //             bytes32("oppositeOrderId"),
    //             amount,
    //             price,
    //             1
    //         );
    // 
    //         // Check that consensus was reached and match created
    //         (bool exists, uint256 matchedAmount, uint256 matchedPrice, uint256 savings) =
    //             cowMatcher.getMatch(requestId);
    // 
    //         assertTrue(exists);
    //         assertEq(matchedAmount, amount);
    //         assertEq(matchedPrice, price);
    //         assertGt(savings, 0);
    //     }

    //     function test_GasEfficiency() public {
    //         // Test gas efficiency of order creation
    //         uint256 gasStart = gasleft();
    // 
    //         vm.prank(operator1);
    //         cowMatcher.findMatch(
    //             bytes32("poolId"),
    //             true,
    //             FHE.asEuint32(0),
    //             FHE.asEuint32(0),
    //             block.chainid
    //         );
    // 
    //         uint256 gasUsed = gasStart - gasleft();
    // 
    //         // Should be under 200k gas for order creation
    //         assertLt(gasUsed, 200_000);
    //         console.log("Gas used for order creation:", gasUsed);
    //     }
    // 
    function test_OrderDiscovery() public {
        bytes32 poolId = bytes32("testPool");

        // Create order
        vm.prank(operator1);
        bytes32 orderId = cowMatcher.findMatch(
            poolId,
            true, // isBuyOrder
            FHE.asEuint32(0),
            FHE.asEuint32(0),
            block.chainid
        );

        // Check that order was added to discovery maps
        bytes32[] memory chainOrders = cowMatcher.getChainOrders(block.chainid, poolId);
        assertEq(chainOrders.length, 1);
        assertEq(chainOrders[0], orderId);

        bytes32[] memory pendingOrders = cowMatcher.getPendingOrders(poolId, true);
        assertEq(pendingOrders.length, 1);
        assertEq(pendingOrders[0], orderId);
    }
}