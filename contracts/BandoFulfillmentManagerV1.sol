// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { IFulfillableRegistry, Service } from './periphery/registry/IFulfillableRegistry.sol';
import { IBandoFulfillable } from './IBandoFulfillable.sol';
import { IBandoERC20Fulfillable } from './BandoERC20FulfillableV1.sol';
import { BandoFulfillableV1 } from './BandoFulfillableV1.sol';
import {
    ERC20FulFillmentRecord,
    ERC20FulFillmentRequest,
    FulFillmentResultState,
    FulFillmentResult
} from "./FulfillmentTypes.sol";

/// @title BandoFulfillmentManagerV1
/// @author g6s
/// @custom:bfp-version 1.0.0
/// @notice This contract manages services and fulfillables for the Bando protocol.
/// It inherits from OwnableUpgradeable and UUPSUpgradeable contracts.
/// 
/// OwnableUpgradeable provides basic access control functionality, 
/// where only the contract owner can perform certain actions.
/// 
/// UUPSUpgradeable enables the contract to be upgraded without 
/// losing its state, allowing for seamless upgrades of the 
/// contract's implementation logic.
/// 
/// The purpose of this contract is to interact with the FulfillableRegistry
/// and the BandoFulfillable contracts to perform the following actions:
/// 
/// - Set up a service escrow address.
/// - Register a fulfillment result for a service.
/// - Withdraw a refund from a service.
/// - Withdraw funds for a beneficiary in a releasable pool.
/// 
/// @dev The owner of the contract is the operator of the fulfillment protocol.
/// But the fulfillers are the only ones that can register a fulfillment result 
/// and withdraw a refund.
contract BandoFulfillmentManagerV1 is OwnableUpgradeable, UUPSUpgradeable {

    /// @notice service registry address
    address public _serviceRegistry;

    /// @notice escrow address
    address public _escrow;

    /// @notice ERC20 escrow address
    address public _erc20_escrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /// @dev UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @dev Sets the service registry address.
    /// @param serviceRegistry_ The address of the service registry.
    function setServiceRegistry(address serviceRegistry_) public onlyOwner {
        require(serviceRegistry_ != address(0), "Service registry cannot be the zero address");
        _serviceRegistry = serviceRegistry_;
    }

    /// @dev Sets the escrow address.
    /// @param escrow_ The address of the escrow.
    function setEscrow(address payable escrow_) public onlyOwner {
        require(escrow_ != address(0), "Escrow cannot be the zero address");
        _escrow = escrow_;
    }

    /// @dev Sets the ERC20 escrow address.
    /// @param erc20Escrow_ The address of the ERC20 escrow.
    function setERC20Escrow(address payable erc20Escrow_) public onlyOwner {
        require(erc20Escrow_ != address(0), "ERC20 escrow cannot be the zero address");
        _erc20_escrow = erc20Escrow_;
    }

    /// @dev setService
    /// @notice This method must only be called by an owner.
    /// It sets up a service escrow address and validator address.
    /// 
    /// The escrow is intended to be a valid Bando escrow contract
    /// 
    /// The validator address is intended to be a contract that validates the service's
    /// identifier. eg. phone number, bill number, etc.
    /// @param serviceID The service identifier
    /// @param feeAmountBasisPoints The fee amount percentage for the service
    /// @param fulfiller The address of the fulfiller
    /// @param beneficiary The address of the beneficiary
    /// @return Service memory The created service
    function setService(
        uint256 serviceID,
        uint16 feeAmountBasisPoints,
        address fulfiller,
        address payable beneficiary
    ) 
        public
        virtual
        onlyOwner 
        returns (Service memory)
    {
        require(serviceID > 0, "Service ID is invalid");
        require(fulfiller != address(0), "Fulfiller address is invalid");
        require(beneficiary != address(0), "Beneficiary address is invalid");
        Service memory service = Service({
            serviceId: serviceID,
            fulfiller: fulfiller,
            beneficiary: beneficiary
        });
        IFulfillableRegistry(_serviceRegistry).addService(serviceID, service, feeAmountBasisPoints);
        return service;
    }

    /// @dev setServiceRef
    /// @notice This method must only be called by the owner.
    /// It sets up a service reference for a service.
    /// @param serviceID The service identifier
    /// @param serviceRef The service reference
    function setServiceRef(uint256 serviceID, string memory serviceRef) public virtual onlyOwner {
        IFulfillableRegistry(_serviceRegistry).addServiceRef(serviceID, serviceRef);
    }

    /// @dev setServiceFulfillmentFeePercentage
    /// @notice This method must only be called by the owner.
    /// It sets up the fulfillment fee percentage for a service.
    /// @param serviceID The service identifier
    /// @param fulfillmentFeePercentage The fulfillment fee percentage
      function setServiceFulfillmentFee(uint256 serviceID, uint16 fulfillmentFeeBasisPoints) public virtual onlyOwner {
        IFulfillableRegistry(_serviceRegistry).updateServicefeeAmountBasisPoints(serviceID, fulfillmentFeePercentage);
    }

    /// @dev registerFulfillment
    /// @notice This method must only be called by the service fulfiller or the owner
    /// It registers a fulfillment result for a service calling the escrow contract.
    /// @param serviceID The service identifier
    /// @param fulfillment The fulfillment result
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        IBandoFulfillable(_escrow).registerFulfillment(serviceID, fulfillment);
    }

    /// @dev registerERC20Fulfillment
    /// @notice This method must only be called by the service fulfiller or the owner
    /// It registers a fulfillment result for a service calling the escrow contract.
    /// @param serviceID The service identifier
    /// @param fulfillment The fulfillment result
    function registerERC20Fulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can register a fulfillment");
        }
        IBandoERC20Fulfillable(_erc20_escrow).registerFulfillment(serviceID, fulfillment);
    }

    /// @dev beneficiaryWithdraw
    /// @notice This method must only be called by the service beneficiary.
    /// @param serviceID The service identifier
    function beneficiaryWithdraw(uint256 serviceID) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        require(service.beneficiary == msg.sender, "Only the beneficiary can withdraw");
        IBandoFulfillable(_escrow).beneficiaryWithdraw(serviceID);
    }

    /// @dev beneficiaryWithdrawERC20
    /// @notice This method must only be called by the service beneficiary.
    /// @param serviceID The service identifier
    /// @param token The address of the ERC20 token
    function beneficiaryWithdrawERC20(uint256 serviceID, address token) public virtual {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        require(service.beneficiary == msg.sender, "Only the beneficiary can withdraw");
        IBandoERC20Fulfillable(_erc20_escrow).beneficiaryWithdraw(serviceID, token);
    }

    /// @dev withdrawERC20Fees
    /// @notice This method must only be called by the owner.
    /// @param serviceID The service identifier
    /// @param token The address of the ERC20 token
    function withdrawERC20Fees(uint256 serviceID, address token) public virtual onlyOwner {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can register a fulfillment");
        }
        IBandoERC20Fulfillable(_erc20_escrow).withdrawAccumulatedFees(serviceID, token);
    }

    /// @dev withdrawNativeFees
    /// @notice This method must only be called by the owner.
    /// @param serviceID The service identifier
    function withdrawNativeFees(uint256 serviceID) public virtual onlyOwner {
        (Service memory service, ) = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can register a fulfillment");
        }
        IBandoFulfillable(_escrow).withdrawAccumulatedFees(serviceID);
    }
}
