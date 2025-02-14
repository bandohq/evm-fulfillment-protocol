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

        // Current releaseable & fees
        uint256 releaseableAmount = _releaseablePools[serviceId][swapData.fromToken];
        uint256 feesAmount = _accumulatedFees[serviceId][swapData.fromToken];
        uint256 totalAvailable = releaseableAmount + feesAmount;

        if (totalAvailable < swapData.amount) {
            revert InsufficientCombinedBalance(totalAvailable, swapData.amount);
        }

        // 1. Calculate how much to subtract from each pool proportionally
        //    Proportional share = (amount * shareOfPool) / totalAvailable.
        //    For example, half from the releaseable pool and half from the fees
        //    pool if they have equal sizes.
        uint256 subReleaseable = (swapData.amount * releaseableAmount) / totalAvailable;
        uint256 subFees = (swapData.amount * feesAmount) / totalAvailable;

        // 2. Handle potential rounding shortfall
        //    Because these divisions floor results, subReleaseable + subFees 
        //    can be less than swapData.amount by a small "leftover."
        uint256 totalSub = subReleaseable + subFees;
        if (totalSub < swapData.amount) {
            uint256 leftover = swapData.amount - totalSub;
            subReleaseable += leftover;
        }

        // 3. Subtract from both pools
        //    Because we did totalAvailable >= swapData.amount, these subtractions
        //    should not underflow.
        _releaseablePools[serviceId][swapData.fromToken] = releaseableAmount - subReleaseable;
        _accumulatedFees[serviceId][swapData.fromToken] = feesAmount - subFees;

        // 4. Approve and perform the aggregator call
        uint256 receivedStable = _callSwap(aggregator, swapData);

        // 5. Distribute the swapped 'toToken' proportionally back into
        //    _releaseablePools and _accumulatedFees, if needed.
        if (totalAvailable > 0) {
            (uint256 releaseableShare, uint256 feesShare) = _distributeStableAmounts(
                totalAvailable,
                swapData.amount,
                receivedStable
            );          
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

    function _callSwap(
        address aggregator,
        SwapData calldata swapData
    )
        internal 
        returns (uint256 receivedStable)
    {
        uint256 initialStableBalance = IERC20(swapData.toToken).balanceOf(address(this));
        IERC20(swapData.fromToken).safeIncreaseAllowance(aggregator, swapData.amount);
        (bool success, ) = aggregator.call(swapData.callData);
        if(!success) {
            revert AggregatorCallFailed();
        }
        IERC20(swapData.fromToken).safeDecreaseAllowance(aggregator, 0);
        uint256 finalStableBalance = IERC20(swapData.toToken).balanceOf(address(this));
        receivedStable = finalStableBalance - initialStableBalance;
    }

    function _distributeStableAmounts(
        uint256 totalAvailable,
        uint256 releaseableAmount,
        uint256 receivedStable
    )
        internal
        pure
        returns (uint256 releaseableShare, uint256 feesShare)
    {
        (, uint256 multResult) = receivedStable.tryMul(releaseableAmount);
        (, releaseableShare) = multResult.tryDiv(totalAvailable);
        (, feesShare) = receivedStable.trySub(releaseableShare);
    }
}
