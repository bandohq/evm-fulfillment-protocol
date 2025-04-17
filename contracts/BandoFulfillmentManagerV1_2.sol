// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "./BandoFulfillmentManagerV1_1.sol";
import { IBandoERC20FulfillableV1_2 } from "./IBandoERC20FulfillableV1_2.sol";
import { IBandoERC20FulfillableV1_1 } from "./IBandoERC20FulfillableV1_1.sol";
import { IBandoFulfillableV1_2 } from "./IBandoFulfillableV1_2.sol";
import { BandoFulfillableV1_2 } from "./BandoFulfillableV1_2.sol";
import { FulfillableRegistryV1_1 } from "./periphery/registry/FulfillableRegistryV1_1.sol";
import { SwapData } from "./libraries/SwapLib.sol";

/// @title BandoFulfillmentManagerV1_2
/// @author g6s
/// @notice The Bando Fulfillment Manager V1.2
/// @dev Adds support for swapping pools to stablecoins using Dex aggregators
/// @custom:bfp-version 1.2.0
contract BandoFulfillmentManagerV1_2 is BandoFulfillmentManagerV1_1 {

    /// @dev Dex aggregator contract addresses
    mapping (address => bool) internal _aggregators;

    /// @dev Fulfiller accumulated stablecoin releaseable pool per token
    mapping (address => mapping (address => uint256)) internal _fulfillerAccumulatedReleaseablePool;

    /// @dev Fulfiller accumulated stablecoin fees per token
    mapping (address => mapping (address => uint256)) internal _fulfillerAccumulatedFees;

    /// @dev Fulfiller accumulated stablecoin releaseable pool per token on the native contract
    mapping (address => mapping (address => uint256)) internal _fulfillerAccumulatedReleaseablePoolNative;

    /// @dev Fulfiller accumulated stablecoin fees per token on the native contract
    mapping (address => mapping (address => uint256)) internal _fulfillerAccumulatedFeesNative;

    /// @dev Error for insufficient balance
    error InsufficientBalance(uint256 requested, uint256 available);

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
        IBandoERC20FulfillableV1_2(_erc20_escrow).swapPoolsToStable(serviceID, result.id, swapData);
        _accumulateFulfillerReleaseablePoolAndFees(serviceID, swapData.toToken);
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
        IBandoFulfillable(_escrow).registerFulfillment(serviceID, result);
        IBandoFulfillableV1_2(_escrow).swapPoolsToStable(serviceID, result.id, swapData);
        _accumulateFulfillerReleaseablePoolAndFeesNative(serviceID, swapData.toToken);
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

    /// @dev Accumulates the releaseable pool and fees for a fulfiller and token
    /// @param serviceId The service identifier
    /// @param token The token address
    function _accumulateFulfillerReleaseablePoolAndFees(uint256 serviceId, address token) internal virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceId);
        uint256 releaseablePool = IBandoERC20FulfillableV1_2(_erc20_escrow).getReleaseablePools(serviceId, token);
        uint256 fees = IBandoERC20FulfillableV1_1(_erc20_escrow).getERC20FeesFor(token, serviceId);
        _fulfillerAccumulatedReleaseablePool[service.fulfiller][token] += releaseablePool;
        _fulfillerAccumulatedFees[service.fulfiller][token] += fees;
        // Subtract the pools and fees for the fulfiller after accumulating them
        IBandoERC20FulfillableV1_2(_erc20_escrow).subtractPoolsAndFees(serviceId, token, releaseablePool, fees);
    }
    
    /// @dev Accumulates the releaseable pool and fees for a fulfiller and token on the native contract
    /// @param serviceId The service identifier
    /// @param token The token address
    function _accumulateFulfillerReleaseablePoolAndFeesNative(uint256 serviceId, address token) internal virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceId);
        uint256 releaseablePool = BandoFulfillableV1_2(_escrow)._stableReleasePools(serviceId, token);
        uint256 fees = BandoFulfillableV1_2(_escrow)._stableAccumulatedFees(serviceId, token);
        _fulfillerAccumulatedReleaseablePoolNative[service.fulfiller][token] += releaseablePool;
        _fulfillerAccumulatedFeesNative[service.fulfiller][token] += fees;
        // Subtract the pools and fees for the fulfiller after accumulating them
        IBandoFulfillableV1_2(_escrow).subtractPoolsAndFees(serviceId, token, releaseablePool, fees);
    }

    /// @dev Withdraws the fulfiller's ERC20 pool and fees
    /// @dev Only the fulfiller can withdraw the releaseable pool and fees
    /// @param token The token address
    /// @param amount The amount to withdraw
    /// @param beneficiary The beneficiary address
    /// @param feesBeneficiary The fees beneficiary address
    function withdrawERC20FulfillerPoolAndFees(
        address token,
        uint256 amount,
        uint256 fees,
        address beneficiary,
        address feesBeneficiary
    )
        public
        virtual
    {
        if (token == address(0)) {
            revert InvalidAddress(token);
        }
        // Use serviceID 1 as a workaround to check if the fulfiller is valid
        bool isValidFulfiller = FulfillableRegistryV1_1(_serviceRegistry).canFulfillerFulfill(msg.sender, 1);
        if (!isValidFulfiller) {
            revert InvalidFulfiller(msg.sender);
        }
        if (amount > _fulfillerAccumulatedReleaseablePool[msg.sender][token]) {
            revert InsufficientBalance(amount, _fulfillerAccumulatedReleaseablePool[msg.sender][token]);
        }
        if (fees > _fulfillerAccumulatedFees[msg.sender][token]) {
            revert InsufficientBalance(fees, _fulfillerAccumulatedFees[msg.sender][token]);
        }
        _fulfillerAccumulatedReleaseablePool[msg.sender][token] -= amount;
        _fulfillerAccumulatedFees[msg.sender][token] -= fees;
        IBandoERC20FulfillableV1_2(_erc20_escrow).withdrawFulfillerPoolAndFees(token, amount, fees, beneficiary, feesBeneficiary);
    }

    /// @dev Withdraws the fulfiller's stablecoin pool and fees from the native contract
    /// @dev Only the fulfiller can withdraw the releaseable pool and fees
    /// @param token The token address
    /// @param amount The amount to withdraw
    /// @param beneficiary The beneficiary address
    /// @param feesBeneficiary The fees beneficiary address
    function withdrawFulfillerStablePoolAndFees(
        address token,
        uint256 amount,
        uint256 fees,
        address beneficiary,
        address feesBeneficiary
    ) public virtual {
        if (token == address(0)) {
            revert InvalidAddress(token);
        }
        // Use serviceID 1 as a workaround to check if the fulfiller is valid
        bool isValidFulfiller = FulfillableRegistryV1_1(_serviceRegistry).canFulfillerFulfill(msg.sender, 1);
        if (!isValidFulfiller) {
            revert InvalidFulfiller(msg.sender);
        }
        if (amount > _fulfillerAccumulatedReleaseablePoolNative[msg.sender][token]) {
            revert InsufficientBalance(amount, _fulfillerAccumulatedReleaseablePoolNative[msg.sender][token]);
        }
        if (fees > _fulfillerAccumulatedFeesNative[msg.sender][token]) {
            revert InsufficientBalance(fees, _fulfillerAccumulatedFeesNative[msg.sender][token]);
        }
        _fulfillerAccumulatedReleaseablePoolNative[msg.sender][token] -= amount;
        _fulfillerAccumulatedFeesNative[msg.sender][token] -= fees;
        IBandoFulfillableV1_2(_escrow).withdrawFulfillerPoolAndFees(token, amount, fees, beneficiary, feesBeneficiary);
    }

    /// @dev Returns the fulfiller's pool for a given token
    /// @param token The token address
    /// @return pool The fulfiller's pool
    function myPool(address token) public view returns (uint256 pool) {
        pool = _fulfillerAccumulatedReleaseablePool[msg.sender][token];
    }

    /// @dev Returns the fulfiller's fees for a given token
    /// @param token The token address
    /// @return fees The fulfiller's fees
    function myFees(address token) public view returns (uint256 fees) {
        fees = _fulfillerAccumulatedFees[msg.sender][token];
    }

    /// @dev Returns the fulfiller's pool for a given token on the native contract
    /// @param token The token address
    /// @return pool The fulfiller's pool
    function myPoolNative(address token) public view returns (uint256 pool) {
        pool = _fulfillerAccumulatedReleaseablePoolNative[msg.sender][token];
    }

    /// @dev Returns the fulfiller's fees for a given token on the native contract
    /// @param token The token address
    /// @return fees The fulfiller's fees
    function myFeesNative(address token) public view returns (uint256 fees) {
        fees = _fulfillerAccumulatedFeesNative[msg.sender][token];
    }
    
}
