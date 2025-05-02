// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { FulfillableRegistryV1_1 } from './FulfillableRegistryV1_1.sol';
import { Service } from './IFulfillableRegistry.sol';

/// @title FulfillableRegistryV1_2
/// @author g6s
/// @notice A registry for fulfillable services
/// @dev This contract extends FulfillableRegistryV1_1 and adds the ability to add service references
/// we perform a lazy service creation, meaning that the service is created only when a service reference is added
/// this allows us not to massively create service beforehand.
/// @dev This contract is upgradeable, Ownable, and uses UUPSUpgradeable
/// @custom:bfp-version 1.2
contract FulfillableRegistryV1_2 is FulfillableRegistryV1_1 {

    /// @notice Error for invalid service
    /// @param service The service that is invalid
    error InvalidService(Service service);

    /// @notice Adds a service reference and creates the service if it does not exist
    /// @param service The service
    /// @param ref The reference to the service
    /// @param fulfillmentFeeBasisPoints The fulfillment fee basis points
    function addServiceRefV2(
        Service memory service,
        string memory ref,
        uint16 fulfillmentFeeBasisPoints
    ) external ownerOrManager {
        //validate service
        if(service.serviceId <= 0 || service.fulfiller == address(0) || service.beneficiary == address(0)) {
            revert InvalidService(service);
        }
        if(fulfillmentFeeBasisPoints > MAX_FULFILLMENT_FEE_BASIS_POINTS || fulfillmentFeeBasisPoints < 0) {
            revert InvalidfeeAmountBasisPoints(fulfillmentFeeBasisPoints);
        }
        // Add service if it does not exist
        if(_serviceRegistry[service.serviceId].fulfiller == address(0)) {
            _serviceRegistry[service.serviceId] = service;
            _serviceFulfillmentFeeBasisPoints[service.serviceId] = fulfillmentFeeBasisPoints;
            _serviceCount++;
            emit ServiceAdded(service.serviceId, service.fulfiller);
        }
        // Add service reference
        uint256 refCount = _serviceRefCount[service.serviceId];
        _serviceRefs[service.serviceId][refCount] = ref;
        _serviceRefCount[service.serviceId]++;
        emit ServiceRefAdded(service.serviceId, ref);
    }
}
