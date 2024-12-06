// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBandoERC20Fulfillable } from "./IBandoERC20Fulfillable.sol";
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Service, IFulfillableRegistry } from "./periphery/registry/IFulfillableRegistry.sol";
import {
    ERC20FulFillmentRecord,
    ERC20FulFillmentRequest,
    FulFillmentResultState,
    FulFillmentResult
} from "./FulfillmentTypes.sol";

/// @title BandoERC20FulfillableV1
/// @author g6s
/// @custom:bfp-version 1.0.0
/// @dev Inspired in: OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)
/// Base escrow contract, holds funds designated for a beneficiary until they
/// withdraw them or a refund is emitted.
///
/// @notice Intended usage: This contract (and derived escrow contracts) should be a
/// standalone contract, that only interacts with the contract that instantiated
/// it. That way, it is guaranteed that all Ether will be handled according to
/// the `Escrow` rules, and there is no need to check for payable functions or
/// transfers in the inheritance tree.
contract BandoERC20FulfillableV1 is
    IBandoERC20Fulfillable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable {

    using Address for address;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*****************************/
    /* ERROR DECLARATIONS        */
    /*****************************/

    /// @notice Error emitted when the address is invalid.
    /// @param addr The address that is invalid.
    error InvalidAddress(address addr);

    /// @notice Error emitted when the address is not allowed any refunds.
    /// @param refundee The address that is not allowed any refunds.
    error NoRefunds(address refundee);

    /// @notice Error emitted when an overflow occurs.
    error Overflow(uint8 reason);

    /// @notice Error emitted when the refund amount are too big.
    error RefundsTooBig();

    /// @notice Error emitted when the fulfillment status is unsupported.
    error UnsupportedFulfillmentStatus();

    /// @notice Error emitted when the fulfillment record does not exist.
    error FulfillmentRecordDoesNotExist();

    /// @notice Error emitted when the fulfillment record is already registered.
    error FulfillmentAlreadyRegistered();

    /// @notice Error emitted when there is no balance to release.
    error NoBalanceToRelease();

    /// @notice Error emitted when there is no fees to withdraw.
    error NoFeesToWithdraw();


    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    /// @notice Event emitted when a deposit is received.
    /// @param record The fulfillment record.
    event ERC20DepositReceived(ERC20FulFillmentRecord record);

    /// @notice Event emitted when a refund is withdrawn.
    /// @param token The address of the token.
    /// @param payee The address of the payee.
    /// @param weiAmount The amount of wei to refund.
    event ERC20RefundWithdrawn(address token, address indexed payee, uint256 weiAmount);

    /// @notice Event emitted when a refund is authorized.
    /// @param payee The address of the payee.
    /// @param weiAmount The amount of wei to refund.
    event ERC20RefundAuthorized(address indexed payee, uint256 weiAmount);

    /// @notice Event emitted when the accumulated fees are withdrawn.
    /// @param serviceId The service identifier
    /// @param token The token address
    /// @param beneficiary The beneficiary address
    /// @param amount The amount of fees withdrawn
    event ERC20FeesWithdrawn(
        uint256 indexed serviceId, 
        address indexed token,
        address beneficiary, 
        uint256 amount
    );

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
    /* STATE VARIABLES           */
    /*****************************/

    /// @notice Auto-incrementable id storage
    uint256 private _fulfillmentIdCount;

    /// @notice All fulfillment records keyed by their ids
    mapping(uint256 => ERC20FulFillmentRecord) private _fulfillmentRecords;

    /// @notice Deposits mapped to subject addresses
    mapping(address => uint256[]) private _fulfillmentRecordsForSubject;

    /// @notice Total deposits registered
    uint256 private _fulfillmentRecordCount;

    /// @notice The amounts per token that is available to be released by the beneficiary.
    /// @dev We must track the amount per service and token to allow for multiple services to be fulfilled.
    /// @dev serviceID => tokenAddress => amount
    mapping(uint256 => mapping(address => uint256)) private _releaseablePools;

    /// @notice The accumulated fees per service.
    /// @dev serviceID => tokenAddress => amount
    mapping(uint256 => mapping(address => uint256)) private _accumulatedFees;

    /// @notice The fulfillable registry address.
    address public _fulfillableRegistry;

    /// @notice The registry contract instance.
    IFulfillableRegistry private _registryContract;

    /// @notice The protocol manager address
    address public _manager;

    /// @notice The protocol router address
    address public _router;

    /// @notice Mapping to store erc20 refunds and deposit amounts
    /// @dev serviceID => tokenAddress => userAddress => depositedAmount
    mapping(
        uint256 => mapping(address => mapping(address => uint256))
    ) private _erc20_deposits;

    /// @dev serviceID => tokenAddress => userAddress => refundableAmount
    mapping(
        uint256 => mapping(address => mapping(address => uint256))
    ) private _erc20_authorized_refunds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice UUPS upgrade authorization
    /// @param newImplementation The address of the new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*****************************/
    /* FULFILLABLE ESCROW LOGIC  */
    /*****************************/

    /// @dev Initializes the contract.
    function initialize(address initialOwner) public virtual initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
        _fulfillmentIdCount = 1;
    }

    /// @dev Sets the protocol manager address.
    /// @param manager_ The address of the protocol manager.
    function setManager(address manager_) public onlyOwner {
        if(manager_ == address(0)) {
            revert InvalidAddress(manager_);
        }
        _manager = manager_;
        emit ManagerUpdated(manager_);
    }

    /// @dev Sets the protocol router address.
    /// @param router_ The address of the protocol router.
    function setRouter(address router_) public onlyOwner {
        if(router_ == address(0)) {
            revert InvalidAddress(router_);
        }
        _router = router_;
        emit RouterUpdated(router_);
    }

    /// @dev Sets the fulfillable registry address.
    /// @param fulfillableRegistry_ The address of the fulfillable registry.
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        if(fulfillableRegistry_ == address(0)) {
            revert InvalidAddress(fulfillableRegistry_);
        }
        _fulfillableRegistry = fulfillableRegistry_;
        _registryContract = IFulfillableRegistry(fulfillableRegistry_);
        emit FulfillableRegistryUpdated(fulfillableRegistry_);
    }

    /// @dev Returns the fulfillment records for a given payer.
    /// @param payer the address of the payer
    function recordsOf(address payer) public view returns (uint256[] memory) {
        return _fulfillmentRecordsForSubject[payer];
    }

    /// @dev Returns the fulfillment record for a given id.
    /// @param id the id of the record
    function record(uint256 id) public view returns (ERC20FulFillmentRecord memory) {
        return _fulfillmentRecords[id];
    }

    /// @dev Stores the sent amount as credit to be claimed.
    /// @param serviceID Service identifier
    /// @param fulfillmentRequest The fulfillment record to be stored.
    function depositERC20(
        uint256 serviceID,
        ERC20FulFillmentRequest memory fulfillmentRequest,
        uint256 feeAmount
    ) public virtual nonReentrant {
        if(msg.sender != _router) {
            revert InvalidAddress(msg.sender);
        }
        (, uint256 fullAmount) = fulfillmentRequest.tokenAmount.tryAdd(feeAmount);
        address token = fulfillmentRequest.token;
        (Service memory service, ) = _registryContract.getService(serviceID);
        uint256 depositsAmount = getERC20DepositsFor(
            token,
            fulfillmentRequest.payer,
            serviceID
        );
        (, uint256 result) = fullAmount.tryAdd(depositsAmount);
        setERC20DepositsFor(
            token,
            fulfillmentRequest.payer,
            serviceID,
            result
        );
        // create a FulfillmentRecord
        ERC20FulFillmentRecord memory fulfillmentRecord = ERC20FulFillmentRecord({
            id: _fulfillmentIdCount,
            serviceRef: fulfillmentRequest.serviceRef,
            externalID: "",
            fulfiller: service.fulfiller,
            entryTime: block.timestamp,
            payer: fulfillmentRequest.payer,
            tokenAmount: fulfillmentRequest.tokenAmount,
            fiatAmount: fulfillmentRequest.fiatAmount,
            feeAmount: feeAmount,
            receiptURI: "",
            status: FulFillmentResultState.PENDING,
            token: fulfillmentRequest.token
        });
        _fulfillmentIdCount += 1;
        _fulfillmentRecordCount += 1;
        _fulfillmentRecords[fulfillmentRecord.id] = fulfillmentRecord;
        _fulfillmentRecordsForSubject[fulfillmentRecord.payer].push(fulfillmentRecord.id);
        emit ERC20DepositReceived(fulfillmentRecord);
    }

    /// @dev Retrieves the amount of ERC20 deposits for a given token, payer, and service ID.
    /// 
    /// This function is used to query the amount of ERC20 tokens deposited by a payer for a specific service.
    /// 
    /// @param token The address of the ERC20 token.
    /// @param payer The address of the payer.
    /// @param serviceID The identifier of the service.
    /// @return amount The amount of ERC20 tokens deposited.
    function getERC20DepositsFor(address token, address payer, uint256 serviceID) public view returns (uint256 amount) {
        amount = _erc20_deposits[serviceID][token][payer];
    }

    /// @dev Sets the amount of ERC20 deposits for a given token, payer, and service ID.
    /// 
    /// This function is used to update the amount of ERC20 tokens deposited by a payer for a specific service.
    /// 
    /// @param token The address of the ERC20 token.
    /// @param payer The address of the payer.
    /// @param serviceID The identifier of the service.
    /// @param amount The amount of ERC20 tokens to be set.
    function setERC20DepositsFor(address token, address payer, uint256 serviceID, uint256 amount) private {
        _erc20_deposits[serviceID][token][payer] = amount;
    }

    /// @dev Retrieves the amount of ERC20 refunds authorized for a given token, refundee, and service ID.
    /// 
    /// This function is used to query the amount of ERC20 tokens authorized for refund to a refundee for a specific service.
    /// 
    /// @param token The address of the ERC20 token.
    /// @param refundee The address of the refundee.
    /// @param serviceID The identifier of the service.
    /// @return amount The amount of ERC20 tokens authorized for refund.
    function getERC20RefundsFor(address token, address refundee, uint256 serviceID) public view returns (uint256 amount) {
        amount = _erc20_authorized_refunds[serviceID][token][refundee];
    }

    /// @dev Retrieves the amount of ERC20 fees accumulated for a given token and service ID.
    /// @param token The address of the ERC20 token.
    /// @param serviceID The identifier of the service.
    /// @return amount The amount of ERC20 tokens accumulated as fees.
    function getERC20FeesFor(address token, uint256 serviceID) public view returns (uint256 amount) {
        amount = _accumulatedFees[serviceID][token];
    }

    /// @dev Sets the amount of ERC20 refunds authorized for a given token, refundee, and service ID.
    /// 
    /// This function is used to update the amount of ERC20 tokens authorized for refund to a refundee for a specific service.
    /// 
    /// @param token The address of the ERC20 token.
    /// @param refundee The address of the refundee.
    /// @param serviceID The identifier of the service.
    /// @param amount The amount of ERC20 tokens to be authorized for refund.
    function setERC20RefundsFor(address token, address refundee, uint256 serviceID, uint256 amount) private {
        _erc20_authorized_refunds[serviceID][token][refundee] = amount;
    }
    

    /// @dev Refund accumulated balance for a refundee, forwarding all gas to the
    /// recipient.
    ///
    /// WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
    /// Make sure you trust the recipient, or are either following the
    /// checks-effects-interactions pattern or using {ReentrancyGuard}.
    /// @param serviceID The identifier of the service.
    /// @param token The address of the ERC20 token.
    /// @param refundee The address whose funds will be withdrawn and transferred to.
    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) public virtual nonReentrant returns (bool) {
        if(msg.sender != _router) {
            revert InvalidAddress(msg.sender);
        }
        uint256 authorized_refunds = getERC20RefundsFor(
            token,
            refundee,
            serviceID
        );
        if(authorized_refunds == 0) {
            revert NoRefunds(refundee);
        }
        _withdrawRefund(token, refundee, authorized_refunds);
        setERC20RefundsFor(token, refundee, serviceID, 0);
        return true;
    }
    
    /// @dev internal function to withdraw.
    /// Should only be called when previously authorized.
    ///
    /// Will emit a RefundWithdrawn event on success.
    ///
    /// @param token The address of the token.
    /// @param refundee The address to send the value to.
    function _withdrawRefund(address token, address refundee, uint256 amount) internal {
        IERC20(token).safeTransfer(refundee, amount);
        emit ERC20RefundWithdrawn(token, refundee, amount);
    }

    /// @dev Allows for refunds to take place.
    /// 
    /// This function will authorize a refund for a later withdrawal.
    /// 
    /// @param token the token to be refunded.
    /// @param refundee the record to be
    /// @param amount the amount to be authorized.
    function _authorizeRefund(Service memory service, address token, address refundee, uint256 amount) internal {
        (bool asuccess, uint256 addResult) = getERC20RefundsFor(token, refundee, service.serviceId).tryAdd(amount);
        uint256 depositsAmount = getERC20DepositsFor(
            token,
            refundee,
            service.serviceId
        );
        if (!asuccess) {
            revert Overflow(1);
        }
        uint256 total_refunds = addResult;
        if (depositsAmount < total_refunds) {
            revert RefundsTooBig();
        }
        (bool ssuccess, uint256 subResult) = depositsAmount.trySub(amount);
        if (!ssuccess) {
            revert Overflow(2);
        }
        setERC20DepositsFor(
            token,
            refundee,
            service.serviceId,
            subResult
        );
        setERC20RefundsFor(token, refundee, service.serviceId, total_refunds);
        emit ERC20RefundAuthorized(refundee, amount);
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
    /// @param fulfillment the fulfillment result attached to it.
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual nonReentrant returns (bool) {
        if(msg.sender != _manager) {
            revert InvalidAddress(msg.sender);
        }
        if(_fulfillmentRecords[fulfillment.id].id == 0) {
            revert FulfillmentRecordDoesNotExist();
        }
        if(_fulfillmentRecords[fulfillment.id].status != FulFillmentResultState.PENDING) {
            revert FulfillmentAlreadyRegistered();
        }
        (Service memory service, ) = _registryContract.getService(serviceID);
        address token = _fulfillmentRecords[fulfillment.id].token;
        uint256 tokenAmount = _fulfillmentRecords[fulfillment.id].tokenAmount;
        (, uint256 fullAmount) = tokenAmount.tryAdd(_fulfillmentRecords[fulfillment.id].feeAmount);
        if(fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(service, token, _fulfillmentRecords[fulfillment.id].payer, fullAmount);
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
        } else if(fulfillment.status != FulFillmentResultState.SUCCESS) {
            revert UnsupportedFulfillmentStatus();
        } else {
            _successFulfillment(serviceID, _fulfillmentRecords[fulfillment.id], fullAmount);
        }
        return true;
    }

    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the fulfiller of the service can withdraw the releaseable pool.
    function beneficiaryWithdraw(uint256 serviceID, address token) public virtual nonReentrant {
        if(msg.sender != _manager) {
            revert InvalidAddress(msg.sender);
        }
        if(_releaseablePools[serviceID][token] == 0) {
            revert NoBalanceToRelease();
        }
        (Service memory service, ) = _registryContract.getService(serviceID);
        uint256 amount = _releaseablePools[serviceID][token];
        _releaseablePools[serviceID][token] = 0;
        IERC20(token).safeTransfer(service.beneficiary, amount);
    }

    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the manager can withdraw the accumulated fees.
    /// @param serviceId The service identifier
    /// @param token The token address
    function withdrawAccumulatedFees(
        uint256 serviceId,
        address token
    ) external nonReentrant {
        if(msg.sender != _manager) {
            revert InvalidAddress(msg.sender);
        }
        (Service memory service, ) = _registryContract.getService(serviceId);
        
        uint256 amount = _accumulatedFees[serviceId][token];
        if(amount == 0) {
            revert NoFeesToWithdraw();
        }
        
        // Reset accumulated fees before transfer
        _accumulatedFees[serviceId][token] = 0;
        
        // Transfer fees to beneficiary
        IERC20(token).safeTransfer(service.beneficiary, amount);
        
        emit ERC20FeesWithdrawn(
            serviceId,
            token,
            service.beneficiary,
            amount
        );
    }

    /// @dev Internal function to handle the success of a fulfillment.
    /// @param serviceID The service identifier.
    /// @param frecord The fulfillment record.
    /// @param fullAmount The total amount of the fulfillment.
    function _successFulfillment(uint256 serviceID, ERC20FulFillmentRecord memory frecord, uint256 fullAmount) internal {
        (bool asuccess, uint256 feeResult) = _accumulatedFees[serviceID][frecord.token].tryAdd(
            _fulfillmentRecords[frecord.id].feeAmount
        );
        uint depositsAmount = getERC20DepositsFor(
            frecord.token,
            _fulfillmentRecords[frecord.id].payer,
            serviceID
        );
        if (!asuccess) {
            revert Overflow(3);
        }
        _accumulatedFees[serviceID][frecord.token] = feeResult;
        (bool rlsuccess, uint256 releaseResult) = _releaseablePools[serviceID][frecord.token].tryAdd(frecord.tokenAmount);
        if (!rlsuccess) {
            revert Overflow(4);
        }
        (bool dsuccess, uint256 subResult) = depositsAmount.trySub(fullAmount);
        if (!dsuccess) {
            revert Overflow(5);
        }
        _releaseablePools[serviceID][frecord.token] = releaseResult;
        setERC20DepositsFor(
            frecord.token,
            frecord.payer,
            serviceID,
            subResult
        );
        _fulfillmentRecords[frecord.id].receiptURI = frecord.receiptURI;
        _fulfillmentRecords[frecord.id].status = FulFillmentResultState.SUCCESS;
        _fulfillmentRecords[frecord.id].externalID = frecord.externalID;
    }
}
