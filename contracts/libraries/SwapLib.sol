// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

struct SwapData {
    address fromToken;
    address toToken;
    uint256 amount;
    uint256 feeAmount;
    address callTo;
    bytes callData;
}

struct SwapNativeData {
    address toToken;
    uint256 amount;
    uint256 feeAmount;
    address payable callTo;
    bytes callData;
}

library SwapLib {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Address for address;

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
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapERC20ToStable(
        mapping(uint256 => mapping(address => uint256)) storage _releaseablePools,
        mapping(uint256 => mapping(address => uint256)) storage _accumulatedFees,
        uint256 serviceId,
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

        uint256 subReleaseable = swapData.amount - swapData.feeAmount;
        uint256 subFees = swapData.feeAmount;

        // Subtract from both pools
        // these subtractions should not underflow.
        _releaseablePools[serviceId][swapData.fromToken] = releaseableAmount - Math.min(releaseableAmount, subReleaseable);
        _accumulatedFees[serviceId][swapData.fromToken] = feesAmount - Math.min(feesAmount, subFees);

        // Approve and perform the aggregator call
        uint256 receivedStable = _callSwap(swapData.callTo, swapData);
        // Distribute the swapped 'toToken' proportionally back into
        // _releaseablePools and _accumulatedFees, if needed.
        (uint256 releaseableShare, uint256 feesShare) = _distributeStableAmounts(
            swapData.amount,
            subReleaseable,
            receivedStable
        );          
        _releaseablePools[serviceId][swapData.toToken] += releaseableShare;
        _accumulatedFees[serviceId][swapData.toToken] += feesShare;

        emit PoolsSwappedToStable(
            serviceId,
            swapData.callTo,
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

    /// @dev Distributes the stable amount proportionally between the releaseable and fees pools
    /// @notice This function is used to distribute the stable amount proportionally between the releaseable and fees pools
    /// @dev Calculation: (receivedStable * fromReleaseableAmount) / totalSwapAmount
    /// @dev Calculation: receivedStable - releaseableShare
    /// @dev eg: receivedStable = 2022, fromReleaseableAmount = 1000, totalSwapAmount = 1011
    /// @dev releaseableShare = (2022 * 1000) / 1011 = 2000
    /// @dev feesShare = 2022 - 2000 = 22
    /// @param totalSwapAmount The total amount of the swap
    /// @param fromReleaseableAmount The amount of the releaseable pool
    /// @param receivedStable The amount of stable received from the swap
    /// @return releaseableShare The amount of the releaseable pool to distribute
    /// @return feesShare The amount of the fees pool to distribute
    function _distributeStableAmounts(
        uint256 totalSwapAmount,
        uint256 fromReleaseableAmount,
        uint256 receivedStable
    )
        internal
        pure
        returns (uint256 releaseableShare, uint256 feesShare)
    {
        (, uint256 multResult) = receivedStable.tryMul(fromReleaseableAmount);
        (, releaseableShare) = multResult.tryDiv(totalSwapAmount);
        (, feesShare) = receivedStable.trySub(releaseableShare);
    }
}

library SwapNativeLib {
    using Math for uint256;
    using Address for address;

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
    /// @param toToken To token address
    /// @param releaseableAmount Releaseable amount
    /// @param feesAmount Fees amount
    /// @param receivedStable Received stable amount
    event PoolsSwappedToStable(
        uint256 indexed serviceId,
        address payable indexed aggregator,
        address toToken,
        uint256 releaseableAmount,
        uint256 feesAmount,
        uint256 receivedStable
    );

    /// @dev Swaps token pools to stablecoins in a single transaction
    /// Requirements:
    /// - The fromToken must have sufficient combined balance.
    /// 
    /// @param serviceId The service identifier.
    /// @param swapData The struct capturing the aggregator call data, tokens, and amounts.
    function swapNativeToStable(
        mapping(uint256 => mapping(address => uint256)) storage stablePool,
        mapping(uint256 => mapping(address => uint256)) storage stableFees,
        mapping (uint256 => uint256) storage _releaseablePool,
        mapping (uint256 => uint256) storage _accumulatedFees,
        uint256 serviceId,
        SwapNativeData calldata swapData
    )
        internal
    {
        if (swapData.toToken == address(0)) {
            revert InvalidTokenAddress();
        }
        if (swapData.amount == 0) {
            revert InvalidSwapAmount();
        }

        // Current releaseable & fees
        uint256 releaseableAmount = _releaseablePool[serviceId];
        uint256 feesAmount = _accumulatedFees[serviceId];
        uint256 totalAvailable = releaseableAmount + feesAmount;

        if (totalAvailable < swapData.amount) {
            revert InsufficientCombinedBalance(totalAvailable, swapData.amount);
        }   

        // Subtract amounts from both pools
        uint256 subReleaseable = swapData.amount - swapData.feeAmount;
        uint256 subFees = swapData.feeAmount;

        // Subtract from both pools
        // these subtractions should not underflow.
        _releaseablePool[serviceId] = releaseableAmount - Math.min(releaseableAmount, subReleaseable);
        _accumulatedFees[serviceId] = feesAmount - Math.min(feesAmount, subFees);

        // Approve and perform the aggregator call
        uint256 receivedStable = _callSwap(swapData.callTo, swapData);
        
        // Distribute the swapped 'toToken' proportionally back into
        //    _releaseablePools and _accumulatedFees, if needed.
        (uint256 releaseableShare, uint256 feesShare) = _distributeStableAmounts(
            swapData.amount,
            subReleaseable,
            receivedStable
        );

        stablePool[serviceId][swapData.toToken] += releaseableShare;
        stableFees[serviceId][swapData.toToken] += feesShare;

        emit PoolsSwappedToStable(
            serviceId,
            swapData.callTo,
            swapData.toToken,
            releaseableAmount,
            feesAmount,
            receivedStable
        );
    }

    function _callSwap(
        address payable aggregator,
        SwapNativeData calldata swapData
    )
        internal 
        returns (uint256 receivedStable)
    {
        uint256 initialStableBalance = IERC20(swapData.toToken).balanceOf(address(this));
        (bool success, ) = aggregator.call{value: swapData.amount}(swapData.callData);
        if(!success) {
            revert AggregatorCallFailed();
        }
        uint256 finalStableBalance = IERC20(swapData.toToken).balanceOf(address(this));
        receivedStable = finalStableBalance - initialStableBalance;
    }

    /// @dev Distributes the stable amount proportionally between the releaseable and fees pools
    /// @notice This function is used to distribute the stable amount proportionally between the releaseable and fees pools
    /// @dev Calculation: (receivedStable * fromReleaseableAmount) / totalSwapAmount
    /// @dev Calculation: receivedStable - releaseableShare
    /// @dev eg: receivedStable = 2022, fromReleaseableAmount = 1000, totalSwapAmount = 1011
    /// @dev releaseableShare = (2022 * 1000) / 1011 = 2000
    /// @param totalSwapAmount The total amount of the swap
    /// @param fromReleaseableAmount The amount of the releaseable pool
    /// @param receivedStable The amount of stable received from the swap
    /// @return releaseableShare The amount of the releaseable pool to distribute
    /// @return feesShare The amount of the fees pool to distribute
    function _distributeStableAmounts(
        uint256 totalSwapAmount,
        uint256 fromReleaseableAmount,
        uint256 receivedStable
    )
        internal
        pure
        returns (uint256 releaseableShare, uint256 feesShare)
    {
        (, uint256 multResult) = receivedStable.tryMul(fromReleaseableAmount);
        (, releaseableShare) = multResult.tryDiv(totalSwapAmount);
        (, feesShare) = receivedStable.trySub(releaseableShare);
    }
}
