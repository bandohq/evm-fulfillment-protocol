// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBandoERC20Fulfillable } from "./IBandoERC20Fulfillable.sol";
import { IBandoFulfillable } from "./IBandoFulfillable.sol";
import { FulFillmentRequest, ERC20FulFillmentRequest } from "./FulfillmentTypes.sol";
import { FulfillmentRequestLib } from "./libraries/FulfillmentRequestLib.sol";

/// @title BandoRouterV1
/// @author g6s
/// @custom:bfp-version 1.0.0
/// @notice This contract is the main entry point for users to request services from the Bando protocol.
/// @notice Considerations:
/// The router contract is intended to handle methods to deposit to the escrow cotract to request a service
/// For fulfillments being requested for payment with an ERC20 compliant token,
/// the router will call the depositERC20 method on the ERC20 escrow contract.
/// - The contract is Ownable, Pausable, UUPSUpgradeable, and ReentrancyGuardUpgradeable.
/// - The owner of the contract can set the fulfillable registry, token registry, escrow, and ERC20 escrow addresses.
/// - The owner of the contract is the protocol operator.
/// - The contract is intended to be user-facing.
/// - The contract will validate the request and transfer the payment to the fulfillable contract.
/// - The contract will emit events for each service requested.
/// - The contract will emit an event if the validation of the request fails.
/// - The contract can be paused by the owner.
contract BandoRouterV1 is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable {

    using Address for address payable;
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public _fulfillableRegistry;
    address public _tokenRegistry;
    address payable public _escrow;
    address payable public _erc20Escrow;

    /// @notice Emitted when an ERC20 service is requested
    /// @param serviceID The ID of the requested service
    /// @param request The details of the ERC20 fulfillment request
    event ERC20ServiceRequested(uint256 serviceID, ERC20FulFillmentRequest request);

    /// @notice Emitted when a native token service is requested
    /// @param serviceID The ID of the requested service
    /// @param request The details of the fulfillment request
    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);

    /// @notice Emitted when the validation of a service reference fails
    /// @param serviceID The ID of the service for which validation failed
    /// @param serviceRef The service reference that failed validation
    event RefValidationFailed(uint256 serviceID, string serviceRef);

    /// @notice Initializes the contract
    /// @dev Sets up the contract with initial state, including Ownable, Pausable, UUPSUpgradeable, and ReentrancyGuard
    function initialize(address initialOwner) public virtual initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
    }

    /// @notice Pauses the contract
    /// @dev Can only be called by the contract owner
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Can only be called by the contract owner
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Required for UUPS upgrades, can only be called by the contract owner
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /// @notice Sets the address of the fulfillable registry
    /// @dev Can only be called by the contract owner
    /// @param fulfillableRegistry_ The new address for the fulfillable registry
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        require(fulfillableRegistry_ != address(0), "Fulfillable registry cannot be the zero address");
        _fulfillableRegistry = fulfillableRegistry_;
    }

    /// @notice Sets the address of the token registry
    /// @dev Can only be called by the contract owner
    /// @param tokenRegistry_ The new address for the token registry
    function setTokenRegistry(address tokenRegistry_) public onlyOwner {
        require(tokenRegistry_ != address(0), "Token registry cannot be the zero address");
        _tokenRegistry = tokenRegistry_;
    }

    /// @notice Sets the address of the escrow contract
    /// @dev Can only be called by the contract owner
    /// @param escrow_ The new address for the escrow contract
    function setEscrow(address payable escrow_) public onlyOwner {
        require(escrow_ != address(0), "Escrow cannot be the zero address");
        _escrow = escrow_;
    }

    /// @notice Sets the address of the ERC20 escrow contract
    /// @dev Can only be called by the contract owner
    /// @param erc20Escrow_ The new address for the ERC20 escrow contract
    function setERC20Escrow(address payable erc20Escrow_) public onlyOwner {
        require(erc20Escrow_ != address(0), "ERC20 escrow cannot be the zero address");
        _erc20Escrow = erc20Escrow_;
    }

    /// @notice Requests an ERC20 service
    /// @dev Validates the request and transfers the payment to the ERC20 escrow contract
    /// @param serviceID The ID of the service being requested
    /// @param request The details of the ERC20 fulfillment request
    /// @return bool True if the amount was transferred to the escrow
    function requestERC20Service(
        uint256 serviceID, 
        ERC20FulFillmentRequest memory request
    ) public whenNotPaused nonReentrant returns (bool) {
        FulfillmentRequestLib.validateERC20Request(serviceID, request, _fulfillableRegistry, _tokenRegistry);
        uint256 pre_balance = IERC20(request.token).balanceOf(msg.sender);
        require(pre_balance >= request.tokenAmount, "BandoRouterV1: Insufficient balance");
        /// @dev Transfer the payment to the ERC20 escrow contract
        /// It is important to have msg.sender in the from field as a best security practice
        /// this is the reason this is done here and not in the escrow contract
        IERC20(request.token).safeTransferFrom(
            msg.sender,
            _erc20Escrow,
            request.tokenAmount
        );
        require(
            IERC20(request.token).balanceOf(msg.sender) <= pre_balance - request.tokenAmount,
            "BandoRouterV1: ERC20 invalid transfer return"
        );
        IBandoERC20Fulfillable(_erc20Escrow).depositERC20(serviceID, request);
        emit ERC20ServiceRequested(serviceID, request);
        return true;
    }

    /// @notice Requests a service using native tokens
    /// @dev Validates the request and transfers the payment to the escrow contract
    /// @param serviceID The ID of the service being requested
    /// @param request The details of the fulfillment request
    /// @return bool True if the amount was transferred to the escrow
    function requestService(
        uint256 serviceID,
        FulFillmentRequest memory request
    ) public payable whenNotPaused nonReentrant returns (bool) {
        FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        IBandoFulfillable(_escrow).deposit{value: request.weiAmount}(serviceID, request);
        emit ServiceRequested(serviceID, request);
        return true;
    }
}
