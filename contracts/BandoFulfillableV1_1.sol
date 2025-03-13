// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IBandoFulfillableV1_1 } from "./IBandoFulfillableV1_1.sol";
import { FulfillmentRequestLib } from "./libraries/FulfillmentRequestLib.sol";
import { IFulfillableRegistry, Service } from "./periphery/registry/IFulfillableRegistry.sol";
import {
    FulFillmentRecord,
    FulFillmentRequest,
    FulFillmentResultState,
    FulFillmentResult
} from "./FulfillmentTypes.sol";

/// @title BandoFulfillableV1_1
/// @author g6s
/// @custom:bfp-version 1.1.0
/// @dev Inspired in: OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)
/// Base escrow contract, holds funds designated for a beneficiary until they
/// withdraw them or a refund is emitted.
///
/// @notice Intended usage: 
/// This contract (and derived escrow contracts) should only be
/// interacted through the router or manager contracts. 
/// The contract that uses the escrow as its payment method 
/// should provide public methods redirecting to the escrow's deposit and withdraw.
contract BandoFulfillableV1_1 is
    IBandoFulfillableV1_1,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable {
    using Address for address payable;
    using Math for uint256;

    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    /// @notice Event emitted when a deposit is received.
    /// @param record The fulfillment record.
    event DepositReceived(FulFillmentRecord record);

    /// @notice Event emitted when a refund is withdrawn.
    /// @param payee Refundee address
    /// @param weiAmount Wei amount to refund
    /// @param recordId The fulfillment record ID
    event RefundWithdrawn(address indexed payee, uint256 weiAmount, uint256 recordId);

    /// @notice Event emitted when a refund is authorized.
    /// @param payee Refundee address
    /// @param weiAmount Wei amount to refund
    event RefundAuthorized(address indexed payee, uint256 weiAmount);

    /// @notice Event emitted when a beneficiary withdraws funds.
    /// @param serviceID The service identifier
    /// @param amount The amount withdrawn
    event FeeUpdated(uint256 serviceID, uint256 amount);

    /// @notice Event emitted when fees are withdrawn.
    /// @param serviceId The service identifier
    /// @param beneficiary The beneficiary address
    /// @param amount The amount withdrawn
    event FeesWithdrawn(uint256 indexed serviceId, address beneficiary, uint256 amount);

    /// @notice Event emitted when the manager is updated.
    /// @param manager The address of the new manager.
    event ManagerUpdated(address indexed manager);

    /// @notice Event emitted when the router is updated.
    /// @param router The address of the new router.
    event RouterUpdated(address indexed router);

    /// @notice Event emitted when the fulfillable registry is updated.
    /// @param fulfillableRegistry The address of the new fulfillable registry.
    event FulfillableRegistryUpdated(address indexed fulfillableRegistry);

    /*****************************/
    /* ERROR DECLARATIONS        */
    /*****************************/

    /// @notice Throws this error when the address is invalid.
    /// @param address_ The address that was invalid
    error InvalidAddress(address address_);

    /// @notice Throws this error when the router address is invalid.
    /// @param router_ The router address that was invalid
    error InvalidRouter(address router_);

    /// @notice Error emitted when an overflow occurs.
    error Overflow(uint8 reason);

    /// @notice Error emitted when the refund amount are too big.
    error RefundsTooBig();

    /// @notice Throws this error when the no refunds are authorized.
    /// @param refundee The refundee address that was invalid
    /// @param serviceID The service ID that was invalid
    error NoRefunds(address refundee, uint256 serviceID);

    /// @notice Throws this error when the caller is not the manager.
    error InvalidManager(address manager);

    /// @notice Throws this error when the fulfillment status is unsupported.
    error UnsupportedStatus(FulFillmentResultState status);

    /// @notice Throws this error when the fulfillment record does not exist.
    error FulfillmentRecordDoesNotExist();

    /// @notice Throws this error when the fulfillment record is already registered.
    error FulfillmentAlreadyRegistered();

    /// @notice Throws this error when there is no balance to release.
    error NoBalanceToRelease();

    /// @notice Throws this error when there is no fees to withdraw.
    error NoFeesToWithdraw();

    /*****************************/
    /* STATE VARIABLES           */
    /*****************************/

    //Auto-incrementable id storage
    uint256 internal _fulfillmentIdCount;

    // All fulfillment records keyed by their ids
    mapping(uint256 => FulFillmentRecord) internal _fulfillmentRecords;

    // Deposits mapped to subject addresses
    mapping(address => uint256[]) internal _fulfillmentRecordsForSubject;

    // Total deposits registered
    uint256 public _fulfillmentRecordCount;

    // The protocol manager address
    address public _manager;

    /// @dev The protocol router address
    address public _router;

    /// @dev The address of the fulfillable registry. Used to fetch service details.
    address public _fulfillableRegistry;

    /// @dev The registry contract instance.
    IFulfillableRegistry internal _registryContract;

    /// @dev The releaseable pool to be withdrawn by the beneficiaries in wei.
    /// serviceID => releaseablePoolAmount
    mapping (uint256 => uint256) public _releaseablePool;

    /// @dev A mapping to track accumulated fees per service
    mapping(uint256 => uint256) public _accumulatedFees;

    /// Mapping to store native coin refunds and deposit amounts
    /// @dev serviceID => userAddress => depositedAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) public _deposits;

    /// @dev serviceID => userAddress => refundableAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) public _authorized_refunds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*****************************/
    /* FULFILLABLE ESCROW LOGIC  */
    /*****************************/

    /// @notice Initializes the contract
    /// @dev set counter to 1 to avoid 0 id
    function initialize(address initialOwner) public virtual initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
        _fulfillmentIdCount = 1;
    }

    /// @notice Sets the protocol manager address
    /// @param manager_ The address of the protocol manager
    /// @dev Only callable by the contract owner
    function setManager(address manager_) public onlyOwner {
        if (manager_ == address(0)) {
            revert InvalidAddress(manager_);
        }
        _manager = manager_;
        emit ManagerUpdated(manager_);
    }

    /// @notice Sets the protocol router address
    /// @param router_ The address of the protocol router
    /// @dev Only callable by the contract owner
    function setRouter(address router_) public onlyOwner {
        if (router_ == address(0)) {
            revert InvalidAddress(router_);
        }
        _router = router_;
        emit RouterUpdated(router_);
    }

    /// @notice Sets the fulfillable registry address
    /// @param fulfillableRegistry_ The address of the fulfillable registry
    /// @dev Only callable by the contract owner
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        if (fulfillableRegistry_ == address(0)) {
            revert InvalidAddress(fulfillableRegistry_);
        }
        _fulfillableRegistry = fulfillableRegistry_;
        _registryContract = IFulfillableRegistry(fulfillableRegistry_);
        emit FulfillableRegistryUpdated(fulfillableRegistry_);
    }

    /// @notice Retrieves the accumulated fees for a given service ID
    /// @param serviceId The ID of the service
    /// @return amount The total amount of accumulated fees for the given service ID
    function getNativeFeesFor(uint256 serviceId) public view returns (uint256 amount) {
        amount = _accumulatedFees[serviceId];
    }

    /// @notice Retrieves the total deposits for a given payer and service ID
    /// @param payer The address of the payer
    /// @param serviceID The ID of the service
    /// @return amount The total amount of deposits for the given payer and service ID
    function getDepositsFor(address payer, uint256 serviceID) public view returns (uint256 amount) {
        amount = _deposits[serviceID][payer];
    }

    /// @notice Sets the total deposits for a given payer and service ID
    /// @param payer The address of the payer
    /// @param serviceID The ID of the service
    /// @param amount The amount of deposits to set
    function setDepositsFor(address payer, uint256 serviceID, uint256 amount) internal {
        _deposits[serviceID][payer] = amount;
    }

    /// @notice Retrieves the total refunds authorized for a given payer and service ID
    /// @param payer The address of the payer
    /// @param serviceID The ID of the service
    /// @return amount The total amount of refunds authorized for the given payer and service ID
    function getRefundsFor(address payer, uint256 serviceID) public view returns (uint256 amount) {
        amount = _authorized_refunds[serviceID][payer];
    }

    /// @notice Sets the total refunds authorized for a given payer and service ID
    /// @param payer The address of the payer
    /// @param serviceID The ID of the service
    /// @param amount The amount of refunds to set
    function setRefundsFor(address payer, uint256 serviceID, uint256 amount) internal {
        _authorized_refunds[serviceID][payer] = amount;
    }

    /// @notice Returns the fulfillment records for a given payer
    /// @param payer The address of the payer
    /// @return An array of fulfillment record IDs
    function recordsOf(address payer) public view returns (uint256[] memory) {
        return _fulfillmentRecordsForSubject[payer];
    }

    /// @notice Returns the fulfillment record for a given id
    /// @param id The id of the record
    /// @return The fulfillment record
    function record(uint256 id) public view returns (FulFillmentRecord memory) {
        return _fulfillmentRecords[id];
    }

    /// @notice Deposits funds into the escrow.
    /// @param serviceID The service identifier.
    /// @param fulfillmentRequest The fulfillment request.
    function deposit(
        uint256 serviceID,
        FulFillmentRequest memory fulfillmentRequest,
        uint256 feeAmount
    ) public payable virtual nonReentrant {
        if (_router != msg.sender) {
            revert InvalidRouter(msg.sender);
        }
        (Service memory service, ) = _registryContract.getService(serviceID);
        uint256 total_amount = msg.value;
        uint256 depositsAmount = getDepositsFor(
            fulfillmentRequest.payer,
            serviceID
        );
        (bool success, uint256 result) = total_amount.tryAdd(depositsAmount);
        if (!success) {
            revert Overflow(6);
        }
        setDepositsFor(
            fulfillmentRequest.payer,
            serviceID,
            result
        );
        // create a FulfillmentRecord
        FulFillmentRecord memory fulfillmentRecord = FulFillmentRecord({
            id: _fulfillmentIdCount,
            serviceRef: fulfillmentRequest.serviceRef,
            externalID: "",
            fulfiller: service.fulfiller,
            entryTime: block.timestamp,
            payer: fulfillmentRequest.payer,
            weiAmount: fulfillmentRequest.weiAmount,
            feeAmount: feeAmount,
            fiatAmount: fulfillmentRequest.fiatAmount,
            receiptURI: "",
            status: FulFillmentResultState.PENDING
        });
        _fulfillmentIdCount += 1;
        _fulfillmentRecordCount += 1;
        _fulfillmentRecords[fulfillmentRecord.id] = fulfillmentRecord;
        _fulfillmentRecordsForSubject[fulfillmentRecord.payer].push(
            fulfillmentRecord.id
        );
        emit DepositReceived(fulfillmentRecord);
    }

    /// @notice Withdraws the authorized refund.
    /// @dev Refund accumulated balance for a refundee, forwarding all gas to the recipient.
    /// WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
    /// Make sure you trust the recipient, or are either following the
    /// checks-effects-interactions pattern or using {ReentrancyGuard}.
    /// @param serviceID The service identifier.
    /// @param recordId The record id.
    function withdrawRefund(
        uint256 serviceID,
        uint256 recordId
    ) public virtual nonReentrant returns (bool) {
        _withdrawRefund(serviceID, recordId);
        return true;
    }

    /// @notice Internal function to withdraw.
    /// Should only be called when previously authorized.
    /// Will emit a RefundWithdrawn event on success.
    /// @param serviceID The service identifier.
    /// @param recordId The record id.
    function _withdrawRefund(
        uint256 serviceID,
        uint256 recordId
    ) internal {
        if (_router != msg.sender) {
            revert InvalidRouter(msg.sender);
        }
        FulFillmentRecord memory fulfillmentRecord = _fulfillmentRecords[recordId];
        uint256 authorized_refunds = getRefundsFor(
            fulfillmentRecord.payer,
            serviceID
        );
        if (authorized_refunds == 0) {
            revert NoRefunds(fulfillmentRecord.payer, serviceID);
        }
        (, uint256 amount) = fulfillmentRecord.weiAmount.tryAdd(fulfillmentRecord.feeAmount);
        if (amount > authorized_refunds) {
            revert RefundsTooBig();
        }
        (, uint256 subResult) = authorized_refunds.trySub(amount);
        setRefundsFor(fulfillmentRecord.payer, serviceID, subResult);
        fulfillmentRecord.status = FulFillmentResultState.REFUNDED;
        payable(fulfillmentRecord.payer).sendValue(amount);
        emit RefundWithdrawn(fulfillmentRecord.payer, amount, fulfillmentRecord.id);
    }

    /// @notice Authorizes a refund for a given refundee.
    /// @param serviceID The service identifier.
    /// @param refundee The address whose funds will be authorized for refund.
    /// @param weiAmount The amount of funds to authorize for refund.
    function _authorizeRefund(
        uint256 serviceID,
        address refundee,
        uint256 weiAmount
    ) internal {
        uint256 authorized_refunds = getRefundsFor(
            refundee,
            serviceID
        );
        uint256 deposits = getDepositsFor(
            refundee,
            serviceID
        );
        (bool asuccess, uint256 addResult) = authorized_refunds.tryAdd(
            weiAmount
        );
        if(!asuccess) {
            revert Overflow(1);
        }
        if(deposits < weiAmount) {
            revert RefundsTooBig();
        }
        (, uint256 subResult) = deposits.trySub(weiAmount);
        setDepositsFor(refundee, serviceID, subResult);
        setRefundsFor(refundee, serviceID, addResult);
        emit RefundAuthorized(refundee, weiAmount);
    }

    /// @dev The fulfiller registers a fulfillment.
    ///
    /// We need to verify the amount of the fulfillment is actually available to release.
    /// Then we can enrich the result with an auto-incremental unique ID.
    /// and the timestamp when the record get inserted.
    ///
    /// If the fulfillment has failed:
    /// - a refund will be authorized for a later withdrawal.
    ///
    /// If these verifications pass:
    /// - add the amount fulfilled to the release pool.
    /// - substract the amount from the payer's deposits.
    /// - update the FulFillmentRecord to the blockchain.
    ///
    /// @param serviceID the service identifier.
    /// @param fulfillment the fulfillment result attached to it.
    function registerFulfillment(
        uint256 serviceID,
        FulFillmentResult memory fulfillment
    ) public virtual nonReentrant returns (bool) {
        if (_manager != msg.sender) {
            revert InvalidManager(msg.sender);
        }
        if(_fulfillmentRecords[fulfillment.id].id == 0) {
            revert FulfillmentRecordDoesNotExist();
        }
        if(_fulfillmentRecords[fulfillment.id].status != FulFillmentResultState.PENDING) {
            revert FulfillmentAlreadyRegistered();
        }
        address payer = _fulfillmentRecords[fulfillment.id].payer;
        uint256 deposits = getDepositsFor(payer, serviceID);
        uint256 wei_amount = _fulfillmentRecords[fulfillment.id].weiAmount;
        (, uint256 total_amount) = wei_amount.tryAdd(_fulfillmentRecords[fulfillment.id].feeAmount);
        if (fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(serviceID, payer, total_amount);
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
        } else if (fulfillment.status != FulFillmentResultState.SUCCESS) {
            revert UnsupportedStatus(fulfillment.status);
        } else {
            (bool asuccess, uint256 addResult) = _accumulatedFees[serviceID].tryAdd(
                _fulfillmentRecords[fulfillment.id].feeAmount
            );
            if(!asuccess) {
                    revert Overflow(3);
            }
            _accumulatedFees[serviceID] = addResult;
            (bool rlsuccess, uint256 releaseResult) = _releaseablePool[serviceID].tryAdd(wei_amount);
            if(!rlsuccess) {
                revert Overflow(4);
            }

            (bool dsuccess, uint256 subResult) = deposits.trySub(total_amount);
            if(!dsuccess) {
                revert Overflow(5);
            }
            _releaseablePool[serviceID] = releaseResult;
            setDepositsFor(payer, serviceID, subResult);
            _fulfillmentRecords[fulfillment.id].receiptURI = fulfillment.receiptURI;
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
            _fulfillmentRecords[fulfillment.id].externalID = fulfillment.externalID;
        }
        return true;
    }

    /// @notice Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// @param serviceID The service identifier.
    function beneficiaryWithdraw(uint256 serviceID) public virtual nonReentrant {
        if (_manager != msg.sender) {
            revert InvalidManager(msg.sender);
        }
        (Service memory service, ) = _registryContract.getService(serviceID);
        if(_releaseablePool[serviceID] == 0) {
            revert NoBalanceToRelease();
        }
        uint256 amount = _releaseablePool[serviceID];
        _releaseablePool[serviceID] = 0;
        service.beneficiary.sendValue(amount);
    }

    /// @notice Withdraws the accumulated fees for a given service ID.
    /// @param serviceId The service identifier.
    function withdrawAccumulatedFees(uint256 serviceId) external nonReentrant {
        if (_manager != msg.sender) {
            revert InvalidManager(msg.sender);
        }
        (Service memory service, ) = _registryContract.getService(serviceId);
        uint256 amount = _accumulatedFees[serviceId];
        if(amount == 0) {
            revert NoFeesToWithdraw();
        }
        _accumulatedFees[serviceId] = 0;
        service.beneficiary.sendValue(amount);
        emit FeesWithdrawn(serviceId, service.beneficiary, amount);
    }
}
