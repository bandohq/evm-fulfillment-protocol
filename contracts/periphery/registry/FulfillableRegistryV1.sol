// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { IFulfillableRegistry, Service } from './IFulfillableRegistry.sol';

/// @title FulfillableRegistryV1
/// @author g6s
/// @notice A registry for fulfillable services
/// @dev This contract is upgradeable, Ownable, and uses UUPSUpgradeable
/// @custom:bfp-version 1.0.0
contract FulfillableRegistryV1 is IFulfillableRegistry, UUPSUpgradeable, OwnableUpgradeable {

    /// @notice The maximum fulfillment fee basis points
    uint16 public constant MAX_FULFILLMENT_FEE_BASIS_POINTS = 10000;

    /// @notice Mapping to store services by their ID
    mapping(uint256 => Service) public _serviceRegistry;

    /// @notice Mapping to store service references by service ID
    /// @dev serviceID => (index => reference)
    mapping(uint256 => mapping(uint256 => string)) public _serviceRefs;

    /// @notice Mapping to store fulfillment fees basis points by service ID
    /// @dev This fee represent the markup fee charged to the payer for the fulfillment
    /// @dev serviceID => fulfillmentFeeBasisPoints
    mapping(uint256 => uint16) public _serviceFulfillmentFeeBasisPoints;

    /// Mapping to store the count of references for each service
    /// @dev serviceID => reference count
    mapping(uint256 => uint256) public _serviceRefCount;

    /// @notice Mapping to store fulfillers and their associated services
    /// @dev fulfiller => (serviceId => exists)
    mapping(address => mapping(uint256 => bool)) public _fulfillerServices;

    /// @dev fulfiller => service count
    mapping(address => uint256) public _fulfillerServiceCount;

    /// @dev The total number of services
    uint256 public _serviceCount;

    /// @dev The manager address
    address public _manager;

    /// @notice Error for invalid fee amount percentage
    /// @param feeAmountBasisPoints The fee amount percentage that is invalid
    error InvalidfeeAmountBasisPoints(uint16 feeAmountBasisPoints);

    /// @notice Error for invalid addresses
    /// @param _address The address that is invalid
    error InvalidAddress(address _address);

    /// @notice Error for service already exists
    /// @param serviceID The service identifier
    error ServiceAlreadyExists(uint256 serviceID);

    /// @notice Error for service does not exist
    /// @param serviceID The service identifier
    error ServiceDoesNotExist(uint256 serviceID);

    /// @notice ServiceAdded event
    /// @param serviceID The service identifier
    event ServiceRemoved(uint256 serviceID);

    /// @notice ServiceAdded event
    /// @param serviceID The service identifier
    /// @param fulfiller The fulfiller address
    event ServiceAdded(uint256 serviceID, address indexed fulfiller);

    /// @notice ManagerUpdated event
    /// @param manager The address of the new manager
    event ManagerUpdated(address indexed manager);

    /// @notice ServiceRefAdded event
    /// @param serviceID The service identifier
    /// @param ref The reference to the service
    event ServiceRefAdded(uint256 serviceID, string ref);

    /// @notice ServiceFulfillmentFeeSet event
    /// @param serviceID The service identifier
    /// @param fulfillmentFeeBasisPoints The fulfillment fee basis points
    event ServiceFulfillmentFeeSet(uint256 serviceID, uint16 fulfillmentFeeBasisPoints);

    /// @notice ServiceBeneficiaryUpdated event
    /// @param serviceID The service identifier
    /// @param beneficiary The beneficiary address
    event ServiceBeneficiaryUpdated(uint256 serviceID, address beneficiary);

    /// @notice ServiceFulfillerUpdated event
    /// @param serviceID The service identifier
    /// @param fulfiller The fulfiller address
    event ServiceFulfillerUpdated(uint256 serviceID, address fulfiller);

    /// @notice FulfillerAdded event
    /// @param fulfiller The fulfiller address
    /// @param serviceID The service identifier
    event FulfillerAdded(address fulfiller, uint256 serviceID);

    modifier onlyManager() {
        if(msg.sender != _manager) {
            revert InvalidAddress(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    function initialize(address initialOwner) public virtual initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(initialOwner);
    }

    /// @dev UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Sets the protocol manager address.
     * @param manager_ The address of the protocol manager.
     */
    function setManager(address manager_) public onlyOwner {
        if(manager_ == address(0)) {
            revert InvalidAddress(manager_);
        }
        _manager = manager_;
        emit ManagerUpdated(manager_);
    }

    /**
     * addService
     * This method must only be called by the owner.
     * @param serviceId the service identifier
     * @param service the service info object
     * @param fulfillmentFeeBasisPoints the fulfillment fee basis points
     */
    function addService(
        uint256 serviceId,
        Service memory service,
        uint16 fulfillmentFeeBasisPoints
    ) external onlyManager returns (bool) {
        if(_serviceRegistry[serviceId].fulfiller != address(0)) {
            revert ServiceAlreadyExists(serviceId);
        }
        _serviceRegistry[serviceId] = service;
        _serviceFulfillmentFeeBasisPoints[serviceId] = fulfillmentFeeBasisPoints;
        _serviceCount++;
        emit ServiceAdded(serviceId, service.fulfiller);
        return true;
    }

    /**
     * @notice updateServiceBeneficiary
     * @dev Updates the beneficiary of a service.
     * @param serviceId the service identifier
     * @param newBeneficiary the new beneficiary address
     */
    function updateServiceBeneficiary(uint256 serviceId, address payable newBeneficiary) external onlyOwner {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _serviceRegistry[serviceId].beneficiary = newBeneficiary;
        emit ServiceBeneficiaryUpdated(serviceId, newBeneficiary);
    }

    /**
     * @notice updateServicefeeAmountBasisPoints
     * @dev Updates the fee amount percentage of a service.
     * @param serviceId the service identifier
     * @param newfeeAmountBasisPoints the new fee amount percentage
     */
    function updateServicefeeAmountBasisPoints(uint256 serviceId, uint16 newfeeAmountBasisPoints) external onlyOwner {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        if(newfeeAmountBasisPoints > MAX_FULFILLMENT_FEE_BASIS_POINTS || newfeeAmountBasisPoints < 0) {
            revert InvalidfeeAmountBasisPoints(newfeeAmountBasisPoints);
        }
        _serviceFulfillmentFeeBasisPoints[serviceId] = newfeeAmountBasisPoints;
        emit ServiceFulfillmentFeeSet(serviceId, newfeeAmountBasisPoints);
    }

    /**
     * @notice updateServiceFulfiller
     * @dev Updates the fulfiller of a service.
     * @param serviceId the service identifier
     * @param newFulfiller the new fulfiller address
     */
    function updateServiceFulfiller(uint256 serviceId, address newFulfiller) external onlyOwner {
        if(newFulfiller == address(0)) {
            revert InvalidAddress(newFulfiller);
        }
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _serviceRegistry[serviceId].fulfiller = newFulfiller;
        emit ServiceFulfillerUpdated(serviceId, newFulfiller);
    }

    /**
     * addFulfiller
     * @param fulfiller the address of the fulfiller
     */
    function addFulfiller(address fulfiller, uint256 serviceID) external onlyOwner {
        if(_fulfillerServices[fulfiller][serviceID]) {
            revert ServiceAlreadyExists(serviceID);
        }
        _fulfillerServices[fulfiller][serviceID] = true; // Associate the service ID with the fulfiller
        _fulfillerServiceCount[fulfiller]++; // Increment the service count for the fulfiller
        emit FulfillerAdded(fulfiller, serviceID);
    }

    /**
     * getService
     * @param serviceId the service identifier
     * @return the service info object and the fulfillment fee basis points
     */
    function getService(uint256 serviceId) external view returns (Service memory, uint16) {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        return (_serviceRegistry[serviceId], _serviceFulfillmentFeeBasisPoints[serviceId]);
    }

    /**
     * removeServiceAddress
     * @param serviceId the service identifier
     */
    function removeServiceAddress(uint256 serviceId) external onlyOwner {
        delete _serviceRegistry[serviceId];
        _serviceCount--;
        emit ServiceRemoved(serviceId);
    }

    /**
     * addServiceRef
     * 
     * @param serviceId the service identifier
     * @param ref the reference to the service
     */
    function addServiceRef(uint256 serviceId, string memory ref) external onlyManager {
        if(_serviceRegistry[serviceId].fulfiller == address(0)) {
            revert ServiceDoesNotExist(serviceId);
        }
        uint256 refCount = _serviceRefCount[serviceId];
        _serviceRefs[serviceId][refCount] = ref; // Store the reference at the current index
        _serviceRefCount[serviceId]++; // Increment the reference count
        emit ServiceRefAdded(serviceId, ref);
    }

    /**
     * @notice isRefValid
     * 
     * @param serviceId the service identifier
     * @param ref the reference to the service
     * @return true if the reference is valid
     */
    function isRefValid(uint256 serviceId, string memory ref) external view returns (bool) {
        uint256 refCount = _serviceRefCount[serviceId];
        for (uint256 i = 0; i < refCount; i++) {
            if (keccak256(abi.encodePacked(_serviceRefs[serviceId][i])) == keccak256(abi.encodePacked(ref))) {
                return true;
            }
        }
        return false;
    }

    // Function to check if a fulfiller can fulfill a service
    function canFulfillerFulfill(address fulfiller, uint256 serviceId) external view returns (bool) {
        return _fulfillerServices[fulfiller][serviceId];
    }
}
