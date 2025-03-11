// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "./BandoFulfillmentManagerV1_1.sol";
import { IBandoERC20FulfillableV1_2 } from "./IBandoERC20FulfillableV1_2.sol";
import { IBandoFulfillableV1_2 } from "./IBandoFulfillableV1_2.sol";
import { SwapNativeData, SwapData } from "./libraries/SwapLib.sol";

/// @title BandoFulfillmentManagerV1_2
/// @author g6s
/// @notice The Bando Fulfillment Manager V1.2
/// @dev Adds support for swapping pools to stablecoins using Dex aggregators
/// @custom:bfp-version 1.2.0
contract BandoFulfillmentManagerV1_2 is BandoFulfillmentManagerV1_1 {

    /// @dev Dex aggregator contract addresses
    mapping (address => bool) internal _aggregators;

    /// @dev Emitted when the caller is not the fulfiller
    /// @param status The FulFillmentResultState
    error InvalidFulfillmentResult(FulFillmentResultState status);

    /// @notice AggregatorAdded event
    /// @param aggregator Dex aggregator contract address
    event AggregatorAdded(address indexed aggregator);

    /// @dev Adds a Dex aggregator address to the whitelist
    /// @param aggregator The Dex aggregator contract address
    function addAggregator(address aggregator) external onlyOwner {
        if(aggregator == address(0)) {
            revert InvalidAddress(aggregator);
        }
        _aggregators[aggregator] = true;
        emit AggregatorAdded(aggregator);
    }

    /// @dev Checks if an address is a Dex aggregator
    /// @param aggregator The Dex aggregator contract address
    function isAggregator(address aggregator) external view returns (bool) {
        return _aggregators[aggregator];
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
    ) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller && msg.sender != owner()) {
            revert InvalidFulfiller(msg.sender);
        }
        if(result.status != FulFillmentResultState.SUCCESS) {
            revert InvalidFulfillmentResult(result.status);
        }
        if(!_aggregators[swapData.callTo]) {
            revert InvalidAddress(swapData.callTo);
        }
        IBandoERC20Fulfillable(_erc20_escrow).registerFulfillment(serviceID, result);
        IBandoERC20FulfillableV1_2(_erc20_escrow).swapPoolsToStable(serviceID, swapData);
        emit ERC20FulfillmentRegistered(serviceID, result);
    }

    /// @dev Registers a fulfillment result and swaps from native currency
    /// both releaseable pool and accumulated fees to stablecoins in a single transaction.
    /// The swap is done using an off-chain generated Dex aggregator call.
    /// @param serviceID The service identifier.
    /// @param result The FulFillmentResult
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function fulfillAndSwap(
        uint256 serviceID,
        FulFillmentResult memory result,
        SwapNativeData memory swapData
    ) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller && msg.sender != owner()) {
            revert InvalidFulfiller(msg.sender);
        }
        if(result.status != FulFillmentResultState.SUCCESS) {
            revert InvalidFulfillmentResult(result.status);
        }
        if(!_aggregators[swapData.callTo]) {
            revert InvalidAddress(swapData.callTo);
        }
        IBandoFulfillable(_escrow).registerFulfillment(serviceID, result);
        IBandoFulfillableV1_2(_escrow).swapPoolsToStable(serviceID, swapData);
        emit FulfillmentRegistered(serviceID, result);
    }

    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the fulfiller can withdraw the releaseable pool.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function beneficiaryWithdrawStable(uint256 serviceId, address token) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceId);
        if (msg.sender != service.fulfiller) {
            revert InvalidFulfiller(msg.sender);
        }
        IBandoFulfillableV1_2(_escrow).beneficiaryWithdrawStable(serviceId, token);
        emit WithdrawnToBeneficiary(serviceId, service.beneficiary);
    }

    /// @dev Withdraws the accumulated fees for a given service ID.
    /// Only the fulfiller can withdraw the accumulated fees.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function withdrawAccumulatedFeesStable(uint256 serviceId, address token) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceId);
        if (msg.sender != service.fulfiller) {
            revert InvalidFulfiller(msg.sender);
        }
        IBandoFulfillableV1_2(_escrow).withdrawAccumulatedFeesStable(serviceId, token);
        emit WithdrawnToBeneficiary(serviceId, service.beneficiary);
    }
}
