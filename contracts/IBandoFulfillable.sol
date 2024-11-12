// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import {
    FulFillmentRequest,
    FulFillmentResult,
    FulFillmentRecord
} from "./FulfillmentTypes.sol";

/// @title IBandoFulfillable
/// @dev Interface for bando fulfillment protocol escrow.
/// This interface is intended to be implemented by any contract that wants to be a fulfillable.
/// A fulfillable is a contract that can accept fulfillments from a router.
/// The router will route fulfillments to the fulfillable based on the serviceID.
interface IBandoFulfillable {
    /// @notice Deposits funds for a service request
    /// @param serviceID The ID of the service
    /// @param request The fulfillment request details
    function deposit(
        uint256 serviceID,
        FulFillmentRequest memory request
    ) external payable;

    /// @notice Registers a fulfillment for a service
    /// @param serviceID The ID of the service
    /// @param fulfillment The fulfillment result
    /// @return bool Indicating if the registration was successful
    function registerFulfillment(
        uint256 serviceID,
        FulFillmentResult memory fulfillment
    ) external returns (bool);

    /// @notice Retrieves the record IDs for a payer
    /// @param payer The address of the payer
    /// @return An array of record IDs
    function recordsOf(address payer) external view returns (uint256[] memory);

    /// @notice Retrieves a specific fulfillment record
    /// @param id The ID of the record
    /// @return The fulfillment record
    function record(uint256 id) external view returns (FulFillmentRecord memory);

    /// @notice Withdraws a refund for a service
    /// @param serviceID The ID of the service
    /// @param refundee The address to receive the refund
    /// @return bool Indicating if the withdrawal was successful
    function withdrawRefund(
        uint256 serviceID,
        address payable refundee
    ) external returns (bool);

    /// @notice Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// @param serviceID The service identifier
    function beneficiaryWithdraw(uint256 serviceID) external;
}
