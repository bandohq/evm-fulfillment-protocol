// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import {
    ERC20FulFillmentRequest,
    FulFillmentResult,
    ERC20FulFillmentRecord
} from "./FulfillmentTypes.sol";

/// @title IBandoERC20Fulfillable
/// @dev Interface for bando fulfillment protocol ERC20 support escrow.
/// This interface is intended to be implemented by any contract that wants to be a fulfillable.
/// It is the same as the BandoFulfillable interface but for ERC20 transfers.
/// A fulfillable is a contract that can accept fulfillments from a router.
/// The router will route fulfillments to the fulfillable based on the serviceID.
interface IBandoERC20Fulfillable {
    /// @notice Deposits ERC20 tokens for a service request
    /// @param serviceID The ID of the service
    /// @param request The ERC20 fulfillment request details
    function depositERC20(uint256 serviceID, ERC20FulFillmentRequest memory request, uint256 feeAmount) external;

    /// @notice Registers a fulfillment for a service
    /// @param serviceID The ID of the service
    /// @param fulfillment The fulfillment result
    /// @return bool Indicating if the registration was successful
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) external returns (bool);

    /// @notice Retrieves the record IDs for a payer
    /// @param payer The address of the payer
    /// @return An array of record IDs
    function recordsOf(address payer) external view returns (uint256[] memory);

    /// @notice Retrieves a specific ERC20 fulfillment record
    /// @param id The ID of the record
    /// @return The ERC20 fulfillment record
    function record(uint256 id) external view returns (ERC20FulFillmentRecord memory);

    /// @notice Withdraws an ERC20 refund for a service
    /// @param serviceID The ID of the service
    /// @param token The address of the ERC20 token
    /// @param refundee The address to receive the refund
    /// @return bool Indicating if the withdrawal was successful
    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) external returns (bool);

    /// @notice Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// @param serviceID The service identifier
    /// @param token The address of the ERC20 token
    function beneficiaryWithdraw(uint256 serviceID, address token) external;

    /// @notice Withdraws the accumulated fees for a service
    /// @param serviceID The service identifier
    /// @param token The address of the ERC20 token
    function withdrawAccumulatedFees(uint256 serviceID, address token) external;
}
