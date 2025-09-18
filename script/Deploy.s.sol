// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Whisper} from "../src/Whisper.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";

/**
 * @title DeployWhisper
 * @notice Simple deployment script for Whisper hook with CoWMatcher
 */
contract DeployWhisper is Script {
    // Known contract addresses for different networks
    address constant SEPOLIA_POOL_MANAGER = 0x8464135c8F25Da09e49BC8782676a84730C318bC;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CoWMatcher first
        CoWMatcher cowMatcher = new CoWMatcher();
        console.log("CoWMatcher deployed at:", address(cowMatcher));

        // 2. Deploy Whisper hook
        IPoolManager poolManager = IPoolManager(SEPOLIA_POOL_MANAGER);
        Whisper whisperHook = new Whisper(poolManager, address(cowMatcher));
        console.log("Whisper Hook deployed at:", address(whisperHook));

        // 3. Register deployer as operator
        cowMatcher.registerOperator();
        console.log("Registered deployer as operator");

        vm.stopBroadcast();
    }
}