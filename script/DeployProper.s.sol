// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Whisper} from "../src/Whisper.sol";
import {CoWMatcher} from "../src/CoWMatcher.sol";

/**
 * @title DeployProperWhisper
 * @notice Proper deployment with CREATE2 hook address mining
 */
contract DeployProperWhisper is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    // We'll deploy PoolManager locally for testing
    IPoolManager public poolManager;
    CoWMatcher public cowMatcher;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PoolManager (for local testing)
        poolManager = new PoolManager(address(this));
        console.log("PoolManager deployed at:", address(poolManager));

        // 2. Deploy CoWMatcher
        cowMatcher = new CoWMatcher();
        console.log("CoWMatcher deployed at:", address(cowMatcher));

        // 3. Mine proper hook address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(Whisper).creationCode,
            abi.encode(address(poolManager), address(cowMatcher))
        );

        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // 4. Deploy hook at mined address
        Whisper whisperHook = new Whisper{salt: salt}(poolManager, address(cowMatcher));
        console.log("Whisper Hook deployed at:", address(whisperHook));

        require(address(whisperHook) == hookAddress, "Hook address mismatch");

        // 5. Register deployer as operator
        cowMatcher.registerOperator();
        console.log("Registered deployer as operator");

        // 6. Verification
        console.log("All deployment verifications passed!");

        vm.stopBroadcast();
    }
}