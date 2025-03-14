// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { FulfillableRegistryV1 } from "./FulfillableRegistryV1.sol";

/// @title FulfillableRegistryV1_1
/// @author g6s
/// @notice This contract extends the FulfillableRegistryV1 contract with additional functionality.
/// @dev It allows to update the beneficiary and the fulfiller of a service.
/// @dev It also allows to update the fulfillment fee basis points of a service.
/// @dev It also allows to withdraw the accumulated fees of a service.
/// @custom:bfp-version 1.1
contract FulfillableRegistryV1_1 is FulfillableRegistryV1 {

    /// @notice InvalidCaller error message
    error InvalidCaller(address caller);

    /// @notice ownerOrManager modifier
    /// @dev It restricts the access to the owner or the manager
    modifier ownerOrManager() {
        if (msg.sender != owner() && msg.sender != _manager) {
            revert InvalidCaller(msg.sender);
        }
        _;
    }

    /// @notice updateServiceBeneficiaryV1_1
    /// @dev Updates the beneficiary of a service.
    /// @param serviceId the service identifier
    /// @param newBeneficiary the new beneficiary address
    function updateServiceBeneficiaryV1_1(uint256 serviceId, address payable newBeneficiary) external ownerOrManager {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _serviceRegistry[serviceId].beneficiary = newBeneficiary;
        emit ServiceBeneficiaryUpdated(serviceId, newBeneficiary);
    }

    /// @notice updateServicefeeAmountBasisPointsV1_1
    /// @dev Updates the fee amount percentage of a service.
    /// @param serviceId the service identifier
    /// @param newfeeAmountBasisPoints the new fee amount percentage
    function updateServicefeeAmountBasisPointsV1_1(uint256 serviceId, uint16 newfeeAmountBasisPoints) external ownerOrManager {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        if(newfeeAmountBasisPoints > MAX_FULFILLMENT_FEE_BASIS_POINTS || newfeeAmountBasisPoints < 0) {
            revert InvalidfeeAmountBasisPoints(newfeeAmountBasisPoints);
        }
        _serviceFulfillmentFeeBasisPoints[serviceId] = newfeeAmountBasisPoints;
        emit ServiceFulfillmentFeeSet(serviceId, newfeeAmountBasisPoints);
    }

    /// @notice updateServiceFulfillerV1_1
    /// @dev Updates the fulfiller of a service.
    /// @param serviceId the service identifier
    /// @param newFulfiller the new fulfiller address
    function updateServiceFulfillerV1_1(uint256 serviceId, address newFulfiller) external ownerOrManager {
        if(newFulfiller == address(0)) {
            revert InvalidAddress(newFulfiller);
        }
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _serviceRegistry[serviceId].fulfiller = newFulfiller;
        emit ServiceFulfillerUpdated(serviceId, newFulfiller);
    }
   
}
