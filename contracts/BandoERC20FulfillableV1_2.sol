// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BandoERC20FulfillableV1_1 } from "./BandoERC20FulfillableV1_1.sol";
import { IBandoERC20FulfillableV1_2 } from "./IBandoERC20FulfillableV1_2.sol";
import { SwapLib, SwapData } from "./libraries/SwapLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20FulFillmentRecord } from "./FulfillmentTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BandoERC20FulfillableV1_2
/// @author g6s
/// @notice BandoERC20FulfillableV1_2 is a contract that extends BandoERC20FulfillableV1_1.
/// @dev Supports the ability to swap both releaseable pool and accumulated fees to stablecoins in a single transaction.
/// The swap is done using an off-chain generated Dex aggregator call.
/// The contract also allows the manager to whitelist Dex aggregator addresses.
/// @custom:bfp-version 1.2.0
contract BandoERC20FulfillableV1_2 is IBandoERC20FulfillableV1_2, BandoERC20FulfillableV1_1 {

    using Address for address;
    using SafeERC20 for IERC20;

    /// @notice InvalidCaller error message
    error InvalidCaller(address caller);

    /// @notice PoolsAndFeesSubtracted event
    event PoolsAndFeesSubtracted(uint256 serviceId, address token, uint256 amount, uint256 fees);

    /// @notice FulfillerPoolAndFeesWithdrawn event
    event FulfillerPoolAndFeesWithdrawn(address token, uint256 amount, uint256 fees, address beneficiary, address feesBeneficiary);

    /// @notice InsufficientBalance error message
    error InsufficientBalance(uint256 required, uint256 balance);

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
    /// - The fulfillment record must exist.
    /// 
    /// @param serviceId The service identifier.
    /// @param recordId The fulfillment record identifier.
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapPoolsToStable(
        uint256 serviceId,
        uint256 recordId,
        SwapData calldata swapData
    )
        external
        nonReentrant
        onlyManager
    {
        ERC20FulFillmentRecord memory fulfillmentRecord = record(recordId);
        SwapLib.swapERC20ToStable(
            _releaseablePools,
            _accumulatedFees,
            serviceId,
            swapData,
            fulfillmentRecord
        );
    }

    /// @dev Returns the releaseable pools for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    /// @return The releaseable pools.
    function getReleaseablePools(uint256 serviceId, address token) external view returns (uint256) {
        return _releaseablePools[serviceId][token];
    }

    /// @dev Subtracts the pools and fees for a given service.
    /// @dev Only the manager can call this.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    /// @param amount The amount to subtract.
    /// @param fees The fees to subtract.
    function subtractPoolsAndFees(uint256 serviceId, address token, uint256 amount, uint256 fees) external onlyManager {
        _subtractPoolsAndFees(serviceId, token, amount, fees);
        emit PoolsAndFeesSubtracted(serviceId, token, amount, fees);
    }

    /// @dev withdraws an amount to a beneficiary
    /// @dev Only the manager can call this.
    /// @param token The token address
    /// @param amount The amount to withdraw
    /// @param beneficiary The beneficiary address
    function withdrawFulfillerPoolAndFees(
        address token,
        uint256 amount,
        uint256 fees,
        address beneficiary,
        address feesBeneficiary
    )
        external
        onlyManager
        nonReentrant
    {
        _withdrawFulfillerPoolAndFees(token, amount, fees, beneficiary, feesBeneficiary);
        emit FulfillerPoolAndFeesWithdrawn(token, amount, fees, beneficiary, feesBeneficiary);
    }

    /// @dev Internal function to reset the releaseable pools and accumulated fees for a given service and token.
    /// @param serviceId The service identifier.
    /// @param token The token address.
    function _subtractPoolsAndFees(uint256 serviceId, address token, uint256 amount, uint256 fees) internal {
        _releaseablePools[serviceId][token] -= amount;
        _accumulatedFees[serviceId][token] -= fees;
    }

    /// @dev Internal function to withdraw the fulfiller's ERC20 pool and fees.
    /// @param token The token address.
    /// @param amount The amount to withdraw.
    /// @param beneficiary The beneficiary address.
    /// @param feesBeneficiary The fees beneficiary address.
    function _withdrawFulfillerPoolAndFees(
        address token,
        uint256 amount,
        uint256 fees,
        address beneficiary,
        address feesBeneficiary
    ) internal {
        if(token == address(0)) {
            revert InvalidAddress(address(0));
        }
        if (beneficiary == address(0) || feesBeneficiary == address(0)) {
            revert InvalidAddress(address(0));
        }
        // Check for non-zero transfer amounts
        if (amount > 0) {
            uint256 totalAmount = amount + fees;
            if (totalAmount > IERC20(token).balanceOf(address(this))) {
                revert InsufficientBalance(totalAmount, IERC20(token).balanceOf(address(this)));
            }
            IERC20(token).safeTransfer(beneficiary, amount);
        }
        if (fees > 0) {
            IERC20(token).safeTransfer(feesBeneficiary, fees);
        }
    }
}
