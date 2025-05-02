// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { FulfillableRegistryV1_1 } from "./FulfillableRegistryV1_1.sol";
import { MerkleProofLib } from "../../libraries/MerkleProofLib.sol";
import { Service } from "../registry/IFulfillableRegistry.sol";
import { IFulfillableRegistryV2 } from "./IFulfillableRegistryV2.sol";

/// @title FulfillableRegistryV2
/// @author g6s
/// @notice This contract extends FulfillableRegistryV1_1 with Merkle proof verification for services
/// @dev Implements per-fulfiller Merkle roots to efficiently manage large service catalogs
/// @custom:bfp-version 2.0
contract FulfillableRegistryV2 is FulfillableRegistryV1_1, IFulfillableRegistryV2 {
    
    /// @notice Mapping of fulfiller address to their service catalog Merkle root
    mapping(address => bytes32) public fulfillerMerkleRoot;

    /// @notice Mapping of the fulfiller's curent tree version
    mapping(address => uint256) public fulfillerTreeVersion;
    
    /// @notice Event emitted when a fulfiller's Merkle root is updated
    /// @param fulfiller The address of the fulfiller
    /// @param merkleRoot The new Merkle root
    /// @param treeVersion The new tree version
    event FulfillerMerkleRootUpdated(address indexed fulfiller, bytes32 merkleRoot, uint256 treeVersion);
    
    /// @notice Error thrown when a Merkle proof verification fails
    error InvalidMerkleProof();
    
    /// @notice Error thrown when a fulfiller doesn't have a Merkle root set
    error NoMerkleRootForFulfiller(address fulfiller);
    
    /// @notice Sets the Merkle root for a fulfiller's service catalog
    /// @param fulfiller The address of the fulfiller
    /// @param merkleRoot The Merkle root of the fulfiller's service catalog
    /// @param treeVersion The tree version
    function setFulfillerMerkleRoot(address fulfiller, bytes32 merkleRoot, uint256 treeVersion) external onlyOwner {
        _setFulfillerMerkleRoot(fulfiller, merkleRoot, treeVersion);
    }

    /// @notice Sets the Merkle root for a fulfiller's service catalog
    /// @param fulfiller The address of the fulfiller
    /// @param merkleRoot The Merkle root of the fulfiller's service catalog
    /// @param treeVersion The tree version
    function _setFulfillerMerkleRoot(address fulfiller, bytes32 merkleRoot, uint256 treeVersion) internal {
        if(fulfiller == address(0)) {
            revert InvalidAddress(fulfiller);
        }
        
        fulfillerMerkleRoot[fulfiller] = merkleRoot;
        fulfillerTreeVersion[fulfiller] = treeVersion;
        emit FulfillerMerkleRootUpdated(fulfiller, merkleRoot, treeVersion);
    }
    
    /// @notice Verifies if a service is valid using a Merkle proof and sets the service
    /// @param service The service details
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service is valid according to the Merkle proof
    function verifyAndSetService(
        Service memory service,
        uint16 fulfillmentFeeBasisPoints,
        bytes32[] calldata proof,
        bool[] directions,
    ) external returns (bool isValid) {
        isValid = _verifyAndSetService(service, fulfillmentFeeBasisPoints, proof, directions);
    }

    /// @notice Verifies and sets a service
    /// @param service The service to verify and set
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service is valid according to the Merkle proof
    function _verifyAndSetService(
        Service memory service,
        uint16 fulfillmentFeeBasisPoints,
        bytes32[] calldata proof,
        bool[] directions,
    ) internal returns (bool isValid) {
        if(_serviceRegistry[service.serviceId].fulfiller != address(0)) {
            isValid = true;
        }
        if(fulfillmentFeeBasisPoints > MAX_FULFILLMENT_FEE_BASIS_POINTS || fulfillmentFeeBasisPoints < 0) {
            revert InvalidfeeAmountBasisPoints(fulfillmentFeeBasisPoints);
        }
        // Get the fulfiller's Merkle root
        bytes32 merkleRoot = fulfillerMerkleRoot[service.fulfiller];
        if (merkleRoot == bytes32(0)) {
            revert NoMerkleRootForFulfiller(service.fulfiller);
        }
        
        // Create leaf node from service data
        bytes32 leaf = keccak256(abi.encodePacked(
            service.serviceId,
            service.fulfiller,
            service.beneficiary,
            fulfillmentFeeBasisPoints
        ));
        
        // Verify the Merkle proof
        isValid = MerkleProofLib.verify(proof, merkleRoot, leaf);
        if (!isValid) {
            revert InvalidMerkleProof();
        }
        _serviceRegistry[service.serviceId] = service;
        _serviceFulfillmentFeeBasisPoints[service.serviceId] = fulfillmentFeeBasisPoints;
        _serviceCount++;
        emit ServiceAdded(service.serviceId, service.fulfiller);
    }

    /// @notice addServiceRefV2
    /// @dev Adds a reference to a service, 
    /// @dev allowing the owner to add references to services that are not in the registry yet.
    /// @param serviceId the service identifier
    /// @param ref the reference to the service
    function addServiceRefV2(uint256 serviceId, string memory ref) external onlyOwner {
        uint256 refCount = _serviceRefCount[serviceId];
        _serviceRefs[serviceId][refCount] = ref; // Store the reference at the current index
        _serviceRefCount[serviceId]++; // Increment the reference count
        emit ServiceRefAdded(serviceId, ref);
    }

}