// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { FulFillmentResult } from "./FulfillmentTypes.sol";

import { SwapNativeData } from "./libraries/SwapLib.sol";

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
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        SwapNativeData calldata swapData
    ) external payable;
}
