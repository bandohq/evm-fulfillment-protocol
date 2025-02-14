// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

library SwapLib {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Address for address;

    struct SwapData {
        address fromToken;
        address toToken;
        uint256 amount;
        uint256 minReturn;
        bytes callData;
    }

    /// @dev InvalidTokenAddress error message
    error InvalidTokenAddress();

    /// @dev InvalidSwapAmount error message
    error InvalidSwapAmount();

    /// @dev AggregatorCallFailed error message
    error AggregatorCallFailed();

    /// @dev InsufficientCombinedBalance error message
    /// @param totalAvailable Total available amount
    /// @param amount Required amount
    error InsufficientCombinedBalance(uint256 totalAvailable, uint256 amount);

    /// @notice PoolsSwappedToStable event
    /// @param serviceId Service identifier
    /// @param aggregator Dex (or other aggregator) contract address
    /// @param fromToken From token address
    /// @param toToken To token address
    /// @param releaseableAmount Releaseable amount
    /// @param feesAmount Fees amount
    /// @param receivedStable Received stable amount
    event PoolsSwappedToStable(
        uint256 indexed serviceId,
        address indexed aggregator,
        address fromToken,
        address toToken,
        uint256 releaseableAmount,
        uint256 feesAmount,
        uint256 receivedStable
    );

    /// @dev Swaps ERC20 token pools to stablecoins in a single transaction
    /// Requirements:
    /// - The fromToken must have sufficient combined balance.
    /// 
    /// @param serviceId The service identifier.
    /// @param aggregator The Dex (or other aggregator) contract address.
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapERC20ToStable(
        mapping(uint256 => mapping(address => uint256)) storage _releaseablePools,
        mapping(uint256 => mapping(address => uint256)) storage _accumulatedFees,
        uint256 serviceId,
        address aggregator,
        SwapData calldata swapData
    )
        internal
    {
        if (swapData.fromToken == address(0) || swapData.toToken == address(0)) {
            revert InvalidTokenAddress();
        }
        if (swapData.amount == 0) {
            revert InvalidSwapAmount();
        }

        uint256 releaseableAmount = _releaseablePools[serviceId][swapData.fromToken];
        uint256 feesAmount = _accumulatedFees[serviceId][swapData.fromToken];
        (, uint256 totalAvailable) = releaseableAmount.tryAdd(feesAmount);
        if (totalAvailable < swapData.amount) {
            revert InsufficientCombinedBalance(totalAvailable, swapData.amount);
        }

        /// @dev Clear pools to prevent reentrancy exploits on reverts
        delete _releaseablePools[serviceId][swapData.fromToken];
        delete _accumulatedFees[serviceId][swapData.fromToken];

        IERC20(swapData.fromToken).safeIncreaseAllowance(aggregator, swapData.amount);

        (bool success, ) = aggregator.call(swapData.callData);
        if(!success) {
            revert AggregatorCallFailed();
        }

        IERC20(swapData.fromToken).safeDecreaseAllowance(aggregator, 0);

        uint256 receivedStable = IERC20(swapData.toToken).balanceOf(address(this));
        if (totalAvailable > 0) {
            (, uint256 multResult) = receivedStable.tryMul(releaseableAmount);
            (, uint256 releaseableShare) = multResult.tryDiv(totalAvailable);
            (, uint256 feesShare) = receivedStable.trySub(releaseableShare);            
            _releaseablePools[serviceId][swapData.toToken] += releaseableShare;
            _accumulatedFees[serviceId][swapData.toToken] += feesShare;
        }

        emit PoolsSwappedToStable(
            serviceId,
            aggregator,
            swapData.fromToken,
            swapData.toToken,
            releaseableAmount,
            feesAmount,
            receivedStable
        );
    }
}
