// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import {
    ERC20FulFillmentRequest,
    FulFillmentResult,
    ERC20FulFillmentRecord
} from "./FulfillmentTypes.sol";

import { SwapData } from "./libraries/SwapLib.sol";

/// @title IBandoERC20FulfillableV1_2
/// @dev The Bando Fulfillment Manager interface for ERC20 tokens V1.2
/// @dev Adds support for swapping pools to stablecoins using Dex aggregators
interface IBandoERC20FulfillableV1_2 {

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

    /// @notice getReleaseablePools
    /// @dev Returns the releaseable pools for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    /// @return The releaseable pools.
    function getReleaseablePools(uint256 serviceId, address token) external view returns (uint256);

    /// @notice resetPoolsAndFees
    /// @dev Resets the releaseable pools and accumulated fees for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function resetPoolsAndFees(uint256 serviceId, address token) external;

    /// @notice withdrawFulfillerPoolAndFees
    /// @dev Withdraws the fulfiller's ERC20 pool and fees.
    /// @param token The token address.
    /// @param amount The amount to withdraw.
    /// @param beneficiary The beneficiary address.
    /// @param feesBeneficiary The fees beneficiary address.
    function withdrawFulfillerPoolAndFees(address token, uint256 amount, uint256 fees, address beneficiary, address feesBeneficiary) external;

}
