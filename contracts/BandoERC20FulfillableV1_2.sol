// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoERC20FulfillableV1_1 } from "./BandoERC20FulfillableV1_1.sol";
import { IBandoERC20FulfillableV1_2 } from "./IBandoERC20FulfillableV1_2.sol";
import { SwapLib, SwapData } from "./libraries/SwapLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/// @title BandoERC20FulfillableV1_2
/// @author g6s
/// @notice BandoERC20FulfillableV1_2 is a contract that extends BandoERC20FulfillableV1_1.
/// @dev Supports the ability to swap both releaseable pool and accumulated fees to stablecoins in a single transaction.
/// The swap is done using an off-chain generated Dex aggregator call.
/// The contract also allows the manager to whitelist Dex aggregator addresses.
/// @custom:bfp-version 1.2.0
contract BandoERC20FulfillableV1_2 is IBandoERC20FulfillableV1_2, BandoERC20FulfillableV1_1 {

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
        SwapData calldata swapData
    )
        external
        nonReentrant
        onlyManager
    {
        SwapLib.swapERC20ToStable(
            _releaseablePools,
            _accumulatedFees,
            serviceId,
            swapData
        );
    }

    /// @dev Returns the releaseable pools for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    /// @return The releaseable pools.
    function getReleaseablePools(uint256 serviceId, address token) external view returns (uint256) {
        return _releaseablePools[serviceId][token];
    }
}
