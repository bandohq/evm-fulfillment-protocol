// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { FulFillmentResult } from "./FulfillmentTypes.sol";

import { SwapData } from "./libraries/SwapLib.sol";

/// @title IBandoFulfillableV1_2
/// @dev The Bando Fulfillment Manager interface for Native Currency V1.2
/// @dev Adds support for swapping pools to stablecoins using Dex aggregators
interface IBandoFulfillableV1_2 {

    /// @notice swapPoolsToStable
    /// @dev Swaps both releaseable pool and accumulated fees to stablecoins in a single transaction
    /// using an off-chain generated Dex aggregator call.
    ///
    /// Requirements:
    /// - Only the manager can call this.
    /// - A Dex aggregator address must be whitelisted.
    /// - The fromToken must have sufficient combined balance.
    ///
    /// @param serviceId The service identifier.
    /// @param recordId The fulfillment record identifier.
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        uint256 recordId,
        SwapData calldata swapData
    ) external;

    /// @notice beneficiaryWithdrawStable
    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the manager can withdraw the releaseable pool.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function beneficiaryWithdrawStable(
        uint256 serviceId,
        address token
    ) external;

    /// @notice withdrawAccumulatedFeesStable
    /// @dev Withdraws the accumulated fees for a given service ID.
    /// Only the manager can withdraw the accumulated fees.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function withdrawAccumulatedFeesStable(
        uint256 serviceId,
        address token
    ) external;

    /// @notice resetPoolsAndFees
    /// @dev Resets the releaseable pools and accumulated fees for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function resetPoolsAndFees(uint256 serviceId, address token) external;

    /// @notice withdrawFulfillerPoolAndFees
    /// @dev Withdraws the fulfiller's pool and fees.
    /// @param token The token address.
    /// @param amount The amount to withdraw.
    /// @param beneficiary The beneficiary address.
    /// @param feesBeneficiary The fees beneficiary address.
    function withdrawFulfillerPoolAndFees(address token, uint256 amount, uint256 fees, address beneficiary, address feesBeneficiary) external;
}
