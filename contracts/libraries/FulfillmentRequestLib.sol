// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FulFillmentRequest, ERC20FulFillmentRequest } from '../FulfillmentTypes.sol';
import { Service, IFulfillableRegistry } from '../periphery/registry/IFulfillableRegistry.sol';
import { IERC20TokenRegistry } from "../periphery/registry/IERC20TokenRegistry.sol";
import { ERC20TokenRegistryV1 } from "../periphery/registry/ERC20TokenRegistryV1.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/// @title FulfillmentRequestLib
/// @author g6s
/// @notice FulfillmentRequestLib is a library that contains functions to validate fulfillment requests
/// @dev This contract is used by BandoRouterV1
library FulfillmentRequestLib {
    using Address for address payable;
    using Math for uint256;
    using Math for uint16;

    /// @notice InsufficientAmount error message
    /// It is thrown when the amount sent is zero
    error InsufficientAmount();

    /// @notice InvalidFiatAmount error message
    /// It is thrown when the fiat amount is zero
    error InvalidFiatAmount();

    /// @notice InvalidRef error message
    /// It is thrown when the service reference is not in the registry
    error InvalidRef();

    /// @notice OverflowError error message
    /// It is thrown when an overflow occurs
    error OverflowError();

    /// @notice AmountMismatch error message
    /// It is thrown when the fee amount validations fail
    error AmountMismatch();

    /// @notice UnsupportedToken error message
    /// It is thrown when the token is not whitelisted
    /// @param token the token address
    error UnsupportedToken(address token);

    /// @notice validateRequest
    /// @dev It checks if the amount sent is greater than zero, if the fiat amount is greater than zero,
    /// @param serviceID the product/service ID
    /// @param request a valid FulFillmentRequest
    /// @param fulfillableRegistry the registry address
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
        
        (Service memory service, ) = IFulfillableRegistry(fulfillableRegistry).getService(serviceID);
        
        if (!IFulfillableRegistry(fulfillableRegistry).isRefValid(serviceID, request.serviceRef)) {
            revert InvalidRef();
        }

        return service;
    }

    /// @notice validateERC20Request
    /// @dev It checks if the token amount sent is greater than zero, if the fiat amount is greater than zero,
    /// if the service reference is valid and returns the service
    /// @dev We will change the way we handle fees so this validation is prone to change.
    /// @param serviceID the product/service ID
    /// @param request a valid FulFillmentRequest
    /// @param fulfillableRegistry the registry address
    /// @param tokenRegistry the token registry address
    function validateERC20Request(
      uint256 serviceID,
      ERC20FulFillmentRequest memory request,
      address fulfillableRegistry,
      address tokenRegistry
    ) internal view returns (Service memory) {
        if (request.tokenAmount == 0) {
            revert InsufficientAmount();
        }
        if (request.fiatAmount == 0) {
            revert InvalidFiatAmount();
        }
        
        if(!IERC20TokenRegistry(tokenRegistry).isTokenWhitelisted(request.token)) {
            revert UnsupportedToken(request.token);
        }
        
        (Service memory service, ) = IFulfillableRegistry(fulfillableRegistry).getService(serviceID);
        
        if (!IFulfillableRegistry(fulfillableRegistry).isRefValid(serviceID, request.serviceRef)) {
            revert InvalidRef();
        }

        return service;
    }

    /// @notice calculateFees: Gets service fee and swap fee (if any)
    /// and calculates the fee based on the configured fees.
    /// @dev Fees are represented in basis points to work with integers
    /// on fee percentages below 1%
    /// The fee is also rounded up to the nearest integer.
    /// This is to avoid rounding errors when calculating the total amount.
    /// And to avoid underpaying.
    /// totalFee = (amount * basisPoints + 9999) / 10000
    /// totalAmount = amount + serviceFee + swapFee
    /// @param fulfillableRegistry Service registry contract address
    /// @param tokenRegistry Token registry contract address
    /// @param serviceID Service/product ID
    /// @param tokenAddress Token address (zero address for native coin)
    /// @param amount The amount to calculate the fees for
    function calculateFees(
        address fulfillableRegistry,
        address tokenRegistry,
        uint256 serviceID,
        address tokenAddress,
        uint256 amount
    ) internal view returns (uint256 serviceFeeAmount) {
        (, uint16 feeBasisPoints) = IFulfillableRegistry(fulfillableRegistry).getService(serviceID);
        // Calculate the service fee in basis points based on the amount
        (, uint256 serviceFeeTemp) = amount.tryMul(feeBasisPoints);
        (, uint256 serviceFeeTemp2) = serviceFeeTemp.tryAdd(9999);
        (, serviceFeeAmount) = serviceFeeTemp2.tryDiv(10000);

        uint16 swapFeeBasisPoints = ERC20TokenRegistryV1(tokenRegistry)._swapFeeBasisPoints(tokenAddress);
        if(swapFeeBasisPoints > 0) {
            (, uint256 swapFeeTemp) = amount.tryMul(swapFeeBasisPoints);
            (, uint256 swapFeeTemp2) = swapFeeTemp.tryAdd(9999);
            (, uint256 swapFeeAmount) = swapFeeTemp2.tryDiv(10000);
            (, uint256 totalFee) = serviceFeeAmount.tryAdd(swapFeeAmount);
            serviceFeeAmount = totalFee;
        }
    }
}
