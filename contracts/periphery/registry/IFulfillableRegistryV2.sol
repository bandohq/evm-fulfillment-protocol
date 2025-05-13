// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IFulfillableRegistry } from './IFulfillableRegistry.sol';

/// @title IFulfillableRegistryV2
/// @dev Interface for FulfillableRegistryV2
/// This interface is intended to be implemented by any contract that wants to be a fulfillable registry.
/// The FulfillableRegistry contract is a contract that can store the address of the contract that implements the fulfillable service.
/// The address can be retrieved by the serviceId.
interface IFulfillableRegistryV2 is IFulfillableRegistry {

    /// @notice Sets the Merkle root for a fulfiller's service catalog
    /// @param fulfiller The address of the fulfiller
    /// @param merkleRoot The Merkle root of the fulfiller's service catalog
    /// @param treeVersion The tree version
    function setFulfillerMerkleRoot(address fulfiller, bytes32 merkleRoot, uint256 treeVersion) external;

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
    ) external returns (bool isValid);
}
