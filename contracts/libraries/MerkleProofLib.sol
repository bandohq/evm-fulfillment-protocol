// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;


/// @title MerkleProofLib
/// @author g6s
/// @notice This library provides functions for verifying Merkle proofs
library MerkleProofLib {
    
    /// @notice generateRawLeaf
    /// @param serviceId The service identifier
    /// @param fulfillerSigner The fulfiller signer address
    /// @param fulfillerBeneficiary The fulfiller beneficiary address
    /// @param bfpFeeAmount The BFP fee amount
    /// @return The raw leaf
    function generateRawLeaf(
        uint256 serviceId,
        address fulfillerSigner,
        address fulfillerBeneficiary,
        uint16 feeAmountBasisPoints
    ) public pure returns (bytes32) {
        // Pack the values in the same order as Python
        bytes memory combined = abi.encodePacked(
            bytes32(serviceId),         // 32 bytes: service ID with big-endian byte order
            fulfillerSigner,            // 20 bytes: fulfiller signer address
            fulfillerBeneficiary,       // 20 bytes: fulfiller beneficiary address
            uint16(feeAmountBasisPoints)        // 2 bytes: BFP fee amount
        );
        
        // Apply the first hash (equivalent to keccak(combined) in Python)
        return keccak256(combined);
    }

    /// @notice verifyProduct
    /// @param serviceId The service identifier
    /// @param fulfillerSigner The fulfiller signer address
    /// @param fulfillerBeneficiary The fulfiller beneficiary address
    /// @param feeAmountBasisPoints The BFP fee amount
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service is valid according to the Merkle proof
    function verifyProduct(
        uint256 serviceId,
        address fulfillerSigner,
        address fulfillerBeneficiary,
        uint16 feeAmountBasisPoints,
        bytes32[] calldata proof,
        bool[] calldata directions // true for RIGHT, false for LEFT
    ) public view returns (bool) {
        require(proof.length == directions.length, "Proof and directions length mismatch");
        
        // Generate the first hash (raw leaf)
        bytes32 rawLeaf = generateRawLeaf(
            serviceId,
            fulfillerSigner,
            fulfillerBeneficiary,
            feeAmountBasisPoints
        );
        
        // Apply the second hash (matching what the MerkleTree library does)
        bytes32 computedHash = keccak256(abi.encodePacked(rawLeaf));
        
        // Apply the verification algorithm with directions
        for (uint256 i = 0; i < proof.length; i++) {
            if (directions[i]) { // RIGHT
                computedHash = keccak256(abi.encodePacked(proof[i], computedHash));
            } else { // LEFT
                computedHash = keccak256(abi.encodePacked(computedHash, proof[i]));
            }
        }
        
        return computedHash == merkleRoot;
    }
    
    /// @notice verifyWithRawLeaf
    /// @param rawLeaf The raw leaf
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service is valid according to the Merkle proof
    function verifyWithRawLeaf(
        bytes32 rawLeaf,
        bytes32[] calldata proof,
        bool[] calldata directions
    ) public view returns (bool) {
        require(proof.length == directions.length, "Proof and directions length mismatch");
        
        // Apply the second hash
        bytes32 computedHash = keccak256(abi.encodePacked(rawLeaf));
        
        for (uint256 i = 0; i < proof.length; i++) {
            if (directions[i]) { // RIGHT
                computedHash = keccak256(abi.encodePacked(proof[i], computedHash));
            } else { // LEFT
                computedHash = keccak256(abi.encodePacked(computedHash, proof[i]));
            }
        }
        
        return computedHash == merkleRoot;
    }
}
