// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoFulfillableV1 } from "./BandoFulfillableV1.sol";
import { IBandoFulfillableV1_2 } from "./IBandoFulfillableV1_2.sol";
import { SwapNativeLib, SwapNativeData } from "./libraries/SwapLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/// @title BandoFulfillableV1_2
/// @author g6s
/// @notice BandoFulfillableV1_2 is a contract that extends BandoFulfillableV1.
/// @dev Supports the ability to swap both releaseable pool and accumulated fees to stablecoins in a single transaction.
/// The swap is done using an off-chain generated Dex aggregator call.
/// The contract also allows the manager to whitelist Dex aggregator addresses.
/// @custom:bfp-version 1.2.0
contract BandoFulfillableV1_2 is IBandoFulfillableV1_2, BandoFulfillableV1 {

    mapping(uint256 => mapping(address => uint256)) internal _stableReleasePools;

    mapping(uint256 => mapping(address => uint256)) internal _stableAccumulatedFees;

    /// @notice InvalidCaller error message
    error InvalidCaller(address caller);

    ///@dev Only the manager can call this
    modifier onlyManager() {
        if(msg.sender != _manager) {
            revert InvalidCaller(msg.sender);
        }
        _;
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
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        SwapNativeData calldata swapData
    )
        external
        nonReentrant
        onlyManager
    {
        SwapNativeLib.swapNativeToStable(
            _stableReleasePools,
            _stableAccumulatedFees,
            _releaseablePool,
            _accumulatedFees,
            serviceId,
            swapData
        );
    }
}
