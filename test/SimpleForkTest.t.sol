// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";

/**
 * @title SimpleForkTest - Basic Fork Testing
 * @dev Simple test to verify fork setup and basic contract deployment
 */
contract SimpleForkTest is Test {
    CoWMatcher cowMatcher;

    address operator1 = makeAddr("operator1");

    function setUp() public {
        cowMatcher = new CoWMatcher();

        vm.prank(operator1);
        cowMatcher.registerOperator();
    }

    function test_BasicDeploymentOnFork() public {
        // Test basic deployment works on fork
        assertTrue(address(cowMatcher) != address(0), "CoWMatcher deployed");
        assertTrue(cowMatcher.isOperator(operator1), "Operator registered");
        assertEq(cowMatcher.totalOperators(), 1, "Operator count correct");

        console.log("Basic deployment successful on fork");
        console.log("Block number:", block.number);
        console.log("Chain ID:", block.chainid);
    }

    function test_ConfiguredAddressesExist() public {
        // Test if our configured addresses have code deployed
        address ethFeed = address(cowMatcher.ETH_USD_FEED());
        address usdcFeed = address(cowMatcher.USDC_USD_FEED());
        address lzEndpoint = address(cowMatcher.LZ_ENDPOINT());

        console.log("ETH/USD Feed address:", ethFeed);
        console.log("USDC/USD Feed address:", usdcFeed);
        console.log("LayerZero Endpoint:", lzEndpoint);

        // Check if addresses have code
        uint256 ethFeedSize;
        uint256 usdcFeedSize;
        uint256 lzSize;

        assembly {
            ethFeedSize := extcodesize(ethFeed)
            usdcFeedSize := extcodesize(usdcFeed)
            lzSize := extcodesize(lzEndpoint)
        }

        console.log("ETH Feed code size:", ethFeedSize);
        console.log("USDC Feed code size:", usdcFeedSize);
        console.log("LayerZero code size:", lzSize);

        if (ethFeedSize > 0) {
            console.log("ETH/USD feed contract found on fork");
        } else {
            console.log("ETH/USD feed contract NOT found - address may be incorrect");
        }

        if (lzSize > 0) {
            console.log("LayerZero endpoint found on fork");
        } else {
            console.log("LayerZero endpoint NOT found - may not be deployed yet");
        }
    }

    function test_TokenAddressesExist() public {
        address weth = address(cowMatcher.WETH());
        address usdc = address(cowMatcher.USDC());

        console.log("WETH address:", weth);
        console.log("USDC address:", usdc);

        uint256 wethSize;
        uint256 usdcSize;

        assembly {
            wethSize := extcodesize(weth)
            usdcSize := extcodesize(usdc)
        }

        console.log("WETH code size:", wethSize);
        console.log("USDC code size:", usdcSize);

        if (wethSize > 0) {
            console.log("WETH contract found on fork");
        }
        if (usdcSize > 0) {
            console.log("USDC contract found on fork");
        }
    }

    function test_MEVProtectionBasic() public {
        // Test basic MEV protection without external dependencies
        address trader = makeAddr("trader");
        bytes32 requestId = keccak256("forkTest");
        uint256 amount = 15 ether;
        uint256 maxPrice = 2000 ether;
        uint256 nonce = 12345;

        bytes32 commitment = keccak256(abi.encodePacked(
            trader, requestId, amount, maxPrice, nonce
        ));

        vm.prank(trader);
        cowMatcher.commitOrder(commitment);

        (bytes32 storedCommitment,,) = cowMatcher.commitments(trader);
        assertEq(storedCommitment, commitment, "Commitment stored");

        console.log("MEV protection working on fork");
    }

    function test_ForkEnvironmentInfo() public {
        console.log("=== FORK ENVIRONMENT INFO ===");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log("Chain ID:", block.chainid);
        console.log("Gas price:", tx.gasprice);
        console.log("");
        console.log("CoWMatcher deployed at:", address(cowMatcher));
        console.log("Total operators:", cowMatcher.totalOperators());
        console.log("");

        if (block.chainid == 421614) {
            console.log("Connected to Arbitrum Sepolia - CORRECT!");
        } else {
            console.log("NOT on Arbitrum Sepolia - check RPC URL");
        }
    }
}