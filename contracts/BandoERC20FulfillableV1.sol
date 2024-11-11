// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

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
    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _fulfillmentIdCount = 1;
    }

    /// @dev Sets the protocol manager address.
    /// @param manager_ The address of the protocol manager.
    function setManager(address manager_) public onlyOwner {
        require(manager_ != address(0), "Manager address cannot be 0");
        _manager = manager_;
    }

    /// @dev Sets the protocol router address.
    /// @param router_ The address of the protocol router.
    function setRouter(address router_) public onlyOwner {
        require(router_ != address(0), "Router address cannot be 0");
        _router = router_;
    }

    /// @dev Sets the fulfillable registry address.
    /// @param fulfillableRegistry_ The address of the fulfillable registry.
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        require(fulfillableRegistry_ != address(0), "Fulfillable registry address cannot be 0");
        _fulfillableRegistry = fulfillableRegistry_;
        _registryContract = IFulfillableRegistry(fulfillableRegistry_);
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
    function depositERC20(uint256 serviceID, ERC20FulFillmentRequest memory fulfillmentRequest) public virtual nonReentrant {
        require(_router == msg.sender, "Caller is not the router");
        uint256 amount = fulfillmentRequest.tokenAmount;
        address token = fulfillmentRequest.token;
        Service memory service = _registryContract.getService(serviceID);
        uint256 depositsAmount = getERC20DepositsFor(
            token,
            fulfillmentRequest.payer,
            serviceID
        );
        (bool success, uint256 result) = amount.tryAdd(depositsAmount);
        require(success, "Overflow while adding deposits");
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
            feeAmount: service.feeAmount,
            fiatAmount: fulfillmentRequest.fiatAmount,
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
    ///
    /// @param token The address of the ERC20 token.
    /// @param refundee The address whose funds will be withdrawn and transferred to.
    ///
    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) public virtual nonReentrant returns (bool) {
        require(_manager == msg.sender, "Caller is not the manager");
        uint256 authorized_refunds = getERC20RefundsFor(
            token,
            refundee,
            serviceID
        );
        require(authorized_refunds > 0, "Address is not allowed any refunds");
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
        require(asuccess, "Overflow while adding authorized refunds");
        uint256 total_refunds = addResult;
        require(
            depositsAmount >= total_refunds,
            "Total token refunds would be bigger than the total in escrow"
        );
        (bool ssuccess, uint256 subResult) = depositsAmount.trySub(amount);
        require(ssuccess, "Overflow while substracting deposits");
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
        require(_manager == msg.sender, "Caller is not the manager");
        require(_fulfillmentRecords[fulfillment.id].id > 0, "Fulfillment record does not exist");
        require(_fulfillmentRecords[fulfillment.id].status == FulFillmentResultState.PENDING, "Fulfillment already registered");
        Service memory service = _registryContract.getService(serviceID);
        address token = _fulfillmentRecords[fulfillment.id].token;
        uint depositsAmount = getERC20DepositsFor(
            token,
            _fulfillmentRecords[fulfillment.id].payer,
            serviceID
        );
        (bool ffsuccess, uint256 total_amount) = _fulfillmentRecords[fulfillment.id].tokenAmount.tryAdd(
            service.feeAmount
        );
        require(ffsuccess, "Overflow while adding fulfillment amount and fee");
        require(depositsAmount >= total_amount, "There is not enough balance to be released");
        if(fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(service, token, _fulfillmentRecords[fulfillment.id].payer, total_amount);
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
        } else if(fulfillment.status != FulFillmentResultState.SUCCESS) {
            revert('Unexpected status');
        } else {
            (bool rlsuccess, uint256 releaseResult) = _releaseablePools[serviceID][token].tryAdd(total_amount);
            require(rlsuccess, "Overflow while adding to releaseable pool");
            (bool dsuccess, uint256 subResult) = depositsAmount.trySub(total_amount);
            require(dsuccess, "Overflow while substracting from deposits");
            _releaseablePools[serviceID][token] = releaseResult;
            setERC20DepositsFor(
                token,
                _fulfillmentRecords[fulfillment.id].payer,
                serviceID,
                subResult
            );
            _fulfillmentRecords[fulfillment.id].receiptURI = fulfillment.receiptURI;
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
            _fulfillmentRecords[fulfillment.id].externalID = fulfillment.externalID;
        }
        return true;
    }

    /// @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
    /// Only the fulfiller of the service can withdraw the releaseable pool.
    function beneficiaryWithdraw(uint256 serviceID, address token) public virtual nonReentrant {
        require(_manager == msg.sender, "Caller is not the manager");
        require(_releaseablePools[serviceID][token] > 0, "There is no balance to release.");
        Service memory service = _registryContract.getService(serviceID);
        uint256 amount = _releaseablePools[serviceID][token];
        _releaseablePools[serviceID][token] = 0;
        IERC20(token).safeTransfer(service.beneficiary, amount);
    }
}
