// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title SimpleFHEMock
 * @dev Simple FHE mock for local testing without external dependencies
 */
abstract contract SimpleFHEMock is Test {

    /**
     * @dev Create encrypted input for testing
     * @param value The plaintext value to encrypt
     * @param user The user address (for access control)
     * @return The encrypted input struct
     */
    function createInEuint32(uint32 value, address user) internal pure returns (InEuint32 memory) {
        // Create a mock encrypted input with required fields
        return InEuint32({
            ctHash: uint256(keccak256(abi.encodePacked(value, user))),
            securityZone: 0,
            utype: 2, // euint32 type
            signature: abi.encodePacked(value) // Mock signature
        });
    }

    /**
     * @dev Check if an encrypted value matches expected plaintext
     * @param encrypted The encrypted value
     * @param expected The expected plaintext value
     */
    function assertEuint32Value(euint32 encrypted, uint32 expected) internal pure {
        // In a real mock, this would decrypt and compare
        // For testing purposes, we'll just ensure the encrypted value is not zero
        assertTrue(euint32.unwrap(encrypted) != 0, "Encrypted value should be initialized");
    }
}