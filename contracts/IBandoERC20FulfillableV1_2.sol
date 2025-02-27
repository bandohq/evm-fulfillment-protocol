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
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        SwapData calldata swapData
    ) external;
}
