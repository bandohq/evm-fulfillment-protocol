// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoFulfillableV1_1 } from "./BandoFulfillableV1_1.sol";
import { IBandoFulfillableV1_2 } from "./IBandoFulfillableV1_2.sol";
import { SwapNativeLib, SwapNativeData } from "./libraries/SwapLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FulFillmentResult } from "./FulfillmentTypes.sol";
import { Service } from "./periphery/registry/IFulfillableRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BandoFulfillableV1_2
/// @author g6s
/// @notice BandoFulfillableV1_2 is a contract that extends BandoFulfillableV1_1.
/// @dev Supports the ability to swap both releaseable pool and accumulated fees to stablecoins in a single transaction.
/// The swap is done using an off-chain generated Dex aggregator call.
/// The contract also allows the manager to whitelist Dex aggregator addresses.
/// @custom:bfp-version 1.2.0
contract BandoFulfillableV1_2 is IBandoFulfillableV1_2, BandoFulfillableV1_1 {
    using Address for address;
    using SafeERC20 for IERC20;

    /// @notice The mapping of service IDs to their corresponding releaseable pools.
    /// @dev The key is the service ID, and the value is a mapping of token addresses to their corresponding releaseable pool amounts.
    mapping(uint256 => mapping(address => uint256)) public _stableReleasePools;

    /// @notice The mapping of service IDs to their corresponding accumulated fees.
    /// @dev The key is the service ID, and the value is a mapping of token addresses to their corresponding accumulated fees amounts.
    mapping(uint256 => mapping(address => uint256)) public _stableAccumulatedFees;

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

    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the manager can withdraw the releaseable pool.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function beneficiaryWithdrawStable(uint256 serviceId, address token) public onlyManager nonReentrant {
        _beneficiaryWithdrawStable(serviceId, token);
    }

    /// @dev Internal function to withdraw the beneficiary's available balance to release (fulfilled with success).
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function _beneficiaryWithdrawStable(uint256 serviceId, address token) internal {
        (Service memory service, ) = _registryContract.getService(serviceId);
        if(_stableReleasePools[serviceId][token] == 0) {
            revert NoBalanceToRelease();
        }
        uint256 amount = _stableReleasePools[serviceId][token];
        _stableReleasePools[serviceId][token] = 0;
        IERC20(token).safeTransfer(service.beneficiary, amount);
    }

    /// @dev Withdraws the accumulated fees for a given service ID.
    /// Only the manager can withdraw the accumulated fees.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function withdrawAccumulatedFeesStable(uint256 serviceId, address token) external onlyManager nonReentrant {
        _withdrawAccumulatedFeesStable(serviceId, token);
    }

    /// @dev Internal function to withdraw the accumulated fees for a given service ID.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function _withdrawAccumulatedFeesStable(uint256 serviceId, address token) internal {
        (Service memory service, ) = _registryContract.getService(serviceId);
        if(_stableAccumulatedFees[serviceId][token] == 0) {
            revert NoBalanceToRelease();
        }
        uint256 amount = _stableAccumulatedFees[serviceId][token];
        _stableAccumulatedFees[serviceId][token] = 0;
        IERC20(token).safeTransfer(service.beneficiary, amount);
    }
}
