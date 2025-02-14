// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "./BandoFulfillmentManagerV1.sol";
import { IBandoERC20FulfillableV1_2 } from "./IBandoERC20FulfillableV1_2.sol";
import { SwapData } from "./libraries/SwapLib.sol";

/// @title BandoFulfillmentManagerV1_2
/// @author g6s
/// @notice The Bando Fulfillment Manager V1.2
/// @dev Adds support for swapping pools to stablecoins using Dex aggregators
/// @custom:bfp-version 1.2.0
contract BandoFulfillmentManagerV1_2 is BandoFulfillmentManagerV1 {

    /// @dev Emitted when the caller is not the fulfiller
    /// @param status The FulFillmentResultState
    error InvalidFulfillmentResult(FulFillmentResultState status);

    /// @dev Adds a Dex aggregator address to the whitelist
    /// @param aggregator The Dex aggregator contract address
    function addAggregator(address aggregator) public onlyOwner {
        IBandoERC20FulfillableV1_2(_erc20_escrow).addAggregator(aggregator);
    }

    /// @dev Registers a fulfillment result and swaps
    /// both releaseable pool and accumulated fees to stablecoins in a single transaction.
    /// The swap is done using an off-chain generated Dex aggregator call.
    /// @param serviceID The service identifier.
    /// @param result The FulFillmentResult
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function fulfillERC20AndSwap(
        uint256 serviceID,
        FulFillmentResult memory result,
        SwapData memory swapData
    ) public onlyOwner {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller && msg.sender != owner()) {
            revert InvalidFulfiller(msg.sender);
        }
        if(result.status != FulFillmentResultState.SUCCESS) {
            revert InvalidFulfillmentResult(result.status);
        }
        IBandoERC20Fulfillable(_erc20_escrow).registerFulfillment(serviceID, result);
        IBandoERC20FulfillableV1_2(_erc20_escrow).swapPoolsToStable(serviceID, swapData);
    }
}
