// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoRouterV1_1 } from './BandoRouterV1_1.sol';
import { FulFillmentRequest, ERC20FulFillmentRequest } from '../FulfillmentTypes.sol';
import { Service } from '../periphery/registry/IFulfillableRegistry.sol';
import { IFulfillableRegistryV2 } from '../periphery/registry/IFulfillableRegistryV2.sol';

/// @title BandoRouterV1_2
/// @author g6s
/// @notice A router for Bando
/// @dev This contract is upgradeable, Ownable, and uses UUPSUpgradeable
/// @custom:bfp-version 1.2
contract BandoRouterV1_2 is BandoRouterV1_1 {

    /// @notice Error thrown when a service is invalid
    error InvalidService();

    /// @notice Requests a service using a Merkle proof
    /// @param request The fulfillment request
    /// @param service The service to request
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service was requested successfully
    function requestServiceWithProof(
      FulFillmentRequest memory request,
      Service memory service,
      uint16 fulfillmentFeeBasisPoints,
      bytes32[] calldata proof,
      bool[] calldata directions
    ) external returns (bool requested) {
        requested = _requestServiceWithProof(request, service, fulfillmentFeeBasisPoints, proof, directions);
    }

    /// @notice Requests a service using a Merkle proof
    /// @param request The fulfillment request
    /// @param service The service to request
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service was requested successfully
    function _requestServiceWithProof(
      FulFillmentRequest memory request,
      Service memory service,
      uint16 fulfillmentFeeBasisPoints,
      bytes32[] calldata proof,
      bool[] calldata directions
    ) internal returns (bool requested) {
        bool isValid = IFulfillableRegistryV2(request.registry).verifyAndSetService(service, fulfillmentFeeBasisPoints, proof, directions);
        if(!isValid) {
            revert InvalidService()
        }
        requested = requestService(service.serviceId, request);
    }

    /// @notice Requests a ERC20 service using a Merkle proof
    /// @param request The fulfillment request
    /// @param service The service to request
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service was requested successfully
    function requestERC20ServiceWithProof(
      ERC20FulFillmentRequest memory request,
      Service memory service,
      uint16 fulfillmentFeeBasisPoints,
      bytes32[] calldata proof,
      bool[] calldata directions
    ) external returns (bool requested) {
        requested = _requestERC20ServiceWithProof(request, service, fulfillmentFeeBasisPoints, proof, directions);
    }

    /// @notice Requests a ERC20 service using a Merkle proof
    /// @param request The fulfillment request
    /// @param service The service to request
    /// @param fulfillmentFeeBasisPoints The fulfillment fee in basis points
    /// @param proof The Merkle proof
    /// @param directions The directions of the proof
    /// @return True if the service was requested successfully
    function _requestERC20ServiceWithProof(
      ERC20FulFillmentRequest memory request,
      Service memory service,
      uint16 fulfillmentFeeBasisPoints,
      bytes32[] calldata proof,
      bool[] calldata directions
    ) internal returns (bool requested) {
        bool isValid = IFulfillableRegistryV2(request.registry).verifyAndSetService(service, fulfillmentFeeBasisPoints, proof, directions);
        if(!isValid) {
            revert InvalidService()
        }
        requested = requestERC20Service(service.serviceId, request);
    }
}
