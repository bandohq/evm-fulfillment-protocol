// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoERC20FulfillableV1_1 } from "./BandoERC20FulfillableV1_1.sol";
import { SwapLib } from "./libraries/SwapLib.sol";

/// @title BandoERC20FulfillableV1_2
/// @author g6s
/// @notice BandoERC20FulfillableV1_2 is a contract that extends BandoERC20FulfillableV1_1.
/// @dev Supports the ability to swap both releaseable pool and accumulated fees to stablecoins in a single transaction.
/// The swap is done using an off-chain generated Dex aggregator call.
/// The contract also allows the manager to whitelist Dex aggregator addresses.
/// @custom:bfp-version 1.2.0
contract BandoERC20FulfillableV1_2 is BandoERC20FulfillableV1_1 {

    /// @dev Dex aggregator contract addresses
    mapping (address => bool) internal _aggregators;

    /// @notice InvalidCaller error message
    error InvalidCaller(address caller);

    ///@dev Only the manager can call this
    modifier onlyManager() {
        if(msg.sender != _manager) {
            revert InvalidCaller(msg.sender);
        }
        _;
    }

    /// @dev Adds a Dex aggregator address to the whitelist
    /// @param aggregator The Dex aggregator contract address
    function addAggregator(address aggregator) external onlyManager {
        _aggregators[aggregator] = true;
    }
  
    /// @dev Swaps both releaseable pool and accumulated fees to stablecoins in a single transaction
    /// using an off-chain generated Dex aggregator call.
    /// 
    /// Requirements:
    /// - Only the manager can call this.
    /// - A Dex aggregator address must be whitelisted.
    /// - The fromToken must have sufficient combined balance.
    /// 
    /// @param serviceId The service identifier.
    /// @param aggregator The Dex (or other aggregator) contract address.
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        address aggregator,
        SwapLib.SwapData calldata swapData
    )
        external
        nonReentrant
        onlyManager
    {
        if(!_aggregators[aggregator]) {
            revert InvalidAddress(aggregator);
        }
        SwapLib.swapERC20ToStable(
            _releaseablePools,
            _accumulatedFees,
            serviceId,
            aggregator,
            swapData
        );
    }
}
