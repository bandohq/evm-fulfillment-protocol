// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

/**
 * Service definition
 */
struct Service {
    uint256 serviceId;
    address payable beneficiary;
    address fulfiller;
}

/// @title IFulfillableRegistry
/// @dev Interface for FulfillableRegistry
/// This interface is intended to be implemented by any contract that wants to be a fulfillable registry.
/// The FulfillableRegistry contract is a contract that can store the address of the contract that implements the fulfillable service.
/// The address can be retrieved by the serviceId.
/// 
/// The FulfillableRegistry contract is upgradeable.
/// The FulfillableRegistry contract is Ownable.
/// The FulfillableRegistry contract uses UUPSUpgradeable.
interface IFulfillableRegistry {

    /// @notice Adds a new service to the registry.
    /// @param serviceId The unique identifier for the service.
    /// @param service The service details.
    /// @return Returns true if the service is successfully added.
    function addService(uint256 serviceId, Service memory service, uint16 fulfillmentFeePercentage) external returns (bool);

    /// @notice Registers a new fulfiller for a service.
    /// @param fulfiller The address of the fulfiller.
    /// @param serviceID The service identifier.
    function addFulfiller(address fulfiller, uint256 serviceID) external;

    /// @notice Retrieves the service details by its identifier.
    /// @param serviceId The service identifier.
    /// @return The service details.
    function getService(uint256 serviceId) external view returns (Service memory, uint16);

    /// @notice Removes a service from the registry.
    /// @param serviceId The service identifier.
    function removeServiceAddress(uint256 serviceId) external;

    /// @notice Adds a reference to a service.
    /// @param serviceId The service identifier.
    /// @param serviceRef The reference to the service.
    function addServiceRef(uint256 serviceId, string memory serviceRef) external;

    /// @notice Checks if a service reference is valid.
    /// @param serviceId The service identifier.
    /// @param serviceRef The reference to check.
    /// @return Returns true if the reference is valid.
    function isRefValid(uint256 serviceId, string memory serviceRef) external view returns (bool);

      /**
     * @notice updateServiceBeneficiary
     * @dev Updates the beneficiary of a service.
     * @param serviceId the service identifier
     * @param newBeneficiary the new beneficiary address
     */
    function updateServiceBeneficiary(uint256 serviceId, address payable newBeneficiary) external;

    /**
     * @notice updateServicefeeAmountBasisPoints
     * @dev Updates the fee amount percentage of a service.
     * @param serviceId the service identifier
     * @param newfeeAmountBasisPoints the new fee amount percentage
     */
    function updateServicefeeAmountBasisPoints(uint256 serviceId, uint16 newfeeAmountBasisPoints) external;

    /**
     * @notice updateServiceFulfiller
     * @dev Updates the fulfiller of a service.
     * @param serviceId the service identifier
     * @param newFulfiller the new fulfiller address
     */
    function updateServiceFulfiller(uint256 serviceId, address newFulfiller) external;
}
