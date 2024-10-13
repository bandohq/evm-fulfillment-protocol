// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { FulFillmentRequest, ERC20FulFillmentRequest } from '../FulfillmentTypes.sol';
import { Service, IFulfillableRegistry } from '../periphery/registry/IFulfillableRegistry.sol';
import { FulfillableRegistry } from '../periphery/registry/FulfillableRegistry.sol';
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library FulfillmentRequestLib {
    using Address for address payable;
    using Math for uint256;

    error InsufficientAmount();
    error InvalidFiatAmount();
    error InvalidRef();
    error OverflowError();
    error AmountMismatch();

    function validateRequest(
        uint256 serviceID,
        FulFillmentRequest memory request,
        address fulfillableRegistry
    ) internal view returns (Service memory) {
        if (msg.value == 0) {
            revert InsufficientAmount();
        }
        if (request.fiatAmount == 0) {
            revert InvalidFiatAmount();
        }
        
        Service memory service = FulfillableRegistry(fulfillableRegistry).getService(serviceID);
        
        if (!FulfillableRegistry(fulfillableRegistry).isRefValid(serviceID, request.serviceRef)) {
            revert InvalidRef();
        }
        
        (bool success, uint256 total_amount) = request.weiAmount.tryAdd(service.feeAmount);
        if (!success) {
            revert OverflowError();
        }
        
        if (msg.value != total_amount) {
            revert AmountMismatch();
        }

        return service;
    }

    function validateRequest(
      uint256 serviceID,
      ERC20FulFillmentRequest memory request,
      address fulfillableRegistry
    ) internal view returns (Service memory) {
        if (msg.value == 0) {
            revert InsufficientAmount();
        }
        if (request.fiatAmount == 0) {
            revert InvalidFiatAmount();
        }
        
        Service memory service = FulfillableRegistry(fulfillableRegistry).getService(serviceID);
        
        if (!FulfillableRegistry(fulfillableRegistry).isRefValid(serviceID, request.serviceRef)) {
            revert InvalidRef();
        }
        
        (bool success, uint256 total_amount) = request.tokenAmount.tryAdd(service.feeAmount);
        if (!success) {
            revert OverflowError();
        }
        
        if (msg.value != total_amount) {
            revert AmountMismatch();
        }

        return service;
    }
}